# Workspace previews

In **Settings → Bar → Layout**, select the **Workspaces** widget. The same options
are available in the panel's edit drawer.

- **Show workspace previews** controls hover miniatures only. Workspace buttons,
  application icons, clicking, and scrolling to switch workspaces remain usable
  when previews are off.
- **Preview behavior → Interactive** lets the pointer enter the miniature to
  select a window. A short grace period allows crossing the gap. Optionally hide
  the preview on fast movement away from the panel; a lower speed threshold makes
  this more sensitive.
- **Preview behavior → Panel only** retains an already open miniature anywhere
  on that monitor's panel. It closes immediately, without a grace period or exit
  animation, when the pointer leaves the panel, including toward the miniature.
  Moving to another monitor's panel does not retain it. The miniature cannot be
  entered in this mode. Merely hovering elsewhere on the panel never opens it.

Hover over a workspace containing windows for 220 ms to open its preview. Sweeping
past a button cancels the opening delay. Empty workspaces do not open previews.
The panel boundary is its actual content rectangle, not the larger auto-hide
activation strip or decorative rounded corners. This applies to all four panel
edges and floating panels.

Dependent options appear only when applicable. Changing modes or disabling
previews does not reset the saved flick preference or speed threshold.

## Configuration

```json
{
  "bar": {
    "workspaces": {
      "showPreviews": true,
      "hidePreviewOnLeave": false,
      "hidePreviewOnFlick": true,
      "flickSpeed": 370
    }
  }
}
```

These defaults preserve the existing interactive behavior. The new settings are
shared by horizontal and vertical panels and persist through the usual Config
service. No compositor polling or background process is added.

## Tests

`python -m unittest discover -s tests -p 'test_workspace_preview*.py'`

Tests execute the production popup state/timers and catalog/options form with
Qt Quick Test. Real Qt pointer events cover all four panel edges, movement to
other panel areas, cancellation, mode changes, disabled previews, and unchanged
owner-controlled popups. Compositor-specific rendering is replaced in these
isolated tests; this is not a physical multi-monitor or auto-hide end-to-end test.
