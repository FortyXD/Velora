//! Mouse links use terminal cell coordinates. Wallpaper file names may never escape their directory.
use anyhow::{ensure, Result};
use regex::Regex;
use sha2::{Digest, Sha256};
use std::{
    os::unix::process::CommandExt,
    process::{Command, ExitCode, Stdio},
};
use unicode_width::UnicodeWidthChar;
use url::Url;

fn web_url(s: &str) -> Option<Url> {
    if s.chars().any(char::is_control) || s.contains('\\') {
        return None;
    }
    let (scheme, rest) = s.split_once("://")?;
    if !(scheme.eq_ignore_ascii_case("http") || scheme.eq_ignore_ascii_case("https"))
        || rest.is_empty()
        || rest.starts_with('/')
    {
        return None;
    }
    Url::parse(s).ok().filter(|u| u.host().is_some())
}
pub fn wallpaper(s: &str) -> Result<()> {
    let url = web_url(s).ok_or_else(|| anyhow::anyhow!("Invalid wallpaper URL"))?;
    let authority = s
        .split_once("://")
        .unwrap()
        .1
        .split(['/', '?', '#'])
        .next()
        .unwrap_or("");
    ensure!(!authority.contains('@'), "Invalid wallpaper URL");
    let path = url.path().rsplit('/').next().unwrap_or("");
    let mut name = crate::apps::unquote(path)
        .replace(|c: char| c.is_control() || matches!(c, '/' | '\\'), "_");
    if matches!(name.as_str(), "" | "." | "..") || name.len() > 220 {
        name = format!("{:x}.image", Sha256::digest(s.as_bytes()));
    }
    println!("{name}");
    Ok(())
}
fn cells(s: &str) -> usize {
    s.chars().map(|c| c.width().unwrap_or(0)).sum()
}
fn link_at(line: &str, column: usize) -> Option<&str> {
    let re = Regex::new(r#"https?://[^\s<>"\x00-\x1f]+"#).ok()?;
    for m in re.find_iter(line) {
        let link = m
            .as_str()
            .trim_end_matches(['.', ',', ';', '!', ')', ']', '}']);
        let left = cells(&line[..m.start()]);
        if column >= left && column - left < cells(link) && web_url(link).is_some() {
            return Some(link);
        }
    }
    None
}
pub fn tmux(argv: &[String]) -> Result<ExitCode> {
    let field = |tag| argv.iter().rev().find_map(|v| v.strip_prefix(tag));
    let url = [field('h'), field('w')]
        .into_iter()
        .flatten()
        .find(|s| web_url(s).is_some())
        .or_else(|| {
            let x = field('x')?.parse::<usize>().ok()?;
            let column = x.checked_sub(field('p').unwrap_or("0").parse().ok()?)?;
            link_at(field('l')?, column)
        });
    let Some(url) = url else {
        return Ok(ExitCode::FAILURE);
    };
    let mut open = Command::new("xdg-open");
    open.arg(url)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // SAFETY: setsid is async-signal-safe and called only in the child.
    unsafe {
        open.pre_exec(|| {
            if libc::setsid() < 0 {
                Err(std::io::Error::last_os_error())
            } else {
                Ok(())
            }
        });
    }
    open.spawn()?;
    Ok(ExitCode::SUCCESS)
}
