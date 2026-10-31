//! Turning NetworkManager's reason numbers into what to tell people, as plasma-nm does: the ones that
//! are routine say nothing, a refused password is told apart, and the rest get a sentence.

use crate::protocol::{ApiError, ErrorCode};

const DEVICE_NO_SECRETS: i64 = 7;
const DEVICE_SUPPLICANT_DISCONNECT: i64 = 8;
const DEVICE_SUPPLICANT_TIMEOUT: i64 = 11;
const DEVICE_SSID_NOT_FOUND: i64 = 53;
const ACTIVE_USER_DISCONNECTED: i64 = 2;
const ACTIVE_NO_SECRETS: i64 = 9;
const ACTIVE_LOGIN_FAILED: i64 = 10;

/// None for the reasons that aren't failures worth a message.
pub fn device_reason_text(reason: i64) -> Option<&'static str> {
    Some(match reason {
        4 => "The device could not be configured",
        5 => "IP configuration is unavailable",
        6 => "IP configuration expired",
        7 => "No password was provided",
        8 => "The access point rejected the connection",
        9 => "The Wi-Fi supplicant could not be configured",
        10 => "The Wi-Fi supplicant failed",
        11 => "The Wi-Fi network did not answer in time",
        12 => "The PPP service could not start",
        13 => "The PPP service disconnected",
        14 => "The PPP service failed",
        15 => "The DHCP service could not start",
        16 => "The DHCP service reported an error",
        17 => "DHCP failed",
        18 => "The shared connection service could not start",
        19 => "The shared connection service failed",
        20 => "The AutoIP service could not start",
        21 => "The AutoIP service reported an error",
        22 => "The AutoIP service failed",
        23 => "The line is busy",
        24 => "There is no dial tone",
        25 => "No carrier could be established",
        26 => "The dialing request timed out",
        27 => "The dialing attempt failed",
        28 => "Modem initialization failed",
        29 => "The APN could not be selected",
        30 => "The device is not searching for a network",
        31 => "Network registration was denied",
        32 => "Network registration timed out",
        33 => "Network registration failed",
        34 => "The PIN check failed",
        35 => "The device's firmware is missing",
        36 => "The device was removed",
        37 => "The system is going to sleep",
        38 => "The connection was removed",
        40 => "The cable was disconnected",
        43 => "The modem could not be found",
        44 => "The Bluetooth connection failed",
        45 => "The SIM card is missing",
        46 => "The SIM PIN is required",
        47 => "The SIM PUK is required",
        48 => "The SIM card is wrong",
        49 => "InfiniBand mode is not supported",
        50 => "A connection this one depends on failed",
        51 => "The bridge is unavailable",
        52 => "No mobile network provider was found",
        54 => "A secondary connection failed",
        55 => "The DCB or FCoE service failed",
        56 => "teamd failed",
        57 => "The modem failed",
        58 => "The modem became available",
        59 => "The SIM PIN is incorrect",
        60 => "A new connection was requested",
        61 => "A carrier could not be found",
        62 => "The device is managed by another service",
        _ => return None,
    })
}

/// What a failed activation means, from the reason its device gave and the one its connection gave.
pub fn activation_error(device_reason: Option<i64>, active_reason: i64) -> ApiError {
    let by_device = match device_reason {
        Some(DEVICE_NO_SECRETS) => Some((ErrorCode::SecretsRequired, "No password was provided")),
        Some(DEVICE_SUPPLICANT_DISCONNECT) => Some((ErrorCode::WrongSecret, "The password was rejected")),
        Some(DEVICE_SUPPLICANT_TIMEOUT) => Some((ErrorCode::Timeout, "The Wi-Fi network did not answer in time")),
        Some(DEVICE_SSID_NOT_FOUND) => Some((ErrorCode::NotFound, "The network is out of range")),
        Some(reason) => device_reason_text(reason).map(|text| (ErrorCode::Failed, text)),
        None => None,
    };
    if let Some((code, text)) = by_device {
        return ApiError::new(code, text);
    }
    match active_reason {
        ACTIVE_USER_DISCONNECTED => ApiError::new(ErrorCode::Canceled, "The connection was canceled"),
        ACTIVE_NO_SECRETS => ApiError::new(ErrorCode::SecretsRequired, "No password was provided"),
        ACTIVE_LOGIN_FAILED => ApiError::new(ErrorCode::WrongSecret, "The login was refused"),
        3 => ApiError::new(ErrorCode::Failed, "The device was disconnected"),
        4 => ApiError::new(ErrorCode::Failed, "The VPN service stopped"),
        5 => ApiError::new(ErrorCode::Failed, "The IP configuration was invalid"),
        6 => ApiError::new(ErrorCode::Timeout, "The connection attempt timed out"),
        7 => ApiError::new(ErrorCode::Timeout, "The VPN service did not start in time"),
        8 => ApiError::new(ErrorCode::Failed, "The VPN service failed to start"),
        11 => ApiError::new(ErrorCode::NotFound, "The connection was removed"),
        12 => ApiError::new(ErrorCode::Failed, "A connection this one depends on failed"),
        13 | 14 => ApiError::new(ErrorCode::Failed, "The device was removed"),
        _ => ApiError::new(ErrorCode::Failed, "Connection failed"),
    }
}

/// A NetworkManager error reply, in the shell's terms.
pub fn dbus_error(error: &zbus::Error) -> ApiError {
    let Some((name, message)) = error_parts(error) else {
        return ApiError::new(ErrorCode::Failed, error.to_string());
    };
    let code = match name.rsplit('.').next().unwrap_or_default() {
        "PermissionDenied" | "NotAuthorized" | "AccessDenied" | "NotAuthorizedError" => ErrorCode::PermissionDenied,
        "NoSecrets" | "NoSecretsError" => ErrorCode::SecretsRequired,
        "UserCanceled" | "AgentCanceled" | "Canceled" => ErrorCode::Canceled,
        "InvalidArguments" | "InvalidConnection" | "InvalidProperty" | "MissingProperty" | "InvalidArgs" => ErrorCode::Invalid,
        "UnknownConnection" | "UnknownDevice" | "UnknownObject" | "UnknownMethod" | "ConnectionNotActive" | "ConnectionNotFound" | "DoesNotExist" => ErrorCode::NotFound,
        "ServiceUnknown" | "NameHasNoOwner" | "NoReply" | "NotReady" | "ServiceUnavailable" => ErrorCode::Unavailable,
        "Timeout" | "TimedOut" => ErrorCode::Timeout,
        _ => ErrorCode::Failed,
    };
    ApiError::new(code, message)
}

fn error_parts(error: &zbus::Error) -> Option<(String, String)> {
    match error {
        zbus::Error::MethodError(name, message, _) => Some((name.to_string(), message.clone().unwrap_or_else(|| name.to_string()))),
        zbus::Error::FDO(inner) => {
            let text = inner.to_string();
            let (name, message) = text.split_once(": ").unwrap_or((text.as_str(), text.as_str()));
            Some((name.to_string(), message.to_string()))
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_refused_password_is_told_apart() {
        assert_eq!(activation_error(Some(8), 3).code, ErrorCode::WrongSecret);
        assert_eq!(activation_error(Some(7), 3).code, ErrorCode::SecretsRequired);
        assert_eq!(activation_error(None, 9).code, ErrorCode::SecretsRequired);
        assert_eq!(activation_error(None, 10).code, ErrorCode::WrongSecret);
    }

    #[test]
    fn the_device_reason_comes_before_the_connections() {
        let error = activation_error(Some(17), 3);
        assert_eq!((error.code, error.message.as_str()), (ErrorCode::Failed, "DHCP failed"));
        assert_eq!(activation_error(Some(53), 3).code, ErrorCode::NotFound);
        assert_eq!(activation_error(Some(11), 3).code, ErrorCode::Timeout);
    }

    #[test]
    fn routine_device_reasons_fall_through_to_the_connections() {
        assert_eq!(activation_error(Some(0), 2).code, ErrorCode::Canceled);
        assert_eq!(activation_error(Some(39), 6).code, ErrorCode::Timeout);
        assert_eq!(activation_error(None, 0).message, "Connection failed");
    }

    #[test]
    fn routine_reasons_have_no_text() {
        for reason in [0, 1, 2, 3, 39, 41, 42, 53, 999] {
            assert_eq!(device_reason_text(reason), None, "reason {reason}");
        }
        assert!(device_reason_text(17).is_some());
    }

    #[test]
    fn every_failure_reason_has_its_own_sentence() {
        let failures: Vec<i64> = (4..=38).chain(40..=40).chain(43..=52).chain(54..=62).collect();
        let mut seen = std::collections::HashSet::new();
        for reason in failures {
            let text = device_reason_text(reason).unwrap_or_else(|| panic!("reason {reason} has no text"));
            assert!(seen.insert(text), "reason {reason} repeats: {text}");
            assert!(!activation_error(Some(reason), 0).message.is_empty());
        }
    }

    #[test]
    fn dbus_error_names_map_to_what_the_shell_acts_on() {
        for (name, code) in [
            ("org.freedesktop.NetworkManager.PermissionDenied", ErrorCode::PermissionDenied),
            ("org.freedesktop.NetworkManager.AgentManager.NoSecrets", ErrorCode::SecretsRequired),
            ("org.freedesktop.NetworkManager.SecretAgent.UserCanceled", ErrorCode::Canceled),
            ("org.freedesktop.NetworkManager.Settings.InvalidProperty", ErrorCode::Invalid),
            ("org.freedesktop.NetworkManager.UnknownConnection", ErrorCode::NotFound),
            ("org.freedesktop.DBus.Error.ServiceUnknown", ErrorCode::Unavailable),
            ("org.freedesktop.DBus.Error.Timeout", ErrorCode::Timeout),
            ("org.freedesktop.NetworkManager.Failed", ErrorCode::Failed),
        ] {
            let call = zbus::message::Message::method_call("/", "Ping").sender(":1.1").destination(":1.2").build(&()).unwrap();
            let message = zbus::message::Message::error(&call.header(), name).build(&("detail",)).unwrap();
            let error = zbus::Error::from(message);
            assert_eq!(dbus_error(&error).code, code, "{name}");
        }
    }

    #[test]
    fn every_connection_reason_has_a_sentence() {
        for reason in 0..=15 {
            assert!(!activation_error(None, reason).message.is_empty());
        }
    }

    #[test]
    fn dbus_errors_keep_their_meaning() {
        let error = zbus::Error::FDO(Box::new(zbus::fdo::Error::AccessDenied("no".to_string())));
        assert_eq!(dbus_error(&error).code, ErrorCode::PermissionDenied);
        let error = zbus::Error::FDO(Box::new(zbus::fdo::Error::ServiceUnknown("gone".to_string())));
        assert_eq!(dbus_error(&error).code, ErrorCode::Unavailable);
        assert_eq!(dbus_error(&zbus::Error::InvalidReply).code, ErrorCode::Failed);
    }
}
