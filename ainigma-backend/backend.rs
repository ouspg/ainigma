use ainigma::flag_generator::{Algorithm, Flag};
use axum::{Json, Router, routing::post};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Deserialize)]
struct GenerateFlagInput {
    identifier: String,
    algorithm: Algorithm,
    user_id: Uuid,
    course_secret: String,
    task_id: String,
}

#[derive(Serialize, Deserialize)]
struct GenerateFlagOutput {
    flag: String,
}

async fn generate_flag_handler(Json(payload): Json<GenerateFlagInput>) -> Json<GenerateFlagOutput> {
    let uuid = payload.user_id;

    let flag = Flag::new_user_flag(
        payload.identifier,     // identifier
        &payload.algorithm,     // algorithm
        &payload.course_secret, // secret
        &payload.task_id,       // taskid
        &uuid,                  // uuid
    )
    .flag_string();

    Json(GenerateFlagOutput { flag })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/generate-task", post(generate_flag_handler));

    println!("Listening on http://localhost:3000");
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
fn app() -> Router {
    Router::new().route("/generate-task", post(generate_flag_handler))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::Json;
    use std::net::SocketAddr;
    use tokio::task;
    use uuid::Uuid;

    #[tokio::test]
    async fn test_generate_task_handler() {
        let user_id = Uuid::now_v7();
        let input = GenerateFlagInput {
            identifier: "id1".to_string(),
            user_id: user_id.clone(),
            task_id: "task1".to_string(),
            algorithm: Algorithm::HMAC_SHA3_256,
            course_secret: "secret".to_string(),
        };

        let response = generate_flag_handler(Json(input)).await;
        let output = response.0;

        // Assert output is non-empty and contains the task id
        assert!(output.flag.starts_with("id1:"));
        println!("Generated flag: {}", output.flag);
    }

    #[tokio::test]
    async fn test_generate_task_integration() {
        let app = app();

        // Spawn the server on a random port
        let addr = SocketAddr::from(([127, 0, 0, 1], 3001));
        task::spawn(async move {
            let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
            axum::serve(listener, app).await.unwrap();
        });

        // Give the server time to start
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        let client = reqwest::Client::new();
        let uuid = Uuid::now_v7();
        let res = client
            .post("http://localhost:3001/generate-task")
            .json(&serde_json::json!({
                "identifier": "id2",
                "algorithm": Algorithm::HMAC_SHA3_256,
                "user_id": uuid,
                "course_secret": "course42",
                "task_id": "taskA"
            }))
            .send()
            .await
            .unwrap();

        let body: GenerateFlagOutput = res.json().await.unwrap();
        assert!(body.flag.starts_with("id2:"));
        println!("Flag: {}", body.flag);
    }
}
