use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::errors::FileObjectError;

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
        for file in files {
            let file_name = file
                .file_name()
                .ok_or_else(|| FileObjectError::SuffixPathTraversal(file.display().to_string()))?
                .to_str()
                .ok_or_else(|| FileObjectError::InvalidUnicode {
                    filename: file.display().to_string(),
                    path_bytes: file.as_os_str().as_encoded_bytes().to_vec(),
                })?
                .to_string();
            file.try_exists()
                .map_err(FileObjectError::InvalidFilePath)?;
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
    /// Returns HashMap with the filename and presigned URL.
    async fn upload(&self, files: FileObjects) -> Result<String, Box<dyn std::error::Error>>;
    /// Retrieves the URL of an uploaded file.
    async fn get_url(&self, file_key: String) -> Result<String, Box<dyn std::error::Error>>;
}
