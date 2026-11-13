use chrono::{Days, Local, TimeZone};
use rust_stemmers::{Algorithm, Stemmer};
use serde::Serialize;
use std::sync::OnceLock;

fn russian_stem(word: &str) -> String {
    static STEMMER: OnceLock<Stemmer> = OnceLock::new();
    if word.chars().count() >= 3 && word.chars().all(|c| ('а'..='я').contains(&c)) {
        STEMMER
            .get_or_init(|| Stemmer::create(Algorithm::Russian))
            .stem(word)
            .into_owned()
    } else {
        word.to_owned()
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct Query {
    pub text: String,
    pub variants: Vec<String>,
    pub kind: Option<String>,
    /// The requested object and the evidence inside it are independent:
    /// `folder config` asks for a folder containing configuration files.
    pub content_kind: Option<String>,
    /// Explicit path tokens are extracted before punctuation normalization.
    pub paths: Vec<std::path::PathBuf>,
    pub extension: Option<String>,
    pub since: Option<i64>,
    pub until: Option<i64>,
    pub activity: bool,
    #[serde(skip)]
    pub scopes: Vec<std::path::PathBuf>,
    #[serde(skip)]
    pub source_roots: Vec<std::path::PathBuf>,
    #[serde(skip)]
    prepared_terms: Vec<Vec<String>>,
    #[serde(skip)]
    original_terms: Vec<Vec<String>>,
    #[serde(skip)]
    pub prepared: bool,
}

#[derive(Clone, Debug, Default, Serialize, serde::Deserialize, PartialEq, Eq)]
pub struct Correction {
    pub from: String,
    pub to: String,
}

#[derive(Default)]
pub struct Evidence {
    pub matched: Vec<String>,
    pub missing: Vec<String>,
    pub corrections: Vec<Correction>,
}

pub fn normalize(s: &str) -> String {
    s.to_lowercase()
        .replace('ё', "е")
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

// Identifiers often encode an ordinal without a separator: task01, hw1, lab_1.
// Keep this separate from display/name normalization so literal filenames retain
// their existing exact-match behavior.
pub fn identifier_words(s: &str) -> Vec<String> {
    let normalized = normalize(s);
    let mut split = String::new();
    let mut numeric = None;
    for c in normalized.chars() {
        if c == ' ' {
            numeric = None;
            split.push(c);
            continue;
        }
        let next = c.is_ascii_digit();
        if numeric.is_some_and(|previous| previous != next) {
            split.push(' ');
        }
        split.push(c);
        numeric = Some(next);
    }
    split
        .split_whitespace()
        .map(|word| {
            if word.chars().all(|c| c.is_ascii_digit()) {
                let value = word.trim_start_matches('0');
                if value.is_empty() {
                    "0".into()
                } else {
                    value.into()
                }
            } else {
                word.into()
            }
        })
        .collect()
}

fn abbreviated_word(word: &str, abbreviation: &str) -> bool {
    if !(2..=4).contains(&abbreviation.chars().count())
        || word.chars().count() < abbreviation.chars().count() + 2
        || word.chars().next() != abbreviation.chars().next()
    {
        return false;
    }
    let mut letters = word.chars();
    abbreviation
        .chars()
        .all(|wanted| letters.any(|c| c == wanted))
}

pub fn semantic_words(text: &str) -> String {
    identifier_words(text).join(" ")
}

pub fn document_role(text: &str) -> Option<&'static str> {
    identifier_words(text)
        .iter()
        .find_map(|word| match russian_stem(word).as_str() {
            "homework" | "assignment" | "hw" | "домашк" | "домашн" | "задан" => {
                Some("assignment")
            }
            "seminar" | "семинар" => Some("seminar"),
            "report" | "отчет" => Some("report"),
            "notes" | "конспект" => Some("notes"),
            "slides" | "presentation" | "презентац" => Some("slides"),
            "lecture" | "лекц" => Some("lecture"),
            _ => None,
        })
}

fn ordinal(word: &str) -> Option<&'static str> {
    match russian_stem(word).as_str() {
        "first" | "перв" => Some("1"),
        "second" | "втор" => Some("2"),
        "third" | "трет" => Some("3"),
        "fourth" | "четверт" => Some("4"),
        "fifth" | "пят" => Some("5"),
        "sixth" | "шест" => Some("6"),
        "seventh" | "седьм" => Some("7"),
        "eighth" | "восьм" => Some("8"),
        "ninth" | "девят" => Some("9"),
        "tenth" | "десят" => Some("10"),
        _ => None,
    }
}

pub fn transliterate(s: &str) -> String {
    s.chars()
        .map(|c| {
            match c {
                'а' => "a",
                'б' => "b",
                'в' => "v",
                'г' => "g",
                'д' => "d",
                'е' => "e",
                'ж' => "zh",
                'з' => "z",
                'и' => "i",
                'й' => "y",
                'к' => "k",
                'л' => "l",
                'м' => "m",
                'н' => "n",
                'о' => "o",
                'п' => "p",
                'р' => "r",
                'с' => "s",
                'т' => "t",
                'у' => "u",
                'ф' => "f",
                'х' => "kh",
                'ц' => "ts",
                'ч' => "ch",
                'ш' => "sh",
                'щ' => "sch",
                'ъ' | 'ь' => "",
                'ы' => "y",
                'э' => "e",
                'ю' => "yu",
                'я' => "ya",
                _ => return c.to_string(),
            }
            .to_string()
        })
        .collect::<String>()
}

pub fn variants(s: &str) -> Vec<String> {
    let s = normalize(s);
    let mut out = vec![s.clone()];
    let latin = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    let cyrillic = "йцукенгшщзхъфывапролджэячсмитьбю";
    let layout = |from: &str, to: &str| {
        s.chars()
            .map(|c| {
                from.chars()
                    .position(|x| x == c)
                    .and_then(|i| to.chars().nth(i))
                    .unwrap_or(c)
            })
            .collect::<String>()
    };
    out.push(layout(latin, cyrillic));
    out.push(layout(cyrillic, latin));
    out.push(transliterate(&s));
    // Expand in place: an alias must never discard the rest of the request.
    for (aliases, replacements) in [
        (
            &["dl"][..],
            &["deep learning", "глубокое обучение", "нейросети"][..],
        ),
        (&["ml"][..], &["machine learning", "машинное обучение"][..]),
        (&["шад", "shad", "ysda"][..], &["шад", "shad", "ysda"][..]),
    ] {
        if s.split_whitespace().any(|word| aliases.contains(&word)) {
            for replacement in replacements {
                out.push(
                    s.split_whitespace()
                        .map(|word| {
                            if aliases.contains(&word) {
                                *replacement
                            } else {
                                word
                            }
                        })
                        .collect::<Vec<_>>()
                        .join(" "),
                );
            }
        }
    }
    out.sort();
    out.dedup();
    out.retain(|s| !s.is_empty());
    out
}

impl Query {
    pub fn use_semantics(&self) -> bool {
        if self.text.is_empty() {
            return false;
        }
        matches!(self.kind.as_deref(), Some("photo" | "video"))
            || self.text.chars().count() > 3
            || self
                .variants
                .iter()
                .any(|v| v.split_whitespace().count() > 1)
    }

    pub fn parse(input: &str, now: chrono::DateTime<Local>) -> Self {
        let (input_text, paths) = extract_paths(input);
        let mut text = normalize(&input_text);
        let extension = text
            .split_whitespace()
            .find_map(|word| match word {
                "пдф" => Some("pdf"),
                "pdf" | "ipynb" | "docx" | "xlsx" | "pptx" | "epub" => Some(word),
                _ => None,
            })
            .map(str::to_owned);
        if let Some(extension) = &extension {
            text = text
                .split_whitespace()
                .filter(|w| *w != extension && *w != "пдф")
                .collect::<Vec<_>>()
                .join(" ");
        }
        let activity = [
            "работал",
            "делал",
            "открывал",
            "настраивал",
            "worked",
            "opened",
            "edited",
        ]
        .iter()
        .any(|w| text.contains(w));
        let mut kind = None;
        let mut content_kind = None;
        for (word, value) in [
            ("папка", "folder"),
            ("папку", "folder"),
            ("проект", "folder"),
            ("folder", "folder"),
            ("project", "folder"),
            ("фото", "photo"),
            ("фотография", "photo"),
            ("photo", "photo"),
            ("видео", "video"),
            ("video", "video"),
            ("конфиг", "config"),
            ("config", "config"),
            ("settings", "config"),
            ("configuration", "config"),
            ("настройки", "config"),
            ("настройка", "config"),
            ("конфигурация", "config"),
            ("приложение", "app"),
            ("app", "app"),
            ("application", "app"),
            ("запусти", "app"),
            ("launch", "app"),
            ("файл", "file"),
            ("файлик", "file"),
            ("документ", "file"),
            ("file", "file"),
        ] {
            if text.split_whitespace().any(|w| w == word) {
                if value == "folder" {
                    kind = Some(value.to_string());
                } else if value == "file" {
                    if kind.is_none() {
                        kind = Some(value.to_string());
                    }
                } else {
                    content_kind = Some(value.to_string());
                    if kind.as_deref() != Some("folder") {
                        kind = Some(value.to_string());
                    }
                }
                text = text
                    .split_whitespace()
                    .filter(|w| *w != word)
                    .collect::<Vec<_>>()
                    .join(" ");
            }
        }
        if kind.is_none() {
            let action = text.split_whitespace().any(|w| {
                matches!(
                    w,
                    "поменять"
                        | "изменить"
                        | "настроить"
                        | "настраивается"
                        | "change"
                        | "configure"
                )
            });
            let setting = text.split_whitespace().any(|w| {
                [
                    "шрифт",
                    "раскладк",
                    "клавиатур",
                    "font",
                    "layout",
                    "keybind",
                ]
                .iter()
                .any(|stem| w.starts_with(stem))
            });
            if (action && setting)
                || [
                    "keyboard layout",
                    "keybindings",
                    "hotkeys",
                    "горячие клавиши",
                    "раскладк",
                ]
                .iter()
                .any(|phrase| text.contains(phrase))
            {
                kind = Some("config".into());
            }
            if kind.is_none()
                && text.split_whitespace().any(|word| {
                    [
                        "homework",
                        "assignment",
                        "report",
                        "домаш",
                        "задан",
                        "отчет",
                    ]
                    .iter()
                    .any(|unit| word.starts_with(unit))
                })
            {
                kind = Some("file".into());
            }
        }
        static DAYS: OnceLock<regex::Regex> = OnceLock::new();
        let re = DAYS.get_or_init(|| {
            regex::Regex::new(r"(\d{1,4})\s+(?:дня|дней|день|days?)\s+(?:назад|ago)").unwrap()
        });
        let days = if let Some(c) = re.captures(&text) {
            let n = c[1].parse::<u64>().ok();
            text = re.replace(&text, "").into_owned();
            n
        } else if text.contains("позавчера") {
            text = text.replace("позавчера", "");
            Some(2)
        } else if text.contains("вчера") || text.contains("yesterday") {
            text = text.replace("вчера", "").replace("yesterday", "");
            Some(1)
        } else if text.contains("сегодня") || text.contains("today") {
            text = text.replace("сегодня", "").replace("today", "");
            Some(0)
        } else {
            None
        };
        let (since, until) = days
            .and_then(|n| now.date_naive().checked_sub_days(Days::new(n)))
            .and_then(|d| {
                let a = Local
                    .from_local_datetime(&d.and_hms_opt(0, 0, 0)?)
                    .earliest()?;
                let b = Local
                    .from_local_datetime(&d.succ_opt()?.and_hms_opt(0, 0, 0)?)
                    .earliest()?;
                Some((Some(a.timestamp()), Some(b.timestamp())))
            })
            .unwrap_or((None, None));
        let stop = [
            "покажи",
            "открой",
            "открыть",
            "open",
            "показать",
            "мне",
            "мой",
            "мою",
            "my",
            "show",
            "please",
            "пожалуйста",
            "поменять",
            "изменить",
            "настроить",
            "настраивается",
            "change",
            "configure",
            "где",
            "я",
            "делал",
            "работал",
            "открывал",
            "настраивал",
            "найди",
            "найти",
            "который",
            "которую",
            "с",
            "на",
            "по",
            "the",
            "where",
            "i",
            "worked",
            "opened",
            "find",
            "with",
            "for",
            "для",
            "a",
        ];
        text = text
            .split_whitespace()
            .filter(|s| !stop.contains(s))
            .collect::<Vec<_>>()
            .join(" ");
        let mut query = Self {
            variants: variants(&text),
            scopes: vec![],
            source_roots: vec![],
            prepared_terms: vec![],
            original_terms: vec![],
            prepared: false,
            text,
            kind: kind.or_else(|| extension.as_ref().map(|_| "file".to_string())),
            content_kind,
            paths,
            extension,
            since,
            until,
            activity,
        };
        query.prepared_terms = query.build_terms();
        query.original_terms = query.prepared_terms.clone();
        query
    }

    // Configuration queries often split their evidence between an application
    // directory and keys in the file (e.g. keyboard -> kb_layout / keybindings).
    pub fn terms(&self) -> &[Vec<String>] {
        &self.prepared_terms
    }

    pub fn add_alternative(&mut self, index: usize, word: String) {
        if let Some(terms) = self.prepared_terms.get_mut(index) {
            if !terms.contains(&word) && terms.len() < 24 {
                terms.push(word);
            }
        }
    }

    pub fn is_config(&self) -> bool {
        self.kind.as_deref() == Some("config") || self.content_kind.as_deref() == Some("config")
    }

    fn build_terms(&self) -> Vec<Vec<String>> {
        self.labels()
            .iter()
            .map(String::as_str)
            .map(|term| {
                let mut words = variants(term);
                if let Some(role) = document_role(term) {
                    words.extend(
                        match role {
                            "assignment" => {
                                &["homework", "assignment", "hw", "домашк", "домашн", "задан"][..]
                            }
                            "seminar" => &["seminar", "семинар"],
                            "report" => &["report", "отчет"],
                            "notes" => &["notes", "конспект"],
                            "slides" => &["slides", "presentation", "презентац"],
                            "lecture" => &["lecture", "лекц"],
                            _ => &[],
                        }
                        .iter()
                        .map(|s| s.to_string()),
                    );
                }
                if !self.ordinal_numbers().is_empty() {
                    if let Some(number) = ordinal(term) {
                        words.push(number.into());
                    }
                }
                let stem = russian_stem(term);
                if stem.chars().count() >= 2 {
                    words.push(stem);
                }
                if self.is_config()
                    && [
                        "keyboard",
                        "keyboards",
                        "клавиатура",
                        "клавиатуры",
                        "клавиатуру",
                    ]
                    .contains(&term)
                {
                    words.extend(
                        ["keyboard", "kb", "keybind", "keymap", "клавиатур"].map(str::to_owned),
                    );
                }
                words.sort();
                words.dedup();
                words
            })
            .collect()
    }

    pub fn labels(&self) -> Vec<String> {
        let assignment = document_role(&self.text) == Some("assignment");
        identifier_words(&self.text)
            .into_iter()
            .filter(|term| {
                !(assignment && matches!(russian_stem(term).as_str(), "работ" | "number" | "номер"))
            })
            .collect()
    }

    pub fn config_matches(&self, path: &str, content: &str) -> bool {
        self.coverage(path, content) == 1.0
    }

    /// Explicit configuration features remain constraints even when an app's
    /// description supplies a very strong semantic match.
    pub fn config_features_match(&self, path: &str, content: &str) -> bool {
        if !self.is_config() {
            return true;
        }
        let text = normalize(&self.text);
        let evidence = normalize(&format!("{path} {content}"));
        let groups: &[(&[&str], &[&str])] = &[
            (
                &["keyboard", "клавиатур", "раскладк"],
                &[
                    "keyboard",
                    "клавиатур",
                    "раскладк",
                    "kb",
                    "keymap",
                    "keybind",
                    "bind",
                ],
            ),
            (&["font", "шрифт"], &["font", "шрифт", "typeface"]),
            (
                &["scrollback", "истори прокрут"],
                &["scrollback", "history", "истори"],
            ),
            (
                &["горяч", "shortcuts", "keybindings"],
                &["bind", "shortcut", "hotkey", "горяч", "клавиш"],
            ),
        ];
        groups.iter().all(|(triggers, words)| {
            !triggers.iter().any(|w| text.contains(w)) || words.iter().any(|w| evidence.contains(w))
        })
    }

    pub fn numbered_labels(&self) -> Vec<(String, String)> {
        identifier_words(&self.text)
            .windows(2)
            .filter(|pair| {
                pair[0].chars().count() >= 2
                    && pair[0].chars().all(char::is_alphabetic)
                    && pair[1].chars().all(|c| c.is_ascii_digit())
            })
            .map(|pair| (pair[0].clone(), pair[1].clone()))
            .collect()
    }

    pub fn matches_numbers(&self, path: &str) -> bool {
        // A browser copy suffix, homework (2), is not assignment number two.
        static COPY: OnceLock<regex::Regex> = OnceLock::new();
        let object = std::path::Path::new(path);
        let base = self
            .scopes
            .iter()
            .chain(&self.source_roots)
            .filter(|root| object != root.as_path() && object.starts_with(root))
            .max_by_key(|root| root.components().count());
        let relative = base
            .and_then(|root| object.strip_prefix(root).ok())
            .unwrap_or(object)
            .to_string_lossy();
        let cleaned = COPY
            .get_or_init(|| regex::Regex::new(r"\s*\(\d+\)(\.[^/]+)$").unwrap())
            .replace_all(&relative, "$1");
        let words = identifier_words(&cleaned);
        self.numbered_labels()
            .iter()
            .all(|(_, number)| words.contains(number))
            && ((self.scopes.is_empty() && self.source_roots.is_empty())
                || self
                    .ordinal_numbers()
                    .iter()
                    .all(|number| words.contains(number)))
    }

    pub fn ordinal_numbers(&self) -> Vec<String> {
        let units = [
            "homework",
            "assignment",
            "experiment",
            "lecture",
            "task",
            "lesson",
            "chapter",
            "part",
            "семинар",
            "домаш",
            "задан",
            "лаборатор",
            "лекц",
            "част",
        ];
        if !self
            .text
            .split_whitespace()
            .any(|word| units.iter().any(|unit| word.starts_with(unit)))
        {
            return vec![];
        }
        self.text
            .split_whitespace()
            .filter_map(|word| {
                match russian_stem(word).as_str() {
                    "first" | "перв" => Some("1"),
                    "second" | "втор" => Some("2"),
                    "third" | "трет" => Some("3"),
                    "fourth" | "четверт" => Some("4"),
                    "fifth" | "пят" => Some("5"),
                    "sixth" | "шест" => Some("6"),
                    "seventh" | "седьм" => Some("7"),
                    "eighth" | "восьм" => Some("8"),
                    "ninth" | "девят" => Some("9"),
                    "tenth" | "десят" => Some("10"),
                    _ => None,
                }
                .map(str::to_owned)
            })
            .collect()
    }

    /// Evidence can be split across directory names, the filename and a passage.
    /// Phrases stay phrases; short abbreviations do not prefix-match arbitrary words.
    pub fn coverage(&self, path: &str, content: &str) -> f64 {
        let document = identifier_words(&format!("{path} {content}"));
        let words: Vec<_> = document.iter().map(String::as_str).collect();
        let numbered = self.numbered_labels();
        let terms = self.terms();
        let count = terms
            .iter()
            .filter(|alternatives| {
                alternatives.iter().any(|term| {
                    let phrase: Vec<_> = term.split_whitespace().collect();
                    !phrase.is_empty()
                        && words.windows(phrase.len()).any(|window| {
                            window.iter().zip(&phrase).all(|(word, term)| {
                                word == term
                                    || (numbered.iter().any(|(label, _)| label == term)
                                        && abbreviated_word(word, term))
                                    || (term.chars().count() >= 3 && word.starts_with(term))
                                    || (term.chars().all(|c| ('а'..='я').contains(&c))
                                        && russian_stem(word) == *term)
                            })
                        })
                })
            })
            .count();
        if terms.is_empty() {
            0.0
        } else {
            count as f64 / terms.len() as f64
        }
    }

    pub fn evidence(&self, path: &str, content: &str) -> Evidence {
        let document = identifier_words(&format!("{path} {content}"));
        let words: Vec<_> = document.iter().map(String::as_str).collect();
        let numbered = self.numbered_labels();
        let matches = |term: &str| {
            let phrase: Vec<_> = term.split_whitespace().collect();
            !phrase.is_empty()
                && words.windows(phrase.len()).any(|window| {
                    window.iter().zip(&phrase).all(|(word, term)| {
                        word == term
                            || (numbered.iter().any(|(label, _)| label == term)
                                && abbreviated_word(word, term))
                            || (term.chars().count() >= 3 && word.starts_with(term))
                            || (term.chars().all(|c| ('а'..='я').contains(&c))
                                && russian_stem(word) == *term)
                    })
                })
        };
        let labels = self.labels();
        let mut evidence = Evidence::default();
        for (index, alternatives) in self.prepared_terms.iter().enumerate() {
            let label = labels
                .get(index)
                .cloned()
                .unwrap_or_else(|| alternatives[0].clone());
            if let Some(matched) = alternatives.iter().find(|term| matches(term)) {
                evidence.matched.push(label.clone());
                if !self.original_terms[index].iter().any(|term| matches(term)) {
                    evidence.corrections.push(Correction {
                        from: label,
                        to: matched.clone(),
                    });
                }
            } else {
                evidence.missing.push(label);
            }
        }
        evidence
    }

    pub fn fts_terms(&self) -> String {
        self.terms()
            .into_iter()
            .flatten()
            .map(|term| {
                let suffix = if term.chars().count() >= 3
                    || term.chars().all(|c| ('а'..='я').contains(&c))
                {
                    "*"
                } else {
                    ""
                };
                format!("\"{term}\"{suffix}")
            })
            .collect::<Vec<_>>()
            .join(" OR ")
    }
}

pub fn distance(a: &str, b: &str) -> usize {
    let a: Vec<_> = a.chars().take(128).collect();
    let b: Vec<_> = b.chars().take(128).collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for (i, x) in a.iter().enumerate() {
        let mut row = vec![i + 1; b.len() + 1];
        for (j, y) in b.iter().enumerate() {
            row[j + 1] = (row[j] + 1)
                .min(prev[j + 1] + 1)
                .min(prev[j] + usize::from(x != y));
        }
        prev = row;
    }
    prev[b.len()]
}

fn transposed(a: &str, b: &str) -> bool {
    let a: Vec<_> = a.chars().collect();
    let b: Vec<_> = b.chars().collect();
    if a.len() != b.len() {
        return false;
    }
    let changed: Vec<_> = a
        .iter()
        .zip(&b)
        .enumerate()
        .filter(|(_, (a, b))| a != b)
        .map(|(i, _)| i)
        .collect();
    changed.len() == 2
        && changed[1] == changed[0] + 1
        && a[changed[0]] == b[changed[1]]
        && a[changed[1]] == b[changed[0]]
}

/// This is tokenization, not shell parsing: there is no variable expansion or
/// command substitution. Quotes preserve spaces inside absolute/home paths.
fn extract_paths(input: &str) -> (String, Vec<std::path::PathBuf>) {
    let mut tokens = Vec::new();
    let mut token = String::new();
    let mut quote = None;
    for c in input.chars() {
        match (quote, c) {
            (Some(q), c) if q == c => quote = None,
            (None, '\'' | '"') => quote = Some(c),
            (None, c) if c.is_whitespace() => {
                if !token.is_empty() {
                    tokens.push(std::mem::take(&mut token));
                }
            }
            _ => token.push(c),
        }
    }
    if !token.is_empty() {
        tokens.push(token);
    }
    let mut paths = Vec::new();
    let mut terms = Vec::new();
    for token in tokens {
        if token.starts_with('/') {
            paths.push(std::path::PathBuf::from(token));
        } else if let Some(relative) = token.strip_prefix("~/") {
            if let Some(home) = std::env::var_os("HOME") {
                paths.push(std::path::PathBuf::from(home).join(relative));
            } else {
                // Preserve an explicit, unresolvable constraint; never turn it
                // into a global search when HOME is unavailable.
                paths.push(std::path::PathBuf::from(token));
            }
        } else {
            terms.push(token);
        }
    }
    paths.sort();
    paths.dedup();
    (terms.join(" "), paths)
}

pub fn name_score(name: &str, query: &Query) -> f64 {
    let names = variants(name);
    let literal = names
        .iter()
        .flat_map(|n| query.variants.iter().map(move |v| (n, v)))
        .map(|(n, v)| {
            if n == v {
                10.0
            } else if n.starts_with(v) {
                8.0
            } else if n.split_whitespace().any(|word| word == v) {
                6.0
            } else if v.chars().count() > 3 && n.contains(v) {
                6.0
            } else {
                0.0
            }
        })
        .fold(0.0, f64::max);
    if literal > 0.0 {
        return literal;
    }
    let normalized = normalize(name);
    if !query.text.is_empty()
        && query.text.split_whitespace().all(|term| {
            normalized
                .split_whitespace()
                .any(|word| russian_stem(word) == russian_stem(term))
        })
    {
        return 7.5;
    }
    // Do not compound a keyboard-layout repair with a typo. For short codes
    // only adjacent transposition is safe: npl -> nlp, not nlp -> тдз -> дз.
    let name = normalize(name);
    let names = [name.clone(), transliterate(&name)];
    let queries = [query.text.clone(), transliterate(&query.text)];
    if queries.iter().any(|q| {
        !q.is_empty()
            && names.iter().any(|n| {
                q.split_whitespace().all(|term| {
                    n.split_whitespace().any(|word| {
                        word == term
                            || (term.chars().count() >= 3 && transposed(word, term))
                            || (term.chars().count() >= 4
                                && distance(word, term)
                                    <= if term.chars().count() > 6 { 2 } else { 1 })
                    })
                })
            })
    }) {
        4.0
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn numbered_abbreviations_combine_filename_and_parent_without_number_prefixes() {
        for input in ["nlp hw1", "nlp hw 01", "nlp homework1", "nlp homework 1"] {
            let q = Query::parse(input, Local::now());
            assert_eq!(
                q.coverage("/courses/NLP/task01/homework.ipynb", ""),
                1.0,
                "{input}"
            );
            assert!(q.matches_numbers("/courses/NLP/task01/homework.ipynb"));
            assert!(q.coverage("/courses/NLP/task10/homework.ipynb", "") < 1.0);
            assert!(!q.matches_numbers("/courses/NLP/task2/homework.ipynb"));
        }
        let q = Query::parse("physics exp2", Local::now());
        assert_eq!(q.coverage("/physics/experiment_02/report.pdf", ""), 1.0);
        assert_eq!(
            Query::parse("nlp", Local::now()).coverage("/new-language-papers", ""),
            0.0
        );
    }
    #[test]
    fn russian_inflections_match_without_confusing_short_roots() {
        let q = Query::parse("pdf по окам", Local::now());
        assert_eq!(q.extension.as_deref(), Some("pdf"));
        assert!(name_score("ОКИ ДЗ8.pdf", &q) > 0.0);
        assert_eq!(name_score("окно.pdf", &q), 0.0);
        assert!(q.coverage("/ОКи/lecture.pdf", "") == 1.0);
        assert!(!q.config_matches("/октябрь/lecture.pdf", ""));
        assert!(Query::parse("лекциями", Local::now()).coverage("/лекция.md", "") == 1.0);
    }
    #[test]
    fn short_identifiers_allow_transposition_without_layout_plus_typo_noise() {
        for input in ["npl", "nlp", "тзд"] {
            let q = Query::parse(input, Local::now());
            assert!(!q.use_semantics());
            assert_eq!(name_score("Дз 1906 ОКи.pdf", &q), 0.0);
        }
        assert!(name_score("NLP", &Query::parse("npl", Local::now())) > 0.0);
        assert!(name_score("bayesian lab", &Query::parse("bayesain lab", Local::now())) > 0.0);
        assert!(Query::parse("фото кот", Local::now()).use_semantics());
        assert!(Query::parse("deep learning convolution", Local::now()).use_semantics());
    }
    #[test]
    fn expansions_preserve_the_entire_query_and_mixed_script_text() {
        let q = Query::parse("shad dl conv layer", Local::now());
        assert!(q.variants.contains(&"shad deep learning conv layer".into()));
        assert!(!q.variants.contains(&"deep learning".into()));
        assert_eq!(name_score("DL_movies.torrent", &q), 0.0);
        assert!(variants("шад dl lecture").contains(&"shad dl lecture".into()));
        assert_eq!(
            q.coverage("/courses/SHAD/DL/03.md", "Convolutional layers"),
            1.0
        );
        assert!(q.coverage("/downloads/DL_movie.torrent", "") < 1.0);
        assert_eq!(
            Query::parse("dl", Local::now()).coverage("/download", ""),
            0.0
        );
    }
    #[test]
    fn configuration_queries_combine_path_and_keyboard_keys() {
        for text in ["config for keyboard hypr", "конфиг для клавиатуры hypr"] {
            let q = Query::parse(text, Local::now());
            assert_eq!(q.kind.as_deref(), Some("config"));
            assert!(q.config_matches(
                "/home/me/.config/hypr/hyprland/general.lua",
                "kb_layout = us,ru"
            ));
            assert!(!q.config_matches(
                "/home/me/.config/other/settings.json",
                "keyboard configuration"
            ));
            assert!(!q.config_matches("/home/me/.config/hypr/colors.conf", "background = blue"));
        }
    }
    #[test]
    fn handles_russian_dates_and_intent() {
        let now = Local.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap();
        let q = Query::parse("папка где я делал DL 2 дня назад", now);
        assert_eq!(q.kind.as_deref(), Some("folder"));
        assert!(q.activity);
        assert_eq!(q.text, "dl");
        assert_eq!(
            q.since.unwrap(),
            Local
                .with_ymd_and_hms(2026, 10, 31, 0, 0, 0)
                .unwrap()
                .timestamp()
        );
        assert!(q.variants.contains(&"deep learning".into()));
    }
    #[test]
    fn fuzzy_multilingual_names() {
        for input in ["шад", "шаад", "ырфв", "shad"] {
            assert!(
                name_score("SHAD", &Query::parse(input, Local::now())) > 0.0,
                "{input}"
            );
        }
        assert_eq!(distance("шад", "шаад"), 1);
    }
}
