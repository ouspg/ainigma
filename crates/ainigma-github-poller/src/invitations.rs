use crate::{database, github};
use clap::ValueEnum;
use reqwest::{Client, StatusCode};
use sqlx::PgPool;
use std::error::Error;
use uuid::Uuid;

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
pub enum InvitationMethod {
    Email,
    GithubUserId,
}

impl InvitationMethod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Email => "email",
            Self::GithubUserId => "github_user_id",
        }
    }
}

pub async fn mark_invited(
    database: &PgPool,
    github_client: &Client,
    github_api_url: &str,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
) -> Result<(), Box<dyn Error>> {
    let data = database::invitation_data(database, course_id, profile_id).await?;
    let resolved_username = match data.github_username.as_deref() {
        Some(username) => Some(username.to_owned()),
        None => Some(
            github::user_login_by_id(github_client, github_api_url, &data.github_user_id).await?,
        ),
    };
    let pending = github::find_pending_invitation(
        github_client,
        github_api_url,
        &data.github_org_slug,
        resolved_username.as_deref(),
        data.github_email.as_deref(),
    )
    .await?
    .ok_or("matching pending GitHub invitation not found")?;
    let target = target(&data, method)?;
    database::record_invitation(
        database,
        course_id,
        profile_id,
        method.as_str(),
        &target,
        pending.id,
    )
    .await
}

pub async fn invite_one(
    database: &PgPool,
    github_client: &Client,
    github_api_url: &str,
    course_id: Uuid,
    profile_id: Uuid,
    method: InvitationMethod,
) -> Result<(), Box<dyn Error>> {
    let data = database::invitation_data(database, course_id, profile_id).await?;
    if data.state == "active" {
        return Ok(());
    }
    if data.state == "invitation_pending" {
        let resolved_username = match data.github_username.as_deref() {
            Some(username) => Some(username.to_owned()),
            None => Some(
                github::user_login_by_id(github_client, github_api_url, &data.github_user_id)
                    .await?,
            ),
        };
        if github::find_pending_invitation(
            github_client,
            github_api_url,
            &data.github_org_slug,
            resolved_username.as_deref(),
            data.github_email.as_deref(),
        )
        .await?
        .is_some_and(|pending| data.github_organization_invitation_id == Some(pending.id))
        {
            return Ok(());
        }
    }
    let target = target(&data, method)?;
    let response = match method {
        InvitationMethod::Email => {
            github::email_invitation(
                github_client,
                github_api_url,
                &data.github_org_slug,
                &target,
            )
            .await?
        }
        InvitationMethod::GithubUserId => {
            github::user_id_invitation(
                github_client,
                github_api_url,
                &data.github_org_slug,
                &data.github_user_id,
            )
            .await?
        }
    };

    let invitation_id = if response.status().is_success() {
        response.json::<github::PendingInvitation>().await?.id
    } else if response.status() == StatusCode::UNPROCESSABLE_ENTITY {
        let resolved_username = match data.github_username.as_deref() {
            Some(username) => Some(username.to_owned()),
            None => Some(
                github::user_login_by_id(github_client, github_api_url, &data.github_user_id)
                    .await?,
            ),
        };
        github::find_pending_invitation(
            github_client,
            github_api_url,
            &data.github_org_slug,
            resolved_username.as_deref(),
            data.github_email.as_deref(),
        )
        .await?
        .ok_or("GitHub rejected the invitation and no matching pending invitation exists")?
        .id
    } else {
        return Err(format!(
            "GitHub invitation failed with HTTP {}",
            response.status().as_u16()
        )
        .into());
    };

    database::record_invitation(
        database,
        course_id,
        profile_id,
        method.as_str(),
        &target,
        invitation_id,
    )
    .await
}

fn target(
    data: &database::InvitationData,
    method: InvitationMethod,
) -> Result<String, Box<dyn Error>> {
    let target = match method {
        InvitationMethod::Email => data.github_email.as_deref(),
        InvitationMethod::GithubUserId => Some(data.github_user_id.as_str()),
    };
    target
        .map(str::to_owned)
        .ok_or_else(|| format!("verified GitHub {method:?} is not available").into())
}
