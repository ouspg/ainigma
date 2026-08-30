use crate::{
    database,
    platform::{ExternalPlatform, InvitationError},
};
use clap::ValueEnum;
use sqlx::PgPool;
use std::error::Error;
use uuid::Uuid;

#[derive(Debug, Default)]
pub struct InvitationSummary {
    pub started: usize,
    pub failed: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
pub enum InvitationMethod {
    Email,
    ExternalUserId,
}

impl InvitationMethod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Email => "email",
            Self::ExternalUserId => "external_user_id",
        }
    }
}

pub async fn mark_invited_with_email<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
    email: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    if !adopt_pending_invitation(database, platform, course_id, profile_id, method, email).await? {
        return Err("matching pending external invitation not found".into());
    }
    Ok(())
}

/// Adopt a pending invitation that was sent outside the worker. Returning
/// `false` means there was no matching invitation to adopt.
async fn adopt_pending_invitation<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
    email: Option<&str>,
) -> Result<bool, Box<dyn Error>> {
    let data = database::invitation_data(database, course_id, profile_id).await?;
    let email = email
        .map(|value| {
            validate_email(
                value,
                data.email_domain_enforced,
                &data.email_domain_suffixes,
            )
        })
        .transpose()?;
    ensure_email_override(&data, email.as_deref())?;
    if data.provider_kind != platform.kind() {
        return Err(format!(
            "configured provider {} is not supported by {}",
            data.provider_kind,
            platform.kind()
        )
        .into());
    }
    let resolved_handle = match data.external_user_handle.as_deref() {
        Some(handle) => Some(handle.to_owned()),
        None => Some(platform.user_login_by_id(&data.external_user_id).await?),
    };
    let pending = platform
        .find_pending_invitation(
            &data.external_group_handle,
            resolved_handle.as_deref(),
            email
                .as_deref()
                .or(data.invitation_target.as_deref())
                .or(data.external_email.as_deref()),
        )
        .await?
        .map(|pending| pending.id);
    let Some(invitation_id) = pending else {
        return Ok(false);
    };
    let target = target(&data, method, email.as_deref())?;
    database::record_invitation(
        database,
        course_id,
        profile_id,
        method.as_str(),
        &target,
        &invitation_id,
    )
    .await?;
    Ok(true)
}

pub async fn invite_one<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
) -> Result<(), Box<dyn Error>> {
    invite_one_with_email(database, platform, course_id, profile_id, method, None).await
}

pub async fn invite_one_with_email<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
    email: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    let data = database::invitation_data(database, course_id, profile_id).await?;
    let email = email
        .map(|value| {
            validate_email(
                value,
                data.email_domain_enforced,
                &data.email_domain_suffixes,
            )
        })
        .transpose()?;
    ensure_email_override(&data, email.as_deref())?;
    if data.provider_kind != platform.kind() {
        return Err(format!(
            "configured provider {} is not supported by {}",
            data.provider_kind,
            platform.kind()
        )
        .into());
    }
    if data.state == "active" {
        return Ok(());
    }
    if data.state == "invitation_pending" {
        let resolved_handle = match data.external_user_handle.as_deref() {
            Some(handle) => Some(handle.to_owned()),
            None => Some(platform.user_login_by_id(&data.external_user_id).await?),
        };
        if platform
            .find_pending_invitation(
                &data.external_group_handle,
                resolved_handle.as_deref(),
                email
                    .as_deref()
                    .or(data.invitation_target.as_deref())
                    .or(data.external_email.as_deref()),
            )
            .await?
            .is_some_and(|pending| data.external_invitation_id == Some(pending.id))
        {
            return Ok(());
        }
    }
    let target = target(&data, method, email.as_deref())?;
    let invitation = match method {
        InvitationMethod::Email => {
            platform
                .invite_by_email(&data.external_group_handle, &target)
                .await
        }
        InvitationMethod::ExternalUserId => {
            platform
                .invite_by_user_id(&data.external_group_handle, &data.external_user_id)
                .await
        }
    };
    let invitation_id = match invitation {
        Ok(invitation) => invitation.id,
        Err(InvitationError::AlreadyExists) => {
            let resolved_handle = match data.external_user_handle.as_deref() {
                Some(handle) => Some(handle.to_owned()),
                None => Some(platform.user_login_by_id(&data.external_user_id).await?),
            };
            platform
                .find_pending_invitation(
                    &data.external_group_handle,
                    resolved_handle.as_deref(),
                    email
                        .as_deref()
                        .or(data.invitation_target.as_deref())
                        .or(data.external_email.as_deref()),
                )
                .await?
                .ok_or(
                    "provider rejected the invitation and no matching pending invitation exists",
                )?
                .id
        }
        Err(InvitationError::Failed(code)) => return Err(code.into()),
    };

    database::record_invitation(
        database,
        course_id,
        profile_id,
        method.as_str(),
        &target,
        &invitation_id,
    )
    .await
}

/// Start invitations for approved access records that do not have a provider
/// invitation yet. First adopt a matching manually sent email invitation;
/// otherwise send a new invitation by stable external user ID. A failed send
/// is recorded and does not abort other records.
pub async fn invite_pending<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Option<Uuid>,
    profile_id: Option<Uuid>,
) -> Result<InvitationSummary, Box<dyn Error>> {
    let candidates = database::access_to_invite(database).await?;
    let mut summary = InvitationSummary::default();

    for candidate in candidates {
        if course_id.is_some_and(|id| id != candidate.course_id)
            || profile_id.is_some_and(|id| id != candidate.profile_id)
        {
            continue;
        }

        let invitation_started = match adopt_pending_invitation(
            database,
            platform,
            candidate.course_id,
            candidate.profile_id,
            InvitationMethod::Email,
            None,
        )
        .await
        {
            Ok(true) => Ok(()),
            Ok(false) => {
                invite_one(
                    database,
                    platform,
                    candidate.course_id,
                    candidate.profile_id,
                    InvitationMethod::ExternalUserId,
                )
                .await
            }
            Err(error) => Err(error),
        };

        match invitation_started {
            Ok(()) => summary.started += 1,
            Err(error) => {
                tracing::warn!(
                    course_id = %candidate.course_id,
                    profile_id = %candidate.profile_id,
                    error = %error,
                    "external invitation could not be started"
                );
                database::record_status(
                    database,
                    candidate.course_id,
                    candidate.profile_id,
                    "failed",
                    Some("external_invitation_failed"),
                )
                .await?;
                summary.failed += 1;
            }
        }
    }

    Ok(summary)
}

fn target(
    data: &database::InvitationData,
    method: InvitationMethod,
    email: Option<&str>,
) -> Result<String, Box<dyn Error>> {
    let target = match method {
        InvitationMethod::Email => email
            .or(data.invitation_target.as_deref())
            .or(data.external_email.as_deref()),
        InvitationMethod::ExternalUserId => Some(data.external_user_id.as_str()),
    };
    target
        .map(str::to_owned)
        .ok_or_else(|| format!("verified external identity for {method:?} is not available").into())
}

fn ensure_email_override(
    data: &database::InvitationData,
    email: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    if let (Some(requested), Some(recorded)) = (email, data.invitation_target.as_deref())
        && requested != recorded
    {
        return Err("email override does not match the recorded invitation target".into());
    }
    Ok(())
}

fn validate_email(
    email: &str,
    domain_enforced: bool,
    allowed_domain_suffixes: &[String],
) -> Result<String, Box<dyn Error>> {
    let normalized = email.trim().to_ascii_lowercase();
    if normalized.is_empty() || normalized.len() > 254 {
        return Err("email must contain between 1 and 254 characters".into());
    }

    let Some((local, domain)) = normalized.rsplit_once('@') else {
        return Err("email must contain one @ character".into());
    };
    if local.is_empty()
        || local.contains('@')
        || local.starts_with('.')
        || local.ends_with('.')
        || local.contains("..")
        || local
            .chars()
            .any(|character| character.is_ascii_whitespace() || character.is_control())
    {
        return Err("email local part is invalid".into());
    }
    if domain.starts_with('.')
        || domain.ends_with('.')
        || domain.contains("..")
        || domain.split('.').any(str::is_empty)
    {
        return Err("email domain is invalid".into());
    }
    if domain_enforced
        && !allowed_domain_suffixes
            .iter()
            .any(|allowed| domain == allowed || domain.ends_with(&format!(".{allowed}")))
    {
        return Err("email domain is not allowed for course invitations".into());
    }

    Ok(normalized)
}

#[cfg(test)]
mod tests {
    use super::validate_email;

    fn oulu_domains() -> Vec<String> {
        ["oulu.fi", "student.oulu.fi"]
            .into_iter()
            .map(str::to_owned)
            .collect()
    }

    #[test]
    fn accepts_allowed_domains_and_normalizes_case() {
        assert_eq!(
            validate_email("Person@Student.Oulu.fi", true, &oulu_domains()).unwrap(),
            "person@student.oulu.fi"
        );
        assert!(validate_email("person@oulu.fi", true, &oulu_domains()).is_ok());
        assert!(validate_email("person@dept.student.oulu.fi", true, &oulu_domains()).is_ok());
    }

    #[test]
    fn rejects_other_domains_and_malformed_addresses() {
        assert!(validate_email("person@example.com", true, &oulu_domains()).is_err());
        assert!(validate_email("person@notoulu.fi", true, &oulu_domains()).is_err());
        assert!(validate_email("person@oulu.fishing", true, &oulu_domains()).is_err());
        assert!(validate_email("person@dept..oulu.fi", true, &oulu_domains()).is_err());
        assert!(validate_email("person@sub.oulu.fi", true, &oulu_domains()).is_ok());
        assert!(validate_email("person..name@student.oulu.fi", true, &oulu_domains()).is_err());
    }

    #[test]
    fn uses_configured_domains_and_can_disable_enforcement() {
        let domains = vec!["example.edu".to_owned()];
        assert!(validate_email("person@dept.example.edu", true, &domains).is_ok());
        assert!(validate_email("person@oulu.fi", true, &domains).is_err());
        assert!(validate_email("person@anywhere.invalid", false, &[]).is_ok());
        assert!(validate_email("person@anywhere.invalid", true, &[]).is_err());
    }
}
