use anyhow::{ensure, Context, Result};
use ct2rs::{ComputeType, Config, Device, Tokenizer, TranslationOptions, Translator};
use sentencepiece::SentencePieceProcessor;
use serde_json::{json, Value};
use std::{
    collections::{hash_map::Entry, HashMap},
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
};

struct Pieces(SentencePieceProcessor);
impl Tokenizer for Pieces {
    fn encode(&self, input: &str) -> Result<Vec<String>> {
        Ok(self.0.encode(input)?.into_iter().map(|p| p.piece).collect())
    }
    fn decode(&self, tokens: Vec<String>) -> Result<String> {
        Ok(self.0.decode_pieces(&tokens)?)
    }
}

fn sentences(line: &str) -> Vec<&str> {
    let line = line.trim();
    let mut parts = Vec::new();
    let mut start = 0;
    let mut last_punct = false;
    for (offset, ch) in line.char_indices() {
        if ch.is_whitespace() && last_punct {
            parts.push(line[start..offset].trim_start());
            start = offset;
        }
        last_punct = ".!?…".contains(ch);
    }
    if start < line.len() {
        parts.push(line[start..].trim_start());
    }
    parts
}

fn translate(
    request: &Value,
    root: &Path,
    models: &mut HashMap<String, Translator<Pieces>>,
) -> Result<String> {
    let pair = match (request["src"].as_str(), request["tgt"].as_str()) {
        (Some("en"), Some("ru")) => "en_ru",
        (Some("ru"), Some("en")) => "ru_en",
        _ => anyhow::bail!("Unsupported translation direction"),
    };
    let text = request["text"]
        .as_str()
        .context("Missing translation text")?;
    let lines: Vec<_> = text.split('\n').map(sentences).collect();
    let batch: Vec<_> = lines.iter().flatten().copied().collect();
    if batch.is_empty() {
        return Ok(String::new());
    }
    let translator = match models.entry(pair.to_owned()) {
        Entry::Occupied(model) => model.into_mut(),
        Entry::Vacant(model) => {
            let dir = root.join(pair);
            let config = Config {
                device: Device::CPU,
                compute_type: ComputeType::INT8,
                num_threads_per_replica: 2,
                ..Default::default()
            };
            let tokenizer = Pieces(SentencePieceProcessor::open(
                dir.join("sentencepiece.model"),
            )?);
            model.insert(Translator::with_tokenizer(
                dir.join("model"),
                tokenizer,
                &config,
            )?)
        }
    };
    let options = TranslationOptions::<String, String> {
        beam_size: 2,
        max_batch_size: 16,
        replace_unknowns: true,
        ..Default::default()
    };
    let result = translator.translate_batch(&batch, &options, None)?;
    ensure!(result.len() == batch.len(), "Incomplete translation");
    let mut translations = result.into_iter().map(|(text, _)| text);
    Ok(lines
        .into_iter()
        .map(|line| {
            translations
                .by_ref()
                .take(line.len())
                .collect::<Vec<_>>()
                .join(" ")
        })
        .collect::<Vec<_>>()
        .join("\n"))
}

fn main() -> Result<()> {
    let root = std::env::var_os("XDG_DATA_HOME")
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share")
        })
        .join("folis/translate/models");
    let mut models = HashMap::new();
    let mut out = io::stdout().lock();
    for line in io::stdin().lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let mut id = Value::Null;
        let result = serde_json::from_str::<Value>(&line)
            .map_err(anyhow::Error::from)
            .and_then(|req| {
                id = req["id"].clone();
                translate(&req, &root, &mut models)
            });
        let reply = match result {
            Ok(text) => json!({"id":id,"text":text}),
            Err(e) => json!({"id":id,"error":e.to_string()}),
        };
        serde_json::to_writer(&mut out, &reply)?;
        out.write_all(b"\n")?;
        out.flush()?;
    }
    Ok(())
}
