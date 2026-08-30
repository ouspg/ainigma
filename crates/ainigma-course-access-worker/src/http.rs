use reqwest::ClientBuilder;
use std::time::Duration;

pub(crate) const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
pub(crate) const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

pub(crate) fn configure_client(builder: ClientBuilder) -> ClientBuilder {
    builder
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(REQUEST_TIMEOUT)
}

pub(crate) fn log_request_error(operation: &'static str, error: &reqwest::Error) {
    if error.is_timeout() {
        tracing::error!(
            operation,
            timeout_seconds = REQUEST_TIMEOUT.as_secs(),
            "External HTTP request timed out"
        );
    }
}
