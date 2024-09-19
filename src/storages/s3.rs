use super::CloudStorage;
use super::FileObjects;
use crate::errors::{AccessError, CloudStorageError};
use futures::future::try_join_all;

use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::{config::Region, Client};
use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

#[derive(Debug)]
pub struct S3Storage {
    client: Client,
    bucket: String,
    // life_cycle: BucketLifecycleConfiguration,
    link_expiration_days: u32,
}

impl S3Storage {
    pub fn from_config(config: crate::config::Upload) -> Result<Self, Box<dyn std::error::Error>> {
        let access_key = env::var("AWS_ACCESS_KEY_ID").map_err(|e| {
            AccessError::MissingAccessKey(
                "AWS_ACCESS_KEY_ID - ".to_owned() + e.to_string().as_str(),
            )
        })?;
        let secret_key = env::var("AWS_SECRET_ACCESS_KEY").map_err(|e| {
            AccessError::MissingAccessKey(
                "AWS_SECRET_ACCESS_KEY - ".to_owned() + e.to_string().as_str(),
            )
        })?;
        let session_token = env::var("AWS_SESSION_TOKEN").ok();
        let credentials = aws_sdk_s3::config::Credentials::new(
            access_key,
            secret_key,
            session_token,
            None,
            "The Provider",
        );
        let region = Region::new(config.aws_region);
        let client_config = aws_sdk_s3::config::Builder::new()
            .endpoint_url(config.aws_s3_endpoint)
            .region(region)
            .credentials_provider(credentials)
            .behavior_version_latest()
            .build();
        let link_expiration_days = config.link_expiration;
        let client = Client::from_conf(client_config);

        Ok(S3Storage {
            client,
            bucket: config.bucket_name,
            link_expiration_days,
        })
    }
}

impl CloudStorage for S3Storage {
    // #[tracing::instrument]
    async fn upload(
        &self,
        files: FileObjects,
    ) -> Result<HashMap<String, String>, CloudStorageError> {
        tracing::info!(
            "Starting to upload {} files in to the S3 bucket '{}' in path '{}'.",
            files.len(),
            self.bucket,
            files.dst_location
        );

        let exists = self
            .client
            .get_bucket_location()
            .bucket(&self.bucket)
            .send()
            .await;
        match exists {
            Ok(resp) => {
                tracing::info!(
                    "Bucket identified: {:?}! Updating the bucket lifecycle.",
                    resp
                );
                // tracing::info!("The result of the bucket lifecycle update: {:?}", result);
                // Upload the files
                let shared_map = Arc::new(Mutex::new(HashMap::<String, String>::with_capacity(
                    files.len(),
                )));
                let mut tasks = Vec::with_capacity(files.len());
                for file in files.files {
                    let file_key = format!("{}/{}", files.dst_location, file.0);
                    // Use structured concurrency whenever possible
                    // Avoid using tokio::spawn, as we lose the control
                    let task = async {
                        let body = ByteStream::from_path(file.1).await;
                        match body {
                            Ok(b) => {
                                let response = self
                                    .client
                                    .put_object()
                                    .bucket(&self.bucket)
                                    .key(&file_key)
                                    .body(b)
                                    .send()
                                    .await;
                                match response {
                                    Ok(r) => {
                                        tracing::info!(
                                            "Created or updated the file with expiration: {}",
                                            r.expiration.unwrap_or_default()
                                        );
                                        let presigned_request = self
                                            .client
                                            .get_object()
                                            .bucket(&self.bucket)
                                            .key(&file_key)
                                            .presigned(
                                                PresigningConfig::expires_in(Duration::from_secs(
                                                    // Days to seconds
                                                    self.link_expiration_days
                                                        .wrapping_mul(86400)
                                                        .into(),
                                                ))
                                                .unwrap(),
                                            )
                                            .await;
                                        match presigned_request {
                                            Ok(url) => {
                                                tracing::debug!(
                                                    "The pre-signed URL: {}",
                                                    url.uri()
                                                );
                                                let mut map = shared_map.lock().await;
                                                map.insert(file_key, url.uri().to_string());
                                            }
                                            Err(e) => {
                                                tracing::error!(
                                                    "Failed to generate the pre-signed URL: {}",
                                                    e
                                                );
                                                return Err(CloudStorageError::AWSSdkError(
                                                    e.to_string(),
                                                ));
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to upload the file: {}", e);
                                        return Err(CloudStorageError::AWSSdkError(e.to_string()));
                                    }
                                }
                            }
                            Err(e) => {
                                tracing::error!("Failed to read the file: {}", e);
                                return Err(CloudStorageError::FileReadError(e.to_string()));
                            }
                        }
                        Ok(())
                    };
                    tasks.push(task);
                }
                let result = try_join_all(tasks).await;
                match result {
                    Ok(_) => {
                        let mut map = shared_map.lock().await;
                        tracing::info!("Uploaded {} files successfully.", map.len());
                        Ok(core::mem::take(&mut map))
                    }
                    Err(e) => {
                        tracing::error!("Failed to upload the files: {}", e);
                        Err(CloudStorageError::AWSSdkError(e.to_string()))
                    }
                }
            }
            Err(e) => {
                tracing::warn!("The bucket likely {} did not exist, we expect currently that you have created it manually: {}", self.bucket, e);
                Err(CloudStorageError::BucketNotFound(self.bucket.to_owned()))
            }
        }
    }

    #[tracing::instrument]
    async fn get_url(&self, file_key: String) -> Result<String, Box<dyn std::error::Error>> {
        // Generate a pre-signed URL valid for 1 hour
        // let url = self.bucket.presign_get(file_key, 3600, None).await?;
        Ok("OK".to_string())
    }
}
#[cfg(test)]
mod tests {
    // Debugging with allas_conf:
    // nix-shell -p openstackclient s3cmd restic
    // source ./allas_conf -u <username> --mode S3

    #[tokio::test]
    async fn test_s3_storage() {
        let one = 1;
        assert_eq!(one, 1);
    }
}
