mod database;
mod github;
mod http;
mod invitations;
mod platform;
mod reconciliation;
mod repositories;

use clap::{Parser, Subcommand};
use invitations::InvitationMethod;
use sqlx::postgres::PgPoolOptions;
use std::{env, error::Error, time::Duration};
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(
    name = "ainigma-course-access-worker",
    about = "Start external course invitations and reconcile course access"
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
        /// Override the target email for an approved profile. The address is
        /// domain-limited and recorded as the invitation target.
        #[arg(long)]
        email: Option<String>,
        #[arg(long, value_enum, default_value_t = InvitationMethod::Email)]
        by: InvitationMethod,
    },
    /// Record a manually sent invitation found in GitHub's pending invitations.
    MarkInvited {
        #[arg(long)]
        course_id: Uuid,
        #[arg(long)]
        profile_id: Uuid,
        /// Override the target email when adopting a manually sent invitation.
        #[arg(long)]
        email: Option<String>,
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
            email,
            by,
        } => {
            let github = github::GithubPlatform::from_env().await?;
            if email.is_some() && by != InvitationMethod::Email {
                return Err("--email can only be used with --by email".into());
            }
            invitations::invite_one_with_email(
                &database,
                &github,
                course_id,
                profile_id,
                by,
                email.as_deref(),
            )
            .await?;
            println!(
                "processed GitHub {by:?} invitation for course {course_id}, profile {profile_id}"
            );
        }
        Command::MarkInvited {
            course_id,
            profile_id,
            email,
            by,
        } => {
            let github = github::GithubPlatform::from_env().await?;
            if email.is_some() && by != InvitationMethod::Email {
                return Err("--email can only be used with --by email".into());
            }
            invitations::mark_invited_with_email(
                &database,
                &github,
                course_id,
                profile_id,
                by,
                email.as_deref(),
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
            let github = github::GithubPlatform::from_env().await?;
            loop {
                let invitation_summary =
                    invitations::invite_pending(&database, &github, course_id, profile_id).await?;
                let count =
                    reconciliation::poll_once(&database, &github, course_id, profile_id).await?;
                let repository_summary =
                    repositories::provision_repositories(&database, &github, course_id, profile_id)
                        .await?;

                if !watch {
                    println!(
                        "processed {} invitation(s), recorded {} invitation failure(s), reconciled {count} GitHub access record(s); {} requested repository job(s) became ready and {} recorded a failure",
                        invitation_summary.started,
                        invitation_summary.failed,
                        repository_summary.ready,
                        repository_summary.failed
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
