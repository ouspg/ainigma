use std::sync::Arc;

use ainigma_backend::backend::{
    Cache, categories_handler, download_file_handler, generate_data_structure,
    get_task_metadata, handler_404, list_courses_handler, tasks_handler,
};
use axum::{Extension, Json, Router, routing::get};
use reqwest::Client;
use tokio::{net::TcpListener, task};

pub fn create_app(cache: Arc<Cache>) -> Router {
    let courses_router = Router::new()
        .route("/", get(list_courses_handler))
        .route("/{course_id}", get(categories_handler))
        .route("/{course_id}/{category_name}", get(tasks_handler))
        .route(
            "/{course_id}/{category_name}/{task_id}/{uuid}",
            get(get_task_metadata),
        )
        .route(
            "/{course_id}/{category_name}/{task_id}/{uuid}/download/{file_name}",
            get(download_file_handler),
        );

    Router::new()
        .nest("/courses", courses_router)
        .route("/health", get(health_check))
        .layer(Extension(cache.clone()))
        .fallback(handler_404)
}

async fn health_check() -> Json<&'static str> {
    Json("OK")
}

#[tokio::test]
async fn test_full_server_with_dummy_task() {
    // Setup course data
    let _ = tracing_subscriber::fmt()
        .with_env_filter("debug")
        .try_init();

    let cwd = std::env::current_dir().expect("current dir");
    tracing::info!("Current working directory: {:?}", cwd);

    let data_path = cwd.join("tests/data");
    tracing::info!("Data path: {:?}", data_path);

    let output_dir = cwd.join("tests/data/courses/01908498-ac98-708d-b886-b6f2747ef785/Network_Security_Fundamentals/task001/output/01908498-ac98-708d-b886-b6f2747ef785");

    unsafe {
        std::env::set_var("AINIGMA_DATA_PATH", data_path);
    }
    let result = generate_data_structure().await.expect("structure");
    let cache = Arc::new(result.cache);
    let app = create_app(cache);

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let server = task::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let url = format!(
        "http://{addr}/courses/01908498-ac98-708d-b886-b6f2747ef785/Network_Security_Fundamentals/task001/01908498-ac98-708d-b886-b6f2747ef785"
    );

    let res = Client::new()
        .get(&url)
        .send()
        .await
        .expect("request failed");

    let status = res.status();
    let body = res
        .text()
        .await
        .unwrap_or_else(|_| "<failed to read body>".to_string());

    if !status.is_success() {
        eprintln!("Request failed: status = {status}, body = {body}");
    }
    assert!(status.is_success());

    println!("Response body:\n{body}");

    let json: serde_json::Value =
        serde_json::from_str(&body).expect("Failed to parse JSON response");

    assert_eq!(json["instructions"], "No instructions available.");

    let files = json["files"].as_array().expect("files should be an array");
    let filenames: Vec<&str> = files
        .iter()
        .map(|file| file["name"].as_str().unwrap())
        .collect();

    let expected_files = vec!["readme.txt", "secret.sh"];

    for expected in expected_files {
        assert!(
            filenames.contains(&expected),
            "Expected file '{expected}' missing in response"
        );
    }

    if output_dir.exists() {
        tracing::info!("Cleaning output directory after test");
        tokio::fs::remove_dir_all(&output_dir)
            .await
            .expect("Failed to clean output directory");
    }

    // Optionally shutdown the server by dropping
    drop(server);
}

#[tokio::test]
async fn test_server_download() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter("debug")
        .try_init();

    let cwd = std::env::current_dir().expect("current dir");
    tracing::info!("Current working directory: {:?}", cwd);

    let data_path = cwd.join("tests/data");
    tracing::info!("Data path: {:?}", data_path);

    unsafe {
        std::env::set_var("AINIGMA_DATA_PATH", data_path);
    }

    let result = generate_data_structure().await.expect("structure");
    let cache = Arc::new(result.cache);
    let app = create_app(cache);

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let server = task::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let course_id = "01908498-ac98-708d-b886-b6f2747ef785";
    let category_name = "Network_Security_Fundamentals";
    let task_id = "task002";
    let uuid = "01908498-ac98-708d-b886-b6f2747ef785";
    let file_name = "readme.txt";

    let url = format!(
        "http://{addr}/courses/{course_id}/{category_name}/{task_id}/{uuid}/download/{file_name}"
    );

    let res = Client::new()
        .get(&url)
        .send()
        .await
        .expect("request failed");

    assert!(res.status().is_success(), "Download failed");

    let content_type = res
        .headers()
        .get("content-type")
        .expect("Missing Content-Type header")
        .to_str()
        .unwrap()
        .to_string();

    let body = res.bytes().await.expect("Failed to read response body");

    let path = cwd.join(format!(
        "tests/data/courses/{course_id}/{category_name}/{task_id}/output/{uuid}/{file_name}"
    ));
    let expected_mime = mime_guess::from_path(&path);

    let guess = expected_mime.first_or_octet_stream();

    let mime_str = guess.essence_str().to_string();

    let content = String::from_utf8_lossy(&body);

    assert_eq!(content_type, mime_str, "MIME type mismatch");

    let expected_body = "File download success";

    assert_eq!(content, expected_body, "Downloaded file contents mismatch");

    drop(server)
}
