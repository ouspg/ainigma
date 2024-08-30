use autograder::{
    build_process::build_task,
    config::{read_check_toml, ConfigError},
};
use clap::{command, Parser, Subcommand};
use std::path::PathBuf;
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
    /// Generate config
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
    let cli = Config::parse();

    if !(cli.config.exists()) {
        panic!("configuration file doesn't exist")
    } else {
        match &cli.command {
            Commands::Generate { week, task, moodle } => {
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
    if task.is_some() {
        println!(
            "Generating task for week {} and task {}",
            &week,
            &task.as_ref().unwrap()
        );
        let mut result = read_check_toml(path.into_os_string().as_os_str())?;
        let uuid = Uuid::now_v7();
        build_task(&mut result, task.unwrap(), uuid)
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
    if task.is_some() {
        println!(
            "Generating {} category {} moodle task for week {} and task {}",
            &number,
            &category,
            &week,
            &task.as_ref().unwrap()
        );
        let mut result = read_check_toml(path.into_os_string().as_os_str())?;
        let uuid = Uuid::now_v7();
        //TODO: Generating moodle tasks
    } else {
        println!("Generating moodle task for week {}", &week);
        // TODO: Generating all tasks from one week
    }
    Ok(())
}

#[cfg(test)]
mod tests {}
