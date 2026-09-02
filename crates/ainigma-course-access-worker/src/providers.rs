use crate::{
    github::GithubPlatform,
    platform::{
        ExternalPlatform, InvitationError, OrganizationSnapshot, PendingInvitation, Repository,
        SnapshotError,
    },
};
use std::{collections::HashSet, error::Error};

/// Provider implementations are concrete types. This enum is the small
/// dispatch boundary used by the worker; adding a provider requires adding its
/// tested adapter here, not changing the workflow modules.
pub(crate) enum ConfiguredPlatform {
    Github(GithubPlatform),
}

impl ExternalPlatform for ConfiguredPlatform {
    fn kind(&self) -> &'static str {
        match self {
            Self::Github(platform) => platform.kind(),
        }
    }

    fn supports(&self, provider_kind: &str, provider_issuer: &str) -> bool {
        match self {
            Self::Github(platform) => platform.supports(provider_kind, provider_issuer),
        }
    }

    async fn user_login_by_id(&self, user_id: &str) -> Result<String, Box<dyn Error>> {
        match self {
            Self::Github(platform) => platform.user_login_by_id(user_id).await,
        }
    }

    async fn find_pending_invitation(
        &self,
        organization: &str,
        username: Option<&str>,
        email: Option<&str>,
    ) -> Result<Option<PendingInvitation>, Box<dyn Error>> {
        match self {
            Self::Github(platform) => {
                platform
                    .find_pending_invitation(organization, username, email)
                    .await
            }
        }
    }

    async fn invite_by_email(
        &self,
        organization: &str,
        email: &str,
    ) -> Result<PendingInvitation, InvitationError> {
        match self {
            Self::Github(platform) => platform.invite_by_email(organization, email).await,
        }
    }

    async fn invite_by_user_id(
        &self,
        organization: &str,
        user_id: &str,
    ) -> Result<PendingInvitation, InvitationError> {
        match self {
            Self::Github(platform) => platform.invite_by_user_id(organization, user_id).await,
        }
    }

    async fn organization_snapshot(
        &self,
        organization: &str,
        unresolved_invitation_ids: &HashSet<String>,
    ) -> Result<OrganizationSnapshot, SnapshotError> {
        match self {
            Self::Github(platform) => {
                platform
                    .organization_snapshot(organization, unresolved_invitation_ids)
                    .await
            }
        }
    }

    async fn find_or_create_repository(
        &self,
        organization: &str,
        repository_name: &str,
        expected_description: &str,
    ) -> Result<Repository, String> {
        match self {
            Self::Github(platform) => {
                platform
                    .find_or_create_repository(organization, repository_name, expected_description)
                    .await
            }
        }
    }

    async fn grant_maintain(
        &self,
        organization: &str,
        repository: &str,
        username: &str,
    ) -> Result<(), String> {
        match self {
            Self::Github(platform) => {
                platform
                    .grant_maintain(organization, repository, username)
                    .await
            }
        }
    }
}

pub(crate) struct PlatformRegistry {
    platforms: Vec<ConfiguredPlatform>,
}

impl PlatformRegistry {
    pub(crate) async fn from_env() -> Result<Self, Box<dyn Error>> {
        let mut platforms = Vec::new();

        if GithubPlatform::is_configured() {
            platforms.push(ConfiguredPlatform::Github(
                GithubPlatform::from_env().await?,
            ));
        }

        if platforms.is_empty() {
            return Err("no external provider adapter is configured".into());
        }

        Ok(Self { platforms })
    }

    pub(crate) fn iter(&self) -> impl Iterator<Item = &ConfiguredPlatform> {
        self.platforms.iter()
    }

    pub(crate) fn find(
        &self,
        provider_kind: &str,
        provider_issuer: &str,
    ) -> Option<&ConfiguredPlatform> {
        self.platforms
            .iter()
            .find(|platform| platform.supports(provider_kind, provider_issuer))
    }
}
