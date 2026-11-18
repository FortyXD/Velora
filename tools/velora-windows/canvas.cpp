#include "windows.hpp"
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/Popup.hpp>
#include <hyprland/src/desktop/view/Subsurface.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/core/Subcompositor.hpp>
#include <hyprland/src/protocols/InputCapture.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Context.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <linux/input-event-codes.h>
#include <set>
#include <unordered_map>

namespace Velora {
using namespace Render;
using namespace Desktop;
using namespace Desktop::View;
bool canvas = false;
namespace {
constexpr auto goal = IGeometric::GEOMETRIC_GOAL, current = IGeometric::GEOMETRIC_CURRENT;
constexpr double minZoom = 1. / 65536, maxZoom = 4.;
uint64_t sceneVersion = 1;
struct Camera {
    Vector2D origin;
    double zoom = 1;
    bool hidden = false;
    Time::steady_tp showMapUntil{};
    uint64_t version = 0;
    std::vector<PHLWINDOWREF> visibleStack;
};
struct Window {
    PHLWINDOWREF w;
    std::string app, home;
    Json::ArrayIndex slot = 0;
    CBox world, original;
    CHyprSignalListener move, resize, geometry, hide;
};
std::unordered_map<CWindow *, Window> windows;
std::map<std::string, Camera> cameras;
std::vector<CHyprSignalListener> listeners;
CFunctionHook *normalHook = nullptr, *fullHook = nullptr, *damageHook = nullptr;
SP<CEventLoopTimer> mapTimer;

bool eligible(PHLWINDOW w) {
    return w && w->mapped() && w->m_workspace && !w->onSpecialWorkspace() && !w->isHidden() &&
           !(w->m_state & WINDOW_STATE_PINNED) && w->wlSurface() && w->wlSurface()->resource();
}
bool validMonitor(PHLMONITOR m) {
    return m && m->m_activeWorkspace && !g_pSessionLockManager->isSessionLocked();
}
PHLMONITOR at(Vector2D p) {
    return State::monitorState()->query().vec(p).run();
}
std::string key(PHLMONITOR m, PHLWORKSPACE ws) {
    return m->m_name + "/" + ws->addressableName();
}
bool numbers(const Json::Value &v, unsigned count) {
    if (!v.isArray() || v.size() != count)
        return false;
    for (auto &n : v)
        if (!n.isNumeric() || !std::isfinite(n.asDouble()))
            return false;
    return true;
}
Camera &camera(PHLMONITOR m, PHLWORKSPACE ws) {
    auto id = key(m, ws);
    auto [it, inserted] = cameras.try_emplace(id);
    if (inserted) {
        auto &c = it->second;
        auto &stored = settings["cameras"][id];
        if (numbers(stored, 3)) {
            c.origin = {stored[0].asDouble(), stored[1].asDouble()};
            c.zoom = std::clamp(stored[2].asDouble(), minZoom, maxZoom);
        } else {
            auto &groups = settings["groups"];
            auto name = ws->addressableName();
            if (!groups.isMember(name))
                groups[name] = static_cast<double>(groups.size()) * 4096.;
            if (groups[name].isNumeric())
                c.origin.x = groups[name].asDouble();
        }
    }
    return it->second;
}
Camera &camera(PHLMONITOR m) {
    return camera(m, m->m_activeWorkspace);
}
Json::Value coordinates(std::initializer_list<double> values) {
    Json::Value array(Json::arrayValue);
    for (auto v : values)
        array.append(v);
    return array;
}
void remember(Window &record) {
    auto &b = record.world;
    settings["windows"][record.app][record.slot] = coordinates({b.x, b.y, b.w, b.h});
    queueSave();
}
bool overlaps(const CBox &a, const CBox &b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}
bool localMax(PHLWINDOW w, PHLMONITOR m) {
    return w->m_workspace == m->m_activeWorkspace && w->m_monitor == m && Fullscreen::controller()->isFullscreen(w);
}
struct Projection {
    CBox box;
    double scale;
};
Projection project(Window &r, PHLWINDOW w, PHLMONITOR m) {
    if (localMax(w, m))
        return {w->geometricBox(current), 1.};
    auto &c = camera(m);
    auto size = w->size(current);
    const bool expanded = Fullscreen::controller()->isFullscreen(w);
    const auto factor = expanded ? std::min(r.world.w / std::max(1., size.x), r.world.h / std::max(1., size.y)) : 1.;
    const auto scale = c.zoom * factor;
    auto p = m->m_position + (r.world.pos() - c.origin) * c.zoom;
    if (expanded)
        p += (r.world.size() - size * factor) * (c.zoom * .5);
    return {{p, size * scale}, scale};
}
bool visible(Window &r, PHLWINDOW w, PHLMONITOR m) {
    if (!eligible(w) || !validMonitor(m) || camera(m).hidden)
        return false;
    auto projected = project(r, w, m);
    auto bounds = w->getFullWindowBoundingBox();
    auto expanded = projected.box;
    expanded.translate((bounds.pos() - w->position(current)) * projected.scale);
    expanded.w = bounds.w * projected.scale;
    expanded.h = bounds.h * projected.scale;
    return overlaps(expanded, {m->m_position, m->m_size});
}
const std::vector<PHLWINDOWREF> &visibleStack(PHLMONITOR m) {
    auto &c = camera(m);
    if (c.version == sceneVersion)
        return c.visibleStack;
    c.visibleStack.clear();
    PHLWINDOWREF maximized;
    for (const auto &w : windowState()->windows()) {
        auto it = windows.find(w.get());
        if (it == windows.end() || !visible(it->second, w, m))
            continue;
        if (localMax(w, m))
            maximized = w;
        else
            c.visibleStack.emplace_back(w);
    }
    if (maximized)
        c.visibleStack.emplace_back(maximized);
    c.version = sceneVersion;
    return c.visibleStack;
}
void damageVisible(PHLWINDOW w) {
    auto it = windows.find(w.get());
    if (it == windows.end())
        return;
    for (auto &m : State::monitorState()->monitors())
        if (visible(it->second, w, m))
            g_pHyprRenderer->damageMonitor(m);
}
void damageAll() {
    ++sceneVersion;
    for (auto &m : State::monitorState()->monitors())
        g_pHyprRenderer->damageMonitor(m);
}
void changed(PHLMONITOR m) {
    ++sceneVersion;
    auto &c = camera(m);
    settings["cameras"][key(m, m->m_activeWorkspace)] = coordinates({c.origin.x, c.origin.y, c.zoom});
    queueSave();
    c.showMapUntil = Time::steadyNow() + std::chrono::milliseconds(1100);
    mapTimer->updateTimeout(std::chrono::milliseconds(1110));
    g_pHyprRenderer->damageMonitor(m);
}
void zoom(PHLMONITOR m, double target, Vector2D anchor) {
    if (!std::isfinite(target) || target <= 0.)
        return;
    auto &c = camera(m);
    target = std::clamp(target, minZoom, maxZoom);
    const auto p = anchor - m->m_position;
    c.origin += p / c.zoom - p / target;
    c.zoom = target;
    changed(m);
}
CBox unionBox(CBox a, CBox b) {
    auto x = std::min(a.x, b.x), y = std::min(a.y, b.y);
    return {x, y, std::max(a.x + a.w, b.x + b.w) - x, std::max(a.y + a.h, b.y + b.h) - y};
}
std::optional<CBox> bounds() {
    std::optional<CBox> result;
    for (auto &[_, r] : windows)
        if (eligible(r.w.lock()))
            result = result ? unionBox(*result, r.world) : r.world;
    return result;
}
void minimap(CRenderContext &ctx, PHLMONITOR m) {
    auto &c = camera(m);
    if (Time::steadyNow() >= c.showMapUntil)
        return;
    CBox viewport{c.origin, m->m_size / c.zoom};
    auto extent = unionBox(bounds().value_or(viewport), viewport);
    double width = std::min(200., m->m_size.x / 3), height = std::min(118., m->m_size.y / 3);
    CBox panel{m->m_size.x - width - 24, m->m_size.y - height - 64, width, height};
    auto draw = [&](CBox box, CHyprColor col, int radius = 0) {
        IHyprRenderer::addPassElement(
            ctx,
            makeUnique<CRectPassElement>(CRectPassElement::SRectData{
                .box = box.scale(m->m_scale).round(), .color = col, .round = static_cast<int>(radius * m->m_scale)}));
    };
    draw(panel, CHyprColor(.08, .10, .14, .93), 10);
    const double factor = std::min((width - 16) / std::max(1., extent.w), (height - 16) / std::max(1., extent.h));
    const auto offset = panel.pos() + (panel.size() - extent.size() * factor) / 2;
    auto map = [&](CBox b) { return CBox{offset + (b.pos() - extent.pos()) * factor, b.size() * factor}; };
    for (auto &[_, r] : windows)
        if (eligible(r.w.lock())) {
            auto b = map(r.world);
            b.w = std::max(2., b.w);
            b.h = std::max(2., b.h);
            draw(b, CHyprColor(.49, .59, .72, .83), 2);
        }
    auto v = map(viewport);
    CHyprColor ink(.58, .84, 1., 1.);
    draw({v.x, v.y, v.w, 1.5}, ink);
    draw({v.x, v.y + v.h - 1.5, v.w, 1.5}, ink);
    draw({v.x, v.y, 1.5, v.h}, ink);
    draw({v.x + v.w - 1.5, v.y, 1.5, v.h}, ink);
}

// Hyprland normally intersects buffer damage with the unscaled output before
// applying a render modifier. Sample the whole source of a projected window,
// while keeping scissoring in output coordinates. Layers use the ordinary path.
class ProjectionScope final : public IPassElement {
    bool begin;
    float scale;

  public:
    ProjectionScope(bool enter, float factor) : begin(enter), scale(factor) {}
    std::vector<UP<IPassElement>> draw(CRenderContext &ctx) override {
        ctx.m_data.renderingTransformedSource = begin;
        ctx.m_data.renderModif = {};
        if (begin)
            ctx.m_data.renderModif.modifs.emplace_back(SRenderModifData::RMOD_TYPE_SCALE, scale);
        return {};
    }
    bool needsLiveBlur(CRenderContext &) override {
        return false;
    }
    bool needsPrecomputeBlur(CRenderContext &) override {
        return false;
    }
    bool undiscardable(CRenderContext &) override {
        return true;
    }
    bool disableSimplification(CRenderContext &) override {
        return true;
    }
    const char *passName() override {
        return "Velora camera transform";
    }
    ePassElementType type() override {
        return EK_CUSTOM;
    }
};
struct RendererAccess : IHyprRenderer {
    using IHyprRenderer::renderWindow;
};
using SceneFn = void (*)(IHyprRenderer *, CRenderContext &, PHLMONITOR, PHLWORKSPACE, const Time::steady_tp &,
                         eSceneMode);
void drawScene(CFunctionHook *hook, IHyprRenderer *renderer, CRenderContext &ctx, PHLMONITOR m, PHLWORKSPACE ws,
               const Time::steady_tp &time, eSceneMode mode) {
    if (!canvas || mode != eSceneMode::MONITOR || !validMonitor(m) || ws != m->m_activeWorkspace) {
        reinterpret_cast<SceneFn>(hook->m_original)(renderer, ctx, m, ws, time, mode);
        return;
    }
    auto &pass = renderer->currentPass(ctx);
    auto draw = [&](PHLWINDOW w) {
        auto it = windows.find(w.get());
        if (it == windows.end() || !eligible(w))
            return;
        auto p = project(it->second, w, m);
        if (p.scale != 1.)
            pass.add(makeUnique<ProjectionScope>(true, static_cast<float>(p.scale)));
        SWindowRenderPresentation presentation{};
        presentation.workspaceOffset = m->m_position + (p.box.pos() - m->m_position) / p.scale - w->position(current);
        (renderer->*(&RendererAccess::renderWindow))(ctx, w, m, presentation, time, true, RENDER_PASS_ALL, false,
                                                     false);
        if (p.scale != 1.)
            pass.add(makeUnique<ProjectionScope>(false, 1.f));
        if (w->m_workspace != ws || w->m_monitor != m) {
            w->setSuspended(false);
            w->wlSurface()->resource()->breadthfirst([&](auto s, const Vector2D &, void *) { s->frame(time); },
                                                     nullptr);
        }
    };
    for (const auto &weak : visibleStack(m))
        if (auto w = weak.lock())
            draw(w);
    minimap(ctx, m);
}
void drawNormal(IHyprRenderer *r, CRenderContext &c, PHLMONITOR m, PHLWORKSPACE w, const Time::steady_tp &t,
                eSceneMode s) {
    drawScene(normalHook, r, c, m, w, t, s);
}
void drawFull(IHyprRenderer *r, CRenderContext &c, PHLMONITOR m, PHLWORKSPACE w, const Time::steady_tp &t,
              eSceneMode s) {
    drawScene(fullHook, r, c, m, w, t, s);
}
void damage(IHyprRenderer *r, SP<CWLSurfaceResource> s, double x, double y, double scale) {
    using Fn = void (*)(IHyprRenderer *, SP<CWLSurfaceResource>, double, double, double);
    if (canvas) {
        auto root = s;
        if (s && s->m_role && s->m_role->role() == SURFACE_ROLE_SUBSURFACE) {
            auto sub = dynamicPointerCast<CSubsurfaceRole>(s->m_role)->m_subsurface.lock();
            if (sub)
                root = sub->t1Parent();
        }
        auto surface = root ? CWLSurface::fromResource(root) : nullptr;
        auto view = surface ? surface->view() : nullptr;
        PHLWINDOW w = CWindow::fromView(view);
        if (!w)
            if (auto popup = CPopup::fromView(view))
                w = popup->windowOwner();
        auto it = windows.find(w.get());
        if (it != windows.end() && eligible(w)) {
            auto source = CWLSurface::fromResource(s);
            if (!source)
                return;
            if (root != s || view->type() == VIEW_TYPE_POPUP)
                ++sceneVersion;
            auto region = source->computeDamage(source->getSurfaceBoxGlobal());
            const bool callbacks = !s->m_current.callbacks.empty();
            if (region.empty() && !callbacks)
                return;
            region.scale(scale).translate(Vector2D{x, y} - w->position(current));
            for (auto &m : State::monitorState()->monitors()) {
                if (!visible(it->second, w, m))
                    continue;
                if (!region.empty()) {
                    auto projected = project(it->second, w, m);
                    auto local = region.copy()
                                     .scale(projected.scale)
                                     .translate(projected.box.pos() - m->m_position)
                                     .scale(m->m_scale);
                    if (projected.scale != 1. || m->m_scale != 1.f)
                        local.expand(1);
                    m->addDamage(local);
                }
                if (callbacks)
                    m->scheduleFrame(Aquamarine::IOutput::AQ_SCHEDULE_NEEDS_FRAME);
            }
            return;
        }
    }
    reinterpret_cast<Fn>(damageHook->m_original)(r, s, x, y, scale);
}
CFunctionHook *hookFunction(std::string name, std::string suffix, void *replacement) {
    for (auto &match : HyprlandAPI::findFunctionsByName(handle, name))
        if (match.demangled.contains("IHyprRenderer::" + name + "(") && match.demangled.ends_with(suffix)) {
            auto hook = HyprlandAPI::createFunctionHook(handle, match.address, replacement);
            if (hook && hook->hook())
                return hook;
        }
    throw std::runtime_error("Velora: incompatible renderer method " + name);
}

enum class Drag { None, Pan, Move, Resize };
struct Interaction {
    Drag drag = Drag::None;
    uint32_t button = 0;
    int edges = 0;
    Vector2D start, origin;
    CBox box;
    PHLMONITORREF monitor;
    PHLWINDOWREF window;
} interaction;
struct Hit {
    PHLWINDOW w;
    Vector2D native, local;
    SP<CWLSurfaceResource> surface;
};
PHLWINDOWREF pressedWindow;
WP<CWLSurfaceResource> pressedSurface;
std::set<uint32_t> buttons, decorationButtons;
bool usedSuperGesture = false;
double pinchStart = 0;
PHLMONITORREF pinchMonitor;
bool meta() {
    return g_pInputManager->getModsFromAllKBs() == Input::HL_MODIFIER_META;
}
bool route(PHLMONITOR m, Vector2D p) {
    if (!canvas || !validMonitor(m) || m->m_activeSpecialWorkspace ||
        (PROTO::inputCapture && PROTO::inputCapture->isCaptured()) || g_pInputManager->pointerConstraints().locked())
        return false;
    if (!buttons.empty() || interaction.drag != Drag::None)
        return true;
    Vector2D local;
    PHLLS layer;
    auto hit = viewState()->hitTest();
    if (hit.layerPopupSurfaceAt(p, m, &local, &layer) ||
        hit.layerSurfaceAt(p, &m->m_layerSurfaceLayers[3], &local, &layer) ||
        hit.layerSurfaceAt(p, &m->m_layerSurfaceLayers[2], &local, &layer))
        return false;
    auto pinned = hit.windowAt(p, ALLOW_FLOATING | INPUT_EXTENTS);
    return !(pinned && (pinned->m_state & WINDOW_STATE_PINNED));
}
Hit hitWindow(PHLMONITOR m, Vector2D point) {
    if (camera(m).hidden)
        return {};
    auto test = [&](PHLWINDOW w, bool held) -> Hit {
        auto it = windows.find(w.get());
        if (it == windows.end() || !eligible(w))
            return {};
        auto p = project(it->second, w, m);
        auto relative = (point - p.box.pos()) / p.scale;
        Hit h{w, w->position(goal) + relative};
        if (held) {
            h.surface = pressedSurface.lock();
            if (h.surface)
                h.local = viewState()->hitTest().surfaceLocalAt(h.native, w, h.surface);
        } else {
            auto bbox = w->getFullWindowBoundingBox();
            if (!bbox.containsPoint(w->position(current) + relative) &&
                !(w->popupHead() && w->popupHead()->at(h.native)))
                return {};
            if (w->backend().isX11()) {
                if (CBox{{0, 0}, w->size(goal)}.containsPoint(relative)) {
                    h.surface = w->wlSurface()->resource();
                    h.local = w->backend().surfaceLocalToBuffer(relative);
                }
            } else {
                auto popup = w->popupHead() ? w->popupHead()->at(h.native) : nullptr;
                if (popup)
                    h.surface = viewState()->hitTest().windowSurfaceAt(h.native, w, h.local);
                else if (CBox{{0, 0}, w->size(goal)}.containsPoint(relative)) {
                    std::tie(h.surface, h.local) =
                        w->wlSurface()->resource()->at(relative + w->backend().geometry().box.pos(), true);
                }
            }
        }
        if (!h.surface &&
            !CBox{w->position(goal) - Vector2D{3, 35}, w->size(goal) + Vector2D{6, 38}}.containsPoint(h.native))
            return {};
        return h;
    };
    if (!buttons.empty())
        return test(pressedWindow.lock(), true);
    for (const auto &weak : std::views::reverse(visibleStack(m)))
        if (auto h = test(weak.lock(), false); h.w)
            return h;
    return {};
}
Hit pointer(PHLMONITOR m, Vector2D p, uint32_t time, bool motion = true) {
    auto h = hitWindow(m, p);
    if (!h.w && buttons.empty()) {
        PHLLS layer;
        for (int i : {1, 0}) {
            h.surface = viewState()->hitTest().layerSurfaceAt(p, &m->m_layerSurfaceLayers[i], &h.local, &layer);
            if (h.surface)
                break;
        }
    }
    if (auto grab = g_pSeatManager->m_seatGrab; grab && grab->m_pointer && !grab->accepts(h.surface))
        return {};
    g_pSeatManager->setPointerFocus(h.surface, h.local);
    if (motion && h.surface)
        g_pSeatManager->sendPointerMotion(time, h.local);
    return h;
}
void focus(PHLWINDOW w, PHLMONITOR m) {
    const bool fullscreenElsewhere =
        w->m_monitor != m && w->m_workspace->visible() && Fullscreen::controller()->isFullscreen(w);
    if (!fullscreenElsewhere && w->m_workspace != m->m_activeWorkspace &&
        !Config::Actions::moveToWorkspace(m->m_activeWorkspace, true, w))
        return;
    ++sceneVersion;
    focusState()->rawMonitorFocus(m);
    focusState()->fullWindowFocus(w, FOCUS_REASON_CLICK_DOWN);
    if (fullscreenElsewhere)
        focusState()->rawMonitorFocus(m);
    windowState()->raise(w);
}
void resizeNative(PHLWINDOW w, Vector2D size) {
    auto t = w->layoutTarget();
    if (!t)
        return;
    if (auto min = t->minSize()) {
        size.x = std::max(min->x, size.x);
        size.y = std::max(min->y, size.y);
    }
    if (auto max = t->maxSize()) {
        if (max->x > 0)
            size.x = std::min(max->x, size.x);
        if (max->y > 0)
            size.y = std::min(max->y, size.y);
    }
    if (size == w->size(goal))
        return;
    if (!Config::Actions::resize(size, false, w))
        return;
    t->warpPositionSize();
}
void motion(Vector2D p, Event::SCallbackInfo &info) {
    if (!canvas)
        return;
    auto m = interaction.drag == Drag::None ? at(p) : interaction.monitor.lock();
    if (!route(m, p))
        return;
    if (interaction.drag == Drag::None) {
        pointer(
            m, p,
            static_cast<uint32_t>(
                std::chrono::duration_cast<std::chrono::milliseconds>(Time::steadyNow().time_since_epoch()).count()));
    } else {
        auto &c = camera(m);
        auto delta = (p - interaction.start) / c.zoom;
        auto w = interaction.window.lock();
        if (interaction.drag == Drag::Pan) {
            c.origin = interaction.origin - delta;
            changed(m);
        } else if (w && windows.contains(w.get())) {
            auto &r = windows.at(w.get());
            damageVisible(w);
            ++sceneVersion;
            r.world = interaction.box;
            if (interaction.drag == Drag::Move)
                r.world.translate(delta);
            else {
                const auto edge = interaction.edges;
                const bool left = (edge & 4), top = (edge & 1);
                auto size = r.world.size();
                if (edge & 12)
                    size.x = std::max(64., size.x + (left ? -delta.x : delta.x));
                if (edge & 3)
                    size.y = std::max(48., size.y + (top ? -delta.y : delta.y));
                resizeNative(w, size);
                auto actual = w->size(goal);
                if (left)
                    r.world.x += r.world.w - actual.x;
                if (top)
                    r.world.y += r.world.h - actual.y;
                r.world.w = actual.x;
                r.world.h = actual.y;
            }
            remember(r);
            damageVisible(w);
        }
    }
    info.cancelled = true;
}
void button(IPointer::SButtonEvent e, Event::SCallbackInfo &info) {
    if (!canvas)
        return;
    auto p = Pointer::mgr()->position();
    auto m = at(p);
    if (e.state == WL_POINTER_BUTTON_STATE_RELEASED && decorationButtons.erase(e.button)) {
        info.cancelled = true;
        return;
    }
    if (!route(m, p))
        return;
    if (interaction.drag != Drag::None) {
        if (e.state == WL_POINTER_BUTTON_STATE_RELEASED && e.button == interaction.button) {
            interaction = {};
            // A client that requested interactive move/resize still owns its original press.
            if (buttons.erase(e.button)) {
                g_pSeatManager->sendPointerButton(e.timeMs, e.button, e.state);
                g_pSeatManager->sendPointerFrame();
                if (buttons.empty()) {
                    pressedWindow.reset();
                    pressedSurface.reset();
                }
            }
            pointer(m, p, e.timeMs);
        }
        info.cancelled = true;
        return;
    }
    auto h = pointer(m, p, e.timeMs, false);
    if (e.state == WL_POINTER_BUTTON_STATE_PRESSED) {
        if (meta() && e.button == BTN_MIDDLE) {
            usedSuperGesture = true;
            interaction = {.drag = Drag::Pan, .button = e.button, .start = p, .origin = camera(m).origin, .monitor = m};
            info.cancelled = true;
            return;
        }
        if (h.w) {
            focus(h.w, m);
            if (meta() && (e.button == BTN_LEFT || e.button == BTN_RIGHT)) {
                usedSuperGesture = true;
                beginWindowDrag(h.w, e.button == BTN_RIGHT);
                interaction.button = e.button;
                info.cancelled = true;
                return;
            }
            if (captionInput(h.w, h.native, e)) {
                if (interaction.drag == Drag::None)
                    decorationButtons.insert(e.button);
                info.cancelled = true;
                return;
            }
        }
        if (h.surface && h.w) {
            pressedWindow = h.w;
            pressedSurface = h.surface;
            buttons.insert(e.button);
        } else if (!h.surface && g_pSeatManager->m_seatGrab) {
            g_pSeatManager->setGrab(nullptr);
        }
    } else {
        buttons.erase(e.button);
        if (buttons.empty()) {
            pressedWindow.reset();
            pressedSurface.reset();
        }
    }
    if (h.surface) {
        g_pSeatManager->sendPointerButton(e.timeMs, e.button, e.state);
        g_pSeatManager->sendPointerFrame();
    }
    info.cancelled = true;
}
void axis(IPointer::SAxisEvent e, Event::SCallbackInfo &info) {
    if (!canvas)
        return;
    auto p = Pointer::mgr()->position();
    auto m = at(p);
    if (!route(m, p))
        return;
    if (!meta()) {
        if (g_pInputManager->getModsFromAllKBs() != Input::HL_MODIFIER_NONE)
            return;
        auto h = pointer(m, p, e.timeMs, false);
        if (!h.w || !h.surface)
            return;
        const double factor =
            e.source == WL_POINTER_AXIS_SOURCE_FINGER ? h.w->getScrollTouchpad() : h.w->getScrollMouse();
        const int value120 = std::lround(e.deltaDiscrete * factor);
        g_pSeatManager->sendPointerAxis(e.timeMs, e.axis, e.delta * factor, value120 / 120, value120, e.source,
                                        e.relativeDirection);
        g_pSeatManager->sendPointerFrame();
        info.cancelled = true;
        return;
    }
    auto &c = camera(m);
    usedSuperGesture = true;
    if (e.source == WL_POINTER_AXIS_SOURCE_FINGER) {
        if (e.axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL)
            c.origin.x += e.delta / c.zoom;
        else
            c.origin.y += e.delta / c.zoom;
        changed(m);
    } else if (e.delta != 0)
        zoom(m, c.zoom * std::pow(1.16, -std::copysign(1., e.delta)), p);
    info.cancelled = true;
}
} // namespace

bool takeCanvasGesture() {
    return std::exchange(usedSuperGesture, false);
}
bool beginWindowDrag(PHLWINDOW w, bool resize, int edges) {
    if (!canvas || !eligible(w) || !windows.contains(w.get()))
        return false;
    auto p = Pointer::mgr()->position();
    auto m = at(p);
    if (!validMonitor(m))
        return false;
    if (g_layoutManager->dragController()->target())
        g_layoutManager->dragController()->dragEnd();
    auto &r = windows.at(w.get());
    if (localMax(w, m))
        Fullscreen::controller()->setFullscreenMode(w, Fullscreen::FSMODE_NONE, Fullscreen::FSMODE_NONE, false);
    interaction = {.drag = resize ? Drag::Resize : Drag::Move,
                   .button = buttons.empty() ? BTN_LEFT : *buttons.begin(),
                   .edges = edges ? edges : 10,
                   .start = p,
                   .box = r.world,
                   .monitor = m,
                   .window = w};
    return true;
}
void trackCanvas(PHLWINDOW w) {
    if (!canvas || !eligible(w) || !w->m_monitor || windows.contains(w.get()))
        return;
    auto m = w->m_monitor.lock();
    Window r;
    r.w = w;
    r.home = w->m_workspace->addressableName();
    if (!std::holds_alternative<Workspace::SWorkspaceNumberedID>(w->m_workspace->id()))
        r.home = "name:" + r.home;
    r.app = w->metadata().appID();
    r.original = w->geometricBox(goal);
    if (r.original.w < 1 || r.original.h < 1)
        return;
    auto &c = camera(m, w->m_workspace);
    auto native = r.original;
    r.world = {c.origin + (native.pos() - m->m_position) / c.zoom, native.size()};
    std::set<Json::ArrayIndex> used;
    for (auto &[_, other] : windows)
        if (other.app == r.app)
            used.insert(other.slot);
    while (used.contains(r.slot))
        ++r.slot;
    auto saved = std::as_const(settings)["windows"][r.app][r.slot];
    if (numbers(saved, 4) && saved[2].asDouble() >= 1 && saved[3].asDouble() >= 1) {
        r.world = {saved[0].asDouble(), saved[1].asDouble(), saved[2].asDouble(), saved[3].asDouble()};
        if (w->isFloating() && !Fullscreen::controller()->isFullscreen(w))
            resizeNative(w, r.world.size());
    }
    auto weak = PHLWINDOWREF(w);
    r.move = w->backend().m_events.moveRequest.listen([weak] {
        if (auto win = weak.lock())
            beginWindowDrag(win, false);
    });
    r.resize = w->backend().m_events.resizeRequest.listen([weak](eBackendResizeEdge e) {
        // Wayland edge masks for top, bottom, left and right respectively.
        constexpr int mask[] = {0, 1, 2, 4, 8, 5, 9, 6, 10};
        if (auto win = weak.lock())
            beginWindowDrag(win, true, mask[static_cast<unsigned>(e)]);
    });
    r.geometry = w->m_events.resize.listen([weak]() {
        ++sceneVersion;
        if (auto win = weak.lock();
            win && windows.contains(win.get()) && !Fullscreen::controller()->isFullscreen(win)) {
            auto &record = windows.at(win.get());
            auto size = win->size(goal);
            if (size.x >= 1 && size.y >= 1 && record.world.size() != size) {
                record.world.w = size.x;
                record.world.h = size.y;
                remember(record);
                damageVisible(win);
            }
        }
    });
    r.hide = w->m_events.hide.listen([]() { damageAll(); });
    ++sceneVersion;
    auto &entry = windows.emplace(w.get(), std::move(r)).first->second;
    remember(entry);
    damageVisible(w);
}
void forgetCanvas(PHLWINDOW w) {
    auto it = windows.find(w.get());
    if (it == windows.end())
        return;
    remember(it->second);
    if (interaction.window == w)
        interaction = {};
    if (pressedWindow == w) {
        pressedWindow.reset();
        pressedSurface.reset();
        buttons.clear();
    }
    windows.erase(it);
    damageAll();
}
void changeMode(bool enabled) {
    if (canvas == enabled)
        return;
    canvas = enabled;
    if (canvas) {
        for (const auto &w : windowState()->windows())
            trackCanvas(w);
    } else {
        buttons.clear();
        decorationButtons.clear();
        pressedWindow.reset();
        pressedSurface.reset();
        interaction = {};
        pinchStart = 0;
        for (auto &[_, r] : windows)
            if (auto w = r.w.lock(); eligible(w) && w->isFloating()) {
                remember(r);
                if (w->m_workspace->addressableName() != r.home &&
                    "name:" + w->m_workspace->addressableName() != r.home &&
                    !Config::Actions::moveToWorkspace(r.home, true, w))
                    continue;
                if (!Fullscreen::controller()->isFullscreen(w)) {
                    if (Config::Actions::resize(r.original.size(), false, w))
                        (void)Config::Actions::move(r.original.pos(), false, w);
                }
            }
        windows.clear();
    }
    damageAll();
}
bool activate(PHLWINDOW w) {
    if (!canvas || !eligible(w))
        return false;
    auto m = focusState()->monitor();
    if (!validMonitor(m))
        return false;
    trackCanvas(w);
    auto it = windows.find(w.get());
    if (it == windows.end())
        return false;
    auto &c = camera(m);
    c.hidden = false;
    if (!visible(it->second, w, m))
        c.origin = it->second.world.pos() + (it->second.world.size() - m->m_size / c.zoom) / 2;
    focus(w, m);
    changed(m);
    return true;
}
bool desktop() {
    if (!canvas)
        return false;
    auto m = focusState()->monitor();
    if (!validMonitor(m))
        return false;
    auto &c = camera(m);
    c.hidden = !c.hidden;
    ++sceneVersion;
    if (c.hidden)
        focusState()->fullWindowFocus(nullptr, FOCUS_REASON_KEYBIND);
    g_pHyprRenderer->damageMonitor(m);
    return true;
}
std::optional<CBox> worldGeometry(PHLWINDOW w) {
    auto it = windows.find(w.get());
    if (!canvas || it == windows.end() || !eligible(w))
        return std::nullopt;
    return it->second.world;
}
bool placeOnCanvas(PHLWINDOW w, CBox box, bool world) {
    if (!std::isfinite(box.x) || !std::isfinite(box.y) || !std::isfinite(box.w) || !std::isfinite(box.h) ||
        box.w <= 0 || box.h <= 0)
        return false;
    if (!canvas || !eligible(w) || !windows.contains(w.get()))
        return false;
    auto m = focusState()->monitor();
    if (!validMonitor(m))
        return false;
    focus(w, m);
    auto &c = camera(m);
    auto &r = windows.at(w.get());
    damageVisible(w);
    ++sceneVersion;
    r.world = world ? box : CBox{c.origin + (box.pos() - m->m_position) / c.zoom, box.size() / c.zoom};
    resizeNative(w, r.world.size());
    remember(r);
    damageVisible(w);
    return true;
}
bool navigate(const std::string &command, double x, double y) {
    if (!canvas || !std::isfinite(x) || !std::isfinite(y))
        return false;
    auto p = Pointer::mgr()->position();
    auto m = at(p);
    if (!validMonitor(m))
        return false;
    auto &c = camera(m);
    if (command == "pan")
        c.origin += Vector2D{x, y} / c.zoom;
    else if (command == "zoom") {
        zoom(m, x, p);
        return true;
    } else if (command == "reset") {
        zoom(m, 1., p);
        return true;
    } else if (command == "fit") {
        if (auto b = bounds()) {
            c.zoom = std::clamp(std::min(m->m_size.x / std::max(1., b->w + 96), m->m_size.y / std::max(1., b->h + 96)),
                                minZoom, maxZoom);
            c.origin = b->pos() + (b->size() - m->m_size / c.zoom) / 2;
        } else {
            c.origin = {};
            c.zoom = 1.;
        }
    } else
        return false;
    changed(m);
    return true;
}
void installCanvas() {
    normalHook = hookFunction("renderWorkspaceWindows", "Render::eSceneMode)", reinterpret_cast<void *>(drawNormal));
    fullHook =
        hookFunction("renderWorkspaceWindowsFullscreen", "Render::eSceneMode)", reinterpret_cast<void *>(drawFull));
    damageHook = hookFunction("damageSurface", "double, double, double)", reinterpret_cast<void *>(damage));
    mapTimer = makeShared<CEventLoopTimer>(
        std::nullopt,
        [](SP<CEventLoopTimer> timer, void *) {
            auto now = Time::steadyNow();
            std::optional<Time::steady_dur> next;
            if (canvas)
                for (auto &m : State::monitorState()->monitors())
                    if (validMonitor(m)) {
                        auto &until = camera(m).showMapUntil;
                        if (until == Time::steady_tp{})
                            continue;
                        if (until <= now) {
                            until = {};
                            g_pHyprRenderer->damageMonitor(m);
                        } else if (!next || until - now < *next)
                            next = until - now;
                    }
            timer->updateTimeout(next);
        },
        nullptr);
    g_pEventLoopManager->addTimer(mapTimer);
    auto &e = Event::bus()->m_events;
    listeners.emplace_back(e.input.mouse.move.listen(motion));
    listeners.emplace_back(e.input.mouse.button.listen(button));
    listeners.emplace_back(e.input.mouse.axis.listen(axis));
    listeners.emplace_back(e.gesture.pinch.begin.listen([](IPointer::SPinchBeginEvent p, Event::SCallbackInfo &info) {
        auto pos = Pointer::mgr()->position();
        auto m = at(pos);
        if (p.fingers == 2 && meta() && route(m, pos)) {
            usedSuperGesture = true;
            pinchStart = camera(m).zoom;
            pinchMonitor = m;
            info.cancelled = true;
        }
    }));
    listeners.emplace_back(e.gesture.pinch.update.listen([](IPointer::SPinchUpdateEvent p, Event::SCallbackInfo &info) {
        if (auto m = pinchMonitor.lock(); pinchStart && validMonitor(m)) {
            zoom(m, pinchStart * p.scale, Pointer::mgr()->position());
            info.cancelled = true;
        }
    }));
    listeners.emplace_back(e.gesture.pinch.end.listen([](IPointer::SPinchEndEvent, Event::SCallbackInfo &info) {
        if (pinchStart) {
            pinchStart = 0;
            pinchMonitor.reset();
            info.cancelled = true;
        }
    }));
    listeners.emplace_back(e.window.moveToWorkspace.listen([](PHLWINDOW w, PHLWORKSPACE) {
        if (canvas) {
            trackCanvas(w);
            damageAll();
        }
    }));
    listeners.emplace_back(e.render.preChecks.listen([](PHLMONITOR m) {
        if (canvas && validMonitor(m) && m->m_solitaryClient) {
            auto &c = camera(m);
            if (c.hidden || c.showMapUntil > Time::steadyNow())
                m->m_solitaryClient.reset();
        }
    }));
    listeners.emplace_back(e.window.title.listen([](PHLWINDOW w) {
        if (canvas)
            damageVisible(w);
    }));
    listeners.emplace_back(e.monitor.layoutChanged.listen([] {
        if (canvas)
            damageAll();
    }));
    listeners.emplace_back(e.window.pin.listen([](PHLWINDOW w) {
        if (canvas) {
            trackCanvas(w);
            damageAll();
        }
    }));
    listeners.emplace_back(e.window.fullscreen.listen([](PHLWINDOW) {
        if (canvas)
            damageAll();
    }));
    listeners.emplace_back(e.window.active.listen([](PHLWINDOW, eFocusReason) {
        if (canvas)
            damageAll();
    }));
    listeners.emplace_back(e.workspace.active.listen([](PHLWORKSPACE) {
        if (canvas)
            damageAll();
    }));
}
void stopCanvas() {
    changeMode(false);
    listeners.clear();
    cameras.clear();
    if (mapTimer)
        g_pEventLoopManager->removeTimer(mapTimer);
    mapTimer.reset();
}
} // namespace Velora
