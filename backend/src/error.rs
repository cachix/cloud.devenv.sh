use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use thiserror::Error;

pub type Result<T, E = Report> = color_eyre::Result<T, E>;
pub struct Report(color_eyre::Report);

impl std::fmt::Debug for Report {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

impl<E> From<E> for Report
where
    E: Into<color_eyre::Report>,
{
    #[track_caller]
    fn from(err: E) -> Self {
        Self(err.into())
    }
}

impl IntoResponse for Report {
    fn into_response(self) -> Response {
        let err = self.0;
        let err_string = format!("{err:?}");
        tracing::error!("{err_string}");

        if let Some(err) = err.downcast_ref::<InternalError>() {
            return err.response();
        }

        (StatusCode::INTERNAL_SERVER_ERROR, Json(())).into_response()
    }
}

#[derive(Error, Debug)]
pub enum InternalError {
    #[error("Octocrab Error")]
    Octocrab(#[from] octocrab::Error),
    #[error("IO Error")]
    Io(#[from] std::io::Error),
    #[error("Pool Error")]
    Pool(#[from] diesel_async::pooled_connection::deadpool::PoolError),
    #[error("String Error")]
    String(String),
    #[error("Query Error")]
    QueryResult(#[from] diesel::result::Error),
    #[error("JSON Error")]
    Json(#[from] serde_json::Error),
    #[error("Invalid Length Error")]
    InvalidLength(#[from] digest::InvalidLength),
    #[error("Hex Error")]
    Hex(#[from] hex::FromHexError),
}

impl InternalError {
    fn response(&self) -> Response {
        (StatusCode::INTERNAL_SERVER_ERROR, Json(())).into_response()
    }
}
