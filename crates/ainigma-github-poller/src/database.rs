use sqlx::PgPool;
use std::error::Error;
use uuid::Uuid;

#[derive(Debug)]
pub struct InvitationData {
    pub github_org_slug: String,
    pub github_user_id: String,
    pub github_username: Option<String>,
    pub github_email: Option<String>,
    pub github_organization_invitation_id: Option<i64>,
    pub state: String,
}

#[derive(Debug)]
pub struct AccessToReconcile {
    pub course_id: Uuid,
    pub profile_id: Uuid,
    pub offering_key: String,
    pub expected_github_org_id: i64,
    pub expected_github_org_slug: String,
    pub github_user_id: String,
    pub github_username: Option<String>,
    pub github_organization_invitation_id: i64,
    pub state: String,
}

#[derive(Debug)]
pub struct RepositoryJob {
    pub course_id: Uuid,
    pub profile_id: Uuid,
    pub offering_key: String,
    pub github_org_slug: String,
    pub repository_name: Option<String>,
    pub github_username: Option<String>,
    pub lease_token: Uuid,
}

pub async fn invitation_data(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
) -> Result<InvitationData, Box<dyn Error>> {
    let row = sqlx::query!(
        r#"select expected_github_org_slug, github_user_id, github_username,
                  github_organization_invitation_id, github_email, state
           from private.list_github_course_access_to_reconcile()
           where course_id = $1 and profile_id = $2"#,
        course_id,
        profile_id
    )
    .fetch_optional(database)
    .await?
    .ok_or("approved GitHub access record not found")?;

    Ok(InvitationData {
        github_org_slug: row
            .expected_github_org_slug
            .ok_or("database returned no GitHub organization slug")?,
        github_user_id: row
            .github_user_id
            .ok_or("database returned no GitHub user ID")?,
        github_username: row.github_username,
        github_organization_invitation_id: row.github_organization_invitation_id,
        github_email: row.github_email,
        state: row
            .state
            .ok_or("database returned no GitHub access state")?,
    })
}

pub async fn record_invitation(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
    method: &str,
    target: &str,
    github_organization_invitation_id: i64,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.record_github_course_access_invitation($1, $2, $3, $4, $5)",
        course_id,
        profile_id,
        method,
        target,
        github_organization_invitation_id
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn access_to_reconcile(
    database: &PgPool,
) -> Result<Vec<AccessToReconcile>, Box<dyn Error>> {
    let rows = sqlx::query!(
        r#"select course_id, profile_id, offering_key,
                  expected_github_org_id, expected_github_org_slug,
                  github_user_id, github_username, github_organization_invitation_id,
                  state
           from private.list_github_course_access_to_reconcile()
           where state not in ('not_started', 'revoked')
             and github_organization_invitation_id is not null"#
    )
    .fetch_all(database)
    .await?;

    rows.into_iter()
        .map(|row| {
            Ok(AccessToReconcile {
                course_id: row
                    .course_id
                    .ok_or("database returned no access course ID")?,
                profile_id: row
                    .profile_id
                    .ok_or("database returned no access profile ID")?,
                offering_key: row
                    .offering_key
                    .ok_or("database returned no offering key")?,
                expected_github_org_id: row
                    .expected_github_org_id
                    .ok_or("database returned no GitHub organization ID")?,
                expected_github_org_slug: row
                    .expected_github_org_slug
                    .ok_or("database returned no GitHub organization slug")?,
                github_user_id: row
                    .github_user_id
                    .ok_or("database returned no GitHub user ID")?,
                github_username: row.github_username,
                github_organization_invitation_id: row
                    .github_organization_invitation_id
                    .ok_or("database returned no GitHub invitation ID")?,
                state: row.state.ok_or("database returned no access state")?,
            })
        })
        .collect()
}

pub async fn record_status(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
    state: &str,
    failure_code: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.record_github_course_access_status($1, $2, $3, $4)",
        course_id,
        profile_id,
        state,
        failure_code
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn record_check_failure(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
    failure_code: &str,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.record_github_course_access_check_failure($1, $2, $3)",
        course_id,
        profile_id,
        failure_code
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn record_membership_absence(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
) -> Result<bool, Box<dyn Error>> {
    let row = sqlx::query!(
        "select private.record_github_course_access_membership_absence($1, $2) as revoked",
        course_id,
        profile_id
    )
    .fetch_one(database)
    .await?;
    Ok(row.revoked.unwrap_or(false))
}

pub async fn confirm_access(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
    github_org_id: i64,
    github_org_slug: &str,
    github_organization_invitation_id: i64,
    github_user_id: &str,
    github_username: &str,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.confirm_github_course_access($1, $2, $3, $4, $5, $6, $7)",
        course_id,
        profile_id,
        github_org_id,
        github_org_slug,
        github_organization_invitation_id,
        github_user_id,
        github_username
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn claim_repository_jobs(
    database: &PgPool,
    course_id: Option<Uuid>,
    profile_id: Option<Uuid>,
) -> Result<Vec<RepositoryJob>, Box<dyn Error>> {
    let rows = sqlx::query!(
        r#"select course_id, profile_id, offering_key, github_org_slug,
                  repository_name, github_username, lease_token
           from private.claim_course_repository_provisioning($1, $2, $3)"#,
        25_i32,
        course_id,
        profile_id
    )
    .fetch_all(database)
    .await?;

    rows.into_iter()
        .map(|row| {
            Ok(RepositoryJob {
                course_id: row
                    .course_id
                    .ok_or("database returned no repository course ID")?,
                profile_id: row
                    .profile_id
                    .ok_or("database returned no repository profile ID")?,
                offering_key: row
                    .offering_key
                    .ok_or("database returned no repository offering key")?,
                github_org_slug: row
                    .github_org_slug
                    .ok_or("database returned no repository GitHub organization slug")?,
                repository_name: row.repository_name,
                github_username: row.github_username,
                lease_token: row
                    .lease_token
                    .ok_or("database returned no repository lease token")?,
            })
        })
        .collect()
}

pub async fn complete_repository_job(
    database: &PgPool,
    job: &RepositoryJob,
    repository_id: i64,
    repository_name: &str,
    repository_url: &str,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.complete_course_repository_provisioning($1, $2, $3, $4, $5, $6)",
        job.course_id,
        job.profile_id,
        job.lease_token,
        repository_id,
        repository_name,
        repository_url
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn fail_repository_job(
    database: &PgPool,
    job: &RepositoryJob,
    error_code: &str,
    retryable: bool,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.record_course_repository_provisioning_failure($1, $2, $3, $4, $5)",
        job.course_id,
        job.profile_id,
        job.lease_token,
        error_code,
        retryable
    )
    .execute(database)
    .await?;
    Ok(())
}
