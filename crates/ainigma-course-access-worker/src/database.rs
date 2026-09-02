use sqlx::PgPool;
use std::error::Error;
use uuid::Uuid;

#[derive(Debug)]
pub struct InvitationData {
    pub provider_kind: String,
    pub provider_issuer: String,
    pub external_group_handle: String,
    pub external_user_id: String,
    pub external_user_handle: Option<String>,
    pub external_email: Option<String>,
    pub invitation_target: Option<String>,
    pub external_invitation_id: Option<String>,
    pub state: String,
    pub email_domain_enforced: bool,
    pub email_domain_suffixes: Vec<String>,
}

#[derive(Debug)]
pub struct AccessToReconcile {
    pub course_id: Uuid,
    pub profile_id: Uuid,
    pub offering_key: String,
    pub provider_kind: String,
    pub provider_issuer: String,
    pub expected_external_group_id: String,
    pub expected_external_group_handle: String,
    pub external_user_id: String,
    pub external_user_handle: Option<String>,
    pub external_invitation_id: Option<String>,
    pub state: String,
}

#[derive(Debug)]
pub struct AccessToInvite {
    pub course_id: Uuid,
    pub profile_id: Uuid,
}

#[derive(Debug)]
pub struct RepositoryJob {
    pub course_id: Uuid,
    pub profile_id: Uuid,
    pub offering_key: String,
    pub provider_kind: String,
    pub provider_issuer: String,
    pub external_group_handle: String,
    pub repository_name: Option<String>,
    pub external_user_handle: Option<String>,
    pub lease_token: Uuid,
}

pub async fn invitation_data(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
) -> Result<InvitationData, Box<dyn Error>> {
    let row = sqlx::query!(
        r#"select provider_kind, provider_issuer, expected_external_group_handle,
                  external_user_id, external_user_handle, external_invitation_id,
                  external_email, invitation_target, state::text
           from private.list_external_course_access_to_reconcile()
           where course_id = $1 and profile_id = $2"#,
        course_id,
        profile_id
    )
    .fetch_optional(database)
    .await?
    .ok_or("approved external access record not found")?;

    let settings = sqlx::query!(
        r#"select organization.email_domain_enforced as "email_domain_enforced!",
                  coalesce(array_agg(domain.domain_suffix order by domain.domain_suffix)
                           filter (where domain.domain_suffix is not null),
                           '{}'::text[]) as "email_domain_suffixes!"
           from public.courses course
           join private.course_definition_external_groups organization
             on organization.course_definition_key = course.course_definition_key
           left join private.course_definition_external_email_domains domain
             on domain.course_definition_key = organization.course_definition_key
           where course.id = $1
           group by organization.email_domain_enforced"#,
        course_id
    )
    .fetch_one(database)
    .await?;

    Ok(InvitationData {
        provider_kind: row
            .provider_kind
            .ok_or("database returned no external provider kind")?,
        provider_issuer: row
            .provider_issuer
            .ok_or("database returned no external provider issuer")?,
        external_group_handle: row
            .expected_external_group_handle
            .ok_or("database returned no external provider group slug")?,
        external_user_id: row
            .external_user_id
            .ok_or("database returned no external user ID")?,
        external_user_handle: row.external_user_handle,
        external_invitation_id: row.external_invitation_id,
        external_email: row.external_email,
        invitation_target: row.invitation_target,
        state: row
            .state
            .ok_or("database returned no external access state")?,
        email_domain_enforced: settings.email_domain_enforced,
        email_domain_suffixes: settings.email_domain_suffixes,
    })
}

pub async fn record_invitation(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
    method: &str,
    target: &str,
    external_invitation_id: &str,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.record_external_course_access_invitation($1, $2, $3::text::private.external_invitation_method, $4, $5)",
        course_id,
        profile_id,
        method,
        target,
        external_invitation_id
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn access_to_reconcile(
    database: &PgPool,
    provider_kind: &str,
) -> Result<Vec<AccessToReconcile>, Box<dyn Error>> {
    let rows = sqlx::query!(
        r#"select course_id, profile_id, offering_key, provider_kind, provider_issuer,
                  expected_external_group_id, expected_external_group_handle,
                  external_user_id, external_user_handle, external_invitation_id,
                  state::text
           from private.list_external_course_access_to_reconcile()
           where state <> 'revoked'
             and provider_kind = $1"#,
        provider_kind
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
                provider_kind: row
                    .provider_kind
                    .ok_or("database returned no external provider kind")?,
                provider_issuer: row
                    .provider_issuer
                    .ok_or("database returned no external provider issuer")?,
                expected_external_group_id: row
                    .expected_external_group_id
                    .ok_or("database returned no external provider group ID")?,
                expected_external_group_handle: row
                    .expected_external_group_handle
                    .ok_or("database returned no external provider group slug")?,
                external_user_id: row
                    .external_user_id
                    .ok_or("database returned no external user ID")?,
                external_user_handle: row.external_user_handle,
                external_invitation_id: row.external_invitation_id,
                state: row.state.ok_or("database returned no access state")?,
            })
        })
        .collect()
}

pub async fn access_to_invite(
    database: &PgPool,
    provider_kind: &str,
) -> Result<Vec<AccessToInvite>, Box<dyn Error>> {
    let rows = sqlx::query!(
        r#"select course_id, profile_id
           from private.list_external_course_access_to_reconcile()
           where state = 'not_started'
             and external_invitation_id is null
             and provider_kind = $1"#,
        provider_kind
    )
    .fetch_all(database)
    .await?;

    rows.into_iter()
        .map(|row| {
            Ok(AccessToInvite {
                course_id: row
                    .course_id
                    .ok_or("database returned no invitation course ID")?,
                profile_id: row
                    .profile_id
                    .ok_or("database returned no invitation profile ID")?,
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
        "select private.record_external_course_access_status($1, $2, $3::text::private.external_course_access_state, $4)",
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
        "select private.record_external_course_access_check_failure($1, $2, $3)",
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
        "select private.record_external_course_access_membership_absence($1, $2) as revoked",
        course_id,
        profile_id
    )
    .fetch_one(database)
    .await?;
    Ok(row.revoked.unwrap_or(false))
}

#[allow(clippy::too_many_arguments)]
pub async fn confirm_access(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
    external_group_id: &str,
    external_group_handle: &str,
    external_invitation_id: Option<&str>,
    external_user_id: &str,
    external_user_handle: &str,
) -> Result<(), Box<dyn Error>> {
    sqlx::query!(
        "select private.confirm_external_course_access($1, $2, $3, $4, $5, $6, $7)",
        course_id,
        profile_id,
        external_group_id,
        external_group_handle,
        external_invitation_id,
        external_user_id,
        external_user_handle
    )
    .execute(database)
    .await?;
    Ok(())
}

pub async fn claim_repository_jobs(
    database: &PgPool,
    provider_kind: &str,
    course_id: Option<Uuid>,
    profile_id: Option<Uuid>,
) -> Result<Vec<RepositoryJob>, Box<dyn Error>> {
    let rows = sqlx::query!(
        r#"select course_id, profile_id, offering_key, provider_kind, provider_issuer,
                  external_group_handle,
                  repository_name, external_user_handle, lease_token
           from private.claim_course_repository_provisioning($1, $2, $3, $4)"#,
        25_i32,
        course_id,
        profile_id,
        provider_kind
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
                provider_kind: row
                    .provider_kind
                    .ok_or("database returned no repository provider kind")?,
                provider_issuer: row
                    .provider_issuer
                    .ok_or("database returned no repository provider issuer")?,
                external_group_handle: row
                    .external_group_handle
                    .ok_or("database returned no repository external provider group slug")?,
                repository_name: row.repository_name,
                external_user_handle: row.external_user_handle,
                lease_token: row
                    .lease_token
                    .ok_or("database returned no repository lease token")?,
            })
        })
        .collect()
}

pub async fn external_provider_for_access(
    database: &PgPool,
    course_id: Uuid,
    profile_id: Uuid,
) -> Result<(String, String), Box<dyn Error>> {
    let row = sqlx::query!(
        r#"select provider_kind, provider_issuer
           from private.list_external_course_access_to_reconcile()
           where course_id = $1 and profile_id = $2"#,
        course_id,
        profile_id
    )
    .fetch_optional(database)
    .await?
    .ok_or("approved external access record not found")?;

    Ok((
        row.provider_kind
            .ok_or("database returned no external provider kind")?,
        row.provider_issuer
            .ok_or("database returned no external provider issuer")?,
    ))
}

pub async fn complete_repository_job(
    database: &PgPool,
    job: &RepositoryJob,
    repository_id: &str,
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
