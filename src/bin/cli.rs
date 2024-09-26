use ainigma::{
    build_process::{build_task, TaskBuildProcessOutput},
    config::{read_check_toml, ConfigError, ModuleConfiguration},
    errors::CloudStorageError,
    moodle::create_exam,
    storages::{CloudStorage, FileObjects, S3Storage},
};
use clap::{crate_description, Args, Parser, Subcommand};
use once_cell::sync::Lazy;
use std::{
    path::{Path, PathBuf},
    process::ExitCode,
    sync::{Arc, Mutex},
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
    /// Check if the configuration has correct syntax and pretty print it
    #[arg(long, action = clap::ArgAction::SetTrue)]
    dry_run: Option<bool>,
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
    files: Vec<TaskBuildProcessOutput>,
) -> Result<Vec<TaskBuildProcessOutput>, Box<dyn std::error::Error>> {
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

    let mut tasks = Vec::with_capacity(files.len());

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

    for mut file in files {
        let module_nro = config
            .get_category_number_by_task_id(&file.task_id)
            .unwrap_or_else(|| {
                panic!("Cannot find module number based on task '{}'", file.task_id)
            });
        let dst_location = format!(
            "category{}/{}/{}",
            module_nro,
            file.task_id.trim_end_matches("/"),
            file.uiid
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
            Ok(files)
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

fn main() -> std::process::ExitCode {
    // Global stdout subscriber for event tracing, defaults to info level
    let subscriber = tracing_subscriber::FmtSubscriber::new();
    // let subscriber = tracing_subscriber::FmtSubscriber::builder()
    //     .with_max_level(tracing::Level::DEBUG) // Set log level to DEBUG
    //     .finish();
    tracing::subscriber::set_global_default(subscriber).unwrap();

    let cli = OptsRoot::parse();

    if !(cli.config.exists()) {
        tracing::error!(
            "Configuration file doesn't exist in path: {:?}",
            cli.config
                .to_str()
                .unwrap_or("The configuration file does not have valid path name. Broken Unicode or something else.")
        );
        std::process::exit(1);
    } else {
        match &cli.command {
            Commands::Generate {
                output_dir,
                selection,
                number,
                moodle,
            } => {
                let config = read_check_toml(cli.config.as_os_str());
                let config = match config {
                    Ok(config) => {
                        if selection.dry_run.unwrap_or(false) {
                            println!("{:#?}", config);
                            return ExitCode::SUCCESS;
                        } else {
                            config
                        }
                    }
                    Err(error) => {
                        tracing::error!("Error when reading the configuration file: {}", error);
                        return ExitCode::FAILURE;
                    }
                };
                let output_dir: OutputDirectory = match output_dir {
                    Some(output_dir) => {
                        if !output_dir.exists() {
                            tracing::error!(
                                "The provided output directory did not exist: {}",
                                output_dir.display()
                            );
                            return ExitCode::FAILURE;
                        } else if !output_dir.is_dir() {
                            tracing::error!(
                                "The provided output directory is not a directory: {}",
                                output_dir.display()
                            );
                            return ExitCode::FAILURE;
                        } else {
                            OutputDirectory::Provided(output_dir.to_path_buf())
                        }
                    }
                    None => {
                        let temp_dir = match TempDir::new() {
                            Ok(dir) => dir,
                            Err(error) => {
                                tracing::error!(
                                    "Error when creating a temporal directory: {}",
                                    error
                                );
                                return ExitCode::FAILURE;
                            }
                        };
                        tracing::info!(
                            "No output directory provided, using a temporal directory in path '{}'",
                            temp_dir.path().display()
                        );
                        OutputDirectory::Temprarory(temp_dir)
                    }
                };

                let outputs = match selection.task {
                    Some(ref task) => {
                        match parallel_task_build(&config, task, *number, output_dir.path()) {
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
                                    Some(task_config) => {
                                        let results = s3_upload(config, outputs).unwrap();
                                        let _examp =
                                            create_exam(&task_config, results, category, output);
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
                                    "Build has been finished and the files are located in the temporal output directory: {}",
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
        }
    }
}

fn parallel_task_build(
    config: &ModuleConfiguration,
    task: &str,
    number: usize,
    output_dir: &Path,
) -> Result<Vec<TaskBuildProcessOutput>, ConfigError> {
    tracing::info!(
        "Building the task '{}' with the variation count {}",
        &task,
        number
    );
    // Fail fast so check if the task exists alrady here
    let task_config = config
        .get_task_by_id(task)
        .ok_or_else(|| ConfigError::TaskIDNotFound(task.to_string()))?;
    let all_outputs = Arc::new(Mutex::new(Vec::with_capacity(number)));
    if number > 1 {
        let mut handles = Vec::with_capacity(number);
        let course_config = Arc::new(config.clone());
        let task_config = Arc::new(task_config);
        let output_dir = Arc::new(output_dir.to_path_buf());
        for i in 0..number {
            let courseconf = Arc::clone(&course_config);
            let taskconf = Arc::clone(&task_config);
            let outputs = Arc::clone(&all_outputs);
            let outdir = Arc::clone(&output_dir);
            let handle = thread::spawn(move || {
                tracing::info!("Starting building the variant {}", i + 1);
                let uuid = Uuid::now_v7();
                let output = build_task(&courseconf, &taskconf, uuid, &outdir);
                match output {
                    Ok(output) => {
                        outputs
                                .lock()
                                .expect(
                                    "Another thread panicked while owning the mutex when building the task.",
                                )
                                .push(output);
                    }
                    Err(error) => {
                        tracing::error!("Error when building the task: {}", error);
                    }
                }
                tracing::info!("Variant {} building finished.", i);
            });
            handles.push(handle)
        }
        // join multithreads together
        for handle in handles {
            handle.join().unwrap_or_else(|error| {
                tracing::error!(
                    "Error when joining the thread. Some files might not be built: {:?}",
                    error
                );
            })
        }
    } else {
        let uuid = Uuid::now_v7();
        let outputs = build_task(config, &task_config, uuid, output_dir).unwrap();
        all_outputs.lock().unwrap().push(outputs);
        tracing::info!("Task '{}' build succesfully", &task);
    }
    let vec = Arc::try_unwrap(all_outputs)
        .expect("There are still other Arc references when there should not")
        .into_inner()
        .expect("Mutex cannot be locked");

    Ok(vec)
}

#[cfg(test)]
mod tests {}
