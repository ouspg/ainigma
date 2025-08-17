use ainigma_backend::{
    backend::{
        DataStructureStatus, categories_handler, generate_data_structure, get_task_metadata,
        handler_404, list_courses_handler, tasks_handler, download_file_handler
    },
    errors::filesystem::FileSystemError,
};
use axum::{Extension, Json, Router, routing::get};
use std::sync::Arc;
use std::net::SocketAddr;
use tracing_subscriber::{EnvFilter, fmt};

#[tokio::main]
async fn main() -> Result<(), Box<FileSystemError>> {
    init_logging();
    tracing::info!("Server is starting...");


    tracing::info!("Generating/Checking server data structure...");
    let data_structure_result = match generate_data_structure().await {
        Ok(result) => result,
        Err(e) => {
            tracing::error!("Failed to initialize data structure: {}", e);
            return Err(Box::new(e));
        }
    };
    match data_structure_result.status {
        DataStructureStatus::EmptyCoursesFolder => {
            tracing::warn!(
                "Inital data structure made successfully. Please add courses to the server."
            );
            return Ok(());
        }
        DataStructureStatus::CoursesLoaded => {
            tracing::info!("Data structure working with courses loaded.")
        }
    }

    let cache = Arc::new(data_structure_result.cache);

    let courses_router = Router::new()
        .route("/", get(list_courses_handler))
        .route("/{course_id}", get(categories_handler))
        .route("/{course_id}/{category_name}", get(tasks_handler))
        .route(
            "/{course_id}/{category_name}/{task_id}/{uuid}",
            get(get_task_metadata),
        )
        .route("/{course_id}/{category_name}/{task_id}/{uuid}/download/{file_name}", get(download_file_handler));

    let app = Router::new()
        .nest("/courses", courses_router)
        .route("/health", get(health_check))
        .layer(Extension(cache.clone()))
        .fallback(handler_404);

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    tracing::info!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(&addr).await.map_err(|e| {
        FileSystemError::BindError(format!(
            "Could not bind to address {addr}: {e}"
        ))
    })?;
    axum::serve(listener, app)
        .await
        .map_err(|e| FileSystemError::ServeError(format!("Server failed: {e}")))?;
    Ok(())
}

fn init_logging() {
    let log_level = std::env::var("RUST_LOG")
        .ok()
        .unwrap_or_else(|| "info".to_string());

    let filter_layer = EnvFilter::try_new(log_level).unwrap_or_else(|_| EnvFilter::new("info"));

    let fmt_layer = fmt::Subscriber::builder()
        .with_env_filter(filter_layer)
        .with_target(false)
        .with_thread_ids(true)
        .with_line_number(true)
        .with_file(true)
        .compact()
        .finish();

    tracing::subscriber::set_global_default(fmt_layer)
        .expect("Failed to set global tracing subscriber");
}

async fn health_check() -> Json<&'static str> {
    Json("OK")
}
