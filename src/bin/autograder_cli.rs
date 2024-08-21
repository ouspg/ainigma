use autograder::{
    build_process::build_task,
    config::{read_check_toml, ConfigError, CourseConfiguration},
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
    },
}

fn main() {
    let cli = Config::parse();

    if !(cli.config.exists()) {
        panic!("configurateion file doesn't exist")
    } else {
        match &cli.command {
            Commands::Generate { week, task, moodle } => {
                let cmd_moodle = moodle;
                match cmd_moodle {
                    Some(cmd_moodle) => match cmd_moodle {
                        Moodle::Moodle { number } => {
                            match moodle_build(cli.config, *week, task.clone(), *number) {
                                Ok(()) => (),
                                Err(error) => (), // error_handler(error),
                            }
                        }
                    },
                    None => {
                        println!(" Generating task for week : {week:?}, task : {task:?}")
                    }
                }
            }
        }
    }
}

fn moodle_build(
    path: PathBuf,
    week: u8,
    task: Option<String>,
    number: u8,
) -> Result<(), ConfigError> {
    if task.is_some() {
        println!(
            "Generating {} moodle task for week {} and task {}",
            &number,
            &week,
            &task.as_ref().unwrap()
        );
        let mut result = read_check_toml(path.into_os_string().as_os_str())?;
        let uuid = Uuid::now_v7();
        build_task(&mut result, task.unwrap(), uuid)
    } else {
        println!("Generating {} moodle task for week {}", &number, &week);
        // TODO: Generating all tasks from one week
    }
    Ok(())
}
///
/// fn error_handler(error: ConfigError) {
///    match error {
///        ConfigError::UuidError => println!("Error in Toml file: Course Uuid must be valid"),
///        ConfigError::CourseNameError => println!("Error in Toml file: Course name must not be empty"),
///    }
/// }
///

#[cfg(test)]
mod tests {}
