use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("Invalid course UUID in configuration file")]
    UuidError,
    #[error("{message}")]
    TomlParseError { message: String },
    #[error("Course name cannot be empty in configuration")]
    CourseNameError,
    #[error("Course version is required and cannot be empty")]
    CourseVersionError,
    #[error("Category numbers must be unique across all categories")]
    CategoryNumberError,
    #[error("Task ID must be provided and cannot be empty")]
    TasksIDsNotUniqueError,
    #[error("Referenced task identifier not found: {0}")]
    TaskIDNotFound(String),
    #[error("Duplicate task ID detected - each task must have a unique identifier")]
    TaskCountError,
    #[error("Task name is required and cannot be empty")]
    TaskNameError,
    #[error("Task points must be a positive value or zero")]
    TaskPointError,
    #[error("Flag type must be one of: \"user_derived\", \"pure_random\", or \"rng_seed\"")]
    FlagTypeError,
    #[error("Duplicate flag ID detected - each flag must have a unique identifier")]
    FlagCountError,
    #[error("Stage incorrectly configured: {0}")]
    StageError(&'static str),
    #[error("Invalid build mode '{0}'. Available modes: [{1}]")]
    BuildModeError(String, String),
}
