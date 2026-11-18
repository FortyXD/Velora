#include "windows.hpp"
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/window/WindowFullscreenPolicy.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <lua.hpp>
#include <filesystem>
#include <fstream>
#include <unistd.h>

namespace Velora {
HANDLE handle;
Json::Value settings(Json::objectValue);
static std::filesystem::path path;
static SP<CEventLoopTimer> saveTimer;
static std::vector<CHyprSignalListener> listeners;
struct Client {
    CHyprSignalListener state, traits;
};
static std::map<Desktop::View::CWindow *, Client> clients;

void save() {
    if (path.empty())
        return;
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    if (ec)
        return;
    auto temp = path.string() + ".XXXXXX";
    int fd = mkstemp(temp.data());
    if (fd < 0)
        return;
    Json::StreamWriterBuilder writer;
    writer["indentation"] = "";
    const std::string data = Json::writeString(writer, settings);
    size_t written = 0;
    while (written < data.size()) {
        auto count = write(fd, data.data() + written, data.size() - written);
        if (count <= 0)
            break;
        written += count;
    }
    const bool ok = close(fd) == 0 && written == data.size();
    if (!ok || rename(temp.c_str(), path.c_str()) != 0)
        unlink(temp.c_str());
}

void queueSave() {
    if (saveTimer)
        saveTimer->updateTimeout(std::chrono::milliseconds(350));
}

void maximize(PHLWINDOW w) {
    auto mode = Fullscreen::controller()->getFullscreenModes(w).internal == Fullscreen::FSMODE_MAXIMIZED
                    ? Fullscreen::FSMODE_NONE
                    : Fullscreen::FSMODE_MAXIMIZED;
    Fullscreen::controller()->setFullscreenMode(w, mode, mode, false);
}

wl_resource *toplevel(PHLWINDOW w) {
    if (w->backend().isX11() || !w->wlSurface() || !w->wlSurface()->resource())
        return nullptr;
    struct Lookup {
        PHLWINDOW w;
        wl_resource *found = nullptr;
    } result{w};
    wl_client_for_each_resource(
        w->wlSurface()->resource()->client(),
        [](wl_resource *r, void *ptr) {
            auto &lookup = *static_cast<Lookup *>(ptr);
            if (std::string_view(wl_resource_get_class(r)) == "xdg_toplevel") {
                auto top = CXDGToplevelResource::fromResource(r);
                if (top && top->m_window == lookup.w) {
                    lookup.found = r;
                    return WL_ITERATOR_STOP;
                }
            }
            return WL_ITERATOR_CONTINUE;
        },
        &result);
    return result.found;
}

static void advertise(PHLWINDOW w, bool minimize) {
    auto r = toplevel(w);
    if (!r || wl_resource_get_version(r) < 5)
        return;
    uint32_t caps[] = {XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN, XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE,
                       XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE};
    wl_array list{(minimize ? 3u : 2u) * sizeof(uint32_t), sizeof(caps), caps};
    static_cast<CXdgToplevel *>(wl_resource_get_user_data(r))->sendWmCapabilities(&list);
    if (auto owner = CXDGToplevelResource::fromResource(r)->m_owner.lock())
        owner->scheduleConfigure();
}

static void track(PHLWINDOW w) {
    if (!w || !w->mapped() || clients.contains(w.get()))
        return;
    auto weak = PHLWINDOWREF(w);
    clients[w.get()].state = w->backend().m_events.stateRequest.listen([weak](Desktop::View::SBackendStateRequest r) {
        auto w = weak.lock();
        if (!w || !w->mapped())
            return;
        if (r.minimized)
            Event::bus()->m_events.window.minimize.emit(w, *r.minimized);
        // The backend processes client state before this listener. Honor suppressed requests
        // and compositor-generated X11 echoes by checking the accepted client mode.
        if (r.maximized && !r.fullscreen && !w->fullscreenPolicy().requestSuppression().maximize) {
            auto fs = Fullscreen::controller()->getFullscreenModes(w);
            auto wanted = *r.maximized ? Fullscreen::FSMODE_MAXIMIZED : Fullscreen::FSMODE_NONE;
            if (fs.client == wanted && fs.internal != wanted && fs.internal != Fullscreen::FSMODE_FULLSCREEN)
                Fullscreen::controller()->setFullscreenMode(w, wanted, wanted, false);
        }
    });
    if (w->backend().isX11())
        clients[w.get()].traits = w->backend().m_events.traitsChanged.listen([weak](const auto &) {
            if (auto w = weak.lock())
                updateCaption(w);
        });
    advertise(w, true);
    updateCaption(w);
    trackCanvas(w);
}

static PHLWINDOW find(lua_State *L) {
    const char *address = luaL_checkstring(L, 1);
    for (auto &w : Desktop::windowState()->windows())
        if (w->mapped() && std::format("0x{:x}", reinterpret_cast<uintptr_t>(w.get())) == address)
            return w;
    return nullptr;
}

static void init(HANDLE h) {
    handle = h;
    if (auto s = getenv("XDG_STATE_HOME"); s && *s)
        path = s;
    else
        path = std::filesystem::path(getenv("HOME")) / ".local/state";
    path /= "velora/windows.json";
    std::ifstream file(path);
    Json::CharReaderBuilder reader;
    Json::Value parsed;
    std::string error;
    if (file && Json::parseFromStream(reader, file, &parsed, &error) && parsed.isObject())
        settings = std::move(parsed);
    for (auto key : {"cameras", "groups", "windows", "captions"})
        if (!settings[key].isObject())
            settings[key] = Json::Value(Json::objectValue);
    for (const auto &app : settings["windows"].getMemberNames())
        if (!settings["windows"][app].isArray())
            settings["windows"].removeMember(app);
    saveTimer = makeShared<CEventLoopTimer>(std::nullopt, [](SP<CEventLoopTimer>, void *) { save(); }, nullptr);
    g_pEventLoopManager->addTimer(saveTimer);
    auto api = [&](const char *name, PLUGIN_LUA_FN fn) {
        if (!HyprlandAPI::addLuaFunction(h, "velora", name, fn))
            throw std::runtime_error(std::string("Velora Lua binding: ") + name);
    };
    api("mode", [](lua_State *L) {
        changeMode(std::string_view(luaL_checkstring(L, 1)) == "canvas");
        return 0;
    });
    api("take_gesture", [](lua_State *L) {
        lua_pushboolean(L, takeCanvasGesture());
        return 1;
    });
    api("active", [](lua_State *L) {
        lua_pushboolean(L, canvas);
        return 1;
    });
    api("regular", [](lua_State *L) {
        auto w = find(L);
        if (!w) {
            lua_pushboolean(L, false);
            return 1;
        }
        auto traits = w->backend().traits();
        lua_pushboolean(L, !traits.transient && !traits.modal && !traits.suggestsFloat && !traits.overrideRedirect);
        return 1;
    });
    api("activate", [](lua_State *L) {
        lua_pushboolean(L, activate(find(L)));
        return 1;
    });
    api("desktop", [](lua_State *L) {
        lua_pushboolean(L, desktop());
        return 1;
    });
    api("camera", [](lua_State *L) {
        lua_pushboolean(L, navigate(luaL_checkstring(L, 1), luaL_optnumber(L, 2, 0), luaL_optnumber(L, 3, 0)));
        return 1;
    });
    api("geometry", [](lua_State *L) {
        auto b = worldGeometry(find(L));
        if (!b)
            return 0;
        lua_createtable(L, 0, 5);
        for (auto [key, value] : {std::pair{"x", b->x}, {"y", b->y}, {"w", b->w}, {"h", b->h}}) {
            lua_pushnumber(L, value);
            lua_setfield(L, -2, key);
        }
        lua_pushboolean(L, true);
        lua_setfield(L, -2, "world");
        return 1;
    });
    api("place", [](lua_State *L) {
        auto w = find(L);
        lua_pushboolean(L, placeOnCanvas(w,
                                         {luaL_checknumber(L, 2), luaL_checknumber(L, 3), luaL_checknumber(L, 4),
                                          luaL_checknumber(L, 5)},
                                         lua_toboolean(L, 6)));
        return 1;
    });
    api("caption", [](lua_State *L) {
        auto w = find(L);
        if (!w)
            return 0;
        auto &option = settings["captions"][w->metadata().appID()];
        auto mode = std::string_view(luaL_checkstring(L, 2));
        if (mode == "auto")
            option = Json::nullValue;
        else if (mode == "on" || mode == "off")
            option = mode == "on";
        for (auto &peer : Desktop::windowState()->windows())
            if (peer->mapped() && peer->metadata().appID() == w->metadata().appID())
                updateCaption(peer);
        queueSave();
        return 0;
    });
    installCanvas();
    installFramePreferences();
    auto &events = Event::bus()->m_events.window;
    listeners.emplace_back(events.openLate.listen(track));
    listeners.emplace_back(events.close.listen([](PHLWINDOW w) {
        forgetCanvas(w);
        forgetCaption(w);
        forgetFramePreference(w);
        clients.erase(w.get());
    }));
    listeners.emplace_back(events.class_.listen([](PHLWINDOW w) {
        if (w->mapped())
            updateCaption(w);
    }));
    for (const auto &w : Desktop::windowState()->windows())
        track(w);
}
} // namespace Velora

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string_view(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Velora Windows: rebuild for this Hyprland ABI");
    Velora::init(handle);
    return {"velora-windows", "Free windows and a shared infinite canvas", "Velora", "1.0"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    using namespace Velora;
    stopFramePreferences();
    stopCanvas();
    for (auto &w : Desktop::windowState()->windows())
        if (clients.contains(w.get())) {
            advertise(w, false);
            forgetCaption(w);
        }
    listeners.clear();
    clients.clear();
    save();
    if (saveTimer)
        g_pEventLoopManager->removeTimer(saveTimer);
    saveTimer.reset();
}
