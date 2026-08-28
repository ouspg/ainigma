use crate::{database, github};
use reqwest::Client;
use sqlx::PgPool;
use std::error::Error;
use uuid::Uuid;

#[derive(Debug, Default)]
pub struct ProvisioningSummary {
    pub ready: usize,
    pub failed: usize,
}

pub async fn provision_repositories(
    database: &PgPool,
    github_client: &Client,
    github_api_url: &str,
    course_id: Option<Uuid>,
    profile_id: Option<Uuid>,
) -> Result<ProvisioningSummary, Box<dyn Error>> {
    let jobs = database::claim_repository_jobs(database, course_id, profile_id).await?;
    let mut summary = ProvisioningSummary::default();

    for job in jobs {
        match provision_repository(database, github_client, github_api_url, &job).await {
            Ok(true) => summary.ready += 1,
            Ok(false) => summary.failed += 1,
            Err(error) => {
                summary.failed += 1;
                tracing::error!(
                    offering = %job.offering_key,
                    repository = ?job.repository_name,
                    %error,
                    "repository job could not record its outcome and its lease will expire"
                );
            }
        }
    }

    Ok(summary)
}

async fn provision_repository(
    database: &PgPool,
    github_client: &Client,
    github_api_url: &str,
    job: &database::RepositoryJob,
) -> Result<bool, Box<dyn Error>> {
    let result = try_provision_repository(database, github_client, github_api_url, job).await;

    if let Err(error_code) = result {
        let retryable = is_retryable_error(&error_code);
        database::fail_repository_job(database, job, &error_code, retryable).await?;
        tracing::warn!(
            offering = %job.offering_key,
            repository = ?job.repository_name,
            error_code,
            retryable,
            "repository provisioning failure recorded"
        );
        return Ok(false);
    }

    Ok(true)
}

async fn try_provision_repository(
    database: &PgPool,
    github_client: &Client,
    github_api_url: &str,
    job: &database::RepositoryJob,
) -> Result<(), String> {
    let username = job
        .github_username
        .as_deref()
        .ok_or_else(|| "github_username_not_found".to_owned())?;
    let repository_name = job
        .repository_name
        .as_deref()
        .ok_or_else(|| "github_repository_name_not_generated".to_owned())?;
    let marker = repository_marker(job.course_id, job.profile_id);

    let repository = github::find_or_create_repository(
        github_client,
        github_api_url,
        &job.github_org_slug,
        repository_name,
        &marker,
    )
    .await?;
    github::grant_maintain(
        github_client,
        github_api_url,
        &job.github_org_slug,
        &repository.name,
        username,
    )
    .await?;
    database::complete_repository_job(
        database,
        job,
        repository.id,
        &repository.name,
        &repository.html_url,
    )
    .await
    .map_err(|_| "repository_completion_failed".to_owned())?;
    Ok(())
}

fn repository_marker(course_id: Uuid, profile_id: Uuid) -> String {
    format!("ainigma:course_id={course_id};profile_id={profile_id}")
}

fn is_retryable_error(error_code: &str) -> bool {
    !matches!(
        error_code,
        "github_username_not_found"
            | "github_repository_name_not_generated"
            | "github_repository_name_collision"
            | "github_collaborator_http_401"
            | "github_collaborator_http_403"
            | "github_repository_lookup_http_401"
            | "github_repository_lookup_http_403"
            | "github_repository_create_http_401"
            | "github_repository_create_http_403"
    )
}

#[cfg(test)]
mod tests {
    use super::is_retryable_error;

    #[test]
    fn classifies_repository_failures_for_bounded_retry() {
        assert!(is_retryable_error("github_repository_create_http_500"));
        assert!(is_retryable_error("github_repository_create_failed"));
        assert!(!is_retryable_error("github_repository_name_collision"));
        assert!(!is_retryable_error("github_collaborator_http_403"));
    }
}
