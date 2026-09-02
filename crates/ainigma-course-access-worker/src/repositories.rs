use crate::{database, platform::ExternalPlatform};
use sqlx::PgPool;
use std::error::Error;
use uuid::Uuid;

#[derive(Debug, Default)]
pub struct ProvisioningSummary {
    pub ready: usize,
    pub failed: usize,
}

pub async fn provision_repositories<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Option<Uuid>,
    profile_id: Option<Uuid>,
) -> Result<ProvisioningSummary, Box<dyn Error>> {
    let jobs =
        database::claim_repository_jobs(database, platform.kind(), course_id, profile_id).await?;
    let mut summary = ProvisioningSummary::default();

    for job in jobs {
        match provision_repository(database, platform, &job).await {
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

async fn provision_repository<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    job: &database::RepositoryJob,
) -> Result<bool, Box<dyn Error>> {
    if !platform.supports(&job.provider_kind, &job.provider_issuer) {
        let error_code = "unsupported_external_provider";
        database::fail_repository_job(database, job, error_code, false).await?;
        tracing::warn!(
            offering = %job.offering_key,
            provider_kind = %job.provider_kind,
            "repository job belongs to another external provider"
        );
        return Ok(false);
    }
    let result = try_provision_repository(database, platform, job).await;

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

async fn try_provision_repository<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    job: &database::RepositoryJob,
) -> Result<(), String> {
    let username = job
        .external_user_handle
        .as_deref()
        .ok_or_else(|| "external_user_handle_not_found".to_owned())?;
    let repository_name = job
        .repository_name
        .as_deref()
        .ok_or_else(|| "external_repository_name_not_generated".to_owned())?;
    let marker = repository_marker(job.course_id, job.profile_id);

    let repository = platform
        .find_or_create_repository(&job.external_group_handle, repository_name, &marker)
        .await?;
    platform
        .grant_maintain(&job.external_group_handle, &repository.name, username)
        .await?;
    database::complete_repository_job(
        database,
        job,
        &repository.id,
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
        "external_user_handle_not_found"
            | "external_repository_name_not_generated"
            | "repository_name_collision"
            | "repository_collaborator_http_401"
            | "repository_collaborator_http_403"
            | "repository_lookup_http_401"
            | "repository_lookup_http_403"
            | "repository_create_http_401"
            | "repository_create_http_403"
    )
}

#[cfg(test)]
mod tests {
    use super::is_retryable_error;

    #[test]
    fn classifies_repository_failures_for_bounded_retry() {
        assert!(is_retryable_error("repository_create_http_500"));
        assert!(is_retryable_error("repository_create_failed"));
        assert!(!is_retryable_error("repository_name_collision"));
        assert!(!is_retryable_error("repository_collaborator_http_403"));
    }
}
