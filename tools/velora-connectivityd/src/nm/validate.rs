//! Checks on what people type, before NetworkManager gets to refuse it with less helpful words.

use std::net::{Ipv4Addr, Ipv6Addr};

/// A WPA password: 8 to 63 bytes, or the raw key as 64 hex digits. The same rule NetworkManager applies.
pub fn wpa_psk(value: &str) -> bool {
    (8..=63).contains(&value.len()) || (value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()))
}

/// WPA3 passwords have no fixed length, only a need to exist.
pub fn sae_password(value: &str) -> bool {
    !value.is_empty()
}

/// A WEP key: 5 or 13 characters, or 10 or 26 hex digits.
pub fn wep_key(value: &str) -> bool {
    let hex = value.bytes().all(|byte| byte.is_ascii_hexdigit());
    matches!(value.len(), 5 | 13) || (matches!(value.len(), 10 | 26) && hex)
}

pub fn ipv4(value: &str) -> bool {
    value.parse::<Ipv4Addr>().is_ok()
}

pub fn ipv6(value: &str) -> bool {
    value.parse::<Ipv6Addr>().is_ok()
}

pub fn ip(value: &str) -> bool {
    ipv4(value) || ipv6(value)
}

fn with_prefix(value: &str, address_ok: fn(&str) -> bool, max_prefix: u32) -> bool {
    match value.split_once('/') {
        Some((address, prefix)) => address_ok(address) && prefix.parse::<u32>().is_ok_and(|prefix| prefix <= max_prefix),
        None => address_ok(value),
    }
}

/// `10.0.0.2/24`, or an address on its own.
pub fn ipv4_cidr(value: &str) -> bool {
    with_prefix(value, ipv4, 32)
}

pub fn ipv6_cidr(value: &str) -> bool {
    with_prefix(value, ipv6, 128)
}

/// `AA:BB:CC:DD:EE:FF`, the only form NetworkManager stores.
pub fn mac(value: &str) -> bool {
    let parts: Vec<&str> = value.split(':').collect();
    parts.len() == 6 && parts.iter().all(|part| part.len() == 2 && part.bytes().all(|byte| byte.is_ascii_hexdigit()))
}

/// A network name is at most 32 bytes.
pub fn ssid(value: &str) -> bool {
    !value.is_empty() && value.len() <= 32
}

/// A WireGuard key: 32 bytes as 44 characters of standard base64.
pub fn wireguard_key(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 44
        && bytes[43] == b'='
        && bytes[..43].iter().all(|byte| byte.is_ascii_alphanumeric() || *byte == b'+' || *byte == b'/')
        // The last character before the padding only carries four bits of the key
        && matches!(bytes[42], b'A' | b'E' | b'I' | b'M' | b'Q' | b'U' | b'Y' | b'c' | b'g' | b'k' | b'o' | b's' | b'w' | b'0' | b'4' | b'8')
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn wpa_passwords() {
        assert!(wpa_psk("12345678"));
        assert!(wpa_psk(&"a".repeat(63)));
        assert!(wpa_psk(&"ab".repeat(32)));
        assert!(!wpa_psk("1234567"));
        assert!(!wpa_psk(&"a".repeat(65)));
        assert!(!wpa_psk(&"z".repeat(64)));
        assert!(wpa_psk("пароль-на-русском"));
        assert!(sae_password("x"));
        assert!(!sae_password(""));
    }

    #[test]
    fn wep_keys() {
        assert!(wep_key("12345"));
        assert!(wep_key("1234567890123"));
        assert!(wep_key("abcdef0123"));
        assert!(wep_key(&"a".repeat(26)));
        assert!(!wep_key("1234"));
        assert!(!wep_key("zzzzzzzzzz"));
    }

    #[test]
    fn addresses() {
        assert!(ipv4("10.0.0.1") && !ipv4("10.0.0") && !ipv4("256.0.0.1") && !ipv4("::1"));
        assert!(ipv6("fe80::1") && !ipv6("10.0.0.1"));
        assert!(ip("10.0.0.1") && ip("::1") && !ip("x"));
        assert!(ipv4_cidr("10.0.0.1/24") && ipv4_cidr("10.0.0.1") && !ipv4_cidr("10.0.0.1/33") && !ipv4_cidr("10.0.0.1/x"));
        assert!(ipv6_cidr("fe80::1/64") && !ipv6_cidr("fe80::1/129"));
    }

    #[test]
    fn macs_names_and_keys() {
        assert!(mac("AA:bb:00:11:22:33") && !mac("AA:BB:00:11:22") && !mac("AA-BB-00-11-22-33") && !mac("GG:BB:00:11:22:33"));
        assert!(ssid("x") && ssid(&"a".repeat(32)) && !ssid("") && !ssid(&"a".repeat(33)));
        // Keys from `wg genkey` end in one of the sixteen characters with the low bits clear
        assert!(wireguard_key("YAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk="));
        assert!(!wireguard_key("YAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmB="));
        assert!(!wireguard_key("short="));
        assert!(!wireguard_key(&"!".repeat(44)));
    }

    proptest! {
        #[test]
        fn every_ipv4_address_is_accepted_with_any_valid_prefix(octets in any::<[u8; 4]>(), prefix in 0u32..=32) {
            let address = Ipv4Addr::from(octets).to_string();
            prop_assert!(ipv4(&address));
            let with_mask = format!("{address}/{prefix}");
            prop_assert!(ipv4_cidr(&with_mask));
        }

        #[test]
        fn nothing_panics_on_odd_input(value in ".*") {
            let _ = (wpa_psk(&value), wep_key(&value), ipv4_cidr(&value), ipv6_cidr(&value), mac(&value), wireguard_key(&value));
        }
    }
}
