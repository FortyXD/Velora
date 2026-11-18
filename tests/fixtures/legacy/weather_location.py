"""Return one GeoClue fix for the weather widget."""
import json
import signal


def main():
    # Bound the initial D-Bus activation as well as the wait for a position.
    signal.alarm(25)
    try:
        import gi
        gi.require_version("Geoclue", "2.0")
        from gi.repository import Geoclue, GLib
    except (ImportError, ValueError):
        return 1
    try:
        client = Geoclue.Simple.new_sync("org.quickshell", Geoclue.AccuracyLevel.EXACT, None)
        location = client.get_location()
    except GLib.Error:
        return 1
    if location is None:
        return 1
    print(json.dumps({"lat": location.props.latitude, "lon": location.props.longitude}, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
