use thiserror::Error;

#[derive(Error, Debug)]
pub enum FileSystemError {
    #[error("Not found")]
    NotFound,
    #[error("Read error: {0}")]
    ReadError(String),
    #[error("Data folder error: {0}")]
    DataFolderError(String),
    #[error("Courses folder error: {0}")]
    CourseFolderError(String),
    #[error("Category folder error: {0}")]
    CategoryFolderError(String),
    #[error("Task folder error: {0}")]
    TaskFolderError(String),
    #[error("Output folder error: {0}")]
    OutputFolderError(String),
    #[error("Config error: {0}")]
    ConfigError(String),
    #[error("Error parsing the correct error: {0}")]
    JoinError(String),
    #[error("Failed to create course cache: {0}")]
    CacheError(String),
    #[error("Failed to bind to address {0}")]
    BindError(String),
    #[error("Server failed: {0}")]
    ServeError(String),
    #[error("Initialization error: {0}")]
    InitializationError(String),
}
