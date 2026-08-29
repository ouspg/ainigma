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

pub async fn mark_invited<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
) -> Result<(), Box<dyn Error>> {
    if !adopt_pending_invitation(database, platform, course_id, profile_id, method).await? {
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
) -> Result<bool, Box<dyn Error>> {
    let data = database::invitation_data(database, course_id, profile_id).await?;
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
            data.external_email.as_deref(),
        )
        .await?
        .map(|pending| pending.id);
    let Some(invitation_id) = pending else {
        return Ok(false);
    };
    let target = target(&data, method)?;
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
    let data = database::invitation_data(database, course_id, profile_id).await?;
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
                data.external_email.as_deref(),
            )
            .await?
            .is_some_and(|pending| data.external_invitation_id == Some(pending.id))
        {
            return Ok(());
        }
    }
    let target = target(&data, method)?;
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
                    data.external_email.as_deref(),
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
) -> Result<String, Box<dyn Error>> {
    let target = match method {
        InvitationMethod::Email => data.external_email.as_deref(),
        InvitationMethod::ExternalUserId => Some(data.external_user_id.as_str()),
    };
    target
        .map(str::to_owned)
        .ok_or_else(|| format!("verified external identity for {method:?} is not available").into())
}
