#include "windows.hpp"
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/TexPassElement.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprgraphics/cairo/CairoSurface.hpp>
#include <linux/input-event-codes.h>

namespace Velora {
namespace {
constexpr double height = 32, buttonWidth = 38;
class Caption final : public IHyprWindowDecoration {
    std::string cachedTitle;
    int cachedWidth = -1;
    float cachedScale = 0, controlsScale = 0;
    bool cachedDark = true, controlsDark = true, controlsMaximized = false;
    std::string cachedFont;
    SP<Render::ITexture> controls;
    SP<Render::ITexture> title;
    Time::steady_tp lastPress{};
    Vector2D lastPoint;

  public:
    using IHyprWindowDecoration::IHyprWindowDecoration;
    SDecorationPositioningInfo getPositioningInfo() override {
        return {.policy = DECORATION_POSITION_STICKY,
                .edges = DECORATION_EDGE_TOP,
                .priority = 10001, // Inside Hyprland's border, so it outlines the complete frame.
                .desiredExtents = {{0., height}, {0, 0}},
                .reserved = true};
    }
    void onPositioningReply(const SDecorationPositioningReply &) override {}
    eDecorationType getDecorationType() override {
        return DECORATION_CUSTOM;
    }
    eDecorationLayer getDecorationLayer() override {
        return DECORATION_LAYER_UNDER;
    }
    uint64_t getDecorationFlags() override {
        return DECORATION_ALLOWS_MOUSE_INPUT | DECORATION_PART_OF_MAIN_WINDOW;
    }
    std::string getDisplayName() override {
        return "Velora title bar";
    }
    void damageEntire() override {
        g_pHyprRenderer->damageBox(g_pDecorationPositioner->getWindowDecorationBox(this));
    }
    void updateWindow(PHLWINDOW) override {}
    void draw(Render::CRenderContext &ctx, PHLMONITOR mon, const float &alpha,
              const Render::SWindowRenderPresentation &presentation) override {
        auto w = owningWindow();
        if (!w)
            return;
        auto box = g_pDecorationPositioner->getWindowDecorationBox(this);
        box.translate(presentation.workspaceOffset + presentation.floatingOffset - mon->m_position).scale(mon->m_scale);
        const double s = mon->m_scale;
        static auto background = CConfigValue<Config::INTEGER>("misc:background_color");
        static auto font = CConfigValue<std::string>("misc:font_family");
        const auto base = CHyprColor(*background);
        const bool dark = base.r * .2126 + base.g * .7152 + base.b * .0722 < .55;
        const double blend = Desktop::focusState()->isWindowActive(w) ? .11 : .06;
        const double fg = dark ? .94 : .12;
        const CHyprColor surface(std::lerp(base.r, fg, blend), std::lerp(base.g, fg, blend),
                                 std::lerp(base.b, fg, blend), alpha);
        const auto ink = CHyprColor(fg, fg, fg, 1);
        const int radius = std::clamp<int>(std::lround(w->presentation().rounding() * s), 0, box.h / 2);
        // Back the client's rounded upper corners where the two surfaces meet.
        CBox rounded = box, clip = box;
        rounded.h += 2 * radius;
        clip.h += radius;
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CRectPassElement>(CRectPassElement::SRectData{
            .box = rounded.round(), .color = surface, .round = radius, .roundingPower = w->presentation().roundingPower(),
            .clipBox = clip.round()}));
        const int maxWidth = std::max(0, int(box.w - (3 * buttonWidth + 32) * s));
        if (cachedTitle != w->metadata().title() || cachedWidth != maxWidth || cachedScale != s ||
            cachedDark != dark || cachedFont != *font) {
            cachedTitle = w->metadata().title();
            cachedWidth = maxWidth;
            cachedScale = s;
            cachedDark = dark;
            cachedFont = *font;
            title = maxWidth > 0 && !cachedTitle.empty()
                        ? g_pHyprRenderer->renderText(cachedTitle, ink, std::round(13 * s), false, cachedFont, maxWidth, 500)
                        : nullptr;
        }
        auto texture = [&](const SP<Render::ITexture> &tex, CBox bounds) {
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CTexPassElement>(CTexPassElement::SRenderData{
                .tex = tex, .box = bounds.round(), .a = alpha}));
        };
        if (title)
            texture(title, {box.x + 16 * s, box.y + (box.h - title->m_size.y) / 2, title->m_size.x, title->m_size.y});

        const bool maximized = Fullscreen::controller()->getFullscreenModes(w).internal != Fullscreen::FSMODE_NONE;
        if (!controls || controlsScale != s || controlsDark != dark || controlsMaximized != maximized) {
            controlsScale = s;
            controlsDark = dark;
            controlsMaximized = maximized;
            Hyprgraphics::CCairoSurface image(cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
                std::ceil(3 * buttonWidth * s), std::ceil(height * s)));
            auto cr = cairo_create(image.cairo());
            cairo_scale(cr, s, s);
            cairo_translate(cr, buttonWidth / 2, height / 2);
            cairo_set_source_rgb(cr, fg, fg, fg);
            cairo_set_line_width(cr, 1.4);
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
            cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
            auto line = [&](double x1, double y1, double x2, double y2) {
                cairo_move_to(cr, x1, y1);
                cairo_line_to(cr, x2, y2);
            };
            line(-5, 3, 5, 3);
            cairo_translate(cr, buttonWidth, 0);
            if (maximized) {
                cairo_rectangle(cr, -5, -2, 7, 7);
                cairo_move_to(cr, -2, -3);
                cairo_line_to(cr, -2, -5);
                cairo_line_to(cr, 5, -5);
                cairo_line_to(cr, 5, 2);
                cairo_line_to(cr, 3, 2);
            } else
                cairo_rectangle(cr, -4.5, -4.5, 9, 9);
            cairo_translate(cr, buttonWidth, 0);
            line(-4, -4, 4, 4);
            line(-4, 4, 4, -4);
            cairo_stroke(cr);
            cairo_destroy(cr);
            controls = g_pHyprRenderer->createTexture(image.cairo());
        }
        if (controls)
            texture(controls, {box.x + box.w - 3 * buttonWidth * s, box.y + (box.h - height * s) / 2,
                               3 * buttonWidth * s, height * s});
    }

    bool click(Vector2D point, IPointer::SButtonEvent e) {
        auto w = owningWindow();
        if (!w)
            return false;
        const auto box = g_pDecorationPositioner->getWindowDecorationBox(this);
        if (!box.containsPoint(point))
            return false;
        if (e.button != BTN_LEFT || e.state != WL_POINTER_BUTTON_STATE_PRESSED)
            return true;
        if (point.y - box.y < 5 && w->isFloating() && !Fullscreen::controller()->isFullscreen(w)) {
            if (!beginWindowDrag(w, true, Layout::CORNER_TOP))
                g_layoutManager->dragController()->dragBegin(w->layoutTarget(), MBIND_RESIZE, Layout::CORNER_TOP);
            return true;
        }
        const double fromRight = box.x + box.w - point.x;
        if (fromRight <= buttonWidth)
            w->backend().close();
        else if (fromRight <= 2 * buttonWidth)
            maximize(w);
        else if (fromRight <= 3 * buttonWidth)
            Event::bus()->m_events.window.minimize.emit(w, true);
        else {
            const auto now = Time::steadyNow();
            if (now - lastPress < std::chrono::milliseconds(380) && (point - lastPoint).size() < 6) {
                lastPress = {};
                maximize(w);
            } else {
                lastPress = now;
                lastPoint = point;
                if (!beginWindowDrag(w, false))
                    g_layoutManager->dragController()->dragBegin(w->layoutTarget(), MBIND_MOVE);
            }
        }
        return true;
    }
    bool onInputOnDeco(eInputType type, const Vector2D &point, std::any data) override {
        return type == INPUT_TYPE_BUTTON && click(point, std::any_cast<IPointer::SButtonEvent>(data));
    }
};
std::map<Desktop::View::CWindow *, WP<Caption>> captions;
} // namespace

bool captionInput(PHLWINDOW w, Vector2D point, IPointer::SButtonEvent e) {
    auto it = captions.find(w.get());
    if (it == captions.end())
        return false;
    auto bar = it->second.lock();
    return bar && bar->click(point, e);
}
void forgetCaption(PHLWINDOW w) {
    auto it = captions.find(w.get());
    if (it == captions.end())
        return;
    if (auto bar = it->second.lock())
        HyprlandAPI::removeWindowDecoration(handle, bar.get());
    captions.erase(it);
}
void updateCaption(PHLWINDOW w) {
    if (!w || w->backend().traits().overrideRedirect || (!w->mapped() && w->backend().isX11()))
        return;
    const auto &override = std::as_const(settings)["captions"][w->metadata().appID()];
    const bool show = systemFrame(w, override.isBool() ? std::optional(override.asBool()) : std::nullopt);
    // Negotiate the mode before the first frame. Reserve compositor space only after map.
    if (!w->mapped())
        return;
    if (show && !captions.contains(w.get())) {
        auto bar = makeShared<Caption>(w);
        if (HyprlandAPI::addWindowDecoration(handle, w, bar))
            captions[w.get()] = bar;
    } else if (!show)
        forgetCaption(w);
}
} // namespace Velora
