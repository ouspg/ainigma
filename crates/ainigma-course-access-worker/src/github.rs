use crate::platform::{
    AcceptedInvitation, ExternalPlatform, InvitationError, OrganizationSnapshot, PendingInvitation,
    Repository, SnapshotError,
};
use reqwest::{Client, StatusCode, header};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    collections::{HashMap, HashSet},
    env,
    error::Error,
};

const DEFAULT_API_URL: &str = "https://api.github.com";
const API_VERSION: &str = "2022-11-28";

impl From<reqwest::Error> for SnapshotError {
    fn from(_: reqwest::Error) -> Self {
        Self::Failed("github_request_failed".to_owned())
    }
}

pub(crate) struct GithubPlatform {
    client: Client,
    api_url: String,
}

impl GithubPlatform {
    pub(crate) fn from_token(token: &str) -> Result<Self, Box<dyn Error>> {
        Ok(Self {
            client: client(token)?,
            api_url: api_url(),
        })
    }
}

impl ExternalPlatform for GithubPlatform {
    fn kind(&self) -> &'static str {
        "github"
    }

    async fn user_login_by_id(&self, user_id: &str) -> Result<String, Box<dyn Error>> {
        user_login_by_id(&self.client, &self.api_url, user_id).await
    }

    async fn find_pending_invitation(
        &self,
        organization: &str,
        username: Option<&str>,
        email: Option<&str>,
    ) -> Result<Option<PendingInvitation>, Box<dyn Error>> {
        find_pending_invitation(&self.client, &self.api_url, organization, username, email).await
    }

    async fn invite_by_email(
        &self,
        organization: &str,
        email: &str,
    ) -> Result<PendingInvitation, InvitationError> {
        let response = email_invitation(&self.client, &self.api_url, organization, email)
            .await
            .map_err(|_| InvitationError::Failed("github_invitation_request_failed".to_owned()))?;
        invitation_response(response).await
    }

    async fn invite_by_user_id(
        &self,
        organization: &str,
        user_id: &str,
    ) -> Result<PendingInvitation, InvitationError> {
        let response = user_id_invitation(&self.client, &self.api_url, organization, user_id)
            .await
            .map_err(|_| InvitationError::Failed("github_invitation_request_failed".to_owned()))?;
        invitation_response(response).await
    }

    async fn organization_snapshot(
        &self,
        organization: &str,
        unresolved_invitation_ids: &HashSet<String>,
    ) -> Result<OrganizationSnapshot, SnapshotError> {
        organization_snapshot(
            &self.client,
            &self.api_url,
            organization,
            unresolved_invitation_ids,
        )
        .await
    }

    async fn find_or_create_repository(
        &self,
        organization: &str,
        repository_name: &str,
        expected_description: &str,
    ) -> Result<Repository, String> {
        find_or_create_repository(
            &self.client,
            &self.api_url,
            organization,
            repository_name,
            expected_description,
        )
        .await
    }

    async fn grant_maintain(
        &self,
        organization: &str,
        repository: &str,
        username: &str,
    ) -> Result<(), String> {
        grant_maintain(
            &self.client,
            &self.api_url,
            organization,
            repository,
            username,
        )
        .await
    }
}

async fn invitation_response(
    response: reqwest::Response,
) -> Result<PendingInvitation, InvitationError> {
    let status = response.status();
    if status.is_success() {
        return response
            .json::<GithubPendingInvitation>()
            .await
            .map(GithubPendingInvitation::into_platform)
            .map_err(|_| InvitationError::Failed("github_invitation_response_invalid".to_owned()));
    }
    if status == StatusCode::UNPROCESSABLE_ENTITY {
        return Err(InvitationError::AlreadyExists);
    }
    Err(InvitationError::Failed(format!(
        "github_invitation_http_{}",
        status.as_u16()
    )))
}

#[derive(Debug, Deserialize)]
struct User {
    pub id: i64,
    pub login: String,
}

#[derive(Debug, Deserialize)]
struct GithubPendingInvitation {
    id: NumericOrString,
    login: Option<String>,
    email: Option<String>,
}

impl GithubPendingInvitation {
    fn into_platform(self) -> PendingInvitation {
        PendingInvitation {
            id: self.id.as_string(),
            login: self.login,
            email: self.email,
        }
    }
}

#[derive(Debug, Deserialize)]
struct GithubRepository {
    id: NumericOrString,
    name: String,
    html_url: String,
    private: bool,
    description: Option<String>,
}

impl GithubRepository {
    fn into_platform(self) -> Repository {
        Repository {
            id: self.id.as_string(),
            name: self.name,
            html_url: self.html_url,
            private: self.private,
            description: self.description,
        }
    }
}

#[derive(Debug, Deserialize)]
struct Organization {
    pub id: i64,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum NumericOrString {
    Number(i64),
    String(String),
}

impl NumericOrString {
    fn as_string(&self) -> String {
        match self {
            Self::Number(value) => value.to_string(),
            Self::String(value) => value.clone(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct AuditLogEntry {
    action: String,
    invitation_id: Option<NumericOrString>,
    user_id: Option<NumericOrString>,
}

#[derive(Debug, Serialize)]
struct CollaboratorPermission {
    permission: &'static str,
}

pub fn api_url() -> String {
    env::var("GITHUB_API_URL")
        .unwrap_or_else(|_| DEFAULT_API_URL.to_owned())
        .trim_end_matches('/')
        .to_owned()
}

pub fn client(token: &str) -> Result<Client, Box<dyn Error>> {
    Ok(Client::builder()
        .user_agent("ainigma-course-access-worker/0.1")
        .default_headers(headers(token)?)
        .build()?)
}

fn headers(token: &str) -> Result<header::HeaderMap, Box<dyn Error>> {
    let mut headers = header::HeaderMap::new();
    headers.insert(
        header::ACCEPT,
        header::HeaderValue::from_static("application/vnd.github+json"),
    );
    headers.insert(
        "x-github-api-version",
        header::HeaderValue::from_static(API_VERSION),
    );
    headers.insert(
        header::AUTHORIZATION,
        header::HeaderValue::try_from(format!("Bearer {token}"))?,
    );
    Ok(headers)
}

pub async fn email_invitation(
    github: &Client,
    api_url: &str,
    organization: &str,
    email: &str,
) -> Result<reqwest::Response, reqwest::Error> {
    github
        .post(format!("{api_url}/orgs/{organization}/invitations"))
        .json(&json!({
            "email": email,
            "role": "direct_member"
        }))
        .send()
        .await
}

pub async fn user_id_invitation(
    github: &Client,
    api_url: &str,
    organization: &str,
    github_user_id: &str,
) -> Result<reqwest::Response, Box<dyn Error>> {
    let invitee_id = github_user_id
        .parse::<i64>()
        .map_err(|_| "invalid GitHub user ID")?;
    github
        .post(format!("{api_url}/orgs/{organization}/invitations"))
        .json(&json!({
            "role": "direct_member",
            "invitee_id": invitee_id
        }))
        .send()
        .await
        .map_err(Into::into)
}

pub async fn user_login_by_id(
    github: &Client,
    api_url: &str,
    github_user_id: &str,
) -> Result<String, Box<dyn Error>> {
    let response = github
        .get(format!("{api_url}/user/{github_user_id}"))
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(format!(
            "GitHub user lookup failed with HTTP {}",
            response.status().as_u16()
        )
        .into());
    }
    Ok(response.json::<User>().await?.login)
}

pub async fn organization_snapshot(
    github: &Client,
    api_url: &str,
    organization: &str,
    unresolved_invitation_ids: &HashSet<String>,
) -> Result<OrganizationSnapshot, SnapshotError> {
    let organization_id = organization_id(github, api_url, organization).await?;
    let active_members = list_active_members(github, api_url, organization).await?;
    let pending_invitations = if unresolved_invitation_ids.is_empty() {
        Vec::new()
    } else {
        list_pending_invitations(github, api_url, organization).await?
    };
    let pending_invitation_ids: HashSet<_> = pending_invitations
        .iter()
        .map(|invitation| invitation.id.clone())
        .collect();
    let accepted_invitation_ids: HashSet<_> = unresolved_invitation_ids
        .difference(&pending_invitation_ids)
        .cloned()
        .collect();
    let audit_log = if accepted_invitation_ids.is_empty() {
        Vec::new()
    } else {
        list_member_additions(github, api_url, organization, &accepted_invitation_ids).await?
    };

    Ok(OrganizationSnapshot {
        organization_id,
        active_members,
        pending_invitations: pending_invitations
            .into_iter()
            .map(|invitation| (invitation.id.clone(), invitation))
            .collect(),
        accepted_invitations: audit_log
            .into_iter()
            .filter(|entry| entry.action == "org.add_member")
            .filter_map(|entry| {
                Some((
                    entry.invitation_id.as_ref()?.as_string(),
                    AcceptedInvitation {
                        user_id: entry.user_id?.as_string(),
                    },
                ))
            })
            .collect(),
    })
}

async fn organization_id(
    github: &Client,
    api_url: &str,
    organization: &str,
) -> Result<String, SnapshotError> {
    let response = github
        .get(format!("{api_url}/orgs/{organization}"))
        .send()
        .await?;
    if response.status() == StatusCode::FORBIDDEN && sso_required(&response) {
        return Err(SnapshotError::SingleSignOnRequired);
    }
    if !response.status().is_success() {
        return Err(SnapshotError::Failed(format!(
            "github_organization_http_{}",
            response.status().as_u16()
        )));
    }
    Ok(response.json::<Organization>().await?.id.to_string())
}

async fn list_active_members(
    github: &Client,
    api_url: &str,
    organization: &str,
) -> Result<HashMap<String, String>, SnapshotError> {
    let mut members_by_id = HashMap::new();
    let mut page = 1;

    loop {
        let response = github
            .get(format!(
                "{api_url}/orgs/{organization}/members?filter=all&per_page=100&page={page}"
            ))
            .send()
            .await?;
        if response.status() == StatusCode::FORBIDDEN && sso_required(&response) {
            return Err(SnapshotError::SingleSignOnRequired);
        }
        if !response.status().is_success() {
            return Err(SnapshotError::Failed(format!(
                "github_members_http_{}",
                response.status().as_u16()
            )));
        }

        let members: Vec<User> = response.json().await?;
        let member_count = members.len();
        members_by_id.extend(
            members
                .into_iter()
                .map(|member| (member.id.to_string(), member.login)),
        );
        if member_count < 100 {
            break;
        }
        page += 1;
    }

    Ok(members_by_id)
}

async fn list_member_additions(
    github: &Client,
    api_url: &str,
    organization: &str,
    invitation_ids: &HashSet<String>,
) -> Result<Vec<AuditLogEntry>, SnapshotError> {
    let mut entries = Vec::new();
    let mut remaining_invitation_ids = invitation_ids.clone();
    let mut next_url = Some(format!(
        "{api_url}/orgs/{organization}/audit-log?phrase=action%3Aorg.add_member&order=desc&per_page=100"
    ));

    while let Some(url) = next_url.take() {
        let response = github.get(url).send().await?;
        if response.status() == StatusCode::FORBIDDEN && sso_required(&response) {
            return Err(SnapshotError::SingleSignOnRequired);
        }
        if !response.status().is_success() {
            return Err(SnapshotError::Failed(format!(
                "github_audit_log_http_{}",
                response.status().as_u16()
            )));
        }

        let next = response
            .headers()
            .get(header::LINK)
            .and_then(|value| value.to_str().ok())
            .and_then(next_link);
        let page_entries: Vec<AuditLogEntry> = response.json().await?;
        let entry_count = page_entries.len();
        for entry in page_entries {
            let invitation_id = entry.invitation_id.as_ref().map(NumericOrString::as_string);
            if invitation_id.is_some_and(|id| remaining_invitation_ids.remove(&id)) {
                entries.push(entry);
            }
        }
        if remaining_invitation_ids.is_empty() {
            break;
        }
        next_url = next;
        if entry_count == 0 {
            break;
        }
    }

    Ok(entries)
}

fn next_link(link_header: &str) -> Option<String> {
    link_header.split(',').find_map(|link| {
        let mut parts = link.split(';');
        let url = parts
            .next()?
            .trim()
            .trim_start_matches('<')
            .trim_end_matches('>');
        let relation = parts.next()?.trim();
        (relation == "rel=\"next\"").then(|| url.to_owned())
    })
}

async fn list_pending_invitations(
    github: &Client,
    api_url: &str,
    organization: &str,
) -> Result<Vec<PendingInvitation>, SnapshotError> {
    let mut invitations = Vec::new();
    let mut page = 1;

    loop {
        let response = github
            .get(format!(
                "{api_url}/orgs/{organization}/invitations?per_page=100&page={page}"
            ))
            .send()
            .await?;
        if response.status() == StatusCode::FORBIDDEN && sso_required(&response) {
            return Err(SnapshotError::SingleSignOnRequired);
        }
        if !response.status().is_success() {
            return Err(SnapshotError::Failed(format!(
                "github_invitations_http_{}",
                response.status().as_u16()
            )));
        }

        let page_invitations: Vec<GithubPendingInvitation> = response.json().await?;
        let invitation_count = page_invitations.len();
        invitations.extend(
            page_invitations
                .into_iter()
                .map(GithubPendingInvitation::into_platform),
        );
        if invitation_count < 100 {
            break;
        }
        page += 1;
    }

    Ok(invitations)
}

fn sso_required(response: &reqwest::Response) -> bool {
    response
        .headers()
        .get("x-github-sso")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.contains("required"))
}

pub async fn find_pending_invitation(
    github: &Client,
    api_url: &str,
    organization: &str,
    github_username: Option<&str>,
    github_email: Option<&str>,
) -> Result<Option<PendingInvitation>, Box<dyn Error>> {
    let invitations = list_pending_invitations(github, api_url, organization)
        .await
        .map_err(|error| match error {
            SnapshotError::SingleSignOnRequired => "github_sso_required".to_owned(),
            SnapshotError::Failed(code) => code,
        })?;
    Ok(invitations.into_iter().find(|invitation| {
        github_username.is_some_and(|username| invitation.login.as_deref() == Some(username))
            || invitation
                .email
                .as_deref()
                .is_some_and(|email| github_email == Some(email))
    }))
}

pub async fn find_or_create_repository(
    github: &Client,
    api_url: &str,
    organization: &str,
    repository_name: &str,
    expected_description: &str,
) -> Result<Repository, String> {
    let get_url = format!("{api_url}/repos/{organization}/{repository_name}");
    let response = github
        .get(&get_url)
        .send()
        .await
        .map_err(|_| "github_repository_lookup_failed".to_owned())?;

    let repository = if response.status().is_success() {
        response
            .json::<GithubRepository>()
            .await
            .map(GithubRepository::into_platform)
            .map_err(|_| "github_repository_response_invalid".to_owned())?
    } else if response.status() == StatusCode::NOT_FOUND {
        let create_response = github
            .post(format!("{api_url}/orgs/{organization}/repos"))
            .json(&json!({
                "name": repository_name,
                "description": expected_description,
                "private": true,
                "has_issues": false,
                "has_projects": false,
                "has_wiki": false
            }))
            .send()
            .await
            .map_err(|_| "github_repository_create_failed".to_owned())?;

        if create_response.status().is_success() {
            create_response
                .json::<GithubRepository>()
                .await
                .map(GithubRepository::into_platform)
                .map_err(|_| "github_repository_response_invalid".to_owned())?
        } else if create_response.status() == StatusCode::UNPROCESSABLE_ENTITY {
            let retry_response = github
                .get(&get_url)
                .send()
                .await
                .map_err(|_| "github_repository_lookup_failed".to_owned())?;
            if !retry_response.status().is_success() {
                return Err("github_repository_create_conflict".to_owned());
            }
            retry_response
                .json::<GithubRepository>()
                .await
                .map(GithubRepository::into_platform)
                .map_err(|_| "github_repository_response_invalid".to_owned())?
        } else {
            return Err(format!(
                "github_repository_create_http_{}",
                create_response.status().as_u16()
            ));
        }
    } else {
        return Err(format!(
            "github_repository_lookup_http_{}",
            response.status().as_u16()
        ));
    };

    if !repository.private || repository.description.as_deref() != Some(expected_description) {
        return Err("github_repository_name_collision".to_owned());
    }
    Ok(repository)
}

pub async fn grant_maintain(
    github: &Client,
    api_url: &str,
    organization: &str,
    repository: &str,
    username: &str,
) -> Result<(), String> {
    let response = github
        .put(format!(
            "{api_url}/repos/{organization}/{repository}/collaborators/{username}"
        ))
        .json(&CollaboratorPermission {
            permission: "maintain",
        })
        .send()
        .await
        .map_err(|_| "github_collaborator_request_failed".to_owned())?;
    if !response.status().is_success() {
        return Err(format!(
            "github_collaborator_http_{}",
            response.status().as_u16()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{GithubPendingInvitation, next_link};

    #[test]
    fn decodes_pending_organization_invitation_shape() {
        let invitation = serde_json::from_str::<GithubPendingInvitation>(
            r#"{"id":123,"login":null,"email":"student@example.com","role":"direct_member"}"#,
        )
        .expect("GitHub pending invitation should decode")
        .into_platform();

        assert_eq!(invitation.id, "123");
        assert_eq!(invitation.login, None);
        assert_eq!(invitation.email.as_deref(), Some("student@example.com"));
    }

    #[test]
    fn extracts_next_audit_log_link() {
        assert_eq!(
            next_link(
                r#"<https://api.github.com/orgs/example/audit-log?after=abc>; rel="next", <https://api.github.com/orgs/example/audit-log?before=xyz>; rel="prev""#
            ),
            Some("https://api.github.com/orgs/example/audit-log?after=abc".to_owned())
        );
    }
}
