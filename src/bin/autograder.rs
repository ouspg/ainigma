use clap::{command, Parser, Subcommand};
use std::path::PathBuf;

/// Autograder CLI Application
#[derive(Parser)]
#[command(name = "Autograder", version = "1.0", about = "Cli for Autograder")]
pub struct Config {
    #[arg(short, long)]
    config: PathBuf,
    #[command(subcommand)]
    command: Commands,
}

/// Generate command
#[derive(Subcommand)]
enum Commands {
    /// Generate config with given week and optionally task
    Generate {
        #[arg(short, long)]
        week: u32,
        #[arg(short, long)]
        task: Option<String>,
        #[command(subcommand)]
        moodle: Option<Moodle>,
    },
}
#[derive(Debug, Subcommand)]
enum Moodle {
    /// Generate tasks for moodle
    Moodle {
        /// Number of task instances created for moodle
        #[arg(short, long)]
        number: u8,
    },
}

fn main() {
    let cli = Config::parse();

    match &cli.command {
        Commands::Generate { week, task, moodle } => {
            let cmd_moodle = moodle;

            match cmd_moodle {
                Some(cmd_moodle) => match cmd_moodle {
                    Moodle::Moodle { number } => println!(
                        // Task in Option format !!
                        " Generating {number:?} Moodle task for  week : {week:?}, task : {task:?}"
                    ),
                },

                None => {
                    // Task in Option format !!
                    println!(" Generating task for week : {week:?}, task : {task:?}")
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {}
