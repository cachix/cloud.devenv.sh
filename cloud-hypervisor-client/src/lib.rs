#![allow(unused_imports)]
#![allow(clippy::too_many_arguments)]
#![cfg(target_os = "linux")]

extern crate futures;
extern crate hyper;
extern crate serde;
extern crate serde_json;
extern crate serde_repr;
extern crate url;

pub mod apis;
pub mod models;
