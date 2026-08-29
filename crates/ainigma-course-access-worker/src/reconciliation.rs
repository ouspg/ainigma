use crate::{
    database,
    platform::{ExternalPlatform, OrganizationSnapshot, SnapshotError},
};
use sqlx::PgPool;
use std::{
    collections::{HashMap, HashSet},
    error::Error,
};
use uuid::Uuid;

pub async fn poll_once<P: ExternalPlatform>(
    database: &PgPool,
    platform: &P,
    course_id: Option<Uuid>,
    profile_id: Option<Uuid>,
) -> Result<usize, Box<dyn Error>> {
    let records = database::access_to_reconcile(database).await?;
    let mut records_by_organization: HashMap<_, Vec<_>> = HashMap::new();
    for access in records {
        if course_id.is_some_and(|id| id != access.course_id)
            || profile_id.is_some_and(|id| id != access.profile_id)
        {
            continue;
        }
        if access.provider_kind != platform.kind() {
            let failure_code = "unsupported_external_provider";
            if access.state == "active" {
                database::record_check_failure(
                    database,
                    access.course_id,
                    access.profile_id,
                    failure_code,
                )
                .await?;
            } else {
                database::record_status(
                    database,
                    access.course_id,
                    access.profile_id,
                    "failed",
                    Some(failure_code),
                )
                .await?;
            }
            continue;
        }
        records_by_organization
            .entry((
                access.provider_kind.clone(),
                access.expected_external_group_id.clone(),
                access.expected_external_group_handle.clone(),
            ))
            .or_default()
            .push(access);
    }

    let mut reconciled = 0;

    for ((_provider_kind, expected_group_id, organization), accesses) in records_by_organization {
        let unresolved_invitation_ids: HashSet<_> = accesses
            .iter()
            .filter(|access| access.state != "active")
            .map(|access| access.external_invitation_id.clone())
            .collect();
        let snapshot = platform
            .organization_snapshot(&organization, &unresolved_invitation_ids)
            .await;

        for access in accesses {
            reconcile_one(database, &access, expected_group_id.clone(), &snapshot).await?;
            reconciled += 1;
        }
    }

    Ok(reconciled)
}

async fn reconcile_one(
    database: &PgPool,
    access: &database::AccessToReconcile,
    expected_group_id: String,
    snapshot: &Result<OrganizationSnapshot, SnapshotError>,
) -> Result<(), Box<dyn Error>> {
    let snapshot = match snapshot {
        Ok(snapshot) => snapshot,
        Err(SnapshotError::SingleSignOnRequired) => {
            if access.state == "active" {
                record_check_failure(database, access, "external_sso_required").await?;
            } else {
                record_status(database, access, "sso_required", None).await?;
            }
            return Ok(());
        }
        Err(SnapshotError::Failed(code)) => {
            record_check_failure(database, access, code).await?;
            return Ok(());
        }
    };

    if snapshot.organization_id() != expected_group_id {
        if access.state == "active" {
            record_check_failure(database, access, "external_group_id_mismatch").await?;
        } else {
            record_status(
                database,
                access,
                "failed",
                Some("external_group_id_mismatch"),
            )
            .await?;
        }
    } else {
        let active_username = snapshot.active_member_username(&access.external_user_id);

        if access.state == "active" {
            if let Some(username) = active_username {
                database::confirm_access(
                    database,
                    access.course_id,
                    access.profile_id,
                    &access.expected_external_group_id,
                    &access.expected_external_group_handle,
                    &access.external_invitation_id,
                    &access.external_user_id,
                    username,
                )
                .await?;
                if access.external_user_handle.as_deref() != Some(username) {
                    tracing::info!(offering = %access.offering_key, "external username cache refreshed");
                } else {
                    tracing::debug!(offering = %access.offering_key, "GitHub membership remains active");
                }
            } else {
                let revoked = database::record_membership_absence(
                    database,
                    access.course_id,
                    access.profile_id,
                )
                .await?;
                if revoked {
                    tracing::info!(offering = %access.offering_key, "GitHub membership absence confirmed; offering access revoked");
                } else {
                    tracing::warn!(offering = %access.offering_key, "GitHub member absent from snapshot; waiting for confirmation");
                }
            }
        } else if let Some(invitation) =
            snapshot.accepted_invitation(&access.external_invitation_id)
        {
            if invitation.user_id != access.external_user_id {
                record_status(
                    database,
                    access,
                    "failed",
                    Some("external_invitation_identity_mismatch"),
                )
                .await?;
            } else if let Some(username) = active_username {
                database::confirm_access(
                    database,
                    access.course_id,
                    access.profile_id,
                    &access.expected_external_group_id,
                    &access.expected_external_group_handle,
                    &access.external_invitation_id,
                    &access.external_user_id,
                    username,
                )
                .await?;
                tracing::info!(offering = %access.offering_key, "external invitation and membership confirmed");
            } else {
                record_status(
                    database,
                    access,
                    "failed",
                    Some("external_membership_not_found"),
                )
                .await?;
            }
        } else if snapshot
            .pending_invitation(&access.external_invitation_id)
            .is_some()
        {
            record_status(database, access, "invitation_pending", None).await?;
        } else {
            record_status(
                database,
                access,
                "failed",
                Some("external_invitation_acceptance_not_confirmed"),
            )
            .await?;
        }
    }

    Ok(())
}

async fn record_check_failure(
    database: &PgPool,
    access: &database::AccessToReconcile,
    failure_code: &str,
) -> Result<(), Box<dyn Error>> {
    database::record_check_failure(database, access.course_id, access.profile_id, failure_code)
        .await?;
    tracing::warn!(
        offering = %access.offering_key,
        failure_code,
        "GitHub reconciliation check failed; confirmed access state was preserved"
    );
    Ok(())
}

async fn record_status(
    database: &PgPool,
    access: &database::AccessToReconcile,
    state: &str,
    failure_code: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    database::record_status(
        database,
        access.course_id,
        access.profile_id,
        state,
        failure_code,
    )
    .await?;
    tracing::info!(offering = %access.offering_key, state, "recorded external access state");
    Ok(())
}
