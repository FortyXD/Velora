//! Only explicit visited timestamps from the desktop's recent-file registry count as activity.
use anyhow::Result;
use quick_xml::{events::Event, Reader};
use std::{
    io::Read,
    path::{Path, PathBuf},
};

pub fn path() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share")
        })
        .join("recently-used.xbel")
}

pub fn parse(xml: &str) -> Vec<(PathBuf, i64)> {
    let mut reader = Reader::from_str(xml);
    let mut output = Vec::new();
    loop {
        match reader.read_event() {
            Ok(Event::Start(e) | Event::Empty(e)) if e.name().as_ref() == b"bookmark" => {
                let mut href = None;
                let mut visited = None;
                for attr in e.attributes().flatten() {
                    let Ok(value) = attr.decode_and_unescape_value(reader.decoder()) else {
                        continue;
                    };
                    match attr.key.as_ref() {
                        b"href" => href = Some(value.into_owned()),
                        b"visited" => {
                            visited = chrono::DateTime::parse_from_rfc3339(&value)
                                .ok()
                                .map(|v| v.timestamp())
                        }
                        _ => {}
                    }
                }
                if let (Some(href), Some(at)) = (href, visited) {
                    if let Some(value) = href.strip_prefix("file://") {
                        if value.starts_with('/') {
                            if let Ok(path) =
                                percent_encoding::percent_decode_str(value).decode_utf8()
                            {
                                output.push((PathBuf::from(path.as_ref()), at));
                            }
                        }
                    }
                }
            }
            Ok(Event::Eof) | Err(_) => break,
            _ => {}
        }
    }
    output
}

pub fn read(file: &Path) -> Result<Vec<(PathBuf, i64)>> {
    anyhow::ensure!(
        file.metadata()?.len() <= 2 * 1024 * 1024,
        "Recent-file registry exceeds its limit"
    );
    let mut text = String::new();
    std::fs::File::open(file)?
        .take(2 * 1024 * 1024 + 1)
        .read_to_string(&mut text)?;
    anyhow::ensure!(
        text.len() <= 2 * 1024 * 1024,
        "Recent-file registry exceeds its limit"
    );
    Ok(parse(&text))
}

#[cfg(test)]
mod tests {
    #[test]
    fn only_explicit_local_visits_are_imported() {
        let entries = super::parse(
            r#"<xbel><bookmark href="file:///tmp/a%20b.md" visited="2026-11-02T12:00:00Z"/><bookmark href="file:///tmp/modified" modified="2026-11-02T12:00:00Z"/><bookmark href="https://example.com" visited="2026-11-02T12:00:00Z"/></xbel>"#,
        );
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].0, std::path::Path::new("/tmp/a b.md"));
    }
}
