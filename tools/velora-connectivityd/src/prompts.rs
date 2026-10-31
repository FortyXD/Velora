//! Questions for the person at the keyboard, asked through the shell: a daemon-side request stays open while a
//! dialog is up, and comes back with what was typed.

use crate::protocol::Outgoing;
use crate::secret::Secret;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

/// Agents are asked for answers by services that give up on their own; this is only so nothing waits forever.
const LONGEST_WAIT: Duration = Duration::from_secs(300);

#[derive(Debug)]
pub enum Answer {
    Accepted(HashMap<String, Secret>),
    Declined,
    /// The asking service gave up, or nobody answered.
    Gone,
}

pub struct Prompts {
    out: mpsc::UnboundedSender<String>,
    pending: Mutex<HashMap<u64, oneshot::Sender<Answer>>>,
    next_id: AtomicU64,
}

impl Prompts {
    pub fn new(out: mpsc::UnboundedSender<String>) -> Self {
        Self { out, pending: Mutex::default(), next_id: AtomicU64::new(1) }
    }

    /// Publishes a question. The handle's id can be used to take it back before an answer comes.
    pub fn open(&self, kind: &str, data: Value) -> (u64, oneshot::Receiver<Answer>) {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = oneshot::channel();
        self.pending.lock().expect("no panics while holding this lock").insert(id, sender);
        let mut message = data;
        message["id"] = json!(id);
        message["kind"] = json!(kind);
        let _ = self.out.send(Outgoing::Event { name: "prompt", data: &message }.to_line());
        (id, receiver)
    }

    pub async fn wait(&self, id: u64, receiver: oneshot::Receiver<Answer>) -> Answer {
        match tokio::time::timeout(LONGEST_WAIT, receiver).await {
            Ok(Ok(answer)) => answer,
            _ => {
                self.withdraw(id);
                Answer::Gone
            }
        }
    }

    pub async fn ask(&self, kind: &str, data: Value) -> Answer {
        let (id, receiver) = self.open(kind, data);
        self.wait(id, receiver).await
    }

    /// Takes a question back: its dialog closes, and whoever waits gets `Gone`.
    pub fn withdraw(&self, id: u64) {
        let sender = self.pending.lock().expect("no panics while holding this lock").remove(&id);
        if let Some(sender) = sender {
            let _ = sender.send(Answer::Gone);
        }
        let _ = self.out.send(Outgoing::Event { name: "promptWithdrawn", data: &json!({ "id": id }) }.to_line());
    }

    /// The shell's answer. False when the question no longer stands.
    pub fn answer(&self, id: u64, answer: Answer) -> bool {
        let sender = self.pending.lock().expect("no panics while holding this lock").remove(&id);
        sender.is_some_and(|sender| sender.send(answer).is_ok())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn prompts() -> (Prompts, mpsc::UnboundedReceiver<String>) {
        let (out, lines) = mpsc::unbounded_channel();
        (Prompts::new(out), lines)
    }

    #[tokio::test]
    async fn a_question_goes_out_and_its_answer_comes_back() {
        let (prompts, mut lines) = prompts();
        let (id, receiver) = prompts.open("secrets", json!({ "connectionName": "Home" }));
        let line: Value = serde_json::from_str(&lines.recv().await.unwrap()).unwrap();
        assert_eq!(line["name"], "prompt");
        assert_eq!(line["data"]["id"], id);
        assert_eq!(line["data"]["kind"], "secrets");
        assert_eq!(line["data"]["connectionName"], "Home");
        let values = HashMap::from([("psk".to_string(), Secret::new("x"))]);
        assert!(prompts.answer(id, Answer::Accepted(values)));
        assert!(matches!(prompts.wait(id, receiver).await, Answer::Accepted(values) if values["psk"].expose() == "x"));
    }

    #[tokio::test]
    async fn an_answer_only_counts_once_and_only_for_a_real_question() {
        let (prompts, _lines) = prompts();
        assert!(!prompts.answer(99, Answer::Declined));
        let (id, _receiver) = prompts.open("x", json!({}));
        assert!(prompts.answer(id, Answer::Declined));
        assert!(!prompts.answer(id, Answer::Declined));
    }

    #[tokio::test]
    async fn taking_a_question_back_tells_both_sides() {
        let (prompts, mut lines) = prompts();
        let (id, receiver) = prompts.open("x", json!({}));
        lines.recv().await.unwrap();
        prompts.withdraw(id);
        assert!(matches!(prompts.wait(id, receiver).await, Answer::Gone));
        let line: Value = serde_json::from_str(&lines.recv().await.unwrap()).unwrap();
        assert_eq!(line["name"], "promptWithdrawn");
    }
}
