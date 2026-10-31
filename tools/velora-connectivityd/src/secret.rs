//! A password or key in transit. It can be read from a request and handed to D-Bus, but it has no
//! `Serialize` and a redacted `Debug`, so a log line or a snapshot can't carry one by accident.

use serde::{Deserialize, Deserializer};
use std::fmt;
use zeroize::Zeroizing;

#[derive(Clone, Default, PartialEq, Eq)]
pub struct Secret(Zeroizing<String>);

impl Secret {
    pub fn new(value: impl Into<String>) -> Self {
        Self(Zeroizing::new(value.into()))
    }

    pub fn expose(&self) -> &str {
        &self.0
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("Secret(<redacted>)")
    }
}

impl<'de> Deserialize<'de> for Secret {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        String::deserialize(deserializer).map(Secret::new)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_never_shows_the_value() {
        let secret = Secret::new("hunter2");
        assert_eq!(format!("{secret:?}"), "Secret(<redacted>)");
        assert_eq!(format!("{:?}", Some(secret.clone())), "Some(Secret(<redacted>))");
        assert_eq!(secret.expose(), "hunter2");
    }

    #[test]
    fn it_reads_from_a_request() {
        let secret: Secret = serde_json::from_str("\"pass word\"").unwrap();
        assert_eq!(secret.expose(), "pass word");
        assert!(!secret.is_empty());
        assert!(Secret::default().is_empty());
    }
}
