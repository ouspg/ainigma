use ainigma::{
    build_process::{build_batch, build_sequential, TaskBuildContainer},
    config::{read_check_toml, ModuleConfiguration, Task},
    errors::{BuildError, CloudStorageError},
    moodle::create_exam,
    storages::{CloudStorage, FileObjects, S3Storage},
};
use clap::{crate_description, Args, Parser, Subcommand};
use once_cell::sync::Lazy;
use std::{
    path::{Path, PathBuf},
    process::ExitCode,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
};

use tempfile::TempDir;
use tokio::runtime::Runtime;
use uuid::Uuid;

// Lazily create a single global Tokio runtime
static RUNTIME: Lazy<Runtime> =
    Lazy::new(|| Runtime::new().expect("Failed to create Tokio runtime"));

/// Autograder CLI Application
#[derive(Parser, Debug)]
#[command(name = "aínigma", version , about = "CLI for aínigma", long_about = crate_description!(), arg_required_else_help = true)]
pub struct OptsRoot {
    #[arg(short, long, value_name = "FILE")]
    config: PathBuf,
    #[command(subcommand)]
    command: Commands,
}

/// Generate command
#[derive(Subcommand, Debug)]
enum Commands {
    /// Build the specified tasks.
    #[command(arg_required_else_help = true)]
    Generate {
        /// The output directory where the build files will be stored. If not set, using temporary directory.
        /// Must exist and be writable if provided.
        #[arg(short, long, value_name = "DIRECTORY")]
        output_dir: Option<PathBuf>,
        #[command(flatten)]
        selection: BuildSelection,
        /// Moodle subcommand is used to automatically upload the files into the cloud storage and then generate a Moodle exam.
        #[command(subcommand)]
        moodle: Option<Moodle>,
        /// The number of build variants to generate
        #[arg(short, long, default_value_t = 1, group = "buildselection")]
        number: usize,
    },
    /// Attempt to upload previously built files to the cloud storage
    Upload {
        /// Check if the bucket exists
        #[arg(short, long)]
        check_bucket: bool,
    },
    /// Check if the configuration has correct syntax and pretty print it
    Validate {
        /// Check if the bucket exists
        #[arg(long, action = clap::ArgAction::SetTrue)]
        check_bucket: bool,
    },
    /// Designed to deploy the flags for a single challenge
    /// Generates flags in possible batch mode and runs build just once
    Deploy {
        /// The output directory where the build files will be stored. If not set, using temporary directory.
        /// Must exist and be writable if provided.
        #[arg(short, long, value_name = "DIRECTORY")]
        output_dir: Option<PathBuf>,
        #[command(flatten)]
        selection: BuildSelection,
    },
}

#[derive(Args, Debug)]
#[group(required = true, multiple = false)]
struct BuildSelection {
    /// Specify if you want to build a single task. Note that task IDs should be unique within the entire configuration
    #[arg(short, long, value_name = "IDENTIFIER")]
    task: Option<String>,
    /// Specify the category which will be built completely at once
    #[arg(short, long, value_name = "NUMBER")]
    category: Option<usize>,
}

#[derive(Debug, Subcommand)]
enum Moodle {
    Moodle {
        #[arg(short, long)]
        category: String,
        /// Output file name
        #[arg(short, long, default_value = "quiz.xml")]
        output: String,
    },
}

fn s3_upload(
    config: ModuleConfiguration,
    mut container: TaskBuildContainer,
) -> Result<TaskBuildContainer, Box<dyn std::error::Error>> {
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

    let health = RUNTIME.block_on(async {
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
    let result = RUNTIME.block_on(async { futures::future::try_join_all(tasks).await });
    match result {
        Ok(files) => {
            if !config.deployment.upload.use_pre_signed {
                let result = RUNTIME.block_on(async { storage.set_public_access().await });
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

#[derive(Debug)]
enum OutputDirectory {
    Temprarory(TempDir),
    Provided(PathBuf),
}
impl OutputDirectory {
    fn path(&self) -> &Path {
        match self {
            OutputDirectory::Temprarory(dir) => dir.path(),
            OutputDirectory::Provided(path) => path.as_path(),
        }
    }
}

fn output_dir_selection(output_dir: Option<&PathBuf>) -> Result<OutputDirectory, BuildError> {
    match output_dir {
        Some(output_dir) => {
            if !output_dir.exists() {
                Err(BuildError::InvalidOutputDirectory(format!(
                    "The provided output directory does not exist: {}",
                    output_dir.display()
                )))?
            } else if !output_dir.is_dir() {
                Err(BuildError::InvalidOutputDirectory(format!(
                    "The provided output directory is not a directory: {}",
                    output_dir.display()
                )))?
            } else {
                Ok(OutputDirectory::Provided(output_dir.to_path_buf()))
            }
        }
        None => {
            let temp_dir = match TempDir::new() {
                Ok(dir) => dir,
                Err(error) => Err(BuildError::TemporaryDirectoryFail(format!(
                    "Error when creating a temporal directory {}",
                    error
                )))?,
            };
            tracing::info!(
                "No output directory provided, using a temporal directory in path '{}'",
                temp_dir.path().display()
            );
            Ok(OutputDirectory::Temprarory(temp_dir))
        }
    }
}

fn main() -> std::process::ExitCode {
    let log_level = std::env::var("RUST_LOG")
        .ok()
        .and_then(|level| match level.to_lowercase().as_str() {
            "trace" => Some(tracing::Level::TRACE),
            "debug" => Some(tracing::Level::DEBUG),
            "info" => Some(tracing::Level::INFO),
            "warn" | "warning" => Some(tracing::Level::WARN),
            "error" => Some(tracing::Level::ERROR),
            _ => None,
        })
        .unwrap_or(tracing::Level::INFO); // Default to INFO if not specified or invalid

    // Global stdout subscriber for event tracing, configure based on env var
    let subscriber = tracing_subscriber::FmtSubscriber::builder()
        .with_max_level(log_level)
        .finish();
    tracing::subscriber::set_global_default(subscriber).unwrap();

    let cli = OptsRoot::parse();

    if !(cli.config.exists()) {
        tracing::error!(
            "Configuration file doesn't exist in path: {:?}",
            cli.config
                .to_str()
                .unwrap_or("The configuration file does not have valid path name. Broken Unicode or something else.")
        );
        ExitCode::FAILURE
    } else {
        let config = read_check_toml(cli.config.as_os_str());
        let config = match config {
            Ok(config) => config,
            Err(error) => {
                tracing::error!("Error when reading the configuration file: {}", error);
                return ExitCode::FAILURE;
            }
        };
        match &cli.command {
            Commands::Generate {
                output_dir,
                selection,
                number,
                moodle,
            } => {
                let output_dir = match output_dir_selection(output_dir.as_ref()) {
                    Ok(dir) => dir,
                    Err(error) => {
                        tracing::error!("Cannot create output directory: {}", error.to_string());
                        return ExitCode::FAILURE;
                    }
                };

                // Fail fast by checking if the task exists first
                let task_config = match &selection.task {
                    Some(ref task) => match config.get_task_by_id(task) {
                        Some(task_config) => task_config,
                        None => {
                            tracing::error!("Task ID not found: {task}");
                            return ExitCode::FAILURE;
                        }
                    },
                    None => {
                        // For category selections, we don't need task_config yet
                        // This branch will be handled separately in the outputs match below
                        // if let Some(_) = selection.category {
                        return ExitCode::SUCCESS;
                        // No task_config needed for category build
                        // }
                        // // We'll return early if neither task nor category is provided
                        // else {
                        //     todo!("Implement category build");
                        // }
                    }
                };

                let outputs = match selection.task {
                    Some(ref task) => {
                        tracing::info!(
                            "Building the task '{}' with the variation count {}",
                            &task,
                            number
                        );
                        // We already have task_config from above
                        match parallel_task_build(&config, &task_config, *number, output_dir.path())
                        {
                            Ok(out) => out,
                            Err(error) => {
                                tracing::error!("Error when building the task: {}", error);
                                return ExitCode::FAILURE;
                            }
                        }
                    }
                    None => match selection.category {
                        Some(_category) => {
                            todo!("Implement category build");
                        }
                        None => {
                            todo!("Implement category build");
                        }
                    },
                };
                match moodle {
                    Some(cmd_moodle) => match cmd_moodle {
                        Moodle::Moodle { category, output } => match selection.task {
                            Some(ref task) => {
                                let task_config = config.get_task_by_id(task);
                                match task_config {
                                    Some(_) => {
                                        let results = s3_upload(config.clone(), outputs).unwrap();
                                        let _examp = create_exam(results, category, output);
                                    }
                                    None => {
                                        tracing::error!(
                                            "Task identifier {} not found from the module configuration when generating the Moodle exam.", task
                                        );
                                        return ExitCode::FAILURE;
                                    }
                                }
                            }
                            None => {
                                tracing::error!(
                                    "Task must be specified when generating the Moodle exam."
                                );
                                return ExitCode::FAILURE;
                            }
                        },
                    },
                    None => {
                        match output_dir {
                            OutputDirectory::Temprarory(output_dir) => {
                                let path = output_dir.into_path();
                                tracing::info!(
                                    "The build has been finished and the files are located in the temporal output directory: {}",
                                    path.display()
                                );
                            }
                            OutputDirectory::Provided(path) => {
                                tracing::info!(
                                    "Build finished and the files are located in the provided output directory: {}",
                                    path.display()
                                );
                            }
                        }
                        return ExitCode::SUCCESS;
                    }
                }
                // Ensure that possible temporal directory is removed at this point, not earlier
                drop(output_dir);
                ExitCode::SUCCESS
            }
            Commands::Upload { check_bucket } => {
                if *check_bucket {
                    // let result = read_check_toml(cli.config.as_os_str());
                    // match result {
                    //     Ok(config) => {
                    //         let result = s3_upload(config, "files".into(), "mytestdir".into());
                    //         match result {
                    //             Ok(links) => {
                    //                 println!("{:#?}", links);
                    //             }
                    //             Err(error) => {
                    //                 tracing::error!("Error when uploading the files: {}", error);
                    //                 drop(error);
                    //                 std::process::exit(1);
                    //             }
                    //         }
                    //     }
                    //     Err(error) => {
                    //         tracing::error!("Error when reading the configuration file: {}", error);
                    //         drop(error);
                    //         std::process::exit(1);
                    //     }
                    // }
                }
                ExitCode::SUCCESS
            }
            Commands::Deploy {
                output_dir,
                selection,
            } => {
                let output_dir = match output_dir_selection(output_dir.as_ref()) {
                    Ok(dir) => dir,
                    Err(error) => {
                        tracing::error!("Cannot create output directory: {}", error.to_string());
                        return ExitCode::FAILURE;
                    }
                };

                // Fail fast by checking if the task exists first
                let task_config = match &selection.task {
                    Some(ref task) => match config.get_task_by_id(task) {
                        Some(task_config) => task_config,
                        None => {
                            tracing::error!("Task ID not found: {task}");
                            return ExitCode::FAILURE;
                        }
                    },
                    None => {
                        // For category selections, we don't need task_config yet
                        // This branch will be handled separately in the outputs match below
                        // if let Some(_) = selection.category {
                        return ExitCode::FAILURE;
                        // No task_config needed for category build
                        // }
                        // // We'll return early if neither task nor category is provided
                        // else {
                        //     todo!("Implement category build");
                        // }
                    }
                };

                let outputs = match build_batch(&config, &task_config, output_dir.path()) {
                    Ok(out) => vec![out],
                    Err(error) => {
                        tracing::error!("Error when building the task: {}", error);
                        return ExitCode::FAILURE;
                    }
                };
                dbg!(outputs);
                ExitCode::SUCCESS
            }
            Commands::Validate { .. } => {
                println!("{:#?}", config);

                ExitCode::SUCCESS
            }
        }
    }
}

fn parallel_task_build<'a>(
    config: &'a ModuleConfiguration,
    task_config: &'a Task,
    number: usize,
    output_dir: &'a Path,
) -> Result<TaskBuildContainer<'a>, BuildError> {
    let all_outputs = Arc::new(Mutex::new(Vec::with_capacity(number)));

    if number > 1 {
        let failure_occurred = Arc::new(AtomicBool::new(false));
        let mut handles = Vec::with_capacity(number);
        let course_config = Arc::new(config.clone());
        let task_config = Arc::new(task_config.clone());
        let output_dir = Arc::new(output_dir.to_path_buf());

        for i in 1..=number {
            let courseconf = Arc::clone(&course_config);
            let taskconf = Arc::clone(&task_config);
            let outputs = Arc::clone(&all_outputs);
            let outdir = Arc::clone(&output_dir);
            let failure_flag = Arc::clone(&failure_occurred);

            let handle = thread::spawn(move || {
                // Check if any thread has already failed
                if failure_flag.load(Ordering::SeqCst) {
                    tracing::info!("Skipping variant {} due to failure in another variant", i);
                    return Err(BuildError::ThreadError(format!(
                        "Stopping variant {} due to failure in another thread",
                        i
                    )));
                }

                tracing::info!("Starting building the variant {}", i);
                let uuid = Uuid::now_v7();

                match build_sequential(&courseconf, &taskconf, uuid, &outdir, i) {
                    Ok(output) => {
                        outputs
                            .lock()
                            .expect("Another thread panicked while owning the mutex when building the task.")
                            .push(output);
                        tracing::info!("Variant {} building finished.", i);
                        Ok(())
                    }
                    Err(error) => {
                        // Signal that a failure occurred
                        failure_flag.store(true, Ordering::SeqCst);
                        tracing::error!("Variant {} failed: {:?}", i, error);
                        Err(error)
                    }
                }
            });

            handles.push(handle);
        }

        // Join threads and collect results
        let mut first_error = None;

        for handle in handles {
            match handle.join() {
                Ok(thread_result) => {
                    if let Err(e) = thread_result {
                        // Save the first error we encounter
                        if first_error.is_none() {
                            first_error = Some(e);
                        }
                    }
                }
                Err(panic_error) => {
                    let error_msg = format!("Thread panicked: {:?}", panic_error);
                    tracing::error!("{}", error_msg);

                    if first_error.is_none() {
                        first_error = Some(BuildError::ThreadError(format!(
                            "Error when joining thread: {}",
                            error_msg
                        )));
                    }
                }
            }
        }

        // If any thread had an error, return it
        if let Some(error) = first_error {
            return Err(error);
        }
    } else {
        // Single variant case, no threading needed
        let uuid = Uuid::now_v7();
        match build_sequential(config, task_config, uuid, output_dir, 1) {
            Ok(outputs) => {
                all_outputs.lock().unwrap().push(outputs);
                tracing::info!("Task '{}' build successfully", task_config.id);
            }
            Err(error) => {
                return Err(error);
            }
        }
    }

    let vec = Arc::try_unwrap(all_outputs)
        .expect("There are still other Arc references when there should not")
        .into_inner()
        .expect("Mutex cannot be locked");

    Ok(TaskBuildContainer::new(
        output_dir.to_path_buf(),
        task_config,
        vec,
        false,
    ))
}
#[cfg(test)]
mod tests {}
