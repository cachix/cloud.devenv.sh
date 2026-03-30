use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

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

        (StatusCode::INTERNAL_SERVER_ERROR, Json(())).into_response()
    }
}
