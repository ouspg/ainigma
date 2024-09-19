use ainigma::{
    build_process::{build_task, TaskBuildProcessOutput},
    config::{read_check_toml, ConfigError, CourseConfiguration},
    storages::{CloudStorage, FileObjects, S3Storage},
};
use clap::{crate_description, Args, Parser, Subcommand};
use std::collections::HashMap;
use std::process::ExitCode;
use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
    thread,
};
use tokio::runtime::Runtime;
use uuid::Uuid;

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
        #[command(flatten)]
        selection: BuildSelection,
        /// Moodle subcommand is used to automatically upload the files into the cloud storage and generate Moodle exam.
        #[command(subcommand)]
        moodle: Option<Moodle>,
        /// The number of build variants to generate
        #[arg(short, long, default_value_t = 1, group = "buildselection")]
        number: usize,
    },
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
    /// Specify the week which will be built completely
    #[arg(short, long, value_name = "NUMBER")]
    week: Option<usize>,
    /// Check if the configuration has correct syntax and pretty print it
    #[arg(short, long, action = clap::ArgAction::SetTrue)]
    dry_run: Option<bool>,
}

#[derive(Debug, Subcommand)]
enum Moodle {
    Moodle {
        #[arg(short, long)]
        category: String,
    },
}

fn s3_upload(
    config: CourseConfiguration,
    src_dir: PathBuf,
    dst_dir: String,
) -> Result<HashMap<String, String>, Box<dyn std::error::Error>> {
    // Check if the bucket exists
    let storage = S3Storage::from_config(config.deployment.upload);
    let storage = match storage {
        Ok(storage) => storage,
        Err(error) => {
            tracing::error!("Error when creating the S3 storage: {}", error);
            tracing::error!("Cannot continue with the file upload.");
            return Err(error);
        }
    };

    let mut files = Vec::with_capacity(30);
    for file in src_dir.read_dir()? {
        let file = file.unwrap();
        files.push(file.path());
    }
    let mut links = <_>::default();
    match FileObjects::new(dst_dir, files) {
        Ok(files) => {
            let rt = Runtime::new().unwrap();
            rt.block_on(async {
                links = storage.upload(files).await.unwrap();
            });
        }
        Err(error) => {
            tracing::error!("Error when creating the file objects: {}", error);
        }
    }
    tracing::info!("Voila!");
    println!("{:#?}", links);
    Ok(links)
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
                selection,
                number,
                moodle: _,
            } => {
                if selection.dry_run.unwrap_or(false) {
                    let config = read_check_toml(cli.config.as_os_str());
                    match config {
                        Ok(config) => {
                            println!("{:#?}", config);
                        }
                        Err(error) => {
                            tracing::error!("Error when reading the configuration file: {}", error);
                            return ExitCode::FAILURE;
                        }
                    }
                }

                let outputs = match selection.task {
                    Some(ref task) => match parallel_task_build(cli.config, task, *number) {
                        Ok(out) => out,
                        Err(error) => {
                            tracing::error!("Error when building the task: {}", error);
                            return ExitCode::FAILURE;
                        }
                    },
                    None => match selection.week {
                        Some(_week) => {
                            todo!("Implement week build");
                        }
                        None => {
                            todo!("Implement week build");
                        }
                    },
                };
                dbg!(&outputs);
                // match moodle {
                //     Some(cmd_moodle) => match cmd_moodle {
                //         Moodle::Moodle { number, category } => {
                //             match moodle_build(
                //                 cli.config,
                //                 None,
                //                 Some("test"),
                //                 *number,
                //                 category.to_string(),
                //             ) {
                //                 Ok(()) => (),
                //                 Err(error) => eprintln!("{}", error),
                //             }
                //         }
                //     },
                //     None => match parallel_task_build(cli.config, "test", 30) {
                //         Ok(()) => (),
                //         Err(error) => eprintln!("{}", error),
                //     },
                // }
                ExitCode::SUCCESS
            }
            Commands::Upload { check_bucket } => {
                if *check_bucket {
                    let result = read_check_toml(cli.config.as_os_str());
                    match result {
                        Ok(config) => {
                            let result = s3_upload(config, "files".into(), "mytestdir".into());
                            match result {
                                Ok(links) => {
                                    println!("{:#?}", links);
                                }
                                Err(error) => {
                                    tracing::error!("Error when uploading the files: {}", error);
                                    drop(error);
                                    std::process::exit(1);
                                }
                            }
                        }
                        Err(error) => {
                            tracing::error!("Error when reading the configuration file: {}", error);
                            drop(error);
                            std::process::exit(1);
                        }
                    }
                }
                ExitCode::SUCCESS
            }
        }
    }
}

fn parallel_task_build(
    path: PathBuf,
    task: &str,
    number: usize,
) -> Result<Vec<TaskBuildProcessOutput>, ConfigError> {
    tracing::info!(
        "Building the task '{}' with the variation count {}",
        &task,
        number
    );
    let result = read_check_toml(path.into_os_string().as_os_str())?;
    let task_config = result
        .get_task_by_id(task)
        .ok_or_else(|| ConfigError::TaskIDNotFound(task.to_string()))?;
    let all_outputs = Arc::new(Mutex::new(Vec::with_capacity(number)));
    if number > 1 {
        let mut handles = Vec::with_capacity(number);
        let course_config = Arc::new(result);
        let task_config = Arc::new(task_config);
        for i in 0..number {
            let courseconf = Arc::clone(&course_config);
            let taskconf = Arc::clone(&task_config);
            let outputs = Arc::clone(&all_outputs);
            let handle = thread::spawn(move || {
                tracing::info!("Starting building the variant {}", i + 1);
                let uuid = Uuid::now_v7();
                let output = build_task(&courseconf, &taskconf, uuid);
                match output {
                    Ok(output) => {
                        outputs
                                .lock()
                                .expect(
                                    "Another thread paniced while owning the mutex when building the task.",
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
            handle.join().unwrap();
        }
    } else {
        let uuid = Uuid::now_v7();
        let outputs = build_task(&result, &task_config, uuid).unwrap();
        all_outputs.lock().unwrap().push(outputs);
        tracing::info!("Task '{}' build succesfully", &task);
    }
    let vec = Arc::try_unwrap(all_outputs)
        .expect("There are still other Arc references")
        .into_inner()
        .expect("Mutex cannot be locked");

    Ok(vec)
}
#[allow(dead_code)]
fn moodle_build(
    path: PathBuf,
    _week: Option<u8>,
    task: Option<&str>,
    number: usize,
    _category: String,
) -> Result<Vec<TaskBuildProcessOutput>, ConfigError> {
    match task {
        Some(task) => parallel_task_build(path, task, number),
        None => {
            todo!("Complete week build todo")
            // let _result = parallel_build(path, week, task, number);
        }
    }
}

#[cfg(test)]
mod tests {}
