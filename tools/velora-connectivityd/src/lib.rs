//! NetworkManager and BlueZ for the Velora shell, over D-Bus. The shell talks to it in JSON lines
//! (see [`protocol`]), so everything that reasons about networks and devices is testable without Qt.

pub mod protocol;
pub mod secret;
pub mod values;
pub mod nm;
pub mod app;
pub mod service;
pub mod prompts;
pub mod secret_store;
pub mod bluez;
pub mod airplane;
