use std::{error::Error, fmt};

/// Provider-neutral result shapes used by the course access workflow.
/// Provider-specific HTTP details stay inside an adapter implementation.
#[derive(Debug, serde::Deserialize)]
pub(crate) struct PendingInvitation {
    pub(crate) id: String,
    pub(crate) login: Option<String>,
    pub(crate) email: Option<String>,
}

#[derive(Debug)]
pub(crate) struct OrganizationSnapshot {
    pub(crate) organization_id: String,
    pub(crate) active_members: std::collections::HashMap<String, String>,
    pub(crate) pending_invitations: std::collections::HashMap<String, PendingInvitation>,
    pub(crate) accepted_invitations: std::collections::HashMap<String, AcceptedInvitation>,
}

#[derive(Debug)]
pub(crate) struct AcceptedInvitation {
    pub(crate) user_id: String,
}

impl OrganizationSnapshot {
    pub(crate) fn active_member_username(&self, user_id: &str) -> Option<&str> {
        self.active_members.get(user_id).map(String::as_str)
    }

    pub(crate) fn pending_invitation(&self, invitation_id: &str) -> Option<&PendingInvitation> {
        self.pending_invitations.get(invitation_id)
    }

    pub(crate) fn accepted_invitation(&self, invitation_id: &str) -> Option<&AcceptedInvitation> {
        self.accepted_invitations.get(invitation_id)
    }

    pub(crate) fn organization_id(&self) -> &str {
        &self.organization_id
    }
}

#[derive(Clone, Debug)]
pub(crate) enum SnapshotError {
    SingleSignOnRequired,
    Failed(String),
}

#[derive(Debug)]
pub(crate) enum InvitationError {
    AlreadyExists,
    Failed(String),
}

impl fmt::Display for InvitationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AlreadyExists => formatter.write_str("invitation_already_exists"),
            Self::Failed(code) => formatter.write_str(code),
        }
    }
}

impl Error for InvitationError {}

#[derive(Debug, serde::Deserialize)]
pub(crate) struct Repository {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) html_url: String,
    pub(crate) private: bool,
    pub(crate) description: Option<String>,
}

/// The stable contract used by the course workflow. An another adapter can
/// implement this contract later without changing invitation reconciliation
/// or durable repository-job orchestration.
pub(crate) trait ExternalPlatform {
    fn kind(&self) -> &'static str;

    async fn user_login_by_id(&self, user_id: &str) -> Result<String, Box<dyn Error>>;

    async fn find_pending_invitation(
        &self,
        organization: &str,
        username: Option<&str>,
        email: Option<&str>,
    ) -> Result<Option<PendingInvitation>, Box<dyn Error>>;

    async fn invite_by_email(
        &self,
        organization: &str,
        email: &str,
    ) -> Result<PendingInvitation, InvitationError>;

    async fn invite_by_user_id(
        &self,
        organization: &str,
        user_id: &str,
    ) -> Result<PendingInvitation, InvitationError>;

    async fn organization_snapshot(
        &self,
        organization: &str,
        unresolved_invitation_ids: &std::collections::HashSet<String>,
    ) -> Result<OrganizationSnapshot, SnapshotError>;

    async fn find_or_create_repository(
        &self,
        organization: &str,
        repository_name: &str,
        expected_description: &str,
    ) -> Result<Repository, String>;

    async fn grant_maintain(
        &self,
        organization: &str,
        repository: &str,
        username: &str,
    ) -> Result<(), String>;
}
