//! Handing a saved password on: the Wi-Fi QR code, and the clipboard. Both go to their program over stdin,
//! so the password never shows up in a process list.

use super::model::Security;
use crate::protocol::{ApiError, ErrorCode};
use crate::secret::Secret;
use std::process::Stdio;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use zeroize::Zeroizing;

fn escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for character in value.chars() {
        if matches!(character, '\\' | ';' | ',' | ':' | '"') {
            escaped.push('\\');
        }
        escaped.push(character);
    }
    escaped
}

/// The standard text a phone's camera reads to join a network.
pub fn wifi_qr_payload(ssid: &str, security: Security, password: Option<&Secret>, hidden: bool) -> Zeroizing<String> {
    let kind = match security {
        Security::Wep => "WEP",
        Security::Sae => "SAE",
        Security::WpaPsk => "WPA",
        _ => "nopass",
    };
    let mut payload = format!("WIFI:T:{kind};S:{};", escape(ssid));
    if let Some(password) = password.filter(|_| kind != "nopass") {
        payload.push_str(&format!("P:{};", escape(password.expose())));
    }
    if hidden {
        payload.push_str("H:true;");
    }
    payload.push(';');
    Zeroizing::new(payload)
}

pub fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let group = u32::from(chunk[0]) << 16 | u32::from(*chunk.get(1).unwrap_or(&0)) << 8 | u32::from(*chunk.get(2).unwrap_or(&0));
        for index in 0..4 {
            if index <= chunk.len() {
                output.push(TABLE[(group >> (18 - index * 6) & 63) as usize] as char);
            } else {
                output.push('=');
            }
        }
    }
    output
}

async fn run_with_stdin(program: &str, arguments: &[&str], input: &[u8]) -> Result<Vec<u8>, ApiError> {
    let mut child = Command::new(program)
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| ApiError::new(ErrorCode::Unavailable, format!("{program} is not installed")))?;
    let mut stdin = child.stdin.take().expect("stdin is piped");
    stdin.write_all(input).await.map_err(|_| ApiError::new(ErrorCode::Failed, format!("{program} stopped reading")))?;
    drop(stdin);
    let output = child.wait_with_output().await.map_err(|_| ApiError::new(ErrorCode::Failed, format!("{program} failed")))?;
    if !output.status.success() {
        return Err(ApiError::new(ErrorCode::Failed, format!("{program} failed")));
    }
    Ok(output.stdout)
}

/// A PNG of the code, as a data URL an image element can show.
pub async fn qr_image(payload: &str) -> Result<String, ApiError> {
    let png = run_with_stdin("qrencode", &["-t", "PNG", "-s", "8", "-m", "2", "-o", "-"], payload.as_bytes()).await?;
    Ok(format!("data:image/png;base64,{}", base64(&png)))
}

/// Puts a password on the clipboard, flagged so clipboard histories leave it out.
pub async fn copy_to_clipboard(secret: &Secret) -> Result<(), ApiError> {
    run_with_stdin("wl-copy", &["--sensitive"], secret.expose().as_bytes()).await.map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qr_text_for_each_kind_of_network() {
        let password = Secret::new("hunter2");
        assert_eq!(wifi_qr_payload("Home", Security::WpaPsk, Some(&password), false).as_str(), "WIFI:T:WPA;S:Home;P:hunter2;;");
        assert_eq!(wifi_qr_payload("Home", Security::Sae, Some(&password), false).as_str(), "WIFI:T:SAE;S:Home;P:hunter2;;");
        assert_eq!(wifi_qr_payload("Old", Security::Wep, Some(&password), false).as_str(), "WIFI:T:WEP;S:Old;P:hunter2;;");
        assert_eq!(wifi_qr_payload("Cafe", Security::None, None, false).as_str(), "WIFI:T:nopass;S:Cafe;;");
        assert_eq!(wifi_qr_payload("Cafe", Security::Owe, Some(&password), false).as_str(), "WIFI:T:nopass;S:Cafe;;");
        assert_eq!(wifi_qr_payload("Ghost", Security::WpaPsk, Some(&password), true).as_str(), "WIFI:T:WPA;S:Ghost;P:hunter2;H:true;;");
    }

    #[test]
    fn special_characters_are_escaped() {
        let password = Secret::new(r#"a;b,c:d"e\f"#);
        assert_eq!(
            wifi_qr_payload("My;Net", Security::WpaPsk, Some(&password), false).as_str(),
            r#"WIFI:T:WPA;S:My\;Net;P:a\;b\,c\:d\"e\\f;;"#
        );
    }

    #[test]
    fn base64_matches_the_standard_vectors() {
        for (input, expected) in [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")] {
            assert_eq!(base64(input.as_bytes()), expected);
        }
        assert_eq!(base64(&[0xFF, 0xEF, 0xBE]), "/+++");
    }
}
