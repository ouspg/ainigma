use std::collections::HashMap;
use std::path::Path;

use crate::build_process::OutputItem;
use crate::errors::{CloudStorageError, FileObjectError};

/// Check for file traversal and unicode errors, just in case
/// Only check if the traversal does not go beyond the current working directory.
/// Returns the file name if the path is valid.
pub fn validate_file_path(base_path: &Path, file: &Path) -> Result<String, FileObjectError> {
    let canonical_base_path = base_path.canonicalize()?;
    let canonical_file_path = file.canonicalize()?;

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
    pub files: HashMap<String, OutputItem>,
}
impl FileObjects {
    /// Creates a new instance of `FileObjects`. Main purpose is to validate the input files path and that they exists.
    #[tracing::instrument]
    pub fn new(dst_location: String, files: Vec<OutputItem>) -> Result<Self, FileObjectError> {
        let mut file_map = HashMap::with_capacity(files.len());
        // Note that not safe if program is called higher up in the directory tree.
        let cwd = std::env::current_dir()?;
        for file in files {
            let file_name = validate_file_path(&cwd, file.kind.get_filename())?;
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
    /// Returns updated list of `OutputItem` with the URL of the uploaded files.
    async fn upload(&self, files: FileObjects) -> Result<Vec<OutputItem>, CloudStorageError>;
    /// Retrieves the URL of an uploaded file. Fily key is the fully qualified path in the remote.
    async fn get_url(&self, file_key: String) -> Result<String, Box<dyn std::error::Error>>;
}

#[cfg(test)]
mod tests {

    use super::*;

    #[test]
    fn test_filetraversal() {
        let base_path = Path::new("/tmp");
        let file = Path::new("/tmp/test123.txt");
        let result = validate_file_path(base_path, file);
        // File does not exist
        assert!(result.is_err());
        // Create the file
        std::fs::write(file, "test").unwrap();
        let result = validate_file_path(base_path, file);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "test123.txt");
        let file = Path::new("tmp/../../etc/passwd");
        let result = validate_file_path(base_path, file);
        assert!(result.is_err());
        // clean up
        std::fs::remove_file("/tmp/test123.txt").unwrap();
    }
}
