#pragma once
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/window/WindowBackend.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <json/json.h>

namespace Velora {
extern HANDLE handle;
extern Json::Value settings;
extern bool canvas;
bool takeCanvasGesture();
void save();
void queueSave();
void changeMode(bool enabled);
void installCanvas();
void stopCanvas();
void trackCanvas(PHLWINDOW window);
void forgetCanvas(PHLWINDOW window);
bool activate(PHLWINDOW window);
bool navigate(const std::string &command, double x = 0, double y = 0);
bool desktop();
std::optional<CBox> worldGeometry(PHLWINDOW window);
bool placeOnCanvas(PHLWINDOW window, CBox box, bool world = false);
bool beginWindowDrag(PHLWINDOW window, bool resize, int edges = 0);
void updateCaption(PHLWINDOW window);
void installFramePreferences();
void stopFramePreferences();
void forgetFramePreference(PHLWINDOW window);
bool systemFrame(PHLWINDOW window, std::optional<bool> override);
void forgetCaption(PHLWINDOW window);
bool captionInput(PHLWINDOW window, Vector2D local, IPointer::SButtonEvent event);
void maximize(PHLWINDOW window);
} // namespace Velora
