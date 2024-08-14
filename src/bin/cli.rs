use autograder::config::CourseConfiguration;
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
    /// Generate config
    Generate {
        #[arg(short, long)]
        week: u32,
        #[arg(short, long)]
        task: Option<u32>,
        #[command(subcommand)]
        moodle: Option<Moodle>,
    },
}
#[derive(Debug, Subcommand)]
enum Moodle {
    Moodle { number: u8 },
}

fn main() {
    let cli = Config::parse();

    match &cli.command {
        Commands::Generate { week, task, moodle } => {
            let cmd_moodle = moodle;

            match cmd_moodle {
                Some(cmd_moodle) => match cmd_moodle {
                    Moodle::Moodle { number } => println!(
                        " Generating {number:?} Moodle task for  week : {week:?}, task : {task:?}"
                    ),
                },

                None => {
                    println!(" Generating task for week : {week:?}, task : {task:?}")
                }
            }
        }
    }
}
