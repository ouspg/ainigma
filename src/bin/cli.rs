use autograder::config::CourseConfiguration;
use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
pub struct Autograder {
    #[arg(short, long)]
    config: String,
    #[clap(subcommand)]
    cmd: Generate,
}
struct Generate {
    #[arg(short, long)]
    week: u8,
    #[arg(short, long)]
    task: String,

    #[command(subcommand)]
    cmd: Builder,
}

fn main() {
    let path = std::env::args().nth(1).expect("no path given");

    let config_args = Autograder.parse();
}
