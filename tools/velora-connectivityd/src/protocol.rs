//! JSON lines between the shell and this daemon: one message per line on stdin and stdout.
//!
//! Replies never echo a request's parameters, so a password sent in one stays out of everything else.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Raised on any change the shell has to know about. It checks this in the first message, so a shell
/// updated without its daemon says so instead of misreading what it gets.
pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Deserialize)]
pub struct Request {
    pub id: u64,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ApiError {
    pub code: ErrorCode,
    pub message: String,
}

/// What went wrong, in the terms the interface acts on. `message` is the raw detail, for a tooltip.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    Invalid,
    UnknownMethod,
    Unavailable,
    NotFound,
    PermissionDenied,
    SecretsRequired,
    WrongSecret,
    Conflict,
    Timeout,
    Canceled,
    Failed,
}

impl ApiError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Invalid, message)
    }
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Outgoing<'a> {
    Hello {
        protocol: u32,
        agents: bool,
    },
    Response {
        id: u64,
        ok: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        result: Option<Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<&'a ApiError>,
    },
    /// The whole state of one domain (`network`, `bluetooth`), sent when it changes.
    Snapshot {
        domain: &'a str,
        data: &'a Value,
    },
    /// Something that needs an answer from the user, or a thing they should hear about.
    Event {
        name: &'a str,
        data: &'a Value,
    },
}

impl Outgoing<'_> {
    pub fn to_line(&self) -> String {
        let mut line = serde_json::to_string(self).expect("messages only hold JSON values and plain fields");
        line.push('\n');
        line
    }

    pub fn reply(id: u64, result: &Result<Value, ApiError>) -> String {
        match result {
            Ok(value) => Outgoing::Response { id, ok: true, result: Some(value.clone()), error: None },
            Err(error) => Outgoing::Response { id, ok: false, result: None, error: Some(error) },
        }
        .to_line()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn replies_are_one_line_of_json() {
        let line = Outgoing::reply(4, &Ok(json!({ "a": "b\nc" })));
        assert_eq!(line.matches('\n').count(), 1);
        assert_eq!(serde_json::from_str::<Value>(&line).unwrap(), json!({ "type": "response", "id": 4, "ok": true, "result": { "a": "b\nc" } }));
    }

    #[test]
    fn errors_carry_a_code_the_shell_acts_on() {
        let line = Outgoing::reply(5, &Err(ApiError::new(ErrorCode::WrongSecret, "supplicant said no")));
        assert_eq!(
            serde_json::from_str::<Value>(&line).unwrap(),
            json!({ "type": "response", "id": 5, "ok": false, "error": { "code": "wrong_secret", "message": "supplicant said no" } })
        );
    }

    #[test]
    fn a_request_may_leave_out_its_parameters() {
        let request: Request = serde_json::from_str(r#"{"id":1,"method":"ping"}"#).unwrap();
        assert_eq!((request.id, request.method.as_str(), request.params), (1, "ping", Value::Null));
    }

    #[test]
    fn hello_states_the_version() {
        let line = Outgoing::Hello { protocol: PROTOCOL_VERSION, agents: true }.to_line();
        assert_eq!(serde_json::from_str::<Value>(&line).unwrap(), json!({ "type": "hello", "protocol": 1, "agents": true }));
    }
}
