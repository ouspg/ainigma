use thiserror::Error;

#[derive(Error, Debug)]
pub enum BuildError {
    #[error("Output directory {0} does not exist or is not valid.")]
    InvalidOutputDirectory(String),
    #[error("Temporary directory creationg failed: {0}")]
    TemporaryDirectoryFail(String),
    #[error("Expected output file {0} but did not find it.")]
    OutputVerificationFailed(String),
    #[error("Serde derserialization failed from output file {0}.")]
    SerdeDerserializationFailed(String),
}

impl From<serde_json::Error> for BuildError {
    fn from(err: serde_json::Error) -> BuildError {
        BuildError::SerdeDerserializationFailed(err.to_string())
    }
}
