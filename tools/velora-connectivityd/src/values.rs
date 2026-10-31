//! Reading the dictionaries D-Bus hands over, which are typed but whose contents depend on the service.

use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use zbus::{OwnedVariant, Variant};

pub type Props = HashMap<String, OwnedVariant>;
pub type Interfaces = HashMap<String, Props>;
/// Everything an `org.freedesktop.DBus.ObjectManager` knows, by object path.
pub type Objects = BTreeMap<String, Interfaces>;
/// A NetworkManager connection profile: setting name → key → value.
pub type Settings = HashMap<String, Props>;

fn unwrap_variant<'a, 'b>(value: &'b Variant<'a>) -> &'b Variant<'a> {
    match value {
        Variant::Variant(inner) => unwrap_variant(inner),
        other => other,
    }
}

pub fn text(props: &Props, key: &str) -> Option<String> {
    match unwrap_variant(props.get(key)?) {
        Variant::Str(value) => Some(value.to_string()),
        Variant::ObjectPath(value) => Some(value.to_string()),
        _ => None,
    }
}

pub fn text_or_empty(props: &Props, key: &str) -> String {
    text(props, key).unwrap_or_default()
}

/// An object path property, with NetworkManager's "/" for "none" read as absent.
pub fn path(props: &Props, key: &str) -> Option<String> {
    text(props, key).filter(|value| value != "/" && !value.is_empty())
}

pub fn flag(props: &Props, key: &str) -> Option<bool> {
    match unwrap_variant(props.get(key)?) {
        Variant::Bool(value) => Some(*value),
        _ => None,
    }
}

pub fn number(props: &Props, key: &str) -> Option<i64> {
    match unwrap_variant(props.get(key)?) {
        Variant::U8(value) => Some(i64::from(*value)),
        Variant::U16(value) => Some(i64::from(*value)),
        Variant::I16(value) => Some(i64::from(*value)),
        Variant::U32(value) => Some(i64::from(*value)),
        Variant::I32(value) => Some(i64::from(*value)),
        Variant::I64(value) => Some(*value),
        Variant::U64(value) => i64::try_from(*value).ok(),
        _ => None,
    }
}

pub fn bytes(props: &Props, key: &str) -> Option<Vec<u8>> {
    let Variant::Array(array) = unwrap_variant(props.get(key)?) else { return None };
    array.inner().iter().map(|item| if let Variant::U8(byte) = unwrap_variant(item) { Some(*byte) } else { None }).collect()
}

pub fn strings(props: &Props, key: &str) -> Vec<String> {
    let Some(Variant::Array(array)) = props.get(key).map(|value| unwrap_variant(value)) else { return Vec::new() };
    array
        .inner()
        .iter()
        .filter_map(|item| match unwrap_variant(item) {
            Variant::Str(value) => Some(value.to_string()),
            Variant::ObjectPath(value) => Some(value.to_string()),
            _ => None,
        })
        .collect()
}

/// `aa{sv}`, as used for `AddressData`, `RouteData` and `Nameservers`.
pub fn dicts(props: &Props, key: &str) -> Vec<Props> {
    let Some(Variant::Array(array)) = props.get(key).map(|value| unwrap_variant(value)) else { return Vec::new() };
    array.inner().iter().filter_map(dict_entries).collect()
}

fn dict_entries(value: &Variant<'_>) -> Option<Props> {
    let Variant::Dict(dict) = unwrap_variant(value) else { return None };
    let mut props = Props::new();
    for (key, entry) in dict.iter() {
        let Variant::Str(key) = unwrap_variant(key) else { return None };
        props.insert(key.to_string(), entry.try_to_owned().ok()?);
    }
    Some(props)
}

/// A readable form of any value, for showing every setting of a profile as it is. Bytes that spell
/// nothing come out as a list of numbers.
pub fn to_json(value: &Variant<'_>) -> Value {
    match unwrap_variant(value) {
        Variant::U8(value) => json!(value),
        Variant::Bool(value) => json!(value),
        Variant::I16(value) => json!(value),
        Variant::U16(value) => json!(value),
        Variant::I32(value) => json!(value),
        Variant::U32(value) => json!(value),
        Variant::I64(value) => json!(value),
        Variant::U64(value) => json!(value),
        Variant::F64(value) => json!(value),
        Variant::Str(value) => json!(value.to_string()),
        Variant::Signature(value) => json!(value.to_string()),
        Variant::ObjectPath(value) => json!(value.to_string()),
        Variant::Array(array) => Value::Array(array.inner().iter().map(to_json).collect()),
        Variant::Dict(dict) => {
            let mut map = Map::new();
            for (key, entry) in dict.iter() {
                let key = match unwrap_variant(key) {
                    Variant::Str(key) => key.to_string(),
                    other => to_json(other).to_string(),
                };
                map.insert(key, to_json(entry));
            }
            Value::Object(map)
        }
        Variant::Structure(structure) => Value::Array(structure.fields().iter().map(to_json).collect()),
        _ => Value::Null,
    }
}

/// `aa:bb:cc:dd:ee:ff` from the bytes NetworkManager stores a MAC address as.
pub fn mac_from_bytes(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02X}")).collect::<Vec<_>>().join(":")
}

/// Test helpers for building the dictionaries above without a bus.
#[cfg(test)]
pub mod build {
    use super::*;

    pub fn owned<'a>(value: impl Into<Variant<'a>>) -> OwnedVariant {
        value.into().try_into_owned().expect("no file descriptors in test values")
    }

    pub fn props<const N: usize>(entries: [(&str, OwnedVariant); N]) -> Props {
        entries.into_iter().map(|(key, value)| (key.to_string(), value)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::build::*;
    use super::*;
    use zbus::ObjectPath;

    #[test]
    fn typed_reads_return_nothing_for_another_type() {
        let values = props([("a", owned("x")), ("b", owned(7u32)), ("c", owned(true))]);
        assert_eq!(text(&values, "a").as_deref(), Some("x"));
        assert_eq!(text(&values, "b"), None);
        assert_eq!(number(&values, "b"), Some(7));
        assert_eq!(number(&values, "a"), None);
        assert_eq!(flag(&values, "c"), Some(true));
        assert_eq!(flag(&values, "missing"), None);
    }

    #[test]
    fn the_root_path_means_none() {
        let root = ObjectPath::try_from("/").unwrap();
        let some = ObjectPath::try_from("/x/1").unwrap();
        let values = props([("a", owned(root)), ("b", owned(some))]);
        assert_eq!(path(&values, "a"), None);
        assert_eq!(path(&values, "b").as_deref(), Some("/x/1"));
    }

    #[test]
    fn bytes_lists_and_dictionaries() {
        let mut address = HashMap::new();
        address.insert("address".to_string(), Variant::from("10.0.0.2"));
        address.insert("prefix".to_string(), Variant::from(24u32));
        let values = props([
            ("ssid", owned(vec![0x41u8, 0xFF])),
            ("names", owned(vec!["a", "b"])),
            ("data", owned(vec![address])),
        ]);
        assert_eq!(bytes(&values, "ssid"), Some(vec![0x41, 0xFF]));
        assert_eq!(strings(&values, "names"), ["a", "b"]);
        let data = dicts(&values, "data");
        assert_eq!(text(&data[0], "address").as_deref(), Some("10.0.0.2"));
        assert_eq!(number(&data[0], "prefix"), Some(24));
    }

    #[test]
    fn any_value_has_a_readable_form() {
        assert_eq!(to_json(&Variant::from(vec![1u8, 2])), json!([1, 2]));
        assert_eq!(to_json(&Variant::from("x")), json!("x"));
        let mut map = HashMap::new();
        map.insert("k".to_string(), 5u32);
        assert_eq!(to_json(&Variant::from(map)), json!({ "k": 5 }));
    }

    #[test]
    fn mac_addresses_are_upper_case_pairs() {
        assert_eq!(mac_from_bytes(&[0x0a, 0x1b, 0, 0xff]), "0A:1B:00:FF");
    }
}
