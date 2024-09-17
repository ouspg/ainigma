use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::errors::{CloudStorageError, FileObjectError};

/// Check for file traversal and unicode errors, just in case
/// Only check if the traversal does not go beyond the current working directory.
/// Returns the file name if the path is valid.
pub fn validate_file_path(base_path: &Path, file: &Path) -> Result<String, FileObjectError> {
    let canonical_base_path = base_path.canonicalize()?;
    let canonical_file_path = std::fs::canonicalize(file)?;

    if canonical_file_path.starts_with(&canonical_base_path) {
        let file_name = file
            .file_name()
            .ok_or_else(|| FileObjectError::SuffixPathTraversal(file.display().to_string()))?
            .to_str()
            .ok_or_else(|| FileObjectError::InvalidUnicode {
                filename: file.display().to_string(),
                path_bytes: file.as_os_str().as_encoded_bytes().to_vec(),
            })?
            .to_string();
        Ok(file_name)
    } else {
        Err(FileObjectError::GeneralPathTraversal(
            file.display().to_string(),
        ))
    }
}

/// A struct used to upload a collection of file objects at once to the service.
/// The `dst_location` is the destination, typically a directory in the storage service.
#[derive(Debug, Clone)]
pub struct FileObjects {
    /// Typically a directory in the storage service.
    pub dst_location: String,
    pub files: HashMap<String, PathBuf>,
}
impl FileObjects {
    /// Creates a new instance of `FileObjects`. Main purpose is to validate the input files path and that they exists.
    #[tracing::instrument]
    pub fn new(dst_location: String, files: Vec<PathBuf>) -> Result<Self, FileObjectError> {
        let mut file_map = HashMap::with_capacity(files.len());
        let cwd = std::env::current_dir()?;
        for file in files {
            let file_name = validate_file_path(&cwd, &file)?;
            if file_map.contains_key(&file_name) {
                return Err(FileObjectError::FilesNotUnique(format!(
                    "File {} already exists in the list",
                    file_name
                )));
            }
            file_map.insert(file_name, file);
        }
        Ok(Self {
            dst_location,
            files: file_map,
        })
    }
    pub fn len(&self) -> usize {
        self.files.len()
    }
    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }
}

#[allow(async_fn_in_trait)]
pub trait CloudStorage {
    /// Uploads all files from the `FileObjects` instance to the storage service.
    /// Returns HashMap with the filename and the URL.
    async fn upload(
        &self,
        files: FileObjects,
    ) -> Result<HashMap<String, String>, CloudStorageError>;
    /// Retrieves the URL of an uploaded file. Fily key is the fully qualified path in the remote.
    async fn get_url(&self, file_key: String) -> Result<String, Box<dyn std::error::Error>>;
}
