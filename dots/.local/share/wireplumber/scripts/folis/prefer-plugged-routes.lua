-- Folis: a port whose jack is plugged in (headphones, a headset mic) is used even when another port was
-- saved for the device. Runs before WirePlumber restores the saved port; the saved volume of whichever port
-- gets picked is still restored afterwards (device/apply-route-props).

cutils = require ("common-utils")
devinfo = require ("device-info-cache")
log = Log.open_topic ("s-device")

SimpleEventHook {
  name = "folis/prefer-plugged-routes",
  before = "device/find-stored-routes",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-routes" },
      Constraint { "profile.active-device-ids", "is-present" },
    },
  },
  execute = function (event)
    local device = event:get_subject ()
    local dev_info = devinfo:get_device_info (device)
    if not dev_info then
      return
    end

    local selected_routes = event:get_data ("selected-routes") or Properties ()
    local active_ids = Json.Raw (event:get_properties () ["profile.active-device-ids"]):parse ()

    for _, device_id in ipairs (active_ids) do
      if selected_routes [tostring (device_id)] then
        goto next_device_id
      end

      -- "yes" only comes from jack detection; built-in speakers and mics report "unknown"
      local plugged = nil
      for _, ri in pairs (dev_info.route_infos) do
        if cutils.arrayContains (ri.devices, device_id) and
            (ri.profiles == nil or cutils.arrayContains (ri.profiles, dev_info.active_profile)) and
            ri.available == "yes" and (plugged == nil or ri.priority > plugged.priority) then
          plugged = ri
        end
      end

      if plugged then
        log:info (device, "using plugged-in route " .. plugged.name)
        selected_routes [tostring (device_id)] =
            Json.Object { index = plugged.index }:to_string ()
      end

      ::next_device_id::
    end

    event:set_data ("selected-routes", selected_routes)
  end
}:register ()
