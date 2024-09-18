use thiserror::Error;

#[derive(Error, Debug)]
pub enum FileObjectError {
    // Not unicode
    #[error("Filepath is not valid Unicode, lossy path: {filename} bytes: {path_bytes:?}")]
    InvalidUnicode {
        filename: String,
        path_bytes: Vec<u8>,
    },
    #[error("Filepath ending to '..', attempted path traversal with suffix? : {0}")]
    SuffixPathTraversal(String),
    #[error("Currently, all the upload files must be in the subdirectory relative the CWD. Filepath attempted path traversal with '..' or higher absolute path : {0}")]
    GeneralPathTraversal(String),
    /// file not exist
    #[error("File {0} does not exist")]
    InvalidFilePath(#[from] std::io::Error),
    #[error("Filenames were not unique! (name: {0})")]
    FilesNotUnique(String),
    #[error("invalid header (expected {expected:?}, found {found:?})")]
    InvalidHeader { expected: String, found: String },
    // Failed to get presigned URL
    #[error("Failed to get presigned URL{0}")]
    PresignedUrlFailure(String),
    #[error("unknown data store error")]
    Unknown,
}

#[derive(Error, Debug)]
pub enum CloudStorageError {
    #[error("Bucket not found: {0}")]
    BucketNotFound(String),
    // inner S3 error wrapped
    #[error("Inner S3 error: {0:?}")]
    S3Error(#[from] s3::error::S3Error),
}

#[derive(Error, Debug)]
pub enum AccessError {
    #[error("Access key not found: {0}")]
    MissingAccessKey(String),
}
