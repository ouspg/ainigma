use autograder::{
    build_process::build_task,
    config::{read_check_toml, ConfigError, CourseConfiguration},
    storages::{CloudStorage, FileObjects, S3Storage},
};
use clap::{command, Parser, Subcommand};
use std::collections::HashMap;
use std::{path::PathBuf, sync::Arc, thread};
use tokio::runtime::Runtime;
use uuid::Uuid;

/// Autograder CLI Application
#[derive(Parser)]
#[command(name = "aínigma", version = "1.0", about = "CLI for aínigma")]
pub struct RootArguments {
    #[arg(short, long, value_name = "FILE")]
    config: PathBuf,
    #[command(subcommand)]
    command: Commands,
}

/// Generate command
#[derive(Subcommand)]
enum Commands {
    /// Generate configuration
    Generate {
        #[arg(short, long)]
        dry_run: bool,
        #[arg(short, long)]
        week: u8,
        #[arg(short, long)]
        task: Option<String>,
        #[command(subcommand)]
        moodle: Option<Moodle>,
    },
    Upload {
        /// Check if the bucket exists
        #[arg(short, long)]
        check_bucket: bool,
    },
}
#[derive(Debug, Subcommand)]
enum Moodle {
    Moodle {
        #[arg(short, long)]
        number: u8,
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

fn main() {
    // Global stdout subscriber for event tracing, defaults to info level
    let subscriber = tracing_subscriber::FmtSubscriber::new();
    // let subscriber = tracing_subscriber::FmtSubscriber::builder()
    //     .with_max_level(tracing::Level::DEBUG) // Set log level to DEBUG
    //     .finish();
    tracing::subscriber::set_global_default(subscriber).unwrap();

    let cli = RootArguments::parse();

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
                dry_run,
                week,
                task,
                moodle,
            } => {
                if *dry_run {
                    // Just parse the config for now
                    tracing::info!("Dry run of generate...");
                    let config = read_check_toml(cli.config.as_os_str()).unwrap();
                    println!("{:#?}", config);
                }
                match moodle {
                    Some(cmd_moodle) => match cmd_moodle {
                        Moodle::Moodle { number, category } => {
                            match moodle_build(
                                cli.config,
                                *week,
                                task.clone(),
                                *number,
                                category.to_string(),
                            ) {
                                Ok(()) => (),
                                Err(error) => eprintln!("{}", error),
                            }
                        }
                    },
                    None => match parallel_build(cli.config, *week, task.clone(), 1) {
                        Ok(()) => (),
                        Err(error) => eprintln!("{}", error),
                    },
                }
            }
            Commands::Upload { check_bucket } => {
                if *check_bucket {
                    let result = read_check_toml(cli.config.as_os_str());
                    match result {
                        Ok(config) => {
                            let result = s3_upload(config, "".into(), "".into());
                            match result {
                                Ok(links) => {
                                    println!("{:#?}", links);
                                }
                                Err(error) => {
                                    eprintln!("{}", error);
                                }
                            }
                        }
                        Err(error) => {
                            tracing::error!("Error when reading the configuration file: {}", error);
                        }
                    }
                }
            }
        }
    }
}

fn parallel_build(
    path: PathBuf,
    week: u8,
    task: Option<String>,
    number: usize,
) -> Result<(), ConfigError> {
    if task.is_some() {
        tracing::info!(
            "Building the task {} for week {}. Variation count: {}",
            &task.as_ref().unwrap(),
            &week,
            number
        );
        let result = read_check_toml(path.into_os_string().as_os_str())?;
        let mut handles = Vec::with_capacity(number);
        let config = Arc::new(result);
        if number > 1 {
            for _i in 0..number {
                let courseconf = Arc::clone(&config);
                let task_clone = task.clone().unwrap();
                let handle = thread::spawn(move || {
                    let uuid = Uuid::now_v7();
                    let _outputs = build_task(&courseconf, task_clone.as_str(), uuid);
                });
                handles.push(handle)
            }
            // join multithreads together
            for handle in handles {
                handle.join().unwrap();
            }
        } else {
            let uuid = Uuid::now_v7();
            let outputs = build_task(&config, task.as_ref().unwrap(), uuid).unwrap();
            dbg!(outputs);
            tracing::info!("Task {} build succesfully", &task.unwrap_or_default());
        }

        // Ok(())
    } else {
        tracing::info!("Generating all Moodle tasks for week {}", &week);
        // TODO: Generating all tasks from one week
    }
    Ok(())
}
fn moodle_build(
    path: PathBuf,
    week: u8,
    task: Option<String>,
    number: u8,
    category: String,
) -> Result<(), ConfigError> {
    if task.is_some() {
        tracing::info!(
            "Generating {} category {} moodle task for week {} and task {}",
            &number,
            &category,
            &week,
            &task.as_ref().unwrap()
        );

        let result = read_check_toml(path.into_os_string().as_os_str())?;
        let mut handles = vec![];
        let config = Arc::new(result);
        for _i in 0..number {
            let courseconf = Arc::clone(&config);
            let task_clone = task.clone().unwrap();
            let handle = thread::spawn(move || {
                let uuid = Uuid::now_v7();
                let _ = build_task(&courseconf, task_clone.as_str(), uuid);
            });
            handles.push(handle)
        }
        // join multithreads together
        for handle in handles {
            handle.join().unwrap();
        }
    } else {
        tracing::info!("Generating moodle task for week {}", &week);
        // TODO: Generating all tasks from one week
    }
    Ok(())
}

#[cfg(test)]
mod tests {}
