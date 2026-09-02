use crate::http::{configure_client, log_request_error};
use crate::platform::{
    AcceptedInvitation, ExternalPlatform, InvitationError, OrganizationSnapshot, PendingInvitation,
    Repository, SnapshotError,
};
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use reqwest::{Client, StatusCode, header};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    collections::{HashMap, HashSet},
    env,
    error::Error,
    fs,
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::sync::Mutex;

const DEFAULT_API_URL: &str = "https://api.github.com";
const API_VERSION: &str = "2026-03-10";
const INSTALLATION_TOKEN_REFRESH: Duration = Duration::from_secs(50 * 60);

impl From<reqwest::Error> for SnapshotError {
    fn from(error: reqwest::Error) -> Self {
        log_request_error("github_snapshot_request", &error);
        Self::Failed("github_request_failed".to_owned())
    }
}

pub(crate) struct GithubPlatform {
    client: Client,
    app_auth: Option<Arc<Mutex<AppAuthentication>>>,
    api_url: String,
}

struct AppAuthentication {
    issuer: String,
    installation_id: u64,
    private_key: String,
    client: Client,
    refresh_at: Instant,
}

impl GithubPlatform {
    pub(crate) fn is_configured() -> bool {
        [
            "GITHUB_TOKEN",
            "GITHUB_APP_CLIENT_ID",
            "GITHUB_APP_ID",
            "GITHUB_APP_PRIVATE_KEY",
            "GITHUB_APP_PRIVATE_KEY_PATH",
            "GITHUB_APP_INSTALLATION_ID",
        ]
        .into_iter()
        .any(|name| {
            env::var(name)
                .ok()
                .is_some_and(|value| !value.trim().is_empty())
        })
    }

    pub(crate) async fn from_env() -> Result<Self, Box<dyn Error>> {
        let api_url = api_url();
        if let Ok(token) = env::var("GITHUB_TOKEN")
            && !token.trim().is_empty()
        {
            tracing::info!("GitHub authentication flow selected: pre-issued token");
            return Ok(Self {
                client: client(&token)?,
                app_auth: None,
                api_url,
            });
        }

        let app_issuer = app_issuer_from_env()?;
        let installation_id = required_numeric_env("GITHUB_APP_INSTALLATION_ID")?;
        let private_key = private_key_from_env()?;
        let token =
            installation_token(&api_url, &app_issuer, installation_id, &private_key).await?;
        let client = client(&token)?;
        tracing::info!("GitHub authentication flow selected: App installation token");
        let app_auth = {
            Arc::new(Mutex::new(AppAuthentication {
                issuer: app_issuer,
                installation_id,
                private_key,
                client: client.clone(),
                refresh_at: Instant::now() + INSTALLATION_TOKEN_REFRESH,
            }))
        };

        Ok(Self {
            client,
            app_auth: Some(app_auth),
            api_url,
        })
    }

    async fn authorized_client(&self) -> Result<Client, Box<dyn Error>> {
        let Some(app_auth) = &self.app_auth else {
            return Ok(self.client.clone());
        };

        let mut app_auth = app_auth.lock().await;
        if Instant::now() >= app_auth.refresh_at {
            tracing::info!("Refreshing GitHub App installation token");
            let token = installation_token(
                &self.api_url,
                &app_auth.issuer,
                app_auth.installation_id,
                &app_auth.private_key,
            )
            .await?;
            app_auth.client = client(&token)?;
            app_auth.refresh_at = Instant::now() + INSTALLATION_TOKEN_REFRESH;
        }
        Ok(app_auth.client.clone())
    }
}

impl ExternalPlatform for GithubPlatform {
    fn kind(&self) -> &'static str {
        "github"
    }

    async fn user_login_by_id(&self, user_id: &str) -> Result<String, Box<dyn Error>> {
        let client = self.authorized_client().await?;
        user_login_by_id(&client, &self.api_url, user_id).await
    }

    async fn find_pending_invitation(
        &self,
        organization: &str,
        username: Option<&str>,
        email: Option<&str>,
    ) -> Result<Option<PendingInvitation>, Box<dyn Error>> {
        let client = self.authorized_client().await?;
        find_pending_invitation(&client, &self.api_url, organization, username, email).await
    }

    async fn invite_by_email(
        &self,
        organization: &str,
        email: &str,
    ) -> Result<PendingInvitation, InvitationError> {
        let client = self
            .authorized_client()
            .await
            .map_err(|_| InvitationError::Failed("github_authentication_failed".to_owned()))?;
        let response = email_invitation(&client, &self.api_url, organization, email)
            .await
            .map_err(|_| InvitationError::Failed("github_invitation_request_failed".to_owned()))?;
        invitation_response(response).await
    }

    async fn invite_by_user_id(
        &self,
        organization: &str,
        user_id: &str,
    ) -> Result<PendingInvitation, InvitationError> {
        let client = self
            .authorized_client()
            .await
            .map_err(|_| InvitationError::Failed("github_authentication_failed".to_owned()))?;
        let response = user_id_invitation(&client, &self.api_url, organization, user_id)
            .await
            .map_err(|_| InvitationError::Failed("github_invitation_request_failed".to_owned()))?;
        invitation_response(response).await
    }

    async fn organization_snapshot(
        &self,
        organization: &str,
        unresolved_invitation_ids: &HashSet<String>,
    ) -> Result<OrganizationSnapshot, SnapshotError> {
        let client = self
            .authorized_client()
            .await
            .map_err(|_| SnapshotError::Failed("github_authentication_failed".to_owned()))?;
        organization_snapshot(
            &client,
            &self.api_url,
            organization,
            unresolved_invitation_ids,
        )
        .await
    }

    async fn find_or_create_repository(
        &self,
        organization: &str,
        template_owner: &str,
        template_name: &str,
        repository_name: &str,
        expected_description: &str,
    ) -> Result<Repository, String> {
        let client = self
            .authorized_client()
            .await
            .map_err(|_| "github_authentication_failed".to_owned())?;
        find_or_create_repository(
            &client,
            &self.api_url,
            organization,
            template_owner,
            template_name,
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
        let client = self
            .authorized_client()
            .await
            .map_err(|_| "github_authentication_failed".to_owned())?;
        grant_maintain(&client, &self.api_url, organization, repository, username).await
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
        log_http_failure("create_organization_invitation", &response);
        return Err(InvitationError::AlreadyExists);
    }
    log_http_failure("create_organization_invitation", &response);
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

#[derive(Debug, Deserialize)]
struct GithubTemplateRepository {
    private: bool,
    is_template: bool,
    visibility: Option<String>,
}

fn validate_public_template(template: &GithubTemplateRepository) -> Result<(), String> {
    if template.private || template.visibility.as_deref() != Some("public") {
        return Err("repository_template_not_public".to_owned());
    }
    if !template.is_template {
        return Err("repository_template_not_enabled".to_owned());
    }
    Ok(())
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
    let mut headers = common_headers();
    headers.insert(
        header::AUTHORIZATION,
        header::HeaderValue::try_from(format!("Bearer {token}"))?,
    );

    Ok(configure_client(
        Client::builder()
            .user_agent("ainigma-course-access-worker/0.1")
            .default_headers(headers),
    )
    .build()?)
}

fn common_headers() -> header::HeaderMap {
    let mut headers = header::HeaderMap::new();
    headers.insert(
        header::ACCEPT,
        header::HeaderValue::from_static("application/vnd.github+json"),
    );
    headers.insert(
        "x-github-api-version",
        header::HeaderValue::from_static(API_VERSION),
    );
    headers
}

#[derive(Debug, Serialize)]
struct AppClaims {
    iat: u64,
    exp: u64,
    iss: String,
}

#[derive(Debug, Deserialize)]
struct InstallationTokenResponse {
    token: String,
}

fn app_issuer_from_env() -> Result<String, Box<dyn Error>> {
    if let Some(client_id) = env::var("GITHUB_APP_CLIENT_ID")
        .ok()
        .filter(|value| !value.trim().is_empty())
    {
        return Ok(client_id.trim().to_owned());
    }

    let app_id = env::var("GITHUB_APP_ID").map_err(
        |_| "GITHUB_APP_CLIENT_ID or GITHUB_APP_ID must be set when GITHUB_TOKEN is absent",
    )?;
    let app_id = app_id.trim();
    if app_id.is_empty()
        || app_id == "0"
        || !app_id.chars().all(|character| character.is_ascii_digit())
    {
        return Err("GITHUB_APP_ID must be a numeric GitHub App ID".into());
    }
    Ok(app_id.to_owned())
}

fn required_numeric_env(name: &str) -> Result<u64, Box<dyn Error>> {
    let value =
        env::var(name).map_err(|_| format!("{name} must be set when GITHUB_TOKEN is absent"))?;
    let parsed = value
        .parse::<u64>()
        .map_err(|_| format!("{name} must be a numeric GitHub ID"))?;
    if parsed == 0 {
        return Err(format!("{name} must be greater than zero").into());
    }
    Ok(parsed)
}

fn private_key_from_env() -> Result<String, Box<dyn Error>> {
    let inline = env::var("GITHUB_APP_PRIVATE_KEY")
        .ok()
        .filter(|value| !value.trim().is_empty());
    let path = env::var("GITHUB_APP_PRIVATE_KEY_PATH")
        .ok()
        .filter(|value| !value.trim().is_empty());

    match (inline, path) {
        (Some(_), Some(_)) => Err(
            "set only one of GITHUB_APP_PRIVATE_KEY and GITHUB_APP_PRIVATE_KEY_PATH".into(),
        ),
        (Some(value), None) => Ok(value.replace("\\n", "\n")),
        (None, Some(path)) => Ok(fs::read_to_string(path)?),
        (None, None) => Err(
            "GITHUB_APP_PRIVATE_KEY or GITHUB_APP_PRIVATE_KEY_PATH must be set when GITHUB_TOKEN is absent".into(),
        ),
    }
}

fn app_jwt(app_issuer: &str, private_key: &str) -> Result<String, Box<dyn Error>> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let claims = AppClaims {
        iat: now.saturating_sub(60),
        exp: now + 9 * 60,
        iss: app_issuer.to_owned(),
    };
    Ok(encode(
        &Header::new(Algorithm::RS256),
        &claims,
        &EncodingKey::from_rsa_pem(private_key.as_bytes())?,
    )?)
}

async fn installation_token(
    api_url: &str,
    app_issuer: &str,
    installation_id: u64,
    private_key: &str,
) -> Result<String, Box<dyn Error>> {
    let jwt = app_jwt(app_issuer, private_key)?;
    let mut headers = common_headers();
    headers.insert(
        header::AUTHORIZATION,
        header::HeaderValue::try_from(format!("Bearer {jwt}"))?,
    );
    let response = configure_client(
        Client::builder()
            .user_agent("ainigma-course-access-worker/0.1")
            .default_headers(headers),
    )
    .build()?
    .post(format!(
        "{api_url}/app/installations/{installation_id}/access_tokens"
    ))
    .send()
    .await
    .inspect_err(|error| {
        log_request_error("create_installation_access_token", error);
    })?;

    let status = response.status();
    if !status.is_success() {
        log_http_failure("create_installation_access_token", &response);
        return Err(format!(
            "GitHub App installation token request failed with HTTP {}",
            status.as_u16()
        )
        .into());
    }

    Ok(response
        .json::<InstallationTokenResponse>()
        .await
        .inspect_err(|error| {
            log_request_error("decode_installation_access_token", error);
        })?
        .token)
}

pub async fn email_invitation(
    github: &Client,
    api_url: &str,
    organization: &str,
    email: &str,
) -> Result<reqwest::Response, reqwest::Error> {
    let response = github
        .post(format!("{api_url}/orgs/{organization}/invitations"))
        .json(&json!({
            "email": email,
            "role": "direct_member"
        }))
        .send()
        .await;
    if let Err(error) = &response {
        log_request_error("invite_by_email", error);
    }
    response
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
    let response = github
        .post(format!("{api_url}/orgs/{organization}/invitations"))
        .json(&json!({
            "role": "direct_member",
            "invitee_id": invitee_id
        }))
        .send()
        .await;
    if let Err(error) = &response {
        log_request_error("invite_by_user_id", error);
    }
    response.map_err(Into::into)
}

pub async fn user_login_by_id(
    github: &Client,
    api_url: &str,
    github_user_id: &str,
) -> Result<String, Box<dyn Error>> {
    let response = github
        .get(format!("{api_url}/user/{github_user_id}"))
        .send()
        .await
        .inspect_err(|error| {
            log_request_error("lookup_github_user", error);
        })?;
    if !response.status().is_success() {
        log_http_failure("lookup_github_user", &response);
        return Err(format!(
            "GitHub user lookup failed with HTTP {}",
            response.status().as_u16()
        )
        .into());
    }
    Ok(response
        .json::<User>()
        .await
        .inspect_err(|error| {
            log_request_error("decode_github_user", error);
        })?
        .login)
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
        log_http_failure("lookup_github_organization", &response);
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
            log_http_failure("list_github_members", &response);
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
            log_http_failure("list_github_audit_log", &response);
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
            log_http_failure("list_github_invitations", &response);
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

/// Log provider diagnostics without logging request URLs, response bodies, or credentials.
fn log_http_failure(operation: &'static str, response: &reqwest::Response) {
    let request_id = response
        .headers()
        .get("x-github-request-id")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("unknown");
    let rate_limit_remaining = response
        .headers()
        .get("x-ratelimit-remaining")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("unknown");
    let rate_limit_reset = response
        .headers()
        .get("x-ratelimit-reset")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("unknown");

    tracing::error!(
        operation,
        http_status = response.status().as_u16(),
        github_request_id = request_id,
        rate_limit_remaining,
        rate_limit_reset,
        "GitHub API request failed"
    );
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
    template_owner: &str,
    template_name: &str,
    repository_name: &str,
    expected_description: &str,
) -> Result<Repository, String> {
    let get_url = format!("{api_url}/repos/{organization}/{repository_name}");
    let response = github.get(&get_url).send().await.map_err(|error| {
        log_request_error("lookup_github_repository", &error);
        "repository_lookup_failed".to_owned()
    })?;

    let repository = if response.status().is_success() {
        response
            .json::<GithubRepository>()
            .await
            .map(GithubRepository::into_platform)
            .map_err(|_| "repository_response_invalid".to_owned())?
    } else if response.status() == StatusCode::NOT_FOUND {
        let template_response = github
            .get(format!("{api_url}/repos/{template_owner}/{template_name}"))
            .send()
            .await
            .map_err(|error| {
                log_request_error("lookup_github_repository_template", &error);
                "repository_template_lookup_failed".to_owned()
            })?;
        if template_response.status() == StatusCode::NOT_FOUND {
            return Err("repository_template_not_found".to_owned());
        }
        if !template_response.status().is_success() {
            log_http_failure("lookup_github_repository_template", &template_response);
            return Err(format!(
                "repository_template_lookup_http_{}",
                template_response.status().as_u16()
            ));
        }
        let template = template_response
            .json::<GithubTemplateRepository>()
            .await
            .map_err(|_| "repository_template_response_invalid".to_owned())?;
        validate_public_template(&template)?;

        let create_response = github
            .post(format!(
                "{api_url}/repos/{template_owner}/{template_name}/generate"
            ))
            .json(&json!({
                "owner": organization,
                "name": repository_name,
                "description": expected_description,
                "private": true,
                "include_all_branches": false
            }))
            .send()
            .await
            .map_err(|error| {
                log_request_error("generate_github_repository_from_template", &error);
                "repository_template_generate_failed".to_owned()
            })?;

        if create_response.status().is_success() {
            create_response
                .json::<GithubRepository>()
                .await
                .map(GithubRepository::into_platform)
                .map_err(|_| "repository_response_invalid".to_owned())?
        } else if create_response.status() == StatusCode::UNPROCESSABLE_ENTITY {
            let retry_response = github.get(&get_url).send().await.map_err(|error| {
                log_request_error("retry_lookup_github_repository", &error);
                "repository_lookup_failed".to_owned()
            })?;
            if !retry_response.status().is_success() {
                log_http_failure("retry_lookup_github_repository", &retry_response);
                return Err("repository_create_conflict".to_owned());
            }
            retry_response
                .json::<GithubRepository>()
                .await
                .map(GithubRepository::into_platform)
                .map_err(|_| "repository_response_invalid".to_owned())?
        } else {
            log_http_failure("generate_github_repository_from_template", &create_response);
            return Err(format!(
                "repository_template_generate_http_{}",
                create_response.status().as_u16()
            ));
        }
    } else {
        log_http_failure("lookup_github_repository", &response);
        return Err(format!(
            "repository_lookup_http_{}",
            response.status().as_u16()
        ));
    };

    if !repository.private || repository.description.as_deref() != Some(expected_description) {
        return Err("repository_name_collision".to_owned());
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
        .map_err(|error| {
            log_request_error("grant_github_repository_maintain", &error);
            "repository_collaborator_request_failed".to_owned()
        })?;
    if !response.status().is_success() {
        log_http_failure("grant_github_repository_maintain", &response);
        return Err(format!(
            "repository_collaborator_http_{}",
            response.status().as_u16()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        GithubPendingInvitation, GithubTemplateRepository, next_link, validate_public_template,
    };

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

    #[test]
    fn accepts_only_public_template_repositories() {
        let public_template = GithubTemplateRepository {
            private: false,
            is_template: true,
            visibility: Some("public".to_owned()),
        };
        assert_eq!(validate_public_template(&public_template), Ok(()));

        let private_template = GithubTemplateRepository {
            private: true,
            is_template: true,
            visibility: Some("private".to_owned()),
        };
        assert_eq!(
            validate_public_template(&private_template),
            Err("repository_template_not_public".to_owned())
        );

        let internal_template = GithubTemplateRepository {
            private: false,
            is_template: true,
            visibility: Some("internal".to_owned()),
        };
        assert_eq!(
            validate_public_template(&internal_template),
            Err("repository_template_not_public".to_owned())
        );

        let ordinary_repository = GithubTemplateRepository {
            private: false,
            is_template: false,
            visibility: Some("public".to_owned()),
        };
        assert_eq!(
            validate_public_template(&ordinary_repository),
            Err("repository_template_not_enabled".to_owned())
        );
    }
}
