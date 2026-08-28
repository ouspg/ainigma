mod database;
mod github;
mod invitations;
mod reconciliation;
mod repositories;

use clap::{Parser, Subcommand};
use invitations::InvitationMethod;
use sqlx::postgres::PgPoolOptions;
use std::{env, error::Error, time::Duration};
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(
    name = "ainigma-github-poller",
    about = "Reconcile manual GitHub course invitations"
)]
struct Arguments {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Send one idempotent GitHub organization invitation by email or stable user ID.
    Invite {
        #[arg(long)]
        course_id: Uuid,
        #[arg(long)]
        profile_id: Uuid,
        #[arg(long, value_enum, default_value_t = InvitationMethod::Email)]
        by: InvitationMethod,
    },
    /// Record a manually sent invitation found in GitHub's pending invitations.
    MarkInvited {
        #[arg(long)]
        course_id: Uuid,
        #[arg(long)]
        profile_id: Uuid,
        #[arg(long, value_enum, default_value_t = InvitationMethod::Email)]
        by: InvitationMethod,
    },
    /// Reconcile GitHub access and requested repositories once, or watch continuously.
    Poll {
        #[arg(long, default_value_t = false)]
        watch: bool,
        #[arg(long, default_value_t = 30)]
        interval_seconds: u64,
        #[arg(long)]
        course_id: Option<Uuid>,
        #[arg(long)]
        profile_id: Option<Uuid>,
    },
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt::init();

    let arguments = Arguments::parse();
    let database_url = required_env("DATABASE_URL")?;
    let database = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;

    match arguments.command {
        Command::Invite {
            course_id,
            profile_id,
            by,
        } => {
            let github_api_url = github::api_url();
            let github = github::client(&required_env("GITHUB_TOKEN")?)?;
            invitations::invite_one(
                &database,
                &github,
                &github_api_url,
                course_id,
                profile_id,
                by,
            )
            .await?;
            println!(
                "processed GitHub {by:?} invitation for course {course_id}, profile {profile_id}"
            );
        }
        Command::MarkInvited {
            course_id,
            profile_id,
            by,
        } => {
            let github_api_url = github::api_url();
            let github = github::client(&required_env("GITHUB_TOKEN")?)?;
            invitations::mark_invited(
                &database,
                &github,
                &github_api_url,
                course_id,
                profile_id,
                by,
            )
            .await?;
            println!(
                "marked GitHub invitation pending for course {course_id}, profile {profile_id}"
            );
        }
        Command::Poll {
            watch,
            interval_seconds,
            course_id,
            profile_id,
        } => {
            let github_api_url = github::api_url();
            let github = github::client(&required_env("GITHUB_TOKEN")?)?;
            loop {
                let count = reconciliation::poll_once(
                    &database,
                    &github,
                    &github_api_url,
                    course_id,
                    profile_id,
                )
                .await?;
                let repository_summary = repositories::provision_repositories(
                    &database,
                    &github,
                    &github_api_url,
                    course_id,
                    profile_id,
                )
                .await?;

                if !watch {
                    println!(
                        "reconciled {count} GitHub access record(s); {} requested repository job(s) became ready and {} recorded a failure",
                        repository_summary.ready, repository_summary.failed
                    );
                    break;
                }

                tokio::time::sleep(Duration::from_secs(interval_seconds.max(1))).await;
            }
        }
    }

    Ok(())
}

fn required_env(name: &str) -> Result<String, Box<dyn Error>> {
    env::var(name).map_err(|_| format!("{name} must be set").into())
}
