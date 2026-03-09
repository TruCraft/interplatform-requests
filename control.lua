-- Interplatform Requests - Control Script
-- Intercepts platform hub requests and fulfills them from other platforms in orbit

-- Constants
local SCAN_INTERVAL = 60 -- Check every 60 ticks (1 second)
local ROBOT_OFFSCREEN_DISTANCE = 64 -- Distance in tiles for robots to travel beyond typical camera visibility
local ROBOT_TICKS_PER_TILE = 4 -- Original speed: 30 tiles over 120 ticks -> 4 ticks per tile
local ROBOT_TRAVEL_TICKS = ROBOT_OFFSCREEN_DISTANCE * ROBOT_TICKS_PER_TILE
local ROBOT_HOVER_TICKS_SOURCE = 60
local ROBOT_HOVER_TICKS_TARGET = 60
local ROBOT_TRANSIT_TICKS = 180
local REQUEST_COMPLETED_DISPLAY_TICKS = 120 -- How long to show a just-completed request
local MAX_CONCURRENT_TRANSFERS = 5 -- Maximum number of active inter-platform transfers per hub at once

-- Technology that gates whether Interplatform Requests is active. We rely on
-- the vanilla unlock-space-location tech effect (see prototypes/space-location.lua)
-- to control when the Planetary Orbit space location is actually usable.
local TECHNOLOGY_NAME = "interplatform-requests"

-- (No-op version of the old sanitizer kept for reference in case we want to
-- re-introduce stricter pre-tech behavior later.)
-- local function sanitize_planetary_orbit_filters_if_locked(hub) end

-- Simple debug logging flag (stored in global `storage`) and helper. This can
-- be toggled at runtime via a chat command.
local function debug_print(msg)
  if storage and storage.debug_logging then
    game.print(msg)
  end
end

-- Initialize storage
local function init_storage()
  if not storage.monitored_hubs then
    storage.monitored_hubs = {}
  end
  if not storage.active_deliveries then
    storage.active_deliveries = {}
  end
  if not storage.request_directions then
    storage.request_directions = {}
  end
  if not storage.viewed_hub_by_player then
    storage.viewed_hub_by_player = {}
  end
  if not storage.request_status then
    storage.request_status = {}
  end
  if storage.debug_logging == nil then
    storage.debug_logging = false
  end
end

script.on_init(function()
  init_storage()
  debug_print "Interplatform Requests: Initialized storage"
  -- When the mod is first added to a save, register any existing hubs so
  -- transfers begin working immediately.
  if scan_all_hubs then
    scan_all_hubs()
  end
end)

script.on_configuration_changed(function()
  init_storage()
  debug_print "Interplatform Requests: Configuration changed, re-initialized storage"
end)

-- Register platform hubs
local function register_hub(entity)
  if entity and entity.valid and entity.name == "space-platform-hub" then
    local surface = entity.surface
    if surface.platform then
      storage.monitored_hubs[entity.unit_number] = {
        entity = entity,
        platform = surface.platform,
      }
    end
  end
end

-- Unregister platform hubs
local function unregister_hub(entity)
  if entity and entity.unit_number then
    storage.monitored_hubs[entity.unit_number] = nil
    if storage and storage.request_directions then
      storage.request_directions[entity.unit_number] = nil
    end
  end
end

-- Event handlers for hub creation/destruction
local hub_filter = { { filter = "name", name = "space-platform-hub" } }

local function on_hub_created(event)
  register_hub(event.entity or event.created_entity)
end

local function on_hub_destroyed(event)
  unregister_hub(event.entity)
end

-- Helper: does this platform's hub have its *own* request for the given item
-- (importing from planetary orbit)? Used to avoid circular requests and to
-- exclude those items from being treated as "available" exports.
local function platform_has_request_for_item(hub, item_name, quality_name)
  if not (hub and hub.valid) then
    return false
  end

  local logistic_point = hub.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not logistic_point then
    return false
  end

  local found = false
  for_each_planetary_orbit_item_request(logistic_point, function(filter)
    local f_item = filter.value.name
    local f_quality = filter.value.quality or "normal"
    local requested_amount = filter.min or 0

    if f_item == item_name and f_quality == quality_name and requested_amount > 0 then
      found = true
      return true -- stop iteration early
    end
  end)

  return found
end

-- Helper: cached access to the Planetary Orbit prototype. Wrapped so we only
-- have one place to touch if the prototype name or lookup changes later.
local function get_planetary_orbit_proto()
  return prototypes.space_location and prototypes.space_location["planetary-orbit"]
end

-- Helper: compute how many items are already in transit to a given hub for a
-- specific item+quality pair, and which source platforms they are coming from.
local function get_in_transit_for_request(hub, item_name, quality_name)
  local total = 0
  local sources = {}

  if not storage or not storage.active_deliveries then
    return 0, sources
  end

  for _, delivery in ipairs(storage.active_deliveries) do
    if
      delivery.target_hub == hub
      and delivery.item_name == item_name
      and delivery.quality_name == quality_name
    then
      total = total + delivery.count

      if delivery.source_platform and delivery.source_platform.valid then
        local name = delivery.source_platform.name or "(unknown platform)"
        sources[name] = true
      end
    end
  end

  return total, sources
end

-- Helper: iterate all logistic filters on a hub that request items from the
-- Planetary Orbit location. Calls the callback once per matching filter.
--
-- `callback(filter, section, section_index, filter_index, planetary_orbit_proto)`
-- If the callback returns true, iteration stops early.
function for_each_planetary_orbit_item_request(logistic_point, callback)
  if not logistic_point then
    return
  end

  local sections = logistic_point.sections
  if not sections or #sections == 0 then
    return
  end

  local planetary_orbit_proto = get_planetary_orbit_proto()
  if not planetary_orbit_proto then
    return
  end

  for section_index = 1, #sections do
    local section = sections[section_index]
    if section and section.filters then
      for filter_index, filter in ipairs(section.filters) do
        if
          filter
          and filter.value
          and filter.value.type == "item"
          and filter.import_from == planetary_orbit_proto
        then
          if callback(filter, section, section_index, filter_index, planetary_orbit_proto) then
            return
          end
        end
      end
    end
  end
end

-- When a player opens a space platform hub GUI, show a summary of the
-- Interplatform Requests view for that hub so the player can see the true
-- "on the way" / "available on other platforms" values. This is rendered
-- in a small GUI panel next to the main game UI rather than as chat spam.
-- Show a popup explaining that the Interplatform Requests technology is
-- required before Planetary Orbit imports will work.
local function show_tech_warning(player)
  if not (player and player.valid) then
    return
  end

  local screen = player.gui.screen
  if screen.interplatform_requests_tech_warning then
    screen.interplatform_requests_tech_warning.destroy()
  end

  local frame = screen.add {
    type = "frame",
    name = "interplatform_requests_tech_warning",
    caption = { "", "[img=technology/interplatform-requests] ", "Interplatform Requests" },
    direction = "vertical",
  }

  frame.add {
    type = "label",
    caption = {
      "",
      "You must research the Interplatform Requests technology before hub requests can import from Planetary Orbit.",
    },
    style = "label",
  }

  local footer = frame.add { type = "flow", direction = "horizontal" }
  footer.add {
    type = "button",
    name = "interplatform_requests_tech_warning_close",
    caption = { "gui.ok" },
  }

  -- Position the warning near the top-left so it isn't hidden behind
  -- the vanilla hub window, which typically appears centered.
  frame.location = { 50, 80 }
end

-- When a player opens a space platform hub GUI, show a summary of the
-- Interplatform Requests view for that hub so the player can see the true
-- "on the way" / "available on other platforms" values. This is rendered
-- in a small GUI panel next to the main game UI rather than as chat spam.
local function on_hub_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == "space-platform-hub") then
    return
  end

  -- Ensure storage tables exist even in older saves where on_init may not
  -- have run with the newer fields yet.
  init_storage()

  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  -- Only show the Interplatform Requests overlay once the technology is
  -- researched for this force. If the tech isn't researched, we simply
  -- skip drawing the overlay (but other events may still show warnings).
  local force = entity.force
  local tech = force and force.valid and force.technologies and force.technologies[TECHNOLOGY_NAME]
  if not (tech and tech.researched) then
    return
  end

  local hub = entity
  local platform = hub.surface and hub.surface.platform
  if not platform or not platform.valid or not platform.space_location then
    return
  end

  -- Clear any previous status panel for this player
  if player.gui.left.platform_requests_status then
    player.gui.left.platform_requests_status.destroy()
  end

  local platform_name = (platform and platform.valid and platform.name) or "(unknown platform)"

  local frame = player.gui.left.add {
    type = "frame",
    name = "platform_requests_status",
    direction = "vertical",
    caption = { "", "Interplatform Requests: ", platform_name },
  }
  local inner = frame.add { type = "flow", direction = "vertical", name = "content" }

  -- We'll create the table lazily only if there is at least one row to show.
  local status_table = nil
  local any_missing = false

  local logistic_point = hub.get_logistic_point(defines.logistic_member_index.logistic_container)
  if logistic_point then
    for_each_planetary_orbit_item_request(logistic_point, function(filter)
      local item_name = filter.value.name
      local quality_name = filter.value.quality or "normal"
      local requested_amount = filter.min or 1

      -- Only show extra info for requests that import from planetary orbit
      local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
      local current_count = 0
      if hub_inventory then
        current_count = hub_inventory.get_item_count {
          name = item_name,
          quality = quality_name,
        }
      end

      -- Count items already in transit for this hub+item+quality and track
      -- which platforms they are coming from.
      local in_transit, in_transit_sources =
        get_in_transit_for_request(hub, item_name, quality_name)

      -- Count what is currently available on other platforms at the same
      -- location. Platforms that have their *own* request for this item
      -- (importing from planetary orbit) are excluded to avoid circular
      -- requests.
      local available_on_other_platforms = 0
      local other_platforms = get_platforms_at_location(platform.space_location, platform)
      if #other_platforms > 0 then
        for _, other in ipairs(other_platforms) do
          local other_hub = other.hub
          if
            other_hub
            and other_hub.valid
            and not platform_has_request_for_item(other_hub, item_name, quality_name)
          then
            local inv = other_hub.get_inventory(defines.inventory.hub_main)
            if inv then
              available_on_other_platforms = available_on_other_platforms
                + inv.get_item_count {
                  name = item_name,
                  quality = quality_name,
                }
            end
          end
        end
      end

      -- Treat "need" as based purely on local inventory so that requests
      -- remain visible until items actually arrive. In-transit items are
      -- shown separately as W (on_way).
      local total_on_the_way = in_transit
      local still_needed = math.max(0, requested_amount - current_count)

      -- Track simple state machine per (hub, item, quality) so we can
      -- keep a just-completed request visible for a short time.
      local key = tostring(hub.unit_number) .. "|" .. item_name .. "|" .. quality_name
      storage.request_status = storage.request_status or {}
      local entry = storage.request_status[key]
      local prev_state = entry and entry.state or "NONE"
      local now_state

      if still_needed > 0 or total_on_the_way > 0 then
        now_state = "ACTIVE"
      else
        now_state = "SATISFIED"
      end

      if not entry then
        entry = { state = now_state, last_change_tick = game.tick }
        storage.request_status[key] = entry
      elseif now_state ~= prev_state then
        entry.state = now_state
        entry.last_change_tick = game.tick
      end

      local show_row = false
      if now_state == "ACTIVE" then
        show_row = true
      elseif now_state == "SATISFIED" and entry.last_change_tick then
        -- Keep a completed request visible for a short time.
        if game.tick - entry.last_change_tick <= REQUEST_COMPLETED_DISPLAY_TICKS then
          show_row = true
        end
      end

      if show_row then
        any_missing = true

        -- Lazily create the status table and its header row the first
        -- time we have something to show, so it doesn't appear when
        -- there are no pending or in-transit items.
        if not status_table then
          status_table = inner.add {
            type = "table",
            name = "platform_requests_status_table",
            column_count = 11,
          }
          -- Columns: icon | need | satisfaction | in transit | available | from
          status_table.add { type = "label", caption = "" } -- icon column
          status_table.add { type = "label", caption = "[color=gray]|[/color]" }
          status_table.add {
            type = "label",
            caption = { "", "[font=default-bold]Need[/font]" },
          }
          status_table.add { type = "label", caption = "[color=gray]|[/color]" }
          status_table.add {
            type = "label",
            caption = { "", "[font=default-bold]Satisfaction[/font]" },
          }
          status_table.add { type = "label", caption = "[color=gray]|[/color]" }
          status_table.add {
            type = "label",
            caption = { "", "[font=default-bold]In transit[/font]" },
          }
          status_table.add { type = "label", caption = "[color=gray]|[/color]" }
          status_table.add {
            type = "label",
            caption = { "", "[font=default-bold]Available[/font]" },
          }
          status_table.add { type = "label", caption = "[color=gray]|[/color]" }
          status_table.add {
            type = "label",
            caption = { "", "[font=default-bold]From[/font]" },
          }
        end

        -- Build a compact table row per item.
        local source_list = {}
        for name, _ in pairs(in_transit_sources) do
          table.insert(source_list, name)
        end
        table.sort(source_list)
        local sources_str = table.concat(source_list, ", ")
        if sources_str == "" then
          sources_str = "-"
        end

        -- Icon (tooltip shows item name)
        status_table.add {
          type = "sprite",
          sprite = "item/" .. item_name,
          tooltip = item_name,
        }

        status_table.add { type = "label", caption = "[color=gray]|[/color]" }

        -- Need (local shortfall only). When Need is 0, show green; otherwise orange.
        local need_color = (still_needed == 0) and "green" or "orange"
        status_table.add {
          type = "label",
          caption = string.format("[color=%s]%d[/color]", need_color, still_needed),
          tooltip = "need: additional items required in this hub to reach the request",
        }

        status_table.add { type = "label", caption = "[color=gray]|[/color]" }

        -- Satisfaction: how many this hub has / how many it needs.
        -- Color encodes the ratio: red < 50%, yellow 50-99%, green >= 100%.
        local satisfied_count = math.min(current_count, requested_amount)
        local ratio = 0
        if requested_amount > 0 then
          ratio = satisfied_count / requested_amount
        end
        local sat_color
        if ratio >= 1 then
          sat_color = "green"
        elseif ratio >= 0.5 then
          sat_color = "yellow"
        else
          sat_color = "red"
        end

        status_table.add {
          type = "label",
          caption = string.format(
            "[color=%s]%d[/color]/[color=green]%d[/color]",
            sat_color,
            satisfied_count,
            requested_amount
          ),
          tooltip = "satisfaction: items in this hub / requested amount (red <50%, yellow 50-99%, green >=100%)",
        }

        status_table.add { type = "label", caption = "[color=gray]|[/color]" }

        -- In transit
        status_table.add {
          type = "label",
          caption = (total_on_the_way > 0)
              and string.format("[color=yellow]%d[/color]", total_on_the_way)
            or string.format("[color=gray]%d[/color]", total_on_the_way),
          tooltip = "in transit: items already being delivered by Interplatform Requests",
        }

        status_table.add { type = "label", caption = "[color=gray]|[/color]" }

        -- Available on other platforms.
        -- Color semantics:
        --   * 0 available  -> red
        --   * < need       -> yellow (not enough to cover remaining need)
        --   * >= need      -> green
        local available_color
        if available_on_other_platforms == 0 then
          available_color = "red"
        elseif still_needed > 0 and available_on_other_platforms < still_needed then
          available_color = "yellow"
        else
          available_color = "green"
        end

        status_table.add {
          type = "label",
          caption = string.format(
            "[color=%s]%d[/color]",
            available_color,
            available_on_other_platforms
          ),
          tooltip = "available: items currently stored on other platforms in the same orbit",
        }

        status_table.add { type = "label", caption = "[color=gray]|[/color]" }

        -- From (source platforms)
        status_table.add {
          type = "label",
          caption = (sources_str ~= "-") and string.format("[color=cyan]%s[/color]", sources_str)
            or sources_str,
          tooltip = "Platforms currently sending this item",
        }
      end
      return false
    end)
  end

  if not any_missing then
    inner.add {
      type = "label",
      caption = "All planetary-orbit imports satisfied",
    }
  end

  -- Remember which hub this player is currently viewing so we can
  -- refresh the overlay when deliveries change.
  if storage.viewed_hub_by_player then
    storage.viewed_hub_by_player[player.index] = hub.unit_number
  end
end

-- Refresh overlays for any players currently viewing this hub
local function refresh_status_for_hub(hub)
  if not (hub and hub.valid) then
    return
  end
  if not storage.viewed_hub_by_player then
    return
  end

  for player_index, hub_unit in pairs(storage.viewed_hub_by_player) do
    if hub_unit == hub.unit_number then
      local player = game.get_player(player_index)
      if player and player.valid then
        on_hub_gui_opened {
          entity = hub,
          player_index = player_index,
        }
      end
    end
  end
end

-- Register creation events
script.on_event(defines.events.on_built_entity, on_hub_created, hub_filter)
script.on_event(defines.events.on_robot_built_entity, on_hub_created, hub_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_hub_created, hub_filter)

-- Register destruction events
script.on_event(defines.events.on_entity_died, on_hub_destroyed, hub_filter)
script.on_event(defines.events.on_player_mined_entity, on_hub_destroyed, hub_filter)
script.on_event(defines.events.on_robot_mined_entity, on_hub_destroyed, hub_filter)
script.on_event(defines.events.on_space_platform_mined_entity, on_hub_destroyed, hub_filter)

-- Show request status when opening a platform hub GUI
script.on_event(defines.events.on_gui_opened, on_hub_gui_opened)

-- Handle clicks in our custom tech warning popup
local function on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  if element.name == "interplatform_requests_tech_warning_close" then
    local parent = element.parent
    while parent and parent.valid do
      if parent.name == "interplatform_requests_tech_warning" then
        parent.destroy()
        break
      end
      parent = parent.parent
    end

    -- After closing the warning, refresh the hub GUI/overlay if the player
    -- still has a space platform hub open, so they can immediately see that
    -- the Planetary Orbit import option was cleared.
    local player = game.get_player(event.player_index)
    if player and player.valid then
      local opened = player.opened
      if opened and opened.valid and opened.name == "space-platform-hub" then
        on_hub_gui_opened {
          entity = opened,
          player_index = event.player_index,
        }
      end
    end
  end
end

script.on_event(defines.events.on_gui_click, on_gui_click)

-- Clean up the status panel when the GUI is closed
local function on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if player.gui.left.platform_requests_status then
    player.gui.left.platform_requests_status.destroy()
  end

  if storage.viewed_hub_by_player then
    storage.viewed_hub_by_player[event.player_index] = nil
  end
end

script.on_event(defines.events.on_gui_closed, on_gui_closed)

-- Refresh the status panel when the player changes a hub's logistic request
local function on_logistic_slot_changed(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == "space-platform-hub") then
    return
  end

  -- Only update for direct player edits; if changed by script, we skip to
  -- avoid surprising overlays popping up.
  if not event.player_index then
    return
  end

  -- If the player is trying to configure a request that imports from
  -- Planetary Orbit before the tech is researched, show a warning popup.
  local player = game.get_player(event.player_index)
  if player then
    local force = entity.force
    local tech = force
      and force.valid
      and force.technologies
      and force.technologies[TECHNOLOGY_NAME]
    if not (tech and tech.researched) then
      local planetary_orbit_proto = get_planetary_orbit_proto()
      if planetary_orbit_proto then
        local logistic_point =
          entity.get_logistic_point(defines.logistic_member_index.logistic_container)
        if logistic_point then
          local sections = logistic_point.sections
          if sections then
            local found = false
            for _, section in ipairs(sections) do
              if section and section.filters then
                local filters = section.filters
                local changed = false

                for _, filter in ipairs(filters) do
                  if
                    filter
                    and filter.import_from
                    and filter.import_from == planetary_orbit_proto
                  then
                    -- Clear the pre-tech Planetary Orbit import so selecting
                    -- it in the GUI effectively "doesn't stick" until the
                    -- technology is researched.
                    filter.import_from = nil
                    changed = true
                    found = true
                  end
                end

                if changed then
                  -- Writing the modified filters table back is required for
                  -- the game to persist the change to the hub's settings.
                  section.filters = filters
                end
              end
            end
            if found then
              show_tech_warning(player)
            end
          end
        end
      end
    end
  end

  -- Reuse the same logic as when opening the GUI to rebuild the panel.
  on_hub_gui_opened(event)
end

script.on_event(defines.events.on_entity_logistic_slot_changed, on_logistic_slot_changed)

-- Get all platforms at the same location
function get_platforms_at_location(space_location, exclude_platform)
  local platforms = {}
  for _, surface in pairs(game.surfaces) do
    if surface.platform then
      local plat_location = surface.platform.space_location
      if surface.platform ~= exclude_platform and plat_location == space_location then
        table.insert(platforms, surface.platform)
      end
    end
  end
  return platforms
end

-- Cross-platform requests no longer attempt to guess rocket capacities from
-- prototype data. The Factorio runtime API does not reliably expose the
-- `rocket_lift_weight` utility constant, which means any capacity derived from
-- it would either be wrong or silently fall back to "uncapped" behavior.
--
-- Instead, we rely on two explicit controls:
--   * The per-request `minimum_delivery_count` field in the logistic filter
--     (the "Custom minimum payload" slider in the hub GUI), which determines
--     when we are allowed to start cross-platform transfers.
--   * The item's stack size, which caps how much we send in a single transfer
--     so that each delivery is at most one full stack.

local function get_item_stack_size(item_name)
  if not (item_name and prototypes and prototypes.item) then
    return nil
  end

  local item_proto = prototypes.item[item_name]
  if not item_proto then
    return nil
  end

  local stack_size = item_proto.stack_size
  if type(stack_size) ~= "number" or stack_size <= 0 then
    return nil
  end

  return stack_size
end

-- Find item in another platform's hub
local function find_item_in_platforms(platforms, item_name, quality_name)
  for _, platform in ipairs(platforms) do
    local hub = platform.hub
    if hub and hub.valid then
      -- Skip platforms that have their *own* request for this item, to avoid
      -- circular requests and only treat true surplus as available.
      if not platform_has_request_for_item(hub, item_name, quality_name) then
        local inventory = hub.get_inventory(defines.inventory.hub_main)
        if inventory then
          local count = inventory.get_item_count { name = item_name, quality = quality_name }
          if count > 0 then
            return hub, inventory
          end
        end
      end
    end
  end
  return nil, nil
end

-- Deliver items to a hub
local function deliver_items_to_hub(hub, item_name, quality_name, count)
  if hub and hub.valid then
    local inventory = hub.get_inventory(defines.inventory.hub_main)
    if inventory then
      inventory.insert {
        name = item_name,
        quality = quality_name,
        count = count,
      }
      return true
    end
  end
  return false
end

-- Process platform hub requests
local function process_hub_requests()
  init_storage()

  -- If we don't have any hubs registered yet (for example, when the mod was
  -- added to an existing save), scan all existing hubs once so that
  -- cross-platform transfers actually run without requiring a manual remote
  -- call.
  if not next(storage.monitored_hubs) then
    if scan_all_hubs then
      scan_all_hubs()
    end
  end

  for unit_number, hub_data in pairs(storage.monitored_hubs) do
    local hub = hub_data.entity

    if not hub or not hub.valid then
      storage.monitored_hubs[unit_number] = nil
    else
      local platform = hub_data.platform
      if platform and platform.valid and platform.space_location then
        -- Only process cross-platform transfers when the gating technology
        -- has been researched for this force.
        local force = hub.force
        local tech = force
          and force.valid
          and force.technologies
          and force.technologies[TECHNOLOGY_NAME]
        if tech and tech.researched then
          -- Count how many active deliveries are already targeting this hub so
          -- we can enforce a per-hub concurrency limit when scheduling new
          -- transfers.
          local active_delivery_count = 0
          if storage.active_deliveries then
            for _, delivery in ipairs(storage.active_deliveries) do
              if delivery.target_hub == hub then
                active_delivery_count = active_delivery_count + 1
              end
            end
          end

          -- Also rate-limit new launches so that we only start a limited number
          -- of new transfers per scan for this hub. With SCAN_INTERVAL = 60,
          -- allowing 1 launch per scan spaces robot departures by at least
          -- ~1 second.
          local launches_this_scan = 0
          -- Get logistic requests from the hub
          local logistic_point =
            hub.get_logistic_point(defines.logistic_member_index.logistic_container)
          if logistic_point then
            for_each_planetary_orbit_item_request(logistic_point, function(filter)
              if launches_this_scan >= 1 or active_delivery_count >= MAX_CONCURRENT_TRANSFERS then
                return true -- stop early for this hub
              end

              local item_name = filter.value.name
              local quality_name = filter.value.quality or "normal"
              local requested_amount = filter.min or 1

              -- Custom minimum payload for this request, if configured in the hub GUI.
              local min_payload = 0
              if
                filter.minimum_delivery_count
                and type(filter.minimum_delivery_count) == "number"
                and filter.minimum_delivery_count > 0
              then
                min_payload = filter.minimum_delivery_count
              end

              -- Check current inventory
              local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
              if not hub_inventory then
                return false
              end

              local current_count = hub_inventory.get_item_count {
                name = item_name,
                quality = quality_name,
              }

              -- Also check if there's already a delivery in progress for this hub/item/quality.
              local in_transit = select(1, get_in_transit_for_request(hub, item_name, quality_name))

              local total_count = current_count + in_transit
              local needed = requested_amount - total_count

              -- If we need more, try to get from other platforms, but respect the per-hub
              -- concurrency limit and rate-limit new launches.
              if total_count >= requested_amount then
                return false
              end

              local other_platforms = get_platforms_at_location(platform.space_location, platform)
              if #other_platforms == 0 then
                return false
              end

              local source_hub, source_inventory =
                find_item_in_platforms(other_platforms, item_name, quality_name)
              if not (source_hub and source_inventory) then
                return false
              end

              -- Transfer items via cargo pod
              local available = source_inventory.get_item_count {
                name = item_name,
                quality = quality_name,
              }
              local to_transfer = math.min(needed, available)

              -- Cap each transfer using both the item's stack size and any custom minimum payload.
              local stack_size = get_item_stack_size(item_name)
              local cap = stack_size
              if stack_size and stack_size > 0 and min_payload > 0 and min_payload < stack_size then
                cap = min_payload
              end
              if cap and cap > 0 then
                to_transfer = math.min(to_transfer, cap)
              end

              -- If a custom minimum payload is set, don't launch a transfer smaller than the
              -- effective minimum. When the slider is higher than the stack size, we require at
              -- least one stack and send at most one stack.
              local effective_min = 0
              if min_payload > 0 then
                if stack_size and stack_size > 0 and min_payload > stack_size then
                  effective_min = stack_size
                else
                  effective_min = min_payload
                end
              end
              if effective_min > 0 and to_transfer < effective_min then
                return false
              end

              local removed = source_inventory.remove {
                name = item_name,
                quality = quality_name,
                count = to_transfer,
              }

              if removed <= 0 then
                return false
              end

              -- Create a robot to deliver the items (custom visual if available)
              local source_platform = source_hub.surface.platform
              local robot =
                create_cinematic_robot(source_hub.surface, source_hub.position, hub.force)

              if robot and robot.valid then
                -- Choose a stable direction per hub and space location so that all deliveries to
                -- this hub share the same path until the hub leaves and returns to a different
                -- location.
                local dir_x, dir_y

                if storage and storage.request_directions then
                  local stored = storage.request_directions[hub.unit_number]
                  if
                    stored
                    and stored.x
                    and stored.y
                    and stored.space_location == platform.space_location
                  then
                    dir_x, dir_y = stored.x, stored.y
                  end
                end

                if not dir_x or not dir_y then
                  local angle = math.random() * 2 * math.pi
                  dir_x = math.cos(angle)
                  dir_y = math.sin(angle)

                  if dir_x == 0 and dir_y == 0 then
                    dir_x, dir_y = 1, 0
                  end

                  if storage and storage.request_directions then
                    storage.request_directions[hub.unit_number] = {
                      x = dir_x,
                      y = dir_y,
                      space_location = platform.space_location,
                    }
                  end
                end

                table.insert(storage.active_deliveries, {
                  pickup_robot = robot,
                  delivery_robot = nil, -- Will be created later on target platform
                  source_hub = source_hub,
                  target_hub = hub,
                  target_platform = platform,
                  source_platform = source_platform,
                  start_tick = game.tick,
                  item_name = item_name,
                  quality_name = quality_name,
                  count = removed,
                  phase = "pickup", -- pickup, transit, deliver
                  direction_x = dir_x,
                  direction_y = dir_y,
                })

                active_delivery_count = active_delivery_count + 1
                launches_this_scan = launches_this_scan + 1

                debug_print(
                  string.format(
                    "Interplatform Requests: Sending %dx %s from %s to %s",
                    removed,
                    item_name,
                    source_platform.name,
                    platform.name
                  )
                )

                refresh_status_for_hub(hub)
              else
                -- Fallback: instant transfer if robot creation fails
                hub_inventory.insert {
                  name = item_name,
                  quality = quality_name,
                  count = removed,
                }
                debug_print(
                  string.format(
                    "Interplatform Requests: Transferred %dx %s from %s to %s (instant)",
                    removed,
                    item_name,
                    source_platform.name,
                    platform.name
                  )
                )
              end

              return launches_this_scan >= 1
            end)
          end
        end
      end

      -- After processing all requests for this hub, refresh overlays for any
      -- players currently viewing it so that completed requests can age out
      -- and disappear after the configured grace period.
      refresh_status_for_hub(hub)
    end
  end
end

-- Resolve the movement direction for a delivery (normalized 2D vector)
local function get_delivery_direction(delivery)
  -- New format: explicit x/y components
  local dx = delivery.direction_x
  local dy = delivery.direction_y
  if dx and dy and (dx ~= 0 or dy ~= 0) then
    -- Normalize to ensure constant speed regardless of direction
    local len_sq = dx * dx + dy * dy
    if len_sq > 0 then
      local len = math.sqrt(len_sq)
      return dx / len, dy / len
    end
  end

  -- Backwards compatibility: old format used a scalar horizontal direction
  local old_dir = delivery.direction
  if type(old_dir) == "number" and old_dir ~= 0 then
    return old_dir, 0
  end

  -- Default to moving to the right
  return 1, 0
end

-- Create a visual delivery robot, falling back to the vanilla logistic robot
-- if the custom prototype is not available or fails to spawn.
function create_cinematic_robot(surface, position, force)
  -- Try custom delivery robot first
  local ok, entity = pcall(surface.create_entity, {
    name = "interplatform-delivery-robot",
    position = position,
    force = force,
  })
  if ok and entity and entity.valid then
    return entity
  end

  -- Fallback: vanilla logistic robot
  local ok2, entity2 = pcall(surface.create_entity, {
    name = "logistic-robot",
    position = position,
    force = force,
  })
  if ok2 and entity2 and entity2.valid then
    return entity2
  end

  return nil
end

-- Process active deliveries
local function process_deliveries()
  init_storage()

  if not storage.active_deliveries then
    return
  end

  for i = #storage.active_deliveries, 1, -1 do
    local delivery = storage.active_deliveries[i]

    if not delivery then
      table.remove(storage.active_deliveries, i)
      goto continue
    end

    local elapsed = game.tick - delivery.start_tick

    if delivery.phase == "pickup" then
      -- Robot is picking up items from source hub and flying off screen
      if delivery.pickup_robot and delivery.pickup_robot.valid then
        local source_pos = delivery.source_hub.position
        local bob = math.sin(game.tick / 10) * 0.2

        if elapsed < ROBOT_HOVER_TICKS_SOURCE then
          -- Hover at source hub before departing (with subtle bobbing)
          delivery.pickup_robot.teleport { source_pos.x, source_pos.y + bob }
        else
          -- Fly off in a random direction away from the hub
          local progress = (elapsed - ROBOT_HOVER_TICKS_SOURCE) / ROBOT_TRAVEL_TICKS
          local dir_x, dir_y = get_delivery_direction(delivery)
          local new_x = source_pos.x + progress * ROBOT_OFFSCREEN_DISTANCE * dir_x
          local new_y = source_pos.y + progress * ROBOT_OFFSCREEN_DISTANCE * dir_y + bob
          delivery.pickup_robot.teleport { new_x, new_y }
        end
      end

      -- After hover + travel, destroy pickup robot and switch to transit
      if elapsed >= (ROBOT_HOVER_TICKS_SOURCE + ROBOT_TRAVEL_TICKS) then
        if delivery.pickup_robot and delivery.pickup_robot.valid then
          delivery.pickup_robot.destroy()
        end
        delivery.phase = "transit"
        delivery.transit_start_tick = game.tick
      end
    elseif delivery.phase == "transit" then
      -- Items are "in transit" between platforms (no visible robot)
      local transit_elapsed = game.tick - delivery.transit_start_tick
      local transit_time = ROBOT_TRANSIT_TICKS

      if transit_elapsed >= transit_time then
        -- Create delivery robot on target platform, coming from the opposite direction
        local dir_x, dir_y = get_delivery_direction(delivery)
        local arrival_x = -dir_x
        local arrival_y = -dir_y

        local target_pos = delivery.target_hub.position
        local spawn_pos = {
          target_pos.x + ROBOT_OFFSCREEN_DISTANCE * arrival_x,
          target_pos.y + ROBOT_OFFSCREEN_DISTANCE * arrival_y,
        }
        local delivery_robot =
          create_cinematic_robot(delivery.target_hub.surface, spawn_pos, delivery.target_hub.force)

        if delivery_robot and delivery_robot.valid then
          delivery.delivery_robot = delivery_robot
          delivery.phase = "deliver"
          delivery.deliver_start_tick = game.tick
        else
          -- Failed to create delivery robot, just deliver instantly
          deliver_items_to_hub(
            delivery.target_hub,
            delivery.item_name,
            delivery.quality_name,
            delivery.count
          )
          table.remove(storage.active_deliveries, i)
          -- Update overlays for any players viewing this hub
          refresh_status_for_hub(delivery.target_hub)
        end
      end
    elseif delivery.phase == "deliver" then
      -- Robot is flying in from off-screen, hovering, then delivering to target hub
      local deliver_elapsed = game.tick - delivery.deliver_start_tick

      if delivery.delivery_robot and delivery.delivery_robot.valid then
        local bob = math.sin(game.tick / 10) * 0.2
        if deliver_elapsed < ROBOT_TRAVEL_TICKS then
          -- Fly in from the opposite direction toward the target hub
          local progress = deliver_elapsed / ROBOT_TRAVEL_TICKS
          local dir_x, dir_y = get_delivery_direction(delivery)
          local arrival_x = -dir_x
          local arrival_y = -dir_y

          local target_pos = delivery.target_hub.position
          local start_x = target_pos.x + ROBOT_OFFSCREEN_DISTANCE * arrival_x
          local start_y = target_pos.y + ROBOT_OFFSCREEN_DISTANCE * arrival_y
          local new_x = start_x + (target_pos.x - start_x) * progress
          local new_y = start_y + (target_pos.y - start_y) * progress + bob

          delivery.delivery_robot.teleport { new_x, new_y }
        else
          -- Hover at target hub after arrival (with subtle bobbing)
          local target_pos = delivery.target_hub.position
          delivery.delivery_robot.teleport { target_pos.x, target_pos.y + bob }
        end
      end

      -- After travel + hover, complete delivery
      if deliver_elapsed >= (ROBOT_TRAVEL_TICKS + ROBOT_HOVER_TICKS_TARGET) then
        -- Transfer items to target hub
        if
          deliver_items_to_hub(
            delivery.target_hub,
            delivery.item_name,
            delivery.quality_name,
            delivery.count
          )
        then
          debug_print(
            string.format(
              "Interplatform Requests: Delivered %dx %s to %s",
              delivery.count,
              delivery.item_name,
              delivery.target_platform.name
            )
          )
        end

        -- Destroy the delivery robot
        if delivery.delivery_robot and delivery.delivery_robot.valid then
          delivery.delivery_robot.destroy()
        end

        -- Remove from active deliveries
        table.remove(storage.active_deliveries, i)
        -- Update overlays for any players viewing this hub
        refresh_status_for_hub(delivery.target_hub)
      end
    end

    ::continue::
  end
end

-- Register the periodic checks
script.on_nth_tick(SCAN_INTERVAL, process_hub_requests)
script.on_nth_tick(1, process_deliveries) -- Check deliveries every tick

-- Scan and register all existing platform hubs
function scan_all_hubs()
  init_storage()
  local count = 0
  for _, surface in pairs(game.surfaces) do
    if surface.platform then
      for _, entity in pairs(surface.find_entities_filtered { name = "space-platform-hub" }) do
        register_hub(entity)
        count = count + 1
      end
    end
  end
  debug_print(
    string.format("Interplatform Requests: Scanned and registered %d platform hubs", count)
  )
end

-- Remote interface for testing
remote.add_interface("interplatform-requests", {
  process_now = function()
    debug_print "Manually triggering platform request processing..."
    process_hub_requests()
  end,
  scan_hubs = function()
    scan_all_hubs()
  end,
  test_robot = function()
    local player = game.player
    if player and player.surface then
      local robot = create_cinematic_robot(
        player.surface,
        { player.position.x + 2, player.position.y },
        player.force
      )
      if robot and robot.valid then
        debug_print "Test robot created at your position!"
      else
        debug_print "Failed to create test robot!"
      end
    end
  end,
})

-- Chat command to control debug logging
commands.add_command(
  "interplatform-requests-debug",
  "Enable/disable Interplatform Requests debug logging: /interplatform-requests-debug [on|off|toggle]",
  function(cmd)
    init_storage()

    local param = cmd.parameter and string.lower(cmd.parameter) or "toggle"
    local new_value

    if param == "on" then
      new_value = true
    elseif param == "off" then
      new_value = false
    elseif param == "toggle" then
      new_value = not storage.debug_logging
    else
      local msg = "Usage: /interplatform-requests-debug [on|off|toggle]"
      if cmd.player_index then
        local player = game.get_player(cmd.player_index)
        if player then
          player.print(msg)
        else
          game.print(msg)
        end
      else
        game.print(msg)
      end
      return
    end

    storage.debug_logging = new_value
    local state_msg = "Interplatform Requests debug logging: " .. (new_value and "ON" or "OFF")

    if cmd.player_index then
      local player = game.get_player(cmd.player_index)
      if player then
        player.print(state_msg)
      else
        game.print(state_msg)
      end
    else
      game.print(state_msg)
    end
  end
)
