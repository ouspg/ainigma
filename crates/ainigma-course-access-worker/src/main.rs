mod database;
mod github;
mod http;
mod invitations;
mod platform;
mod providers;
mod reconciliation;
mod repositories;

use clap::{Parser, Subcommand};
use invitations::InvitationMethod;
use providers::PlatformRegistry;
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
    /// Send one idempotent external-provider group invitation by email or stable user ID.
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
    /// Record a manually sent invitation found in the provider's pending invitations.
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
    /// Reconcile external-provider access and requested repositories once, or watch continuously.
    Poll {
        #[arg(long, default_value_t = false)]
        watch: bool,
        #[arg(long, default_value_t = 30)]
        interval_seconds: u64,
        #[arg(long)]
        course_id: Option<Uuid>,
        #[arg(long)]
        profile_id: Option<Uuid>,
        /// Queue a repository automatically after external access is confirmed.
        #[arg(long, default_value_t = false)]
        auto_request_repository: bool,
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
    let platforms = PlatformRegistry::from_env().await?;

    match arguments.command {
        Command::Invite {
            course_id,
            profile_id,
            email,
            by,
        } => {
            if email.is_some() && by != InvitationMethod::Email {
                return Err("--email can only be used with --by email".into());
            }
            let (provider_kind, provider_issuer) =
                database::external_provider_for_access(&database, course_id, profile_id).await?;
            let platform = platforms
                .find(&provider_kind, &provider_issuer)
                .ok_or_else(|| {
                    format!(
                        "no configured adapter supports provider {provider_kind} ({provider_issuer})"
                    )
                })?;
            reconciliation::poll_once(
                &database,
                platform,
                Some(course_id),
                Some(profile_id),
                false,
            )
            .await?;
            invitations::invite_one_with_email(
                &database,
                platform,
                course_id,
                profile_id,
                by,
                email.as_deref(),
            )
            .await?;
            println!(
                "processed {provider_kind} {by:?} invitation for course {course_id}, profile {profile_id}"
            );
        }
        Command::MarkInvited {
            course_id,
            profile_id,
            email,
            by,
        } => {
            if email.is_some() && by != InvitationMethod::Email {
                return Err("--email can only be used with --by email".into());
            }
            let (provider_kind, provider_issuer) =
                database::external_provider_for_access(&database, course_id, profile_id).await?;
            let platform = platforms
                .find(&provider_kind, &provider_issuer)
                .ok_or_else(|| {
                    format!(
                        "no configured adapter supports provider {provider_kind} ({provider_issuer})"
                    )
                })?;
            invitations::mark_invited_with_email(
                &database,
                platform,
                course_id,
                profile_id,
                by,
                email.as_deref(),
            )
            .await?;
            println!(
                "marked {provider_kind} invitation pending for course {course_id}, profile {profile_id}"
            );
        }
        Command::Poll {
            watch,
            interval_seconds,
            course_id,
            profile_id,
            auto_request_repository,
        } => loop {
            let mut count = 0;
            let mut invitation_summary = invitations::InvitationSummary::default();
            let mut repository_summary = repositories::ProvisioningSummary::default();
            for platform in platforms.iter() {
                count += reconciliation::poll_once(
                    &database,
                    platform,
                    course_id,
                    profile_id,
                    auto_request_repository,
                )
                .await?;
                let summary =
                    invitations::invite_pending(&database, platform, course_id, profile_id).await?;
                invitation_summary.started += summary.started;
                invitation_summary.failed += summary.failed;
                let summary = repositories::provision_repositories(
                    &database, platform, course_id, profile_id,
                )
                .await?;
                repository_summary.ready += summary.ready;
                repository_summary.failed += summary.failed;
            }

            if !watch {
                println!(
                    "processed {} invitation(s), recorded {} invitation failure(s), reconciled {count} external access record(s); {} requested repository job(s) became ready and {} recorded a failure",
                    invitation_summary.started,
                    invitation_summary.failed,
                    repository_summary.ready,
                    repository_summary.failed
                );
                break;
            }

            tokio::time::sleep(Duration::from_secs(interval_seconds.max(1))).await;
        },
    }

    Ok(())
}

fn required_env(name: &str) -> Result<String, Box<dyn Error>> {
    env::var(name).map_err(|_| format!("{name} must be set").into())
}
