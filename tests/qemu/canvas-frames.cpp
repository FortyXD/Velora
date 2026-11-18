// Optional instrumentation for the isolated QEMU compositor. No active listener outside a sample.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <lua.hpp>
#include <hyprland/src/render/Context.hpp>
#include <algorithm>

namespace {
CHyprSignalListener listener;
Time::steady_tp begin;
std::vector<double> times;
std::string output;
uint64_t pixels = 0, windows = 0;
double build = 0;
} // namespace
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE h) {
    if (std::string_view(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("ABI mismatch");
    HyprlandAPI::addLuaFunction(h, "velora_test", "frames", [](lua_State *L) {
        listener.reset();
        if (lua_gettop(L) == 1) {
            output = luaL_checkstring(L, 1);
            times.clear();
            begin = {};
            pixels = 0;
            windows = 0;
            build = 0;
            listener = Event::bus()->m_events.render.stage.listen([](Event::SRenderStageEvent e) {
                if (!e.monitor || e.monitor->m_name != output)
                    return;
                if (e.stage == RENDER_PRE)
                    begin = Time::steadyNow();
                if (e.stage == RENDER_BEGIN && e.context) {
                    for (const auto &r : e.context->get().m_data.damage.getRects())
                        pixels += (r.x2 - r.x1) * (r.y2 - r.y1);
                }
                if (e.stage == RENDER_PRE_WINDOW)
                    ++windows;
                if (e.stage == RENDER_LAST_MOMENT && begin != Time::steady_tp{})
                    build += std::chrono::duration<double, std::milli>(Time::steadyNow() - begin).count();
                if (e.stage == RENDER_POST && begin != Time::steady_tp{} && times.size() < 4096)
                    times.emplace_back(std::chrono::duration<double, std::milli>(Time::steadyNow() - begin).count());
            });
            return 0;
        }
        std::ranges::sort(times);
        lua_pushinteger(L, times.size());
        lua_pushnumber(L, times.empty() ? 0. : times[static_cast<size_t>(std::ceil(.95 * times.size())) - 1]);
        double n = std::max<size_t>(1, times.size());
        lua_pushnumber(L, pixels / n);
        lua_pushnumber(L, windows / n);
        lua_pushnumber(L, build / n);
        return 5;
    });
    return {"velora-test-frames", "QEMU frame timings", "Velora", "1"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    listener.reset();
}
