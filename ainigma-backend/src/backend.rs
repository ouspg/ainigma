use ainigma::config::{ModuleConfiguration, Task, read_toml};
use std::fs;
use std::path::Path;
use uuid::Uuid;

const DATA_PATH: &str = "/srv/ainigma/data";
const COURSES_DIR: &str = "courses";

pub async fn get_task() -> Result<bool, std::io::Error> {
    // This function is a placeholder for fetching a task information to display.
    Ok(true)
}

pub async fn find_course_config(course_id: Uuid) -> Result<ModuleConfiguration, std::io::Error> {
    // TODO: CHECK RACE CONDITION (Locking the directory)
    let courses_path = Path::new(DATA_PATH).join(COURSES_DIR);
    let course_string = course_id.to_string();

    for entry in fs::read_dir(&courses_path)? {
        let entry = entry?;
        let path = entry.path();

        if let Some(folder_name) = path.file_name().and_then(|n| n.to_str()) {
            if path.is_dir() && folder_name == course_string.as_str() {
                let config_path = path.join("config.toml");
                if config_path.exists() {
                    // course config need to be valid
                    let config = read_toml(config_path)
                        .expect("All course configs should be valid so they should read correctly");
                    return Ok(config);
                }
            }
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::NotFound,
        format!("Course with id {course_id} not found"),
    ))
}

pub async fn find_task(
    course: ModuleConfiguration,
    task_id: String,
) -> Result<Task, std::io::Error> {
    // Searches for a task in the course configuration
    let task = course.get_task_by_id(task_id.as_str());
    if let Some(task) = task {
        return Ok(task.clone());
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::NotFound,
        format!("Task with id {task_id} not found in course"),
    ))
}

pub async fn compareanswer(
    course_id: Uuid,
    task_id: String,
    user_id: Uuid,
    answer: String,
) -> Result<bool, std::io::Error> {
    // Compares the user's answer with the correct answer from database
    Ok(false) // Placeholder for actual comparison logic
}
