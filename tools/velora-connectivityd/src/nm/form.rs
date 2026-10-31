//! A profile as the settings forms see it, and back. The form is flat (`ipv4.method`), with readable values
//! where D-Bus has bytes (`802-11-wireless.ssid` as text, a MAC address as `AA:BB:..`).
//!
//! Edits are applied onto the profile as it stands rather than rebuilding it, so whatever isn't edited goes
//! back exactly as it came, keys this code has never heard of included.

use super::validate;
use crate::protocol::{ApiError, ErrorCode};
use crate::values::{self, Props, Settings};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::hash::{Hash, Hasher};
use std::net::{Ipv4Addr, Ipv6Addr};
use zbus::{OwnedVariant, Variant};

/// How a setting's form value maps to its D-Bus type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Text,
    Flag,
    Int,
    Uint,
    Long,
    /// `ay`: a network name.
    Ssid,
    /// `ay`: a hardware address.
    Mac,
    /// `ay`: a certificate or key file, stored as a `file://` path ending in a NUL.
    FilePath,
    TextList,
    /// `aa{sv}`: `10.0.0.2/24` per entry.
    Addresses,
    /// `aa{sv}`: `{ dest, prefix, next-hop, metric }` per entry.
    Routes,
    /// `a{ss}`
    TextMap,
    /// `aa{sv}`: WireGuard peers.
    Peers,
}

fn kind_of(section: &str, key: &str) -> Option<Kind> {
    use Kind::*;
    Some(match (section, key) {
        (_, "mtu") => Uint,
        ("connection", "id" | "uuid" | "type" | "interface-name" | "zone" | "stable-id" | "controller" | "master" | "port-type" | "slave-type") => Text,
        ("connection", "autoconnect" | "read-only") => Flag,
        ("connection", "autoconnect-priority" | "autoconnect-retries" | "metered" | "multi-connect") => Int,
        ("connection", "timestamp") => Long,
        ("connection", "permissions" | "secondaries") => TextList,
        ("802-11-wireless", "ssid") => Ssid,
        ("802-11-wireless", "mode" | "band" | "assigned-mac-address") => Text,
        ("802-11-wireless", "channel" | "mac-address-randomization" | "powersave" | "rate" | "tx-power") => Uint,
        ("802-11-wireless", "bssid" | "mac-address" | "cloned-mac-address") => Mac,
        ("802-11-wireless", "hidden") => Flag,
        ("802-11-wireless", "seen-bssids" | "mac-address-blacklist") => TextList,
        ("802-11-wireless-security", "key-mgmt" | "auth-alg" | "psk" | "wep-key0" | "wep-key1" | "wep-key2" | "wep-key3" | "leap-username" | "leap-password") => Text,
        ("802-11-wireless-security", "proto" | "pairwise" | "group") => TextList,
        ("802-11-wireless-security", "psk-flags" | "wep-key-flags" | "wep-key-type" | "wep-tx-keyidx" | "leap-password-flags") => Uint,
        ("802-11-wireless-security", "pmf" | "fils" | "wps-method") => Int,
        ("802-1x", "eap" | "altsubject-matches" | "phase2-altsubject-matches") => TextList,
        ("802-1x", "identity" | "anonymous-identity" | "password" | "domain-suffix-match" | "domain-match" | "subject-match" | "phase1-peapver" | "phase1-peaplabel"
            | "phase1-fast-provisioning" | "phase2-auth" | "phase2-autheap" | "private-key-password" | "pac-file" | "ca-path" | "pin") => Text,
        ("802-1x", "ca-cert" | "client-cert" | "private-key" | "phase2-ca-cert" | "phase2-client-cert" | "phase2-private-key") => FilePath,
        ("802-1x", "password-flags" | "private-key-password-flags" | "phase2-private-key-password-flags" | "pin-flags" | "auth-timeout") => Uint,
        ("802-1x", "system-ca-certs" | "optional") => Flag,
        ("802-3-ethernet", "mac-address" | "cloned-mac-address") => Mac,
        ("802-3-ethernet", "assigned-mac-address" | "duplex" | "port" | "wake-on-lan-password") => Text,
        ("802-3-ethernet", "speed" | "wake-on-lan") => Uint,
        ("802-3-ethernet", "auto-negotiate") => Flag,
        ("ipv4" | "ipv6", "method" | "gateway" | "dhcp-client-id" | "dhcp-hostname" | "token" | "dhcp-duid") => Text,
        ("ipv4" | "ipv6", "address-data") => Addresses,
        ("ipv4" | "ipv6", "route-data") => Routes,
        ("ipv4" | "ipv6", "dns-data" | "dns-search" | "dns-options") => TextList,
        ("ipv4" | "ipv6", "ignore-auto-dns" | "ignore-auto-routes" | "never-default" | "may-fail" | "dhcp-send-hostname") => Flag,
        ("ipv4" | "ipv6", "dns-priority" | "dad-timeout" | "route-table" | "ip6-privacy" | "addr-gen-mode" | "dhcp-timeout") => Int,
        ("ipv4" | "ipv6", "route-metric") => Long,
        ("vpn", "service-type" | "user-name") => Text,
        ("vpn", "data" | "secrets") => TextMap,
        ("vpn", "persistent") => Flag,
        ("wireguard", "private-key") => Text,
        ("wireguard", "private-key-flags" | "listen-port" | "fwmark") => Uint,
        ("wireguard", "peer-routes" | "ip4-auto-default-route" | "ip6-auto-default-route") => Flag,
        ("wireguard", "peers") => Peers,
        ("proxy", "method") => Int,
        ("proxy", "pac-url" | "pac-script") => Text,
        ("proxy", "browser-only") => Flag,
        ("gsm", "apn" | "number" | "username" | "password" | "pin" | "network-id" | "sim-id") => Text,
        ("gsm", "password-flags" | "pin-flags") => Uint,
        ("gsm", "home-only" | "auto-config") => Flag,
        ("cdma", "number" | "username" | "password") => Text,
        ("cdma", "password-flags") => Uint,
        ("pppoe", "username" | "password" | "service" | "parent") => Text,
        ("pppoe", "password-flags") => Uint,
        ("bridge", "stp") => Flag,
        ("bridge", "priority" | "forward-delay" | "hello-time" | "max-age" | "ageing-time") => Uint,
        ("bridge", "mac-address") => Mac,
        ("bond", "options") => TextMap,
        ("vlan", "id" | "flags") => Uint,
        ("vlan", "parent") => Text,
        ("team", "config") => Text,
        ("bluetooth", "bdaddr") => Mac,
        ("bluetooth", "type") => Text,
        _ => return None,
    })
}

fn bad(field: &str, why: &str) -> ApiError {
    ApiError::invalid(format!("{field}: {why}"))
}

fn owned<'a>(value: impl Into<Variant<'a>>) -> OwnedVariant {
    value.into().try_into_owned().expect("form values hold no file descriptors")
}

fn wrong_type(field: &str) -> ApiError {
    bad(field, "wrong type of value")
}

fn file_path_from_bytes(bytes: &[u8]) -> Value {
    match bytes.strip_prefix(b"file://") {
        Some(path) => {
            let path = path.strip_suffix(&[0]).unwrap_or(path);
            json!(String::from_utf8_lossy(path))
        }
        // A blob kept inside the profile, not a path: shown as nothing, and left alone unless replaced
        None => Value::Null,
    }
}

fn addresses_to_form(entries: &[Props]) -> Value {
    Value::Array(
        entries
            .iter()
            .filter_map(|entry| {
                let address = values::text(entry, "address")?;
                Some(json!(match values::number(entry, "prefix") {
                    Some(prefix) => format!("{address}/{prefix}"),
                    None => address,
                }))
            })
            .collect(),
    )
}

fn routes_to_form(entries: &[Props]) -> Value {
    Value::Array(
        entries
            .iter()
            .map(|entry| {
                json!({
                    "dest": values::text_or_empty(entry, "dest"),
                    "prefix": values::number(entry, "prefix").unwrap_or(0),
                    "next-hop": values::text_or_empty(entry, "next-hop"),
                    "metric": values::number(entry, "metric"),
                })
            })
            .collect(),
    )
}

/// The readable form of one setting, for a key this code knows or one it doesn't.
pub fn value_to_form(section: &str, key: &str, value: &OwnedVariant) -> Value {
    let props: Props = HashMap::from([(key.to_string(), value.clone())]);
    match kind_of(section, key) {
        Some(Kind::Ssid) => values::bytes(&props, key).map_or(Value::Null, |bytes| json!(String::from_utf8_lossy(&bytes))),
        Some(Kind::Mac) => values::bytes(&props, key).map_or_else(|| values::to_json(value), |bytes| json!(values::mac_from_bytes(&bytes))),
        Some(Kind::FilePath) => values::bytes(&props, key).map_or(Value::Null, |bytes| file_path_from_bytes(&bytes)),
        Some(Kind::Addresses) => addresses_to_form(&values::dicts(&props, key)),
        Some(Kind::Routes) => routes_to_form(&values::dicts(&props, key)),
        _ => values::to_json(value),
    }
}

fn legacy_dns(section: &str, value: &OwnedVariant) -> Vec<String> {
    let Value::Array(entries) = values::to_json(value) else { return Vec::new() };
    entries
        .iter()
        .filter_map(|entry| match (section, entry) {
            // Stored in network byte order
            ("ipv4", Value::Number(number)) => number.as_u64().and_then(|raw| u32::try_from(raw).ok()).map(|raw| Ipv4Addr::from(raw.to_le_bytes()).to_string()),
            ("ipv6", Value::Array(bytes)) => {
                let bytes: Vec<u8> = bytes.iter().filter_map(|byte| byte.as_u64().and_then(|byte| u8::try_from(byte).ok())).collect();
                let octets: [u8; 16] = bytes.try_into().ok()?;
                Some(Ipv6Addr::from(octets).to_string())
            }
            _ => None,
        })
        .collect()
}

/// Every setting of a profile, flat. `ipv4.dns` and `ipv6.dns` are presented as text whichever way they're stored.
pub fn to_form(settings: &Settings) -> Map<String, Value> {
    let mut form = Map::new();
    for (section, props) in settings {
        for (key, value) in props {
            form.insert(format!("{section}.{key}"), value_to_form(section, key, value));
        }
        if matches!(section.as_str(), "ipv4" | "ipv6") {
            let dns = match props.get("dns-data") {
                Some(_) => values::strings(props, "dns-data"),
                None => props.get("dns").map(|value| legacy_dns(section, value)).unwrap_or_default(),
            };
            form.insert(format!("{section}.dns"), json!(dns));
        }
    }
    form
}

/// A fingerprint of a profile as read, to spot it changing under an open editor.
pub fn revision(settings: &Settings) -> String {
    let sorted: BTreeMap<String, Value> = to_form(settings).into_iter().collect();
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    serde_json::to_string(&sorted).expect("plain values").hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn parse_mac(field: &str, text: &str) -> Result<Vec<u8>, ApiError> {
    if !validate::mac(text) {
        return Err(bad(field, "not a hardware address"));
    }
    Ok(text.split(':').map(|part| u8::from_str_radix(part, 16).expect("validated above")).collect())
}

fn parse_address(field: &str, section: &str, text: &str) -> Result<HashMap<String, Variant<'static>>, ApiError> {
    let valid = if section == "ipv4" { validate::ipv4_cidr(text) } else { validate::ipv6_cidr(text) };
    if !valid {
        return Err(bad(field, "not an address"));
    }
    let (address, prefix) = match text.split_once('/') {
        Some((address, prefix)) => (address, prefix.parse::<u32>().expect("validated above")),
        None => (text, if section == "ipv4" { 32 } else { 128 }),
    };
    Ok(HashMap::from([("address".to_string(), Variant::from(address.to_string())), ("prefix".to_string(), Variant::from(prefix))]))
}

fn parse_route(field: &str, section: &str, entry: &Value) -> Result<HashMap<String, Variant<'static>>, ApiError> {
    let address_ok: fn(&str) -> bool = if section == "ipv4" { validate::ipv4 } else { validate::ipv6 };
    let dest = entry["dest"].as_str().filter(|dest| address_ok(dest)).ok_or_else(|| bad(field, "a route needs a valid destination"))?;
    let prefix = entry["prefix"].as_u64().ok_or_else(|| bad(field, "a route needs a prefix length"))?;
    if prefix > if section == "ipv4" { 32 } else { 128 } {
        return Err(bad(field, "the prefix length is too long"));
    }
    let mut route = HashMap::from([
        ("dest".to_string(), Variant::from(dest.to_string())),
        ("prefix".to_string(), Variant::from(u32::try_from(prefix).expect("bounded above"))),
    ]);
    if let Some(next_hop) = entry["next-hop"].as_str().filter(|hop| !hop.is_empty()) {
        if !address_ok(next_hop) {
            return Err(bad(field, "the route's gateway isn't an address"));
        }
        route.insert("next-hop".to_string(), Variant::from(next_hop.to_string()));
    }
    if let Some(metric) = entry["metric"].as_u64() {
        let metric = u32::try_from(metric).map_err(|_| bad(field, "the route's metric is too large"))?;
        route.insert("metric".to_string(), Variant::from(metric));
    }
    Ok(route)
}

fn parse_peer(field: &str, entry: &Value) -> Result<HashMap<String, Variant<'static>>, ApiError> {
    let key = entry["public-key"].as_str().filter(|key| validate::wireguard_key(key)).ok_or_else(|| bad(field, "a peer needs a valid public key"))?;
    let mut peer = HashMap::from([("public-key".to_string(), Variant::from(key.to_string()))]);
    if let Some(endpoint) = entry["endpoint"].as_str().filter(|endpoint| !endpoint.is_empty()) {
        peer.insert("endpoint".to_string(), Variant::from(endpoint.to_string()));
    }
    let allowed: Vec<String> = entry["allowed-ips"].as_array().map(|list| list.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default();
    for address in &allowed {
        if !validate::ipv4_cidr(address) && !validate::ipv6_cidr(address) {
            return Err(bad(field, "an allowed address isn't valid"));
        }
    }
    if !allowed.is_empty() {
        peer.insert("allowed-ips".to_string(), Variant::from(allowed));
    }
    if let Some(shared) = entry["preshared-key"].as_str().filter(|shared| !shared.is_empty()) {
        if !validate::wireguard_key(shared) {
            return Err(bad(field, "the preshared key isn't valid"));
        }
        peer.insert("preshared-key".to_string(), Variant::from(shared.to_string()));
        peer.insert("preshared-key-flags".to_string(), Variant::from(0u32));
    }
    if let Some(interval) = entry["persistent-keepalive"].as_u64() {
        let interval = u32::try_from(interval).map_err(|_| bad(field, "the keepalive is too large"))?;
        peer.insert("persistent-keepalive".to_string(), Variant::from(interval));
    }
    Ok(peer)
}

fn typed_text<'a>(field: &str, value: &'a Value) -> Result<&'a str, ApiError> {
    value.as_str().ok_or_else(|| wrong_type(field))
}

fn typed_number(field: &str, value: &Value) -> Result<i64, ApiError> {
    if let Some(number) = value.as_i64() {
        return Ok(number);
    }
    // A form field holding digits
    value.as_str().and_then(|text| text.trim().parse().ok()).ok_or_else(|| bad(field, "not a number"))
}

fn text_list(field: &str, value: &Value) -> Result<Vec<String>, ApiError> {
    value
        .as_array()
        .ok_or_else(|| wrong_type(field))?
        .iter()
        .map(|entry| entry.as_str().map(str::to_string).ok_or_else(|| wrong_type(field)))
        .collect()
}

/// A form value as what D-Bus wants. `Ok(None)` means the key should go away: empty text and empty lists
/// are how a form says "not set", and the service refuses most of them as values.
pub fn value_from_form(section: &str, key: &str, kind: Kind, value: &Value) -> Result<Option<OwnedVariant>, ApiError> {
    let field = format!("{section}.{key}");
    let field = field.as_str();
    if value.is_null() {
        return Ok(None);
    }
    Ok(Some(match kind {
        Kind::Text => {
            let text = typed_text(field, value)?;
            if text.is_empty() {
                return Ok(None);
            }
            owned(text.to_string())
        }
        Kind::Flag => owned(value.as_bool().ok_or_else(|| wrong_type(field))?),
        Kind::Int => owned(i32::try_from(typed_number(field, value)?).map_err(|_| bad(field, "the number is out of range"))?),
        Kind::Uint => owned(u32::try_from(typed_number(field, value)?).map_err(|_| bad(field, "the number is out of range"))?),
        Kind::Long => owned(typed_number(field, value)?),
        Kind::Ssid => {
            let text = typed_text(field, value)?;
            if !validate::ssid(text) {
                return Err(bad(field, "a network name is 1 to 32 bytes long"));
            }
            owned(text.as_bytes().to_vec())
        }
        Kind::Mac => {
            let text = typed_text(field, value)?;
            if text.is_empty() {
                return Ok(None);
            }
            owned(parse_mac(field, text)?)
        }
        Kind::FilePath => {
            let text = typed_text(field, value)?;
            if text.is_empty() {
                return Ok(None);
            }
            let mut bytes = b"file://".to_vec();
            bytes.extend_from_slice(text.as_bytes());
            bytes.push(0);
            owned(bytes)
        }
        Kind::TextList => {
            let list = text_list(field, value)?;
            if list.is_empty() {
                return Ok(None);
            }
            owned(list)
        }
        Kind::Addresses => {
            let list = text_list(field, value)?;
            if list.is_empty() {
                return Ok(None);
            }
            let parsed: Vec<_> = list.iter().map(|text| parse_address(field, section, text)).collect::<Result<_, _>>()?;
            owned(parsed)
        }
        Kind::Routes => {
            let list = value.as_array().ok_or_else(|| wrong_type(field))?;
            if list.is_empty() {
                return Ok(None);
            }
            let parsed: Vec<_> = list.iter().map(|entry| parse_route(field, section, entry)).collect::<Result<_, _>>()?;
            owned(parsed)
        }
        Kind::TextMap => {
            let map = value.as_object().ok_or_else(|| wrong_type(field))?;
            if map.is_empty() {
                return Ok(None);
            }
            let parsed: HashMap<String, String> =
                map.iter().map(|(entry, text)| text.as_str().map(|text| (entry.clone(), text.to_string())).ok_or_else(|| wrong_type(field))).collect::<Result<_, _>>()?;
            owned(parsed)
        }
        Kind::Peers => {
            let list = value.as_array().ok_or_else(|| wrong_type(field))?;
            let parsed: Vec<_> = list.iter().map(|entry| parse_peer(field, entry)).collect::<Result<_, _>>()?;
            if parsed.is_empty() {
                return Ok(None);
            }
            owned(parsed)
        }
    }))
}

/// A value for a key the table above doesn't know, typed after what the profile holds there now.
fn value_like_existing(field: &str, existing: &OwnedVariant, value: &Value) -> Result<Option<OwnedVariant>, ApiError> {
    if value.is_null() {
        return Ok(None);
    }
    Ok(Some(match &**existing {
        Variant::Str(_) => {
            let text = typed_text(field, value)?;
            if text.is_empty() {
                return Ok(None);
            }
            owned(text.to_string())
        }
        Variant::Bool(_) => owned(value.as_bool().ok_or_else(|| wrong_type(field))?),
        Variant::I32(_) => owned(i32::try_from(typed_number(field, value)?).map_err(|_| bad(field, "the number is out of range"))?),
        Variant::U32(_) => owned(u32::try_from(typed_number(field, value)?).map_err(|_| bad(field, "the number is out of range"))?),
        Variant::I64(_) => owned(typed_number(field, value)?),
        Variant::U64(_) => owned(u64::try_from(typed_number(field, value)?).map_err(|_| bad(field, "the number is out of range"))?),
        _ => return Err(bad(field, "this setting can't be edited here")),
    }))
}

fn check_semantics(settings: &Settings) -> Result<(), ApiError> {
    if let Some(security) = settings.get("802-11-wireless-security") {
        let key_mgmt = values::text_or_empty(security, "key-mgmt");
        if let Some(psk) = values::text(security, "psk") {
            let flagged = values::number(security, "psk-flags").unwrap_or(0) != 0;
            if !flagged && key_mgmt == "wpa-psk" && !validate::wpa_psk(&psk) {
                return Err(bad("802-11-wireless-security.psk", "a password is 8 to 63 characters long"));
            }
            if !flagged && key_mgmt == "sae" && !validate::sae_password(&psk) {
                return Err(bad("802-11-wireless-security.psk", "the password is empty"));
            }
        }
        if let Some(key) = values::text(security, "wep-key0") {
            if key_mgmt == "none" && !validate::wep_key(&key) {
                return Err(bad("802-11-wireless-security.wep-key0", "a WEP key is 5 or 13 characters, or 10 or 26 hex digits"));
            }
        }
    }
    for (section, address_ok) in [("ipv4", validate::ipv4 as fn(&str) -> bool), ("ipv6", validate::ipv6)] {
        let Some(props) = settings.get(section) else { continue };
        if let Some(gateway) = values::text(props, "gateway") {
            if !address_ok(&gateway) {
                return Err(bad(&format!("{section}.gateway"), "not an address"));
            }
        }
        for server in values::strings(props, "dns-data") {
            if !address_ok(&server) {
                return Err(bad(&format!("{section}.dns"), "a DNS server isn't an address"));
            }
        }
        if values::text_or_empty(props, "method") == "manual" && !props.contains_key("address-data") && !props.contains_key("addresses") {
            return Err(bad(&format!("{section}.address-data"), "a fixed configuration needs an address"));
        }
    }
    if let Some(wireguard) = settings.get("wireguard") {
        if let Some(key) = values::text(wireguard, "private-key") {
            if !validate::wireguard_key(&key) {
                return Err(bad("wireguard.private-key", "not a valid key"));
            }
        }
    }
    Ok(())
}

/// Applies a form's edits (`section.key` → value, `null` to clear) to a profile.
pub fn apply_changes(settings: &mut Settings, changes: &Map<String, Value>) -> Result<(), ApiError> {
    for (field, value) in changes {
        let (section, key) = field.split_once('.').ok_or_else(|| bad(field, "not a setting"))?;
        // One entry of a VPN's dictionary, the rest of which stays as it is
        if let Some((dictionary, entry)) = key.split_once('.').filter(|(dictionary, _)| section == "vpn" && matches!(*dictionary, "data" | "secrets")) {
            let text = match value {
                Value::Null => "",
                Value::String(text) => text.as_str(),
                _ => return Err(wrong_type(field)),
            };
            let props = settings.entry(section.to_string()).or_default();
            let mut map: HashMap<String, String> = props.get(dictionary).and_then(|stored| HashMap::<String, String>::try_from(stored.clone()).ok()).unwrap_or_default();
            if text.is_empty() {
                map.remove(entry);
            } else {
                map.insert(entry.to_string(), text.to_string());
            }
            if map.is_empty() {
                props.remove(dictionary);
            } else {
                props.insert(dictionary.to_string(), owned(map));
            }
            continue;
        }
        // Names on a form that stand for more than one stored key
        if matches!(section, "ipv4" | "ipv6") && key == "dns" {
            let props = settings.entry(section.to_string()).or_default();
            props.remove("dns");
            match value_from_form(section, "dns-data", Kind::TextList, value)? {
                Some(entry) => props.insert("dns-data".to_string(), entry),
                None => props.remove("dns-data"),
            };
            continue;
        }
        let converted = match kind_of(section, key) {
            Some(kind) => value_from_form(section, key, kind, value)?,
            None => match settings.get(section).and_then(|props| props.get(key)) {
                Some(existing) => value_like_existing(field, existing, value)?,
                None if value.is_null() => None,
                None => return Err(bad(field, "unknown setting")),
            },
        };
        let props = settings.entry(section.to_string()).or_default();
        match converted {
            Some(entry) => {
                props.insert(key.to_string(), entry);
            }
            None => {
                props.remove(key);
            }
        }
        // The older stored forms lose to the newer ones only when these are present, so they go together
        let replaces: &[&str] = match (section, key) {
            ("ipv4" | "ipv6", "address-data") => &["addresses"],
            ("ipv4" | "ipv6", "route-data") => &["routes"],
            ("802-11-wireless" | "802-3-ethernet", "assigned-mac-address") => &["cloned-mac-address"],
            _ => &[],
        };
        for older in replaces {
            props.remove(*older);
        }
    }
    settings.retain(|name, props| name == "connection" || !props.is_empty() || REQUIRED_EVEN_EMPTY.contains(&name.as_str()));
    check_semantics(settings)
}

/// Sections whose presence means something by itself.
const REQUIRED_EVEN_EMPTY: [&str; 8] = ["802-3-ethernet", "802-11-wireless", "ipv4", "ipv6", "proxy", "wireguard", "bridge", "bond"];

fn random_uuid() -> Result<String, ApiError> {
    std::fs::read_to_string("/proc/sys/kernel/random/uuid").map(|text| text.trim().to_string()).map_err(|_| ApiError::new(ErrorCode::Failed, "couldn't generate a profile ID"))
}

/// The starting point of a new profile of a kind, before its form's values go on top.
pub fn new_profile(connection_type: &str, vpn_service: Option<&str>) -> Result<Settings, ApiError> {
    let mut settings = Settings::new();
    let section = match connection_type {
        "802-11-wireless" | "802-3-ethernet" | "wireguard" | "bridge" | "bond" | "vlan" | "pppoe" | "team" | "gsm" | "cdma" | "vpn" => connection_type,
        other => return Err(ApiError::invalid(format!("can't create a profile of type {other}"))),
    };
    let mut connection = Props::new();
    connection.insert("uuid".to_string(), owned(random_uuid()?));
    connection.insert("type".to_string(), owned(connection_type));
    settings.insert("connection".to_string(), connection);
    settings.insert(section.to_string(), Props::new());
    match connection_type {
        "802-11-wireless" => {
            settings.get_mut(section).expect("just added").insert("mode".to_string(), owned("infrastructure"));
        }
        "vpn" => {
            let service = vpn_service.filter(|service| !service.is_empty()).ok_or_else(|| ApiError::invalid("a VPN needs a kind"))?;
            settings.get_mut(section).expect("just added").insert("service-type".to_string(), owned(service));
        }
        // Their addresses come through the tunnel's own configuration, unless given
        "wireguard" => {
            settings.insert("ipv4".to_string(), Props::from([("method".to_string(), owned("disabled"))]));
            settings.insert("ipv6".to_string(), Props::from([("method".to_string(), owned("ignore"))]));
        }
        _ => {}
    }
    settings.entry("ipv4".to_string()).or_default().entry("method".to_string()).or_insert_with(|| owned("auto"));
    settings.entry("ipv6".to_string()).or_default().entry("method".to_string()).or_insert_with(|| owned("auto"));
    Ok(settings)
}

/// A WireGuard profile as a `wg-quick` configuration file.
pub fn wireguard_config(settings: &Settings, secrets: &Settings) -> Result<String, ApiError> {
    let wireguard = settings.get("wireguard").ok_or_else(|| ApiError::invalid("This isn't a WireGuard profile"))?;
    let hidden = secrets.get("wireguard");
    let private_key = hidden.and_then(|props| values::text(props, "private-key")).or_else(|| values::text(wireguard, "private-key"));
    let private_key = private_key.ok_or_else(|| ApiError::new(ErrorCode::SecretsRequired, "No saved private key was found"))?;
    let mut text = format!("[Interface]\nPrivateKey = {private_key}\n");
    if let Some(port) = values::number(wireguard, "listen-port").filter(|port| *port != 0) {
        text.push_str(&format!("ListenPort = {port}\n"));
    }
    let mut addresses = Vec::new();
    let mut dns = Vec::new();
    for section in ["ipv4", "ipv6"] {
        if let Some(props) = settings.get(section) {
            for entry in values::dicts(props, "address-data") {
                if let (Some(address), Some(prefix)) = (values::text(&entry, "address"), values::number(&entry, "prefix")) {
                    addresses.push(format!("{address}/{prefix}"));
                }
            }
            dns.extend(values::strings(props, "dns-data"));
        }
    }
    if !addresses.is_empty() {
        text.push_str(&format!("Address = {}\n", addresses.join(", ")));
    }
    if !dns.is_empty() {
        text.push_str(&format!("DNS = {}\n", dns.join(", ")));
    }
    if let Some(mtu) = values::number(wireguard, "mtu").filter(|mtu| *mtu != 0) {
        text.push_str(&format!("MTU = {mtu}\n"));
    }
    let hidden_peers = hidden.map(|props| values::dicts(props, "peers")).unwrap_or_default();
    for peer in values::dicts(wireguard, "peers") {
        let key = values::text_or_empty(&peer, "public-key");
        text.push_str(&format!("\n[Peer]\nPublicKey = {key}\n"));
        let shared = hidden_peers.iter().find(|other| values::text_or_empty(other, "public-key") == key).and_then(|other| values::text(other, "preshared-key")).or_else(|| values::text(&peer, "preshared-key"));
        if let Some(shared) = shared {
            text.push_str(&format!("PresharedKey = {shared}\n"));
        }
        let allowed = values::strings(&peer, "allowed-ips");
        if !allowed.is_empty() {
            text.push_str(&format!("AllowedIPs = {}\n", allowed.join(", ")));
        }
        if let Some(endpoint) = values::text(&peer, "endpoint") {
            text.push_str(&format!("Endpoint = {endpoint}\n"));
        }
        if let Some(keepalive) = values::number(&peer, "persistent-keepalive").filter(|interval| *interval != 0) {
            text.push_str(&format!("PersistentKeepalive = {keepalive}\n"));
        }
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::values::build::{owned as value, props};
    use proptest::prelude::*;

    fn map(entries: Value) -> Map<String, Value> {
        entries.as_object().unwrap().clone()
    }

    fn wifi() -> Settings {
        let mut settings = Settings::new();
        settings.insert(
            "connection".to_string(),
            props([("id", value("Home")), ("uuid", value("u")), ("type", value("802-11-wireless")), ("timestamp", value(99u64)), ("some-future-key", value("keep me"))]),
        );
        settings.insert(
            "802-11-wireless".to_string(),
            props([("ssid", value(vec![0x41u8, 0xFF])), ("mode", value("infrastructure")), ("mac-address", value(vec![0xAAu8, 0xBB, 0xCC, 0, 1, 2]))]),
        );
        settings.insert("802-11-wireless-security".to_string(), props([("key-mgmt", value("wpa-psk"))]));
        settings.insert("ipv4".to_string(), props([("method", value("auto"))]));
        settings.insert("x-unknown-section".to_string(), props([("thing", value(vec![1u32, 2]))]));
        settings
    }

    #[test]
    fn applying_nothing_changes_nothing() {
        let original = wifi();
        let mut edited = original.clone();
        apply_changes(&mut edited, &Map::new()).unwrap();
        assert_eq!(edited, original);
    }

    #[test]
    fn edits_leave_everything_else_alone_unknown_keys_and_all() {
        let original = wifi();
        let mut edited = original.clone();
        apply_changes(&mut edited, &map(json!({ "connection.autoconnect": false, "ipv4.method": "disabled" }))).unwrap();
        assert_eq!(values::flag(&edited["connection"], "autoconnect"), Some(false));
        assert_eq!(values::text(&edited["ipv4"], "method").as_deref(), Some("disabled"));
        assert_eq!(edited["x-unknown-section"], original["x-unknown-section"]);
        assert_eq!(edited["802-11-wireless"], original["802-11-wireless"]);
        assert_eq!(values::text(&edited["connection"], "some-future-key").as_deref(), Some("keep me"));
    }

    #[test]
    fn the_form_reads_bytes_as_people_would() {
        let form = to_form(&wifi());
        assert_eq!(form["802-11-wireless.mac-address"], "AA:BB:CC:00:01:02");
        assert_eq!(form["802-11-wireless.ssid"], "A\u{FFFD}");
        assert_eq!(form["connection.timestamp"], 99);
        assert_eq!(form["ipv4.dns"], json!([]));
    }

    #[test]
    fn a_form_value_that_comes_back_unchanged_stores_the_same() {
        let original = wifi();
        let form = to_form(&original);
        let mut edited = original.clone();
        let changes = map(json!({
            "802-11-wireless.mac-address": form["802-11-wireless.mac-address"],
            "802-11-wireless.mode": form["802-11-wireless.mode"],
            "connection.id": form["connection.id"],
        }));
        apply_changes(&mut edited, &changes).unwrap();
        assert_eq!(edited, original);
    }

    #[test]
    fn addresses_round_trip() {
        let mut settings = Settings::new();
        settings.insert("ipv4".to_string(), props([("method", value("manual"))]));
        apply_changes(&mut settings, &map(json!({ "ipv4.address-data": ["10.0.0.2/24", "10.0.0.3"] }))).unwrap();
        assert_eq!(to_form(&settings)["ipv4.address-data"], json!(["10.0.0.2/24", "10.0.0.3/32"]));
        let entries = values::dicts(&settings["ipv4"], "address-data");
        assert_eq!(values::text(&entries[0], "address").as_deref(), Some("10.0.0.2"));
        assert_eq!(values::number(&entries[0], "prefix"), Some(24));
    }

    #[test]
    fn editing_addresses_drops_the_older_stored_form() {
        let mut settings = Settings::new();
        settings.insert("ipv4".to_string(), props([("method", value("manual")), ("addresses", value(vec![vec![1u32, 2, 3]]))]));
        apply_changes(&mut settings, &map(json!({ "ipv4.address-data": ["10.0.0.2/24"] }))).unwrap();
        assert!(!settings["ipv4"].contains_key("addresses"));
    }

    #[test]
    fn a_fixed_configuration_needs_an_address() {
        let mut settings = Settings::new();
        settings.insert("ipv4".to_string(), props([("method", value("auto"))]));
        let error = apply_changes(&mut settings, &map(json!({ "ipv4.method": "manual" }))).unwrap_err();
        assert!(error.message.contains("ipv4.address-data"));
        apply_changes(&mut settings, &map(json!({ "ipv4.method": "manual", "ipv4.address-data": ["10.0.0.2/24"], "ipv4.gateway": "10.0.0.1" }))).unwrap();
    }

    #[test]
    fn dns_reads_from_either_stored_form_and_writes_the_new_one() {
        let mut settings = Settings::new();
        // 1.1.1.1 in network byte order, as `au`
        settings.insert("ipv4".to_string(), props([("method", value("auto")), ("dns", value(vec![0x0101_0101u32, 0x0808_0808]))]));
        let mut server = vec![0u8; 16];
        server[15] = 1;
        settings.insert("ipv6".to_string(), props([("method", value("auto")), ("dns", value(vec![server]))]));
        let form = to_form(&settings);
        assert_eq!(form["ipv4.dns"], json!(["1.1.1.1", "8.8.8.8"]));
        assert_eq!(form["ipv6.dns"], json!(["::1"]));

        apply_changes(&mut settings, &map(json!({ "ipv4.dns": ["9.9.9.9"] }))).unwrap();
        assert!(!settings["ipv4"].contains_key("dns"));
        assert_eq!(values::strings(&settings["ipv4"], "dns-data"), ["9.9.9.9"]);
        assert_eq!(to_form(&settings)["ipv4.dns"], json!(["9.9.9.9"]));

        apply_changes(&mut settings, &map(json!({ "ipv4.dns": [] }))).unwrap();
        assert!(!settings["ipv4"].contains_key("dns-data"));
        assert_eq!(apply_changes(&mut settings, &map(json!({ "ipv4.dns": ["nope"] }))).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn routes_round_trip() {
        let mut settings = Settings::new();
        settings.insert("ipv4".to_string(), props([("method", value("auto"))]));
        let route = json!({ "dest": "10.1.0.0", "prefix": 16, "next-hop": "10.0.0.1", "metric": 50 });
        apply_changes(&mut settings, &map(json!({ "ipv4.route-data": [route.clone()] }))).unwrap();
        assert_eq!(to_form(&settings)["ipv4.route-data"], json!([route]));
        for bad_route in [json!({ "dest": "x", "prefix": 1 }), json!({ "dest": "10.0.0.0" }), json!({ "dest": "10.0.0.0", "prefix": 40 }), json!({ "dest": "10.0.0.0", "prefix": 8, "next-hop": "x" })] {
            assert_eq!(apply_changes(&mut settings, &map(json!({ "ipv4.route-data": [bad_route] }))).unwrap_err().code, ErrorCode::Invalid);
        }
        apply_changes(&mut settings, &map(json!({ "ipv4.route-data": [] }))).unwrap();
        assert!(!settings["ipv4"].contains_key("route-data"));
    }

    #[test]
    fn empty_means_not_set() {
        let mut settings = wifi();
        apply_changes(&mut settings, &map(json!({ "802-11-wireless.mac-address": "", "ipv4.gateway": "", "connection.some-future-key": null }))).unwrap();
        assert!(!settings["802-11-wireless"].contains_key("mac-address"));
        assert!(!settings["ipv4"].contains_key("gateway"));
        assert!(!settings["connection"].contains_key("some-future-key"));
    }

    #[test]
    fn digits_from_a_text_field_count_as_numbers() {
        let mut settings = wifi();
        apply_changes(&mut settings, &map(json!({ "802-11-wireless.mtu": "1400", "connection.autoconnect-priority": -5, "ipv4.route-metric": 100 }))).unwrap();
        assert_eq!(values::number(&settings["802-11-wireless"], "mtu"), Some(1400));
        assert_eq!(values::number(&settings["connection"], "autoconnect-priority"), Some(-5));
        assert_eq!(values::number(&settings["ipv4"], "route-metric"), Some(100));
        assert_eq!(apply_changes(&mut settings, &map(json!({ "802-11-wireless.mtu": "lots" }))).unwrap_err().code, ErrorCode::Invalid);
        assert_eq!(apply_changes(&mut settings, &map(json!({ "802-11-wireless.mtu": -1 }))).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn unknown_keys_take_the_type_they_already_have() {
        let mut settings = Settings::new();
        settings.insert("x".to_string(), props([("s", value("a")), ("b", value(true)), ("u", value(1u32)), ("i", value(1i32)), ("l", value(1i64)), ("t", value(1u64)), ("list", value(vec![1u32]))]));
        apply_changes(&mut settings, &map(json!({ "x.s": "b", "x.b": false, "x.u": 2, "x.i": -2, "x.l": 3, "x.t": 4 }))).unwrap();
        assert_eq!(values::text(&settings["x"], "s").as_deref(), Some("b"));
        assert_eq!(values::flag(&settings["x"], "b"), Some(false));
        assert_eq!(values::number(&settings["x"], "u"), Some(2));
        assert_eq!(values::number(&settings["x"], "i"), Some(-2));
        assert_eq!(values::number(&settings["x"], "l"), Some(3));
        assert_eq!(values::number(&settings["x"], "t"), Some(4));
        assert_eq!(apply_changes(&mut settings, &map(json!({ "x.list": [2] }))).unwrap_err().code, ErrorCode::Invalid);
        assert_eq!(apply_changes(&mut settings, &map(json!({ "x.never-seen": 1 }))).unwrap_err().code, ErrorCode::Invalid);
        assert_eq!(apply_changes(&mut settings, &map(json!({ "nosection": 1 }))).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn wrong_types_are_refused_with_the_field_named() {
        let mut settings = wifi();
        for (field, bad_value) in [
            ("connection.id", json!(5)),
            ("connection.autoconnect", json!("yes")),
            ("802-11-wireless-security.proto", json!("rsn")),
            ("vpn.data", json!(["a"])),
            ("ipv4.address-data", json!(["999.0.0.1/24"])),
            ("802-11-wireless.bssid", json!("not a mac")),
            ("802-11-wireless.ssid", json!("x".repeat(33))),
        ] {
            let error = apply_changes(&mut settings, &map(json!({ field: bad_value }))).unwrap_err();
            assert_eq!(error.code, ErrorCode::Invalid, "{field}");
            assert!(error.message.starts_with(field), "{field}: {}", error.message);
        }
    }

    #[test]
    fn passwords_are_checked_by_the_security_they_are_for() {
        let mut settings = wifi();
        assert_eq!(apply_changes(&mut settings, &map(json!({ "802-11-wireless-security.psk": "short" }))).unwrap_err().code, ErrorCode::Invalid);
        let mut settings = wifi();
        apply_changes(&mut settings, &map(json!({ "802-11-wireless-security.psk": "long enough" }))).unwrap();
        // "Ask every time" holds nothing to check
        let mut settings = wifi();
        apply_changes(&mut settings, &map(json!({ "802-11-wireless-security.psk-flags": 2, "802-11-wireless-security.psk": "short" }))).unwrap();
        let mut settings = wifi();
        apply_changes(&mut settings, &map(json!({ "802-11-wireless-security.key-mgmt": "sae", "802-11-wireless-security.psk": "short" }))).unwrap();
        let mut settings = wifi();
        assert_eq!(apply_changes(&mut settings, &map(json!({ "802-11-wireless-security.key-mgmt": "none", "802-11-wireless-security.wep-key0": "bad" }))).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn certificates_are_paths_with_their_prefix_and_end_marker() {
        let mut settings = Settings::new();
        settings.insert("802-1x".to_string(), Props::new());
        apply_changes(&mut settings, &map(json!({ "802-1x.ca-cert": "/etc/ssl/ca.pem", "802-1x.eap": ["peap"], "802-1x.phase2-auth": "mschapv2" }))).unwrap();
        let stored = values::bytes(&settings["802-1x"], "ca-cert").unwrap();
        assert_eq!(stored, b"file:///etc/ssl/ca.pem\0");
        assert_eq!(to_form(&settings)["802-1x.ca-cert"], "/etc/ssl/ca.pem");
        assert_eq!(to_form(&settings)["802-1x.eap"], json!(["peap"]));
    }

    #[test]
    fn a_certificate_held_inside_the_profile_isnt_shown_or_lost() {
        let mut settings = Settings::new();
        settings.insert("802-1x".to_string(), props([("ca-cert", value(vec![0x30u8, 0x82]))]));
        assert_eq!(to_form(&settings)["802-1x.ca-cert"], Value::Null);
        apply_changes(&mut settings, &map(json!({ "802-1x.identity": "me" }))).unwrap();
        assert_eq!(values::bytes(&settings["802-1x"], "ca-cert").unwrap(), [0x30, 0x82]);
    }

    #[test]
    fn vpn_dictionaries_go_whole() {
        let mut settings = new_profile("vpn", Some("org.freedesktop.NetworkManager.openvpn")).unwrap();
        apply_changes(&mut settings, &map(json!({ "vpn.data": { "remote": "vpn.example.com", "connection-type": "password" }, "vpn.secrets": { "password": "s3cret" } }))).unwrap();
        let form = to_form(&settings);
        assert_eq!(form["vpn.data"]["remote"], "vpn.example.com");
        assert_eq!(form["vpn.secrets"]["password"], "s3cret");
        assert_eq!(form["vpn.service-type"], "org.freedesktop.NetworkManager.openvpn");
        assert_eq!(apply_changes(&mut settings, &map(json!({ "vpn.data": { "remote": 5 } }))).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn one_vpn_setting_can_change_without_the_others() {
        let mut settings = new_profile("vpn", Some("org.freedesktop.NetworkManager.openvpn")).unwrap();
        apply_changes(&mut settings, &map(json!({ "vpn.data": { "remote": "a", "port": "1194" }, "vpn.secrets": { "password": "x", "cert-pass": "y" } }))).unwrap();
        apply_changes(&mut settings, &map(json!({ "vpn.data.remote": "b", "vpn.data.proto-tcp": "yes", "vpn.data.port": "", "vpn.secrets.password": "z" }))).unwrap();
        let form = to_form(&settings);
        assert_eq!(form["vpn.data"], json!({ "remote": "b", "proto-tcp": "yes" }));
        assert_eq!(form["vpn.secrets"], json!({ "password": "z", "cert-pass": "y" }));
        apply_changes(&mut settings, &map(json!({ "vpn.secrets.password": null, "vpn.secrets.cert-pass": null }))).unwrap();
        assert!(!settings["vpn"].contains_key("secrets"));
        assert_eq!(apply_changes(&mut settings, &map(json!({ "vpn.data.remote": 5 }))).unwrap_err().code, ErrorCode::Invalid);
    }

    const KEY_A: &str = "YAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=";
    const KEY_B: &str = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";

    #[test]
    fn wireguard_peers_are_typed_and_checked() {
        let mut settings = new_profile("wireguard", None).unwrap();
        apply_changes(
            &mut settings,
            &map(json!({
                "connection.interface-name": "wg0",
                "wireguard.private-key": KEY_A,
                "wireguard.listen-port": 51820,
                "wireguard.peers": [{ "public-key": KEY_B, "endpoint": "vpn.example.com:51820", "allowed-ips": ["0.0.0.0/0", "::/0"], "persistent-keepalive": 25 }],
            })),
        )
        .unwrap();
        let peers = values::dicts(&settings["wireguard"], "peers");
        assert_eq!(values::text(&peers[0], "endpoint").as_deref(), Some("vpn.example.com:51820"));
        assert_eq!(values::strings(&peers[0], "allowed-ips"), ["0.0.0.0/0", "::/0"]);
        assert_eq!(values::number(&peers[0], "persistent-keepalive"), Some(25));
        for bad_peer in [json!({ "public-key": "short" }), json!({ "public-key": KEY_B, "allowed-ips": ["nope"] }), json!({ "public-key": KEY_B, "preshared-key": "short" })] {
            assert_eq!(apply_changes(&mut settings, &map(json!({ "wireguard.peers": [bad_peer] }))).unwrap_err().code, ErrorCode::Invalid);
        }
        assert_eq!(apply_changes(&mut settings, &map(json!({ "wireguard.private-key": "short" }))).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn wireguard_exports_as_a_wg_quick_file() {
        let mut settings = new_profile("wireguard", None).unwrap();
        apply_changes(
            &mut settings,
            &map(json!({
                "wireguard.listen-port": 51820,
                "wireguard.mtu": 1420,
                "ipv4.method": "manual",
                "ipv4.address-data": ["10.0.0.2/32"],
                "ipv4.dns": ["1.1.1.1"],
                "wireguard.peers": [{ "public-key": KEY_B, "endpoint": "vpn.example.com:51820", "allowed-ips": ["0.0.0.0/0"], "persistent-keepalive": 25 }],
            })),
        )
        .unwrap();
        let mut secrets = Settings::new();
        secrets.insert("wireguard".to_string(), props([("private-key", value(KEY_A))]));
        let text = wireguard_config(&settings, &secrets).unwrap();
        assert_eq!(
            text,
            format!("[Interface]\nPrivateKey = {KEY_A}\nListenPort = 51820\nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\nMTU = 1420\n\n[Peer]\nPublicKey = {KEY_B}\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example.com:51820\nPersistentKeepalive = 25\n")
        );
        assert_eq!(wireguard_config(&settings, &Settings::new()).unwrap_err().code, ErrorCode::SecretsRequired);
        assert_eq!(wireguard_config(&wifi(), &Settings::new()).unwrap_err().code, ErrorCode::Invalid);
    }

    #[test]
    fn new_profiles_have_what_the_service_requires() {
        let settings = new_profile("802-3-ethernet", None).unwrap();
        assert_eq!(values::text(&settings["connection"], "type").as_deref(), Some("802-3-ethernet"));
        assert_eq!(values::text(&settings["connection"], "uuid").unwrap().len(), 36);
        assert!(settings.contains_key("802-3-ethernet"));
        assert_eq!(values::text(&settings["ipv4"], "method").as_deref(), Some("auto"));
        let settings = new_profile("802-11-wireless", None).unwrap();
        assert_eq!(values::text(&settings["802-11-wireless"], "mode").as_deref(), Some("infrastructure"));
        let settings = new_profile("wireguard", None).unwrap();
        assert_eq!(values::text(&settings["ipv4"], "method").as_deref(), Some("disabled"));
        assert_eq!(new_profile("vpn", None).unwrap_err().code, ErrorCode::Invalid);
        assert_eq!(new_profile("loopback", None).unwrap_err().code, ErrorCode::Invalid);
        assert_ne!(
            values::text(&new_profile("bridge", None).unwrap()["connection"], "uuid"),
            values::text(&new_profile("bridge", None).unwrap()["connection"], "uuid"),
        );
    }

    #[test]
    fn revisions_change_with_the_content_only() {
        let a = wifi();
        assert_eq!(revision(&a), revision(&a.clone()));
        let mut b = a.clone();
        apply_changes(&mut b, &map(json!({ "connection.id": "Other" }))).unwrap();
        assert_ne!(revision(&a), revision(&b));
    }

    #[test]
    fn empty_sections_that_mean_nothing_are_dropped() {
        let mut settings = wifi();
        apply_changes(&mut settings, &map(json!({ "802-1x.identity": "me" }))).unwrap();
        assert!(settings.contains_key("802-1x"));
        apply_changes(&mut settings, &map(json!({ "802-1x.identity": null }))).unwrap();
        assert!(!settings.contains_key("802-1x"));
        assert!(settings.contains_key("802-11-wireless"));
    }

    proptest! {
        #[test]
        fn any_text_setting_round_trips(text in "[^\u{0}]{1,40}") {
            let mut settings = wifi();
            let changes = map(json!({ "connection.zone": text.clone() }));
            apply_changes(&mut settings, &changes).unwrap();
            prop_assert_eq!(to_form(&settings)["connection.zone"].clone(), json!(text));
        }

        #[test]
        fn any_mac_round_trips(bytes in any::<[u8; 6]>()) {
            let original = wifi();
            let mac = values::mac_from_bytes(&bytes);
            let mut settings = original;
            apply_changes(&mut settings, &map(json!({ "802-11-wireless.bssid": mac.clone() }))).unwrap();
            prop_assert_eq!(values::bytes(&settings["802-11-wireless"], "bssid").unwrap(), bytes.to_vec());
            prop_assert_eq!(to_form(&settings)["802-11-wireless.bssid"].clone(), json!(mac));
        }

        #[test]
        fn any_address_list_round_trips(octets in proptest::collection::vec((any::<[u8; 4]>(), 0u32..=32), 1..5)) {
            let list: Vec<String> = octets.iter().map(|(octets, prefix)| format!("{}/{prefix}", Ipv4Addr::from(*octets))).collect();
            let mut settings = Settings::new();
            settings.insert("ipv4".to_string(), props([("method", value("manual"))]));
            apply_changes(&mut settings, &map(json!({ "ipv4.address-data": list.clone() }))).unwrap();
            prop_assert_eq!(to_form(&settings)["ipv4.address-data"].clone(), json!(list));
        }

        #[test]
        fn form_values_written_back_never_change_a_profile(ssid in proptest::collection::vec(any::<u8>(), 1..32), autoconnect in any::<bool>(), priority in -100i32..100) {
            // The non-UTF-8 name is the hard case: its form value is lossy, so it can only stay intact by being left out of the edits
            let mut original = wifi();
            original.get_mut("802-11-wireless").unwrap().insert("ssid".to_string(), value(ssid));
            original.get_mut("connection").unwrap().insert("autoconnect".to_string(), value(autoconnect));
            original.get_mut("connection").unwrap().insert("autoconnect-priority".to_string(), value(priority));
            let form = to_form(&original);
            let mut edited = original.clone();
            let changes = map(json!({ "connection.autoconnect": form["connection.autoconnect"], "connection.autoconnect-priority": form["connection.autoconnect-priority"] }));
            apply_changes(&mut edited, &changes).unwrap();
            prop_assert_eq!(edited, original);
        }
    }
}
