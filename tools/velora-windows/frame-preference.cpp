#include "windows.hpp"
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <kde-server-decoration.hpp>
#include <xdg-decoration-unstable-v1.hpp>
// Hyprland 0.57 stores the requested modes but has no public decoration lookup.
#define private public
#include <hyprland/src/protocols/XDGDecoration.hpp>
#include <hyprland/src/protocols/ServerDecorationKDE.hpp>
#undef private
#include <xcb/xcb.h>

namespace Velora {
wl_resource *toplevel(PHLWINDOW w);

namespace {
wl_protocol_logger *decorationRequests = nullptr;
wl_event_source *pendingUpdate = nullptr, *xEvents = nullptr;
xcb_connection_t *xConnection = nullptr;
xcb_atom_t motifHints = XCB_ATOM_NONE, gtkExtents = XCB_ATOM_NONE;
struct XFrame {
    PHLWINDOWREF window;
    bool titled = true;
};
std::map<xcb_window_t, XFrame> xWindows;

void flushWaylandUpdates(void *) {
    pendingUpdate = nullptr;
    for (const auto &w : Desktop::windowState()->windows())
        if (!w->backend().isX11())
            updateCaption(w);
}

void observeDecoration(void *, wl_protocol_logger_type direction, const wl_protocol_logger_message *msg) {
    if (direction != WL_PROTOCOL_LOGGER_REQUEST)
        return;
    const std::string_view type = wl_resource_get_class(msg->resource);
    if (type != "zxdg_toplevel_decoration_v1" && type != "zxdg_decoration_manager_v1" &&
        type != "org_kde_kwin_server_decoration" && type != "org_kde_kwin_server_decoration_manager")
        return;
    // After four requests Hyprland stops recording legacy KDE preferences.
    if (type == "org_kde_kwin_server_decoration" && std::string_view(msg->message->name) == "request_mode" &&
        PROTO::serverDecorationKDE && msg->arguments[0].u <= ORG_KDE_KWIN_SERVER_DECORATION_MODE_SERVER)
        for (const auto &deco : PROTO::serverDecorationKDE->m_decos)
            if (deco->m_resource->resource() == msg->resource && deco->m_requestsSent > 3)
                deco->m_mostRecentlyRequested = msg->arguments[0].u;
    if (!pendingUpdate)
        pendingUpdate = wl_event_loop_add_idle(g_pCompositor->m_wlEventLoop, flushWaylandUpdates, nullptr);
}

// XWayland's window type alone doesn't say whether a normal window draws a header.
// Only read properties on map and on relevant PropertyNotify events.
template <class T> auto xReply(T *reply) {
    return std::unique_ptr<T, decltype(&std::free)>(reply, std::free);
}

bool xWantsTitle(xcb_window_t id) {
    const auto motif = xcb_get_property(xConnection, false, id, motifHints, XCB_GET_PROPERTY_TYPE_ANY, 0, 5);
    const auto gtk = xcb_get_property(xConnection, false, id, gtkExtents, XCB_ATOM_CARDINAL, 0, 4);
    auto hints = xReply(xcb_get_property_reply(xConnection, motif, nullptr));
    auto extents = xReply(xcb_get_property_reply(xConnection, gtk, nullptr));
    if (extents && extents->format == 32 && xcb_get_property_value_length(extents.get()) == 16)
        return false;
    if (!hints || hints->format != 32 || xcb_get_property_value_length(hints.get()) < 12)
        return true;
    const auto fields = static_cast<const uint32_t *>(xcb_get_property_value(hints.get()));
    constexpr uint32_t decorationsFlag = 1u << 1, all = 1u, title = 1u << 3;
    if (!(fields[0] & decorationsFlag))
        return true;
    return (fields[2] & all) ? !(fields[2] & title) : (fields[2] & title);
}

void closeXConnection() {
    if (xEvents)
        wl_event_source_remove(std::exchange(xEvents, nullptr));
    if (xConnection)
        xcb_disconnect(std::exchange(xConnection, nullptr));
    xWindows.clear();
}
int receiveXEvents(int, uint32_t mask, void *) {
    if (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR)) {
        closeXConnection();
        return 0;
    }
    while (auto event = xReply(xcb_poll_for_event(xConnection))) {
        if ((event->response_type & 0x7f) != XCB_PROPERTY_NOTIFY)
            continue;
        auto prop = reinterpret_cast<xcb_property_notify_event_t *>(event.get());
        if (prop->atom != motifHints && prop->atom != gtkExtents)
            continue;
        auto it = xWindows.find(prop->window);
        if (it != xWindows.end())
            if (auto w = it->second.window.lock()) {
                it->second.titled = xWantsTitle(prop->window);
                updateCaption(w);
            }
    }
    return 0;
}

bool xFrame(PHLWINDOW w) {
    if (!xConnection) {
        xConnection = xcb_connect(nullptr, nullptr);
        if (xcb_connection_has_error(xConnection)) {
            closeXConnection();
            return false;
        }
        auto atom = [](std::string_view name) -> xcb_atom_t {
            auto cookie = xcb_intern_atom(xConnection, false, name.size(), name.data());
            auto reply = xReply(xcb_intern_atom_reply(xConnection, cookie, nullptr));
            return reply ? reply->atom : XCB_ATOM_NONE;
        };
        motifHints = atom("_MOTIF_WM_HINTS");
        gtkExtents = atom("_GTK_FRAME_EXTENTS");
        xEvents = wl_event_loop_add_fd(g_pCompositor->m_wlEventLoop, xcb_get_file_descriptor(xConnection),
                                       WL_EVENT_READABLE, receiveXEvents, nullptr);
    }
    const auto id = static_cast<xcb_window_t>(w->backend().clientID().id);
    auto [it, inserted] = xWindows.try_emplace(id);
    if (inserted) {
        const uint32_t mask = XCB_EVENT_MASK_PROPERTY_CHANGE;
        xcb_change_window_attributes(xConnection, id, XCB_CW_EVENT_MASK, &mask);
        it->second = {w, xWantsTitle(id)};
        // Synchronous replies may already have pulled PropertyNotify into XCB's queue.
        if (xEvents)
            wl_event_source_check(xEvents);
    }
    return it->second.titled && !w->backend().traits().suggestsNoBorder;
}
}

void installFramePreferences() {
    decorationRequests = wl_display_add_protocol_logger(g_pCompositor->m_wlDisplay, observeDecoration, nullptr);
}
void forgetFramePreference(PHLWINDOW w) {
    if (w->backend().isX11() && xConnection) {
        const auto id = static_cast<xcb_window_t>(w->backend().clientID().id);
        xWindows.erase(id);
    }
}
void stopFramePreferences() {
    if (decorationRequests)
        wl_protocol_logger_destroy(std::exchange(decorationRequests, nullptr));
    if (pendingUpdate)
        wl_event_source_remove(std::exchange(pendingUpdate, nullptr));
    closeXConnection();
}

bool systemFrame(PHLWINDOW w, std::optional<bool> override) {
    if (w->backend().isX11())
        return override.value_or(xFrame(w));

    // Without a decoration protocol object this Wayland surface owns its frame.
    if (auto r = toplevel(w); r && PROTO::xdgDecoration) {
        auto it = PROTO::xdgDecoration->m_decorations.find(r);
        if (it != PROTO::xdgDecoration->m_decorations.end()) {
            auto &deco = *it->second;
            const bool wantsServer = deco.mostRecentlyRequested != ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
            const bool show = override.value_or(wantsServer);
            const auto mode = show ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
            if (deco.mostRecentlySent != mode) {
                deco.mostRecentlySent = mode;
                deco.m_resource->sendConfigure(mode);
                if (auto owner = CXDGToplevelResource::fromResource(r)->m_owner.lock(); owner && !owner->m_initialCommit)
                    owner->scheduleConfigure();
            }
            return show;
        }
    }
    if (w->wlSurface() && PROTO::serverDecorationKDE) {
        const auto surface = w->wlSurface()->resource();
        for (const auto &deco : PROTO::serverDecorationKDE->m_decos) {
            if (deco->m_surf != surface)
                continue;
            auto mode = deco->m_requestsSent ? deco->m_mostRecentlyRequested : uint32_t(ORG_KDE_KWIN_SERVER_DECORATION_MODE_SERVER);
            if (override)
                mode = *override ? ORG_KDE_KWIN_SERVER_DECORATION_MODE_SERVER : ORG_KDE_KWIN_SERVER_DECORATION_MODE_CLIENT;
            if (deco->m_mostRecentlySent != mode) {
                deco->m_mostRecentlySent = mode;
                deco->m_resource->sendMode(mode);
            }
            return mode == ORG_KDE_KWIN_SERVER_DECORATION_MODE_SERVER;
        }
    }
    return override.value_or(false);
}
} // namespace Velora
