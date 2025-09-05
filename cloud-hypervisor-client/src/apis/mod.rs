use std::fmt::Debug;
use std::fmt::{self, Display};

use hyper;
use hyper::http;
use hyper_util::client::legacy::connect::Connect;
use serde_json;

#[derive(Debug)]
pub enum Error {
    Api(ApiError),
    Header(http::header::InvalidHeaderValue),
    Http(http::Error),
    Hyper(hyper::Error),
    HyperClient(hyper_util::client::legacy::Error),
    Serde(serde_json::Error),
    UriError(http::uri::InvalidUri),
}

impl Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            Error::Api(ref e) => {
                write!(
                    f,
                    "API error: {} {}",
                    e.code,
                    String::from_utf8_lossy(&e.body)
                )
            }
            Error::Header(ref e) => write!(f, "Header error: {e}"),
            Error::Http(ref e) => write!(f, "HTTP error: {e}"),
            Error::Hyper(ref e) => write!(f, "Hyper error: {e}"),
            Error::HyperClient(ref e) => write!(f, "Hyper client error: {e}"),
            Error::Serde(ref e) => write!(f, "Serde error: {e}"),
            Error::UriError(ref e) => write!(f, "URI error: {e}"),
        }
    }
}

pub struct ApiError {
    pub code: hyper::StatusCode,
    pub body: hyper::body::Bytes,
}

impl Debug for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ApiError")
            .field("code", &self.code)
            .field("body", &"hyper::body::Incoming")
            .finish()
    }
}

impl From<(hyper::StatusCode, hyper::body::Bytes)> for Error {
    fn from(e: (hyper::StatusCode, hyper::body::Bytes)) -> Self {
        Error::Api(ApiError {
            code: e.0,
            body: e.1,
        })
    }
}

impl From<http::Error> for Error {
    fn from(e: http::Error) -> Self {
        Error::Http(e)
    }
}

impl From<hyper_util::client::legacy::Error> for Error {
    fn from(e: hyper_util::client::legacy::Error) -> Self {
        Error::HyperClient(e)
    }
}

impl From<hyper::Error> for Error {
    fn from(e: hyper::Error) -> Self {
        Error::Hyper(e)
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Error::Serde(e)
    }
}

mod request;

mod default_api;
pub use self::default_api::{DefaultApi, DefaultApiClient};

pub mod client;
pub mod configuration;
