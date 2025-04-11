use crate::build_process::TaskBuildContainer;
use crate::config::ModuleConfiguration;
use crate::errors::CloudStorageError;
use crate::storages::s3::S3Storage;
use crate::storages::storage::{CloudStorage, FileObjects};
use tokio::runtime::Runtime;

pub fn s3_upload<'a>(
    config: &'a ModuleConfiguration,
    mut container: TaskBuildContainer<'a>,
    runtime: &Runtime,
) -> Result<TaskBuildContainer<'a>, Box<dyn std::error::Error>> {
    // Check if the bucket exists
    let storage = S3Storage::from_config(config.deployment.upload.clone());
    let storage = match storage {
        Ok(storage) => storage,
        Err(error) => {
            tracing::error!("Error when creating the S3 storage: {}", error);
            tracing::error!("Cannot continue with the file upload.");
            return Err(error);
        }
    };

    let mut tasks = Vec::with_capacity(container.outputs.len());

    let health = runtime.block_on(async {
        match storage.health_check().await {
            Ok(_) => Ok(()),
            Err(error) => {
                tracing::error!("Error when checking the health of the storage: {}", error);
                Err(error)
            }
        }
    });
    match health {
        Ok(_) => {}
        Err(e) => {
            tracing::error!("Cannot continue with the file upload.");
            return Err(e.into());
        }
    }
    tracing::info!(
        "Strating the file upload into the bucket: {}",
        config.deployment.upload.bucket_name.as_str()
    );

    for mut file in container.outputs {
        // TODO batch not supported yet
        let module_nro = config
            .get_category_number_by_task_id(&container.task.id)
            .unwrap_or_else(|| {
                panic!(
                    "Cannot find module number based on task '{}'",
                    container.task.id
                )
            });
        let dst_location = format!(
            "category{}/{}/{}",
            module_nro,
            container.task.id.trim_end_matches("/"),
            file.uuid
        );
        let future = async {
            match FileObjects::new(dst_location, file.get_resource_files())
                .map_err(CloudStorageError::FileObjectError)
            {
                Ok(files) => {
                    let items = storage
                        .upload(files, config.deployment.upload.use_pre_signed)
                        .await?;
                    file.update_files(items);
                    Ok(file)
                }
                Err(error) => {
                    tracing::error!("Error when creating the file objects: {}", error);
                    Err(error)
                }
            }
        };
        tasks.push(future);
    }
    let result = runtime.block_on(async { futures::future::try_join_all(tasks).await });
    match result {
        Ok(files) => {
            if !config.deployment.upload.use_pre_signed {
                let result = runtime.block_on(async { storage.set_public_access().await });
                match result {
                    Ok(_) => {}
                    Err(error) => {
                        tracing::error!("Error when setting the public access: {}", error);
                    }
                }
            }
            tracing::info!("All {} files uploaded successfully.", files.len());
            container.outputs = files;
            Ok(container)
        }
        Err(error) => {
            tracing::error!("Overall file upload process resulted with error: {}", error);
            tracing::error!("There is a chance that you are rate limited by the cloud storage. Please try again later.");
            Err(error.into())
        }
    }
}
