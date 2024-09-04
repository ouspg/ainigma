use autograder::{
    build_process::build_task,
    config::{read_check_toml, ConfigError},
};
use clap::{command, Parser, Subcommand};
use std::path::PathBuf;
use tracing::{debug, event, info, subscriber, Level};
use tracing_subscriber;
use uuid::Uuid;

/// Autograder CLI Application
#[derive(Parser)]
#[command(name = "Autograder", version = "1.0", about = "Cli for Autograder")]
pub struct Config {
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
        week: u8,
        #[arg(short, long)]
        task: Option<String>,
        #[command(subcommand)]
        moodle: Option<Moodle>,
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

fn main() {
    let collector = tracing_subscriber::fmt().finish();
    let cli = Config::parse();

    if !(cli.config.exists()) {
        tracing::error!("Given configuration file is not found");
        panic!("configuration file doesn't exist")
    } else {
        event!(Level::DEBUG, "Config file found");
        match &cli.command {
            Commands::Generate { week, task, moodle } => {
                if task.is_some() {
                    event!(
                        Level::DEBUG,
                        "Generating task {:?} for week {} with Moodle:{}",
                        task,
                        week,
                        moodle.is_some()
                    );
                } else {
                    event!(
                        Level::DEBUG,
                        "Generating tasks for week {} with Moodle:{}",
                        week,
                        moodle.is_some()
                    );
                }
                let cmd_moodle = moodle;
                match cmd_moodle {
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
                    None => match normal_build(cli.config, *week, task.clone()) {
                        Ok(()) => (),
                        Err(error) => eprintln!("{}", error),
                    },
                }
            }
        }
    }
}

fn normal_build(path: PathBuf, week: u8, task: Option<String>) -> Result<(), ConfigError> {
    event!(Level::INFO, "Normal build option selected");
    if task.is_some() {
        println!(
            "Generating task for week {} and task {}",
            &week,
            &task.as_ref().unwrap()
        );
        let result = read_check_toml(path.into_os_string().as_os_str())?;
        event!(Level::INFO, "Course configuration created successfully");
        let uuid = Uuid::now_v7();
        event!(Level::DEBUG, "Uuid created: {}", uuid.to_string());
        build_task(&result, task.unwrap(), uuid)
    } else {
        println!("Generating moodle task for week {}", &week);
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
    event!(Level::INFO, "Moodle build option selected");
    event!(
        Level::DEBUG,
        "Moodle building tasks for category {}, amount : {}",
        category,
        number
    );
    if task.is_some() {
        println!(
            "Generating {} category {} moodle task for week {} and task {}",
            &number,
            &category,
            &week,
            &task.as_ref().unwrap()
        );
        let result = read_check_toml(path.into_os_string().as_os_str())?;
        event!(
            Level::INFO,
            "Course configuration created and checked successfully"
        );
        let uuid = Uuid::now_v7();
        build_task(&result, task.unwrap(), uuid)
    } else {
        println!("Generating moodle task for week {}", &week);
        // TODO: Generating all tasks from one week
    }
    Ok(())
}

#[cfg(test)]
mod tests {}
