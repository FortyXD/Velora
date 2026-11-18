//! Google screen OCR, translation and service-account OAuth. Secrets travel on file descriptors.
use anyhow::{ensure, Context, Result};
use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine,
};
use rustix::fs::{memfd_create, MemfdFlags};
use serde_json::{json, Value};
use std::{
    fs::{self, File},
    io::{self, Seek, Write},
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::{Command, Output, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

fn memory_file(bytes: &[u8]) -> Result<File> {
    let mut f = File::from(memfd_create("velora-cloud", MemfdFlags::CLOEXEC)?);
    f.write_all(bytes)?;
    f.rewind()?;
    Ok(f)
}

// The first descriptor is stdin. The second is private to this call and survives exec as fd 3.
fn request_process(cmd: &mut Command, input: &[u8], extra: &[u8]) -> Result<Output> {
    let source = memory_file(extra)?;
    let fd = source.as_raw_fd();
    cmd.stdin(Stdio::from(memory_file(input)?))
        .stderr(Stdio::null());
    // SAFETY: source stays open through spawn; dup2 and fcntl are async-signal-safe.
    unsafe {
        cmd.pre_exec(move || {
            if libc::dup2(fd, 3) < 0 || libc::fcntl(3, libc::F_SETFD, 0) < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    Ok(cmd.output()?)
}

fn post(url: &str, headers: &str, body: &[u8]) -> Result<(u16, Value)> {
    let out = request_process(
        Command::new("curl").args([
            "-q",
            "--silent",
            "--proto",
            "=https",
            "--max-time",
            "60",
            "--header",
            "@/dev/fd/3",
            "--data-binary",
            "@-",
            "--write-out",
            "\n%{response_code}",
            "--url",
            url,
        ]),
        body,
        headers.as_bytes(),
    )?;
    ensure!(out.status.success(), "Cloud transport failed");
    let split = out
        .stdout
        .iter()
        .rposition(|&b| b == b'\n')
        .context("Missing HTTP status")?;
    let status = std::str::from_utf8(&out.stdout[split + 1..])?
        .trim()
        .parse::<u16>()?;
    let data = serde_json::from_slice(&out.stdout[..split]);
    if (200..300).contains(&status) {
        return Ok((status, data?));
    }
    let value: Value = data.unwrap_or(Value::Null);
    Ok((
        status,
        json!({"error":{"code":status,"message":value.pointer("/error/message").and_then(Value::as_str).unwrap_or("Google Cloud request failed")}}),
    ))
}

fn field<'a>(value: &'a Value, name: &str) -> Result<&'a str> {
    value[name]
        .as_str()
        .filter(|s| !s.is_empty())
        .with_context(|| format!("Missing {name}"))
}
fn screen(params: &Value) -> Result<Value> {
    let project = field(params, "project")?;
    let token = field(params, "token")?;
    ensure!(
        project.as_bytes()[0].is_ascii_alphanumeric()
            && project
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b".:-".contains(&b))
            && token.bytes().all(|b| (33..=126).contains(&b)),
        "Invalid cloud credentials"
    );
    let (url, body) = match field(params, "operation")? {
        "vision" => (
            "https://vision.googleapis.com/v1/images:annotate".into(),
            json!({"requests":[{"image":{"content":STANDARD.encode(fs::read(field(params,"path")?)?)},"features":[{"type":"DOCUMENT_TEXT_DETECTION"}]}]}),
        ),
        "translate" => (
            format!(
                "https://translation.googleapis.com/v3/projects/{}:translateText",
                crate::apps::quote(project, "")
            ),
            json!({"targetLanguageCode":field(params,"language")?,"contents":params["contents"].as_array().context("Missing contents")?,"mimeType":"text/plain"}),
        ),
        _ => anyhow::bail!("Unknown cloud operation"),
    };
    let headers=format!("Authorization: Bearer {token}\nx-goog-user-project: {project}\nContent-Type: application/json\n");
    Ok(post(&url, &headers, &serde_json::to_vec(&body)?)?.1)
}

fn token(key: &Value) -> Result<Value> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let endpoint = field(key, "token_uri")?;
    ensure!(
        endpoint.starts_with("https://") && !endpoint.chars().any(char::is_control),
        "Invalid token endpoint"
    );
    let mut header = json!({"alg":"RS256","typ":"JWT"});
    if let Some(kid) = key["private_key_id"].as_str() {
        header["kid"] = json!(kid);
    }
    let claims = json!({"iss":field(key,"client_email")?,"scope":"https://www.googleapis.com/auth/cloud-platform","aud":"https://oauth2.googleapis.com/token","iat":now,"exp":now+3600});
    let signed = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&header)?),
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims)?)
    );
    let signature = request_process(
        Command::new("openssl").args([
            "dgst",
            "-sha256",
            "-sign",
            "/dev/stdin",
            "-binary",
            "/dev/fd/3",
        ]),
        field(key, "private_key")?.as_bytes(),
        signed.as_bytes(),
    )?;
    ensure!(
        signature.status.success(),
        "Could not sign the service account assertion"
    );
    let body = format!(
        "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={signed}.{}",
        URL_SAFE_NO_PAD.encode(signature.stdout)
    );
    let (status, response) = post(
        endpoint,
        "Content-Type: application/x-www-form-urlencoded\n",
        body.as_bytes(),
    )?;
    ensure!(
        (200..300).contains(&status),
        "Token request failed (HTTP {status})"
    );
    Ok(
        json!({"token":field(&response,"access_token")?,"expiry":now.checked_add(response["expires_in"].as_u64().context("Missing expiry")?).context("Invalid expiry")?}),
    )
}
pub fn run(is_token: bool) -> Result<()> {
    let request: Value =
        serde_json::from_reader(io::stdin().lock()).context("Invalid cloud request")?;
    let response = if is_token {
        token(&request)?
    } else {
        screen(&request)?
    };
    println!("{response}");
    Ok(())
}
