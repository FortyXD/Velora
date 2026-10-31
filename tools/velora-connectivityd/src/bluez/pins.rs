//! Fixed PIN codes of old devices that can't show or take one, from the database bluedevil's wizard uses
//! (`/usr/share/bluedevilwizard/pin-code-database.xml`), if it's there. Matching goes in file order on type,
//! address prefix and name, so specific devices come first.

const DATABASE: &str = "/usr/share/bluedevilwizard/pin-code-database.xml";

fn attribute<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let needle = format!(" {name}=\"");
    let start = tag.find(&needle)? + needle.len();
    let end = tag[start..].find('"')? + start;
    Some(&tag[start..end])
}

/// The PIN from database text, without opening a file. `NULL` entries are devices with no PIN worth
/// entering, and `max:` ones can take any short PIN; neither names one to send.
pub fn lookup(database: &str, device_type: &str, address: &str, name: &str) -> Option<String> {
    let body = database.split("]>").nth(1).unwrap_or(database);
    for part in body.split("<device").skip(1) {
        // `<devices>` starts the same way
        if !part.starts_with(char::is_whitespace) {
            continue;
        }
        let Some(tag) = part.split("/>").next() else { continue };
        let tag = format!(" {tag}");
        let type_ok = attribute(&tag, "type").is_none_or(|wanted| wanted == "any" || wanted == device_type);
        let oui_ok = attribute(&tag, "oui").is_none_or(|prefix| address.to_uppercase().starts_with(&prefix.to_uppercase()));
        let name_ok = attribute(&tag, "name").is_none_or(|wanted| name.contains(wanted));
        if type_ok && oui_ok && name_ok {
            return attribute(&tag, "pin").filter(|pin| *pin != "NULL" && !pin.starts_with("max:")).map(str::to_string);
        }
    }
    None
}

pub fn known_pin(device_type: &str, address: &str, name: &str) -> Option<String> {
    lookup(&std::fs::read_to_string(DATABASE).ok()?, device_type, address, name)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"<?xml version="1.0"?>
<!DOCTYPE devices [ <!ELEMENT devices (device)+> ]>
<devices>
    <device oui="00:0E:6D:" name="Nokia" pin="1234"/>
    <device type="headset" name="Specific Headset" pin="9999"/>
    <device type="mouse" pin="NULL"/>
    <device type="keyboard" pin="max:6"/>
    <device type="headset" pin="0000"/>
</devices>"#;

    #[test]
    fn the_first_matching_entry_decides() {
        assert_eq!(lookup(SAMPLE, "phone", "00:0E:6D:11:22:33", "Nokia 3310").as_deref(), Some("1234"));
        assert_eq!(lookup(SAMPLE, "headset", "11:22:33:44:55:66", "Specific Headset").as_deref(), Some("9999"));
        assert_eq!(lookup(SAMPLE, "headset", "11:22:33:44:55:66", "Other").as_deref(), Some("0000"));
    }

    #[test]
    fn entries_without_a_usable_pin_or_without_a_match_give_none() {
        assert_eq!(lookup(SAMPLE, "mouse", "11:22:33:44:55:66", "Mouse"), None);
        assert_eq!(lookup(SAMPLE, "keyboard", "11:22:33:44:55:66", "Keyboard"), None);
        assert_eq!(lookup(SAMPLE, "phone", "11:22:33:44:55:66", "Phone"), None);
    }

    #[test]
    fn the_database_on_this_kind_of_system_reads_as_expected() {
        // Skipped where bluedevil isn't installed; the sample above covers the format
        if let Ok(text) = std::fs::read_to_string(DATABASE) {
            assert_eq!(lookup(&text, "mouse", "11:22:33:44:55:66", "Some mouse"), None);
            assert_eq!(lookup(&text, "headset", "11:22:33:44:55:66", "Some headset").as_deref(), Some("0000"));
        }
    }

    #[test]
    fn the_address_prefix_ignores_case() {
        assert_eq!(lookup(SAMPLE, "phone", "00:0e:6d:11:22:33", "Nokia").as_deref(), Some("1234"));
    }
}
