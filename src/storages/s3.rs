use super::CloudStorage;
use super::FileObjects;
use crate::build_process::OutputItem;
use crate::errors::{AccessError, CloudStorageError};
use futures::future::try_join_all;

use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::{config::Region, Client};
use serde_json::json;

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
        let conf_req: aws_sdk_s3::config::RequestChecksumCalculation =
            aws_sdk_s3::config::RequestChecksumCalculation::WhenRequired;
        let client_config = aws_sdk_s3::config::Builder::new()
            .endpoint_url(&config.aws_s3_endpoint)
            .region(region)
            .credentials_provider(credentials)
            .behavior_version_latest()
            .request_checksum_calculation(conf_req)
            .build();
        let link_expiration_days = config.link_expiration;
        let client = Client::from_conf(client_config);

        Ok(S3Storage {
            client,
            bucket: config.bucket_name.trim_end_matches("/").to_string(),
            link_expiration_days,
        })
    }
    /// Makes all files in the bucket available for download
    /// Does not give listing permissions
    pub async fn set_public_access(&self) -> Result<(), CloudStorageError> {
        // Modify with care, has potential security implications
        let json_policy = json!({
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "PublicReadGetObject",
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "s3:GetObject",
                    "Resource": format!("arn:aws:s3:::{}/*", self.bucket)
                }
            ]
        });
        let result = self
            .client
            .put_bucket_policy()
            .bucket(&self.bucket)
            .set_policy(Some(json_policy.to_string()))
            .send()
            .await;
        match result {
            Ok(_) => {
                tracing::info!(
                    "Updated the bucket policy successfully for '{}'.",
                    self.bucket
                );
                Ok(())
            }
            Err(e) => {
                tracing::error!("Failed to update the bucket policy: {}", e);
                Err(CloudStorageError::AWSSdkError(e.to_string()))?
            }
        }
    }
}

impl CloudStorage for S3Storage {
    async fn health_check(&self) -> Result<(), CloudStorageError> {
        let exist = self
            .client
            .get_bucket_location()
            .bucket(&self.bucket)
            .send()
            .await;
        match exist {
            Ok(resp) => {
                tracing::debug!("Bucket identified: {:?}!", resp);
                // TODO - Implement the lifecycle configuration
                // tracing::info!("The result of the bucket lifecycle update: {:?}", result);
                Ok(())
            }
            Err(e) => {
                tracing::warn!("The bucket likely {} did not exist or upstream connection issues, we expect currently that you have created it manually: {}", self.bucket, e);
                Err(CloudStorageError::BucketNotFound(self.bucket.to_owned()))
            }
        }
    }

    // #[tracing::instrument]
    async fn upload(
        &self,
        files: FileObjects,
        pre_signed_urls: bool,
    ) -> Result<Vec<OutputItem>, CloudStorageError> {
        tracing::debug!(
            "Starting to upload {} files in to the S3 bucket '{}' in path '{}'.",
            files.len(),
            self.bucket,
            files.dst_location
        );
        // Upload the files
        let shared_vec = Arc::new(Mutex::new(Vec::with_capacity(files.len())));
        let mut tasks = Vec::with_capacity(files.len());
        for mut file in files.files {
            let file_key = format!("{}/{}", files.dst_location.trim_end_matches("/"), file.0);
            // Use structured concurrency whenever possible
            // Avoid using tokio::spawn, as we lose the control
            tracing::debug!(
                "Uploading with remote file key: {} from local path : {}",
                file_key,
                file.1.kind.get_filename().to_string_lossy()
            );
            let body = ByteStream::from_path(file.1.kind.get_filename()).await;
            let task = async {
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
                                tracing::debug!(
                                    "Created or updated the file with expiration: {}",
                                    r.expiration.unwrap_or_default()
                                );
                                let presigned_request = self
                                    .client
                                    .get_object()
                                    .bucket(&self.bucket)
                                    .key(file_key)
                                    .presigned(
                                        PresigningConfig::expires_in(Duration::from_secs(
                                            // Days to seconds
                                            self.link_expiration_days.wrapping_mul(86400).into(),
                                        ))
                                        .unwrap(),
                                    )
                                    .await;
                                match presigned_request {
                                    Ok(url) => {
                                        if pre_signed_urls {
                                            tracing::debug!("The pre-signed URL: {}", url.uri());
                                            let mut vec = shared_vec.lock().await;
                                            file.1.set_link(url.uri().to_string());
                                            vec.push(file.1);
                                        } else {
                                            // strip the url by '?' to get the working public link in all scenarios
                                            let url = url
                                                .uri()
                                                .to_string()
                                                .split_once("?")
                                                .map(|(base, _)| base.to_string())
                                                .ok_or_else(|| {
                                                    CloudStorageError::UrlParseError(
                                                        "Failed to parse the pre-signed URL when constructing the public base by splitting with '?'.".to_string()
                                                    )
                                                })?;
                                            let mut vec = shared_vec.lock().await;
                                            file.1.set_link(url);
                                            vec.push(file.1);
                                        }
                                    }
                                    Err(e) => {
                                        tracing::error!(
                                            "Failed to generate the pre-signed URL: {}",
                                            e
                                        );
                                        return Err(CloudStorageError::AWSSdkError(e.to_string()));
                                    }
                                }
                            }
                            Err(e) => {
                                tracing::error!(
                                    "Failed to upload the file: {:?}",
                                    e.as_service_error()
                                );
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
        let upload_results = try_join_all(tasks).await;

        match upload_results {
            Ok(_) => {
                let mut vec = shared_vec.lock().await;
                tracing::debug!("Uploaded {} files successfully.", vec.len());
                Ok(core::mem::take(&mut vec))
            }
            Err(e) => {
                tracing::error!("Failed to upload the files: {}", e);
                Err(CloudStorageError::AWSSdkError(e.to_string()))
            }
        }
    }

    #[tracing::instrument]
    async fn get_url(&self, file_key: String) -> Result<String, Box<dyn std::error::Error>> {
        todo!("Implement the get_url method for S3 storage.")
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
