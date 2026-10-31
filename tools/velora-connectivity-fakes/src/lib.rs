//! Stand-ins for the system services Velora talks to, on a private bus, so its tests run the real
//! daemon against real D-Bus without touching anyone's network or devices.

pub mod bus;
pub mod nm;
pub mod secrets;
pub mod bluez;
