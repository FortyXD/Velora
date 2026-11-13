//! Offline-trained fusion, reproducible with evaluation/calibrate.py.
//! Personal files and queries are never used for training.
use serde::Deserialize;
use std::sync::OnceLock;

#[derive(Deserialize)]
pub struct Ranker {
    intercept: f64,
    cosine: f64,
    cross_encoder: f64,
    margin: f64,
    pub threshold: f64,
}

pub fn model() -> &'static Ranker {
    static MODEL: OnceLock<Ranker> = OnceLock::new();
    MODEL.get_or_init(|| {
        serde_json::from_str(include_str!("../evaluation/ranking-model.json"))
            .expect("bundled relevance model")
    })
}

impl Ranker {
    pub fn score(&self, similarity: Option<f64>, logit: f64, competitor: Option<f64>) -> f64 {
        // Missing vectors use a conservative baseline; exact lexical hits survive
        // independently, including metadata that has not been embedded yet.
        let similarity = similarity.unwrap_or(0.75);
        let margin = competitor.map_or(0.0, |other| similarity - other);
        let value = self.intercept
            + self.cosine * similarity
            + self.cross_encoder * logit
            + self.margin * margin;
        1.0 / (1.0 + (-value).exp())
    }
}
