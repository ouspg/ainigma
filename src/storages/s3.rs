use super::CloudStorage;
use super::FileObjects;
use crate::errors::AccessError;
use s3::{
    bucket::Bucket,
    creds::Credentials,
    serde_types::{BucketLifecycleConfiguration, Expiration, LifecycleRule},
    Region,
};
use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug)]
pub struct S3Storage {
    bucket: Box<Bucket>,
    life_cycle: BucketLifecycleConfiguration,
    link_expiration_days: u32,
}

impl S3Storage {
    /// Creates a new instance of `S3Storage`.
    pub fn new(
        bucket_name: String,
        region: Region,
        file_expiration_days: u32,
        link_expiration_days: u32,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        // We currently support only acquiring credentials from environment variables
        let access_key = env::var("AWS_ACCESS_KEY_ID")
            .map_err(|e| AccessError::MissingAccessKey(e.to_string()))?;
        let secret_key = env::var("AWS_SECRET_ACCESS_KEY")
            .map_err(|e| AccessError::MissingAccessKey(e.to_string()))?;
        let session_token = env::var("AWS_SESSION_TOKEN").ok();
        let credentials = Credentials::new(
            Some(&access_key),
            Some(&secret_key),
            session_token.as_deref(),
            None,
            None,
        )?;
        let expiraton = Expiration {
            date: None,
            days: Some(file_expiration_days),
            expired_object_delete_marker: None,
        };
        let rules = LifecycleRule::builder("Enabled")
            .expiration(expiraton)
            .id("Rule1");

        let life_cycle = BucketLifecycleConfiguration::new(vec![rules.build()]);

        let bucket = Bucket::new(&bucket_name, region, credentials)?;

        Ok(S3Storage {
            bucket,
            life_cycle,
            link_expiration_days,
        })
    }
    pub fn from_config(config: crate::config::Upload) -> Result<Self, Box<dyn std::error::Error>> {
        let region = Region::Custom {
            region: config.aws_region,
            endpoint: config.aws_s3_endpoint,
        };
        let link_expiration_days = config.link_expiration;
        S3Storage::new(
            config.bucket_name,
            region,
            config.file_expiration,
            link_expiration_days,
        )
    }
}

impl CloudStorage for S3Storage {
    // #[tracing::instrument]
    async fn upload(&self, files: FileObjects) -> Result<String, Box<dyn std::error::Error>> {
        //

        tracing::info!(
            "Starting to upload {} files in to the S3 bucket {} in path '{}'.",
            files.len(),
            self.bucket.name(),
            files.dst_location
        );
        let exists = self.bucket.exists().await?;
        if exists {
            tracing::info!("Bucket exists! Updating the bucket lifecycle.");
            let result = self
                .bucket
                .put_bucket_lifecycle(self.life_cycle.clone())
                .await?;
            tracing::info!("The result of the bucket lifecycle update: {:?}", result);
            // Upload the files
            let shared_map = Arc::new(Mutex::new(HashMap::<String, String>::with_capacity(
                files.len(),
            )));
            let mut tasks = Vec::with_capacity(files.len());
            for file in files.files {
                let shared_map = Arc::clone(&shared_map);
                let bucket = self.bucket.clone();
                // let bucket = self.bucket.clone();
                // let dst_location = files.dst_location.clone();
                let link_expiration_days = self.link_expiration_days;
                let file_key = format!("/{}/{}", files.dst_location, file.0);
                let task = tokio::spawn(async move {
                    match tokio::fs::read(&file.1).await {
                        Ok(bytes) => {
                            let response = bucket.put_object(&file_key, &bytes).await;
                            match response {
                                Ok(_) => {
                                    let pre_signed_url = bucket
                                        .presign_get(
                                            &file_key,
                                            link_expiration_days.wrapping_mul(43200),
                                            None,
                                        )
                                        .await;
                                    match pre_signed_url {
                                        Ok(url) => {
                                            tracing::info!("The pre-signed URL: {}", url);
                                            let mut map = shared_map.lock().await;
                                            map.insert(file_key, url);
                                        }
                                        Err(e) => {
                                            tracing::error!(
                                                "Failed to generate the pre-signed URL: {}",
                                                e
                                            );
                                        }
                                    }
                                }
                                Err(e) => {
                                    tracing::error!("Failed to upload the file: {}", e);
                                }
                            }
                        }
                        Err(e) => tracing::error!("Failed to read the file: {}", e),
                    }
                });
                tasks.push(task);
            }
            for task in tasks {
                task.await.unwrap();
            }
            let map = shared_map.lock().await;
            println!("{:#?}", *map);
        } else {
            tracing::error!("The bucket {} did not exist", self.bucket.name());
            return Ok("Not nice".to_string());
        }
        Ok("Nice!".to_string())
    }

    #[tracing::instrument]
    async fn get_url(&self, file_key: String) -> Result<String, Box<dyn std::error::Error>> {
        // Generate a pre-signed URL valid for 1 hour
        let url = self.bucket.presign_get(file_key, 3600, None).await?;
        Ok(url)
    }
}
#[cfg(test)]
mod tests {
    // use super::*;
    // use std::env;
    // use std::fs::File;
    // use std::io::Write;
    // Debugging with allas_conf:
    // nix-shell -p openstackclient s3cmd restic
    // source ./allas_conf -u <username> --mode S3

    #[tokio::test]
    async fn test_s3_storage() {
        let one = 1;
        assert_eq!(one, 1);
    }
}
