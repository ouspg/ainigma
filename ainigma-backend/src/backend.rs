use crate::errors::filesystem::FileSystemError;
use ainigma::build_process::build_task;
use ainigma::config::{ModuleConfiguration, read_toml, server_read_check_toml};
use axum::Extension;
use axum::body::Body;
use axum::extract::Path as AxumPath;
use axum::{Json, http::StatusCode, response::IntoResponse, response::Response};
use regex::Regex;
use serde::Serialize;
use serde_json::json;
use std::collections::HashMap;
use std::env;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::fs::{self, File};
use tokio::task::JoinSet;
use tokio_util::io::ReaderStream;
use uuid::Uuid;

lazy_static::lazy_static! {
    static ref SAFE_ID_PATTERN: Regex = Regex::new(r"^[a-zA-Z0-9_-]{1,64}$").unwrap();
}

const COURSES_DIR: &str = "courses";

fn get_data_path() -> PathBuf {
    // Try reading from an environment variable first
    if let Ok(path) = env::var("AINIGMA_DATA_PATH") {
        PathBuf::from(path)
    } else {
        // fallback to the default production path
        PathBuf::from("/srv/ainigma/data")
    }
}
#[derive(Serialize)]
pub struct FileMetadata {
    pub name: String,
    pub size: u64,
    pub last_modified: String,
}

#[derive(Serialize)]
pub struct TaskMetadataResponse {
    pub instructions: String,
    pub files: Vec<FileMetadata>,
}

#[derive(Clone, Serialize)]
pub struct CourseResponse {
    pub id: String,
    pub name: String,
    pub description: String,
}

#[derive(Clone, Serialize)]
pub struct CategoryResponse {
    pub name: String,
    pub number: u8,
}

#[derive(Clone, Serialize)]
pub struct TaskResponse {
    pub id: String,
    pub name: String,
    pub description: String,
}
#[derive(Clone, Serialize)]
pub struct AnswerPayload {
    pub answer: String,
}

pub struct CheckAnswerResponse {
    pub correct: bool,
}

#[derive(Clone, Serialize)]
pub struct CourseCache {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub categories: Vec<CategoryCache>,
}

#[derive(Clone, Serialize)]
pub struct CategoryCache {
    pub name: String,
    pub number: u8,
    pub tasks: Vec<TaskCache>,
}

#[derive(Clone, Serialize)]
pub struct TaskCache {
    pub id: String,
    pub name: String,
    pub description: String,
}

#[derive(Clone)]
pub struct Cache {
    pub courses: Arc<Json<Vec<CourseResponse>>>,
    pub categories: HashMap<String, Arc<Json<Vec<CategoryResponse>>>>,
    pub tasks: HashMap<(String, String), Arc<Json<Vec<TaskResponse>>>>,
}

pub async fn list_courses_handler(
    Extension(cache): Extension<Cache>,
) -> Result<Json<Vec<CourseResponse>>, (StatusCode, String)> {
    Ok((*(cache.courses)).clone())
}

pub async fn categories_handler(
    AxumPath(course_id): AxumPath<String>,
    Extension(cache): Extension<Cache>,
) -> Result<Json<Vec<CategoryResponse>>, (StatusCode, String)> {
    if !SAFE_ID_PATTERN.is_match(&course_id) {
        return Err((StatusCode::BAD_REQUEST, "Invalid course ID".to_string()));
    }

    match cache.categories.get(&course_id) {
        Some(categories_json) => Ok((**categories_json).clone()),
        None => Err((StatusCode::NOT_FOUND, "Categories not found".to_string())),
    }
}

pub async fn tasks_handler(
    AxumPath((course_id, category_name)): AxumPath<(String, String)>,
    Extension(cache): Extension<Cache>,
) -> Result<Json<Vec<TaskResponse>>, (StatusCode, String)> {
    if !SAFE_ID_PATTERN.is_match(&course_id) || !SAFE_ID_PATTERN.is_match(&category_name) {
        return Err((
            StatusCode::BAD_REQUEST,
            "Invalid course or category ID".to_string(),
        ));
    }

    match cache.tasks.get(&(course_id, category_name)) {
        Some(tasks_json) => Ok((**tasks_json).clone()),
        None => Err((StatusCode::NOT_FOUND, "Tasks not found".to_string())),
    }
}
pub async fn get_task_metadata(
    AxumPath((course_id, category_name, task_id, uuid)): AxumPath<(String, String, String, String)>,
) -> Result<Json<TaskMetadataResponse>, (StatusCode, String)> {
    if !SAFE_ID_PATTERN.is_match(&course_id)
        || !SAFE_ID_PATTERN.is_match(&category_name)
        || !SAFE_ID_PATTERN.is_match(&task_id)
    {
        return Err((
            StatusCode::BAD_REQUEST,
            "Invalid course or category ID".to_string(),
        ));
    }
    // TODO!: add authentication check here

    let task_root = get_data_path()
        .join(COURSES_DIR)
        .join(&course_id)
        .join(&category_name)
        .join(&task_id);

    let output_path = task_root.join("output").join(&uuid);
    // Check task
    let output_exists = match fs::metadata(&output_path).await {
        Ok(meta) => meta.is_dir(),
        Err(_) => false,
    };

    // if not build it
    if !output_exists {
        let course_toml_path = get_data_path()
            .join(COURSES_DIR)
            .join(&course_id)
            .join("config.toml");
        let toml = read_toml(course_toml_path)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        let uuid = match Uuid::parse_str(&uuid) {
            Ok(uuid) => uuid,
            Err(_) => return Err((StatusCode::BAD_REQUEST, "Invalid UUID".to_string())),
        };
        let build_result = build_task(&toml, &task_root, &task_id, uuid).await;
        if let Err(err) = build_result {
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to build task: {err}"),
            ));
        }
    }

    let student_instructions_path = output_path.join("instructions.md");
    let instructions = if let Ok(content) = fs::read_to_string(&student_instructions_path).await {
        content
    } else {
        //TODO!: Add to checking the instructions exists in config check
        let universal_instructions_path = task_root.join("instructions.md");
        match fs::read_to_string(&universal_instructions_path).await {
            Ok(content) => content,
            Err(_) => String::from("No instructions available."),
        }
    };

    let mut files = Vec::new();
    let mut entries = match tokio::fs::read_dir(&output_path).await {
        Ok(e) => e,
        Err(_) => return Err((StatusCode::NOT_FOUND, "Output folder not found".into())),
    };

    while let Ok(Some(entry)) = entries.next_entry().await {
        let file_name = entry.file_name().to_string_lossy().into_owned();
        if file_name == "instructions.md" || file_name == "build-manifest.json" {
            continue;
        }
        let meta = entry.metadata().await.map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Could not read file metadata".into(),
            )
        })?;

        let modified = match entry.metadata().await {
            Ok(meta) => meta.modified().unwrap_or_else(|_| SystemTime::now()),
            Err(_) => SystemTime::now(),
        };

        let last_modified = match modified.duration_since(UNIX_EPOCH) {
            Ok(duration) => {
                let datetime = chrono::DateTime::<chrono::Utc>::from(UNIX_EPOCH + duration);
                datetime.to_rfc3339()
            }
            Err(_) => chrono::Utc::now().to_rfc3339(), // fallback in case of clock issues
        };

        files.push(FileMetadata {
            name: entry.file_name().to_string_lossy().to_string(),
            size: meta.len(),
            last_modified,
        });
    }
    Ok(Json(TaskMetadataResponse {
        instructions,
        files,
    }))
}

pub async fn download_file_handler(
    AxumPath((course_id, category_name, task_id, user_id, file_name)): AxumPath<(
        String,
        String,
        String,
        String,
        String,
    )>,
) -> Result<Response, (StatusCode, String)> {
    if !SAFE_ID_PATTERN.is_match(&course_id)
        || !SAFE_ID_PATTERN.is_match(&category_name)
        || !SAFE_ID_PATTERN.is_match(&task_id)
        || !SAFE_ID_PATTERN.is_match(&user_id)
    {
        return Err((StatusCode::BAD_REQUEST, "Invalid path".to_string()));
    }

    let task_root = get_data_path()
        .join(COURSES_DIR)
        .join(&course_id)
        .join(&category_name)
        .join(&task_id);

    let output_path = task_root.join("output").join(&user_id).join(&file_name);
    if !output_path.exists() {
        return Err((StatusCode::NOT_FOUND, "File not found".to_string()));
    }

    let file = File::open(&output_path).await.map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "File not found".to_string(),
        )
    })?;

    let mime_type = mime_guess::from_path(&output_path)
        .first_or_octet_stream()
        .to_string();

    let stream = ReaderStream::new(file);

    let response = Response::builder()
        .status(StatusCode::OK)
        .header(
            "Content-Disposition",
            format!("attachment; filename=\"{file_name}\""),
        )
        .header("Content-Type", mime_type)
        .body(Body::from_stream(stream))
        .map_err(|_| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to create response".to_string(),
            )
        })?;

    Ok(response)
}

pub async fn check_answer_handler(
    AxumPath((course_id, category_name, task_id, user_id)): AxumPath<(
        String,
        String,
        String,
        String,
    )>,
    Json(payload): Json<AnswerPayload>,
) -> Result<Json<CheckAnswerResponse>, (StatusCode, String)> {
    // Implement the database checking logic later
    if !SAFE_ID_PATTERN.is_match(&course_id)
        || !SAFE_ID_PATTERN.is_match(&category_name)
        || !SAFE_ID_PATTERN.is_match(&task_id)
        || !SAFE_ID_PATTERN.is_match(&user_id)
    {
        return Err((
            StatusCode::BAD_REQUEST,
            "Invalid course or category ID".to_string(),
        ));
    }

    let path = get_data_path()
        .join(COURSES_DIR)
        .join(&course_id)
        .join(&category_name)
        .join(&task_id)
        .join("output")
        .join(&user_id)
        .join("CorrectAnswer.txt");

    let correct_answer = fs::read_to_string(&path).await.map_err(|_| {
        (
            StatusCode::NOT_FOUND,
            "Correct Answer for task not found".to_string(),
        )
    })?;

    let correct = payload.answer.trim() == correct_answer.trim();

    Ok(Json(CheckAnswerResponse { correct }))
}
pub struct DataStructureResult {
    pub status: DataStructureStatus,
    pub cache: Cache,
}

pub enum DataStructureStatus {
    EmptyCoursesFolder,
    CoursesLoaded,
}
/// Initializes the directory structure for all available courses on the server.
///
/// # Returns
/// `Ok(DataStructureResult)` on successful structure generation or validation.
/// containing the status of the data structure and a cache of course metadata.
/// `Err(FileSystemError)` if any IO, config, or task-related errors occur.
///
/// # Errors
/// Returns a `FileSystemError` if:
/// - The base directory or subdirectories cannot be created
/// - A `config.toml` file is missing or invalid
/// - Reading directory entries fails
/// - One of the spawned async tasks encounters an error
pub async fn generate_data_structure() -> Result<DataStructureResult, FileSystemError> {
    // This function is a placeholder for generating the initial data structure.
    let path = get_data_path().join(COURSES_DIR);
    fs::create_dir_all(&path).await.map_err(|e| {
        FileSystemError::DataFolderError(format!(
            "Failed to create or access data path: {} because of {}",
            path.to_string_lossy(),
            e
        ))
    })?;

    let mut directories = fs::read_dir(&path).await.map_err(|e| {
        FileSystemError::CourseFolderError(format!("Failed to read courses directory: {e}"))
    })?;

    let mut join_set = JoinSet::new();
    let mut found_course = false;

    while let Some(entry) = directories.next_entry().await.map_err(|e| {
        FileSystemError::CourseFolderError(format!("Failed to read courses directory: {e}"))
    })? {
        let path = entry.path();
        if path.is_dir() {
            found_course = true;
            let config_path = path.join("config.toml");
            if config_path.exists() {
                join_set.spawn(async move {
                    let config = server_read_check_toml(config_path.as_os_str())
                        .await
                        .map_err(|e| FileSystemError::ConfigError(e.to_string()))?;
                    generate_course_structure(config.clone())
                        .await
                        .map_err(|e| FileSystemError::ConfigError(e.to_string()))?;
                    build_course_cache(config)
                        .await
                        .map_err(|e| FileSystemError::CacheError(e.to_string()))
                });
            } else {
                return Err(FileSystemError::ConfigError(format!(
                    "Config file not found in course directory: {}",
                    path.to_string_lossy()
                )));
            }
        }
    }
    let mut course_caches: Vec<CourseCache> = Vec::new();
    while let Some(res) = join_set.join_next().await {
        let course_cache = res.map_err(|e| FileSystemError::JoinError(e.to_string()))??;
        course_caches.push(course_cache);
    }
    let cache = precompute_json_cache(course_caches.clone())
        .await
        .map_err(|e| FileSystemError::CacheError(e.to_string()))?;
    let status = if found_course {
        DataStructureStatus::CoursesLoaded
    } else {
        DataStructureStatus::EmptyCoursesFolder
    };
    Ok(DataStructureResult { status, cache })
}
/// Generates the internal folder structure for a single course based on its configuration.
///
/// # Arguments
/// * `config` - A parsed `ModuleConfiguration` object representing the course's structure.
///
/// # Returns
/// `Ok(true)` on success, or `Err(FileSystemError)` if any directory creation fails.
///
/// # Example
/// ```rust
/// generate_course_structure(config).await?;
pub async fn generate_course_structure(
    config: ModuleConfiguration,
) -> Result<ModuleConfiguration, FileSystemError> {
    let path = get_data_path()
        .join(COURSES_DIR)
        .join(config.identifier.to_string());
    fs::create_dir_all(&path).await.map_err(|e| {
        FileSystemError::CourseFolderError(format!(
            "Failed to create course directory: {} because of {}",
            path.to_string_lossy(),
            e
        ))
    })?;

    for category in &config.categories {
        let category_dir = path.join(&category.name);
        fs::create_dir_all(&category_dir).await.map_err(|e| {
            FileSystemError::CategoryFolderError(format!(
                "Failed to create course category directory: {} because of {}",
                category_dir.to_string_lossy(),
                e
            ))
        })?;

        for task in &category.tasks {
            let task_dir = category_dir.join(&task.id);
            fs::create_dir_all(&task_dir).await.map_err(|e| {
                FileSystemError::TaskFolderError(format!(
                    "Failed to create course task directory: {} because of {}",
                    task_dir.to_string_lossy(),
                    e
                ))
            })?;

            let output_path = task_dir.join("output");
            fs::create_dir_all(&output_path).await.map_err(|e| {
                FileSystemError::OutputFolderError(format!(
                    "Failed to create course task output directory: {} because of {}",
                    output_path.to_string_lossy(),
                    e
                ))
            })?;
            // Check for entrypont?
        }
    }
    Ok(config)
}

/// Precomputes the JSON cache for the server based on the provided course structures.
/// Cache holds json API responses for courses, categories, and tasks.
pub async fn precompute_json_cache(courses: Vec<CourseCache>) -> Result<Cache, FileSystemError> {
    let precomputed_courses_json = {
        let courses_response: Vec<CourseResponse> = courses
            .iter()
            .map(|c| CourseResponse {
                id: c.id.to_string(),
                name: c.name.clone(),
                description: c.description.clone(),
            })
            .collect();
        Arc::new(Json(courses_response))
    };

    let mut category_json: HashMap<String, Arc<Json<Vec<CategoryResponse>>>> = HashMap::new();
    let mut task_json: HashMap<(String, String), Arc<Json<Vec<TaskResponse>>>> = HashMap::new();
    for course in &courses {
        let course_id_str = course.id.to_string();

        let categories_response: Vec<CategoryResponse> = course
            .categories
            .iter()
            .map(|cat| CategoryResponse {
                name: cat.name.clone(),
                number: cat.number,
            })
            .collect();
        category_json.insert(course_id_str.clone(), Arc::new(Json(categories_response)));

        for category in &course.categories {
            let tasks_response: Vec<TaskResponse> = category
                .tasks
                .iter()
                .map(|task| TaskResponse {
                    id: task.id.clone(),
                    name: task.name.clone(),
                    description: task.description.clone(),
                })
                .collect();

            task_json.insert(
                (course_id_str.clone(), category.name.clone()),
                Arc::new(Json(tasks_response)),
            );
        }
    }
    Ok(Cache {
        courses: precomputed_courses_json,
        categories: category_json,
        tasks: task_json,
    })
}

/// Builds a course cache for the server based on course structures.
/// Cache holds data data about courses, categories, and tasks that is used to build the API responses.
///
/// # Returns
/// CourseCache on success, or FileSystemError if any IO or parsing errors occur.
///
pub async fn build_course_cache(
    config: ModuleConfiguration,
) -> Result<CourseCache, FileSystemError> {
    let categories = config
        .categories
        .iter()
        .map(|cat| CategoryCache {
            name: cat.name.clone(),
            number: cat.number,
            tasks: cat
                .tasks
                .iter()
                .map(|task| TaskCache {
                    id: task.id.clone(),
                    name: task.name.clone(),
                    description: task.description.clone(),
                })
                .collect(),
        })
        .collect();

    Ok(CourseCache {
        id: config.identifier,
        name: config.name,
        description: config.description,
        categories,
    })
}

pub async fn handler_404() -> impl IntoResponse {
    let body = Json(json!({
        "error": "Not Found",
        "message": "The requested resource was not found on this server."
    }));

    (StatusCode::NOT_FOUND, body)
}
