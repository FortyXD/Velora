//! A small parser for `--name value` and `--flag` arguments, so the helper stays dependency-light.

use anyhow::{anyhow, bail, Result};

pub struct Args {
    options: Vec<(String, Option<String>)>,
    pub positional: Vec<String>,
}

impl Args {
    /// `flags` take no value; every other `--name` takes the next argument.
    pub fn parse(argv: Vec<String>, flags: &[&str]) -> Result<Self> {
        let mut options = Vec::new();
        let mut positional = Vec::new();
        let mut iter = argv.into_iter();
        while let Some(arg) = iter.next() {
            if let Some(name) = arg.strip_prefix("--").or_else(|| short_option(&arg)) {
                let name = name.replace('_', "-"); // The Python scripts used underscores
                if let Some((name, value)) = name.split_once('=') {
                    options.push((name.to_string(), Some(value.to_string())));
                } else if flags.contains(&name.as_str()) {
                    options.push((name, None));
                } else {
                    let value = iter.next().ok_or_else(|| anyhow!("--{name} needs a value"))?;
                    options.push((name, Some(value)));
                }
            } else {
                positional.push(arg);
            }
        }
        Ok(Self { options, positional })
    }

    pub fn flag(&self, name: &str) -> bool {
        self.options.iter().any(|(option, _)| option == name)
    }

    pub fn value(&self, name: &str) -> Option<&str> {
        self.options.iter().rev().find(|(option, _)| option == name).and_then(|(_, value)| value.as_deref())
    }

    pub fn require(&self, name: &str) -> Result<&str> {
        self.value(name).ok_or_else(|| anyhow!("--{name} is required"))
    }

    pub fn number<T: std::str::FromStr>(&self, name: &str, fallback: T) -> Result<T> {
        match self.value(name) {
            None => Ok(fallback),
            Some(text) => text.trim().parse().map_err(|_| anyhow!("--{name}: not a number: {text}")),
        }
    }

    pub fn reject_unknown(&self, known: &[&str]) -> Result<()> {
        for (name, _) in &self.options {
            if !known.contains(&name.as_str()) {
                bail!("unknown option --{name}");
            }
        }
        Ok(())
    }
}

// The region script accepted -hp/-vp and -l/-t/-v as short forms
fn short_option(arg: &str) -> Option<&'static str> {
    match arg {
        "-hp" => Some("horizontal-padding"),
        "-vp" => Some("vertical-padding"),
        "-l" => Some("largest-region"),
        "-t" => Some("variance-threshold"),
        "-v" => Some("visual-output"),
        _ => None,
    }
}
