pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

import qs.modules.common
import qs.modules.common.functions

/**
 * Current weather and a short forecast.
 * Where: GPS (GeoClue) when "automatic", else the city from the settings. When GPS gives nothing: the last place
 * GPS found, then the city, then a guess from the IP address. The place is always shown, so a wrong guess is seen.
 * Data: met.no, Open-Meteo or wttr.in, starting with the one that answered last time (some networks block or
 * throttle one of them). Failed fetches are retried after 30 s, 2 and 5 minutes.
 * Only the shell (load() in shell.qml) fetches; other processes, like the settings app, read the cache file it writes.
 */
Singleton {
    id: root

    readonly property var options: Config.options.bar.weather
    readonly property int fetchInterval: Math.max(5, root.options.fetchInterval) * 60 * 1000
    readonly property string city: root.options.city.trim()
    readonly property bool automatic: root.options.enableGPS
    readonly property bool useUSCS: root.options.useUSCS
    // Something shows the weather; nothing is fetched otherwise
    readonly property bool wanted: root.options.enable || Config.options.background.widgets.weather.enable || LockLayout.items.weather.show

    property string status: "loading" // "loading", "ready", "error"
    property string error: ""
    property bool busy: false
    property var place: ({ "lat": 0, "lon": 0, "name": "", "source": "", "time": 0 }) // source: gps, saved, city, ip
    property var lastGps: null // { lat, lon, name, time } of the last GPS fix
    property var geocoded: null // { query, lat, lon, name } for the city in the settings
    property string provider: "" // The service that answered last
    property real updatedAt: 0
    property var hourly: [] // { time, temp, code, night }, the next hours
    property var daily: [] // { day, high, low, code }, 3 days
    property var data: root.emptyData()

    readonly property bool hasData: root.updatedAt > 0
    readonly property string sourceText: ({
        "gps": Translation.tr("by GPS"),
        "saved": Translation.tr("last place found by GPS"),
        "city": Translation.tr("your city"),
        "ip": Translation.tr("by IP address")
    })[root.place.source] ?? ""

    function emptyData() {
        return {
            "uv": 0, "humidity": "", "sunrise": "", "sunset": "", "windDir": "", "wCode": "116", "city": "",
            "wind": "", "precip": "", "visib": "", "press": "", "temp": "--", "tempFeelsLike": "--",
            "tempShort": "--°", "description": "", "night": false, "lastRefresh": ""
        };
    }

    // ---- Main shell only ----

    property bool loaded: false
    property int retryStep: 0
    readonly property list<int> retryDelays: [30000, 120000, 300000]
    readonly property list<string> providers: ["met.no", "Open-Meteo", "wttr.in"]

    function load() {
        if (root.loaded) return;
        root.loaded = true;
        cacheFile.reload();
    }

    function getData() { // Kept for older callers
        root.refresh();
    }

    function refresh() {
        if (!root.loaded) {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "weather", "refresh"]);
            return;
        }
        if (root.busy) return;
        root.busy = true;
        if (!root.hasData) root.status = "loading";
        root.findPlace();
    }

    onWantedChanged: if (root.loaded && root.wanted && !root.busy) root.refresh()
    onUseUSCSChanged: if (root.loaded) refetchTimer.restart()
    onCityChanged: if (root.loaded) refetchTimer.restart()
    onAutomaticChanged: if (root.loaded) refetchTimer.restart()

    Timer {
        id: refetchTimer
        interval: 1500 // Typing a city changes it on every key
        onTriggered: {
            if (root.busy) refetchTimer.restart();
            else root.refresh();
        }
    }

    // Steady refresh; after a failure the retries come first
    Timer {
        id: refreshTimer
        running: root.loaded && root.wanted && !root.busy && !retryTimer.running
        repeat: true
        interval: root.fetchInterval
        onTriggered: root.refresh()
    }
    Timer {
        id: retryTimer
        onTriggered: root.refresh()
    }
    Timer { // A request that never ends doesn't block the next ones
        running: root.busy
        interval: 120000
        onTriggered: root.failed(Translation.tr("The weather services didn't answer"))
    }

    // 1. Where
    function findPlace() {
        if (!root.automatic && root.city.length > 0) {
            root.useCity(() => root.failed(Translation.tr("Couldn't find “%1”").arg(root.city)));
            return;
        }
        const gpsFresh = root.lastGps && Date.now() - root.lastGps.time < 30 * 60 * 1000;
        if (root.automatic && positionSource.valid && !gpsFresh) {
            gps.ask();
            return;
        }
        root.placeWithoutGps();
    }

    function placeWithoutGps() {
        if (root.automatic && root.lastGps) {
            const fresh = Date.now() - root.lastGps.time < 30 * 60 * 1000;
            root.setPlace(root.lastGps.lat, root.lastGps.lon, root.lastGps.name, fresh ? "gps" : "saved");
            return;
        }
        if (root.city.length > 0) {
            root.useCity(() => root.useIp());
            return;
        }
        root.useIp();
    }

    function useCity(onFail) {
        if (root.geocoded && root.geocoded.query === root.city) {
            root.setPlace(root.geocoded.lat, root.geocoded.lon, root.geocoded.name, "city");
            return;
        }
        geocodeRequest.get(`https://geocoding-api.open-meteo.com/v1/search?count=1&language=${root.language()}&name=${encodeURIComponent(root.city)}`, json => {
            const found = json?.results?.[0];
            if (!found) {
                onFail();
                return;
            }
            root.geocoded = { "query": root.city, "lat": found.latitude, "lon": found.longitude, "name": found.name };
            root.setPlace(found.latitude, found.longitude, found.name, "city");
        });
    }

    function useIp() {
        ipRequest.get("https://ipinfo.io/json", json => {
            const loc = (json?.loc ?? "").split(",").map(Number);
            if (loc.length === 2 && !isNaN(loc[0])) {
                root.setPlace(loc[0], loc[1], json.city ?? "", "ip");
            } else {
                root.place = { "lat": 0, "lon": 0, "name": "", "source": "ip", "time": Date.now() };
                root.fetchWttr("", () => root.failed(Translation.tr("No connection to the weather services")));
            }
        });
    }

    function setPlace(lat, lon, name, source) {
        root.place = { "lat": lat, "lon": lon, "name": name, "source": source, "time": Date.now() };
        if (name.length > 0) {
            root.fetchForecast();
            return;
        }
        reverseRequest.get(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&lat=${lat}&lon=${lon}&accept-language=${root.language()}`, json => {
            const address = json?.address ?? {};
            const found = address.city ?? address.town ?? address.village ?? address.municipality ?? address.county ?? json?.name ?? "";
            root.place = Object.assign({}, root.place, { "name": found });
            if (root.place.source === "gps" && root.lastGps) root.lastGps = Object.assign({}, root.lastGps, { "name": found });
            root.fetchForecast();
        });
    }

    // 2. The weather there, from the first service that answers
    function fetchForecast() {
        const preferred = root.providers.includes(root.provider) ? [root.provider] : [];
        root.tryProviders([...preferred, ...root.providers.filter(p => p !== root.provider)], 0);
    }

    function tryProviders(order, index) {
        if (index >= order.length) {
            root.failed(Translation.tr("The weather services didn't answer"));
            return;
        }
        const next = () => root.tryProviders(order, index + 1);
        const p = root.place;
        const where = `${p.lat.toFixed(4)},${p.lon.toFixed(4)}`;
        if (order[index] === "met.no") root.fetchMetNo(next);
        else if (order[index] === "Open-Meteo") root.fetchOpenMeteo(next);
        else root.fetchWttr(where, next);
    }

    function fetchMetNo(onFail) {
        const p = root.place;
        metNoRequest.get(`https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=${p.lat.toFixed(4)}&lon=${p.lon.toFixed(4)}`, json => {
            if (!json?.properties?.timeseries?.length) {
                onFail();
                return;
            }
            root.readMetNo(json);
            root.succeeded("met.no");
        });
    }

    function fetchOpenMeteo(onFail) {
        const p = root.place;
        const units = root.useUSCS ? "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch" : "";
        openMeteoRequest.get("https://api.open-meteo.com/v1/forecast"
            + `?latitude=${p.lat.toFixed(4)}&longitude=${p.lon.toFixed(4)}&timezone=auto&forecast_days=3${units}`
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure,precipitation,uv_index,visibility,is_day"
            + "&hourly=temperature_2m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset", json => {
            if (!json?.current) {
                onFail();
                return;
            }
            root.readOpenMeteo(json);
            root.succeeded("Open-Meteo");
        });
    }

    // wttr.in's full answer is large and some networks throttle it, so only the current weather in one short line
    function fetchWttr(where, onFail) {
        wttrRequest.get(`https://wttr.in/${where}?format=%t|%f|%h|%w|%p|%P|%u|%S|%s|%C|%l&${root.useUSCS ? "u" : "m"}`, text => {
            const fields = (text ?? "").trim().split("|");
            if (fields.length < 11 || !/\d/.test(fields[0])) {
                onFail();
                return;
            }
            root.readWttr(fields);
            root.succeeded("wttr.in");
        });
    }

    function succeeded(provider) {
        root.provider = provider;
        root.updatedAt = Date.now();
        root.status = "ready";
        root.error = "";
        root.retryStep = 0;
        retryTimer.stop();
        root.busy = false;
        root.save();
    }

    function failed(message) {
        console.warn("[Weather]", message);
        root.error = message;
        root.status = "error";
        if (root.retryStep < root.retryDelays.length) {
            retryTimer.interval = root.retryDelays[root.retryStep];
            root.retryStep++;
            retryTimer.restart();
        }
        root.busy = false;
        root.save();
    }

    // ---- Reading the answers ----

    function language() {
        return Translation.languageCode.split(/[_-]/)[0] || "en";
    }

    function formatTemp(value) {
        return `${Math.round(value)}°`;
    }

    function formatClock(date) {
        return Qt.locale().toString(date, Config.options.time.format);
    }

    function dayName(date, index) {
        if (index === 0) return Translation.tr("Today");
        return Qt.locale().dayName(date.getDay(), Locale.ShortFormat);
    }

    function compass(degrees) {
        return ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"][Math.round(degrees / 22.5) % 16];
    }

    function toF(celsius) {
        return celsius * 9 / 5 + 32;
    }

    // The icons and texts are keyed by wttr.in's condition codes; Open-Meteo answers in WMO codes
    function codeFromWmo(wmo) {
        const map = {
            "0": 113, "1": 116, "2": 116, "3": 122, "45": 248, "48": 260,
            "51": 266, "53": 266, "55": 266, "56": 281, "57": 284,
            "61": 296, "63": 299, "65": 305, "66": 311, "67": 314,
            "71": 326, "73": 332, "75": 338, "77": 335,
            "80": 353, "81": 356, "82": 356, "85": 368, "86": 371,
            "95": 389, "96": 389, "99": 389
        };
        return String(map[String(wmo)] ?? 116);
    }

    // met.no symbols, like "lightrainshowers_day"
    function codeFromSymbol(symbol) {
        const s = (symbol ?? "").replace(/_(day|night|polartwilight)$/, "");
        if (s.includes("thunder")) return "389";
        if (s.includes("snow")) return s.startsWith("heavy") ? "338" : s.startsWith("light") ? "326" : (s.includes("showers") ? "371" : "332");
        if (s.includes("sleet")) return "317";
        if (s.includes("rain")) return s.startsWith("heavy") ? "305" : s.startsWith("light") ? (s.includes("showers") ? "353" : "296") : (s.includes("showers") ? "356" : "299");
        return ({ "clearsky": "113", "fair": "116", "partlycloudy": "116", "cloudy": "122", "fog": "248" })[s] ?? "116";
    }

    // wttr.in's condition text, like "Light rain shower"
    function codeFromText(text) {
        const t = (text ?? "").toLowerCase();
        if (t.includes("thunder")) return "389";
        if (t.includes("snow") || t.includes("blizzard")) return t.includes("heavy") ? "338" : "326";
        if (t.includes("sleet") || t.includes("ice")) return "317";
        if (t.includes("drizzle")) return "266";
        if (t.includes("rain") || t.includes("shower")) return t.includes("heavy") || t.includes("torrential") ? "305" : t.includes("light") || t.includes("patchy") ? "296" : "299";
        if (t.includes("fog") || t.includes("mist")) return "248";
        if (t.includes("overcast") || t === "cloudy") return "122";
        if (t.includes("cloud")) return "116";
        return t.includes("clear") || t.includes("sunny") ? "113" : "116";
    }

    function describe(code) {
        const c = Number(code);
        if (c === 113) return Translation.tr("Clear");
        if (c === 116) return Translation.tr("Partly cloudy");
        if (c === 119 || c === 122) return Translation.tr("Cloudy");
        if ([143, 248, 260].includes(c)) return Translation.tr("Fog");
        if ([200, 386, 389, 392, 395].includes(c)) return Translation.tr("Thunderstorm");
        if ([179, 227, 230, 320, 323, 326, 329, 332, 335, 338, 350, 368, 371, 374, 377].includes(c)) return Translation.tr("Snow");
        if ([182, 185, 281, 284, 311, 314, 317].includes(c)) return Translation.tr("Sleet");
        if ([263, 266].includes(c)) return Translation.tr("Drizzle");
        return Translation.tr("Rain");
    }

    // Sunrise and sunset for a day at a place (the usual solar position formulas, as in SunCalc)
    function sunTimes(date, lat, lon) {
        const rad = Math.PI / 180;
        const dayMs = 86400000;
        const J1970 = 2440588;
        const J2000 = 2451545;
        const J0 = 0.0009;
        const e = rad * 23.4397;
        const lw = rad * -lon;
        const phi = rad * lat;
        const d = date.valueOf() / dayMs - 0.5 + J1970 - J2000;
        const n = Math.round(d - J0 - lw / (2 * Math.PI));
        const ds = J0 + lw / (2 * Math.PI) + n;
        const M = rad * (357.5291 + 0.98560028 * ds);
        const L = M + rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M)) + rad * 102.9372 + Math.PI;
        const dec = Math.asin(Math.sin(e) * Math.sin(L));
        const noon = J2000 + ds + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
        const cosW = (Math.sin(-0.833 * rad) - Math.sin(phi) * Math.sin(dec)) / (Math.cos(phi) * Math.cos(dec));
        if (cosW < -1 || cosW > 1) return null; // Polar day or night
        const w = Math.acos(cosW);
        const set = J2000 + J0 + (w + lw) / (2 * Math.PI) + n + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
        const rise = noon - (set - noon);
        const toDate = j => new Date((j + 0.5 - J1970) * dayMs);
        return { "rise": toDate(rise), "set": toDate(set) };
    }

    function isNight(date) {
        const sun = root.sunTimes(new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12), root.place.lat, root.place.lon);
        if (!sun) return false;
        return date < sun.rise || date > sun.set;
    }

    function setSun(current) {
        const sun = root.place.source.length > 0 && (root.place.lat !== 0 || root.place.lon !== 0)
            ? root.sunTimes(new Date(new Date().setHours(12, 0, 0, 0)), root.place.lat, root.place.lon) : null;
        if (!current.sunrise) current.sunrise = sun ? root.formatClock(sun.rise) : "";
        if (!current.sunset) current.sunset = sun ? root.formatClock(sun.set) : "";
    }

    function finishCurrent(current) {
        current.description = root.describe(current.wCode);
        current.city = root.place.name || current.city || "";
        current.lastRefresh = `${DateTime.time} • ${DateTime.date}`;
        root.setSun(current);
        root.data = current;
    }

    function readMetNo(json) {
        const series = json.properties.timeseries;
        const u = root.useUSCS;
        const temp = value => u ? root.toF(value) : value;
        const now = Date.now();
        // The entry for the current hour
        let first = series.findIndex(entry => new Date(entry.time).valueOf() + 3600000 > now);
        if (first < 0) first = 0;
        const c = series[first].data.instant.details;
        const next = series[first].data.next_1_hours ?? series[first].data.next_6_hours;
        const windKmh = c.wind_speed * 3.6;
        root.finishCurrent({
            "uv": Math.round(c.ultraviolet_index_clear_sky ?? 0),
            "humidity": `${Math.round(c.relative_humidity)}%`,
            "windDir": root.compass(c.wind_from_direction ?? 0),
            "wCode": root.codeFromSymbol(next?.summary?.symbol_code),
            "wind": u ? `${Math.round(windKmh / 1.609)} mph` : `${Math.round(windKmh)} km/h`,
            "precip": u ? `${((next?.details?.precipitation_amount ?? 0) / 25.4).toFixed(2)} in` : `${next?.details?.precipitation_amount ?? 0} mm`,
            "visib": "",
            "press": u ? `${(c.air_pressure_at_sea_level * 0.02953).toFixed(2)} inHg` : `${Math.round(c.air_pressure_at_sea_level)} hPa`,
            "temp": `${Math.round(temp(c.air_temperature))}°${u ? "F" : "C"}`,
            "tempFeelsLike": `${Math.round(temp(c.apparent_air_temperature ?? c.air_temperature))}°${u ? "F" : "C"}`,
            "tempShort": root.formatTemp(temp(c.air_temperature)),
            "night": root.isNight(new Date())
        });

        let hours = [];
        for (let i = first; i < series.length && hours.length < 24; i++) {
            const date = new Date(series[i].time);
            const symbol = series[i].data.next_1_hours?.summary?.symbol_code;
            if (!symbol) break; // Past the hourly part of the forecast
            hours.push({ "time": root.formatClock(date), "temp": root.formatTemp(temp(series[i].data.instant.details.air_temperature)),
                "code": root.codeFromSymbol(symbol), "night": symbol.endsWith("_night") || (!symbol.endsWith("_day") && root.isNight(date)) });
        }
        root.hourly = hours;

        // Days from the local dates of the entries; the symbol is the one for the day's middle
        let days = [];
        for (const entry of series) {
            const date = new Date(entry.time);
            const key = date.toDateString();
            let day = days.find(d => d.key === key);
            if (!day) {
                if (days.length === 3) break;
                day = { "key": key, "date": date, "high": -999, "low": 999, "code": "", "noonDistance": 99 };
                days.push(day);
            }
            const t = entry.data.instant.details.air_temperature;
            day.high = Math.max(day.high, t);
            day.low = Math.min(day.low, t);
            const symbol = entry.data.next_6_hours?.summary?.symbol_code ?? entry.data.next_1_hours?.summary?.symbol_code;
            const distance = Math.abs(date.getHours() - 12);
            if (symbol && distance < day.noonDistance) {
                day.code = root.codeFromSymbol(symbol);
                day.noonDistance = distance;
            }
        }
        root.daily = days.map((d, i) => ({ "day": root.dayName(d.date, i), "high": root.formatTemp(temp(d.high)), "low": root.formatTemp(temp(d.low)), "code": d.code || "116" }));
    }

    function readOpenMeteo(json) {
        const c = json.current;
        const u = root.useUSCS;
        const today = json.daily;
        root.finishCurrent({
            "uv": Math.round(c.uv_index ?? 0),
            "humidity": `${c.relative_humidity_2m}%`,
            "sunrise": today?.sunrise?.[0] ? root.formatClock(new Date(today.sunrise[0])) : "",
            "sunset": today?.sunset?.[0] ? root.formatClock(new Date(today.sunset[0])) : "",
            "windDir": root.compass(c.wind_direction_10m ?? 0),
            "wCode": root.codeFromWmo(c.weather_code),
            "wind": `${Math.round(c.wind_speed_10m)} ${u ? "mph" : "km/h"}`,
            "precip": `${c.precipitation} ${u ? "in" : "mm"}`,
            "visib": u ? `${Math.round(c.visibility / 1609)} mi` : `${Math.round(c.visibility / 1000)} km`,
            "press": u ? `${(c.surface_pressure * 0.02953).toFixed(2)} inHg` : `${Math.round(c.surface_pressure)} hPa`,
            "temp": `${Math.round(c.temperature_2m)}°${u ? "F" : "C"}`,
            "tempFeelsLike": `${Math.round(c.apparent_temperature)}°${u ? "F" : "C"}`,
            "tempShort": root.formatTemp(c.temperature_2m),
            "night": c.is_day === 0
        });

        // The next 24 hours, from the current one
        const h = json.hourly;
        const start = Math.max(0, h.time.findIndex(t => t >= c.time.slice(0, 13)));
        let hours = [];
        for (let i = start; i < Math.min(h.time.length, start + 24); i++) {
            hours.push({ "time": root.formatClock(new Date(h.time[i])), "temp": root.formatTemp(h.temperature_2m[i]),
                "code": root.codeFromWmo(h.weather_code[i]), "night": h.is_day[i] === 0 });
        }
        root.hourly = hours;

        let days = [];
        for (let i = 0; i < (today?.time?.length ?? 0); i++) {
            days.push({ "day": root.dayName(new Date(today.time[i]), i), "high": root.formatTemp(today.temperature_2m_max[i]),
                "low": root.formatTemp(today.temperature_2m_min[i]), "code": root.codeFromWmo(today.weather_code[i]) });
        }
        root.daily = days;
    }

    // Fields of the short format: temp|feels like|humidity|wind|precipitation|pressure|UV|sunrise|sunset|condition|place
    function readWttr(fields) {
        const number = text => (text.match(/-?\d+(\.\d+)?/) ?? ["0"])[0];
        const u = root.useUSCS;
        const arrows = { "↓": "N", "↙": "NE", "←": "E", "↖": "SE", "↑": "S", "↗": "SW", "→": "W", "↘": "NW" }; // Arrows point where the wind blows
        const where = fields[10].trim();
        if (root.place.name.length === 0 && !/^-?\d/.test(where)) {
            root.place = Object.assign({}, root.place, { "name": where.split(",")[0] });
        }
        const code = root.codeFromText(fields[9].trim());
        root.finishCurrent({
            "uv": Number(number(fields[6])),
            "humidity": fields[2].trim(),
            "sunrise": root.formatClock(new Date(`2000-01-01T${fields[7].trim()}`)),
            "sunset": root.formatClock(new Date(`2000-01-01T${fields[8].trim()}`)),
            "windDir": arrows[fields[3].trim().charAt(0)] ?? "",
            "wCode": code,
            "wind": `${number(fields[3])} ${u ? "mph" : "km/h"}`,
            "precip": `${number(fields[4])} ${u ? "in" : "mm"}`,
            "visib": "",
            "press": `${number(fields[5])} hPa`,
            "temp": `${Number(number(fields[0]))}°${u ? "F" : "C"}`,
            "tempFeelsLike": `${Number(number(fields[1]))}°${u ? "F" : "C"}`,
            "tempShort": `${Number(number(fields[0]))}°`,
            "night": root.place.source.length > 0 && root.place.lat !== 0 ? root.isNight(new Date()) : false
        });
        root.hourly = [];
        root.daily = [];
    }

    // ---- Requests ----

    component Request: Process {
        id: request
        property var callback: null
        property int timeout: 15
        property bool json: true
        function get(url, callback) {
            request.callback = callback;
            request.command = ["curl", "-sSfL", "-m", String(request.timeout), "-A", "Folis-shell/1.0 (weather widget)", url];
            request.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let result = text;
                if (request.json) {
                    try {
                        result = text.length > 0 ? JSON.parse(text) : null;
                    } catch (e) {
                        result = null;
                    }
                }
                const callback = request.callback;
                request.callback = null;
                if (callback) callback(result);
            }
        }
    }
    Request { id: geocodeRequest }
    Request { id: ipRequest; timeout: 8 }
    Request { id: reverseRequest; timeout: 8 }
    Request { id: metNoRequest } // One per service: a request isn't reused before its process has ended
    Request { id: openMeteoRequest }
    Request { id: wttrRequest; json: false }

    // GPS: one fix per ask, given up after 25 s
    QtObject {
        id: gps
        property bool waiting: false
        property bool agentStarted: false
        function ask() {
            gps.waiting = true;
            if (!gps.agentStarted) {
                // The GeoClue agent is only needed for this, so it's started here instead of at login
                gps.agentStarted = true;
                Quickshell.execDetached(["bash", "-c", "~/.config/hypr/hyprland/scripts/start_geoclue_agent.sh"]);
                agentWait.restart();
                return;
            }
            positionSource.update(25000);
            gpsTimeout.restart();
        }
        function done(ok) {
            if (!gps.waiting) return;
            gps.waiting = false;
            gpsTimeout.stop();
            if (ok) {
                const c = positionSource.position.coordinate;
                const moved = !root.lastGps || Math.abs(root.lastGps.lat - c.latitude) + Math.abs(root.lastGps.lon - c.longitude) > 0.05;
                root.lastGps = { "lat": c.latitude, "lon": c.longitude, "name": moved ? "" : root.lastGps.name, "time": Date.now() };
                root.setPlace(c.latitude, c.longitude, root.lastGps.name, "gps");
            } else {
                root.placeWithoutGps();
            }
        }
    }
    Timer {
        id: agentWait
        interval: 2000
        onTriggered: gps.ask()
    }
    Timer {
        id: gpsTimeout
        interval: 27000
        onTriggered: gps.done(false)
    }
    PositionSource {
        id: positionSource
        active: false
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) gps.done(true);
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) gps.done(false);
        }
    }

    // ---- Cache, shared with the settings app ----

    function save() {
        cacheFile.setText(JSON.stringify({
            "version": 1, "place": root.place, "lastGps": root.lastGps, "geocoded": root.geocoded, "provider": root.provider,
            "updatedAt": root.updatedAt, "status": root.status, "error": root.error, "units": root.useUSCS ? "us" : "metric",
            "data": root.data, "hourly": root.hourly, "daily": root.daily
        }, null, 2));
    }

    function restore(text) {
        let cache = null;
        try {
            cache = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!cache || cache.version !== 1) return;
        root.lastGps = cache.lastGps ?? null;
        root.geocoded = cache.geocoded ?? null;
        root.provider = cache.provider ?? "";
        if (cache.place) root.place = cache.place;
        const sameUnits = cache.units === (root.useUSCS ? "us" : "metric");
        if (sameUnits && cache.data && cache.updatedAt > 0) {
            root.data = cache.data;
            root.hourly = cache.hourly ?? [];
            root.daily = cache.daily ?? [];
            root.updatedAt = cache.updatedAt;
        }
        if (!root.loaded) {
            root.status = cache.status ?? "loading";
            root.error = cache.error ?? "";
        } else if (root.hasData) {
            root.status = "ready";
        }
    }

    property bool cacheRead: false
    FileView {
        id: cacheFile
        path: `${FileUtils.trimFileProtocol(Directories.state)}/user/weather.json`
        watchChanges: !root.loaded // The settings app follows what the shell writes
        onFileChanged: cacheFile.reload()
        onLoaded: {
            if (root.loaded && root.cacheRead) return; // The shell only reads it once, at start
            root.restore(cacheFile.text());
            if (!root.loaded) return;
            root.cacheRead = true;
            // Fresh enough data is shown at once; the next fetch comes on schedule
            if (root.wanted && (!root.hasData || Date.now() - root.updatedAt > root.fetchInterval)) root.refresh();
        }
        onLoadFailed: error => {
            if (!root.loaded || root.cacheRead) return;
            root.cacheRead = true;
            if (root.wanted) root.refresh();
        }
    }

    IpcHandler {
        target: "weather"
        function refresh(): void {
            root.retryStep = 0;
            retryTimer.stop();
            root.refresh();
        }
        function status(): string {
            return `${root.status} ${root.data.temp} ${root.place.name} (${root.place.source}, ${root.provider}) ${root.error}`;
        }
    }
}
