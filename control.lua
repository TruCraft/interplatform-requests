-- Interplatform Requests - Control Script
-- Intercepts platform hub requests and fulfills them from other platforms in orbit

-- Constants
local SCAN_INTERVAL = 60 -- Check every 60 ticks (1 second)
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
  if not storage.viewed_hub_by_player then
    storage.viewed_hub_by_player = {}
  end
  if not storage.request_status then
    storage.request_status = {}
  end
  if not storage.reserved_items then
    storage.reserved_items = {}
  end
  if not storage.hold_until_satisfied then
    storage.hold_until_satisfied = {}
  end
  if not storage.mod_paused_platforms then
    storage.mod_paused_platforms = {}
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

  -- When the mod or its dependencies change (including game version
  -- upgrades on a server), make sure we (re)discover all existing
  -- platform hubs so cross-platform transfers start working without
  -- requiring a manual /remote.call("interplatform-requests", "scan_hubs").
  if scan_all_hubs then
    scan_all_hubs()
  end

  -- Migrate old "Planetary Orbit" requests to per-planet format.
  if migrate_planetary_orbit_to_per_planet then
    migrate_planetary_orbit_to_per_planet()
  end
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
    local id = entity.unit_number
    storage.monitored_hubs[id] = nil
    if storage.hold_until_satisfied then
      storage.hold_until_satisfied[id] = nil
    end
    if storage.mod_paused_platforms then
      storage.mod_paused_platforms[id] = nil
    end
  end
end

-- Event handlers for hub creation/destruction
local hub_filter = { { filter = "name", name = "space-platform-hub" } }

local function on_hub_created(event)
  register_hub(event.entity or event.created_entity)
end

local function on_hub_destroyed(event)
  -- Clean up reserves for the destroyed hub.
  if event.entity and event.entity.unit_number and storage.reserved_items then
    storage.reserved_items[event.entity.unit_number] = nil
  end
  unregister_hub(event.entity)
end

-- Helper: get the total amount of an item that a hub is requesting via
-- interplatform imports. Returns 0 if the hub has no such request.
-- When planet_name is provided, only counts requests scoped to that planet.
local function get_hub_request_amount(hub, item_name, quality_name, planet_name)
  if not (hub and hub.valid) then
    return 0
  end

  local logistic_point = hub.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not logistic_point then
    return 0
  end

  local total = 0
  for_each_interplatform_item_request(
    logistic_point,
    function(filter, section, si, fi, filter_planet)
      local f_item = filter.value.name
      local f_quality = filter.value.quality or "normal"
      local requested_amount = filter.min or 0

      if f_item == item_name and f_quality == quality_name and requested_amount > 0 then
        if not planet_name or filter_planet == planet_name then
          total = total + requested_amount
        end
      end
    end
  )

  return total
end

-- Convenience wrapper: does this hub have any interplatform request for the item?
-- When planet_name is provided, only checks requests scoped to that planet.
local function platform_has_request_for_item(hub, item_name, quality_name, planet_name)
  return get_hub_request_amount(hub, item_name, quality_name, planet_name) > 0
end

-- Helper: check if all interplatform requests on a hub are satisfied.
-- Returns true if every interplatform request that matches the hub's
-- current orbit has enough items in the hub inventory. Requests scoped
-- to planets the hub is NOT orbiting are ignored (they cannot block).
local function all_requests_satisfied(hub)
  if not (hub and hub.valid) then
    return true
  end
  local logistic_point = hub.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not logistic_point then
    return true
  end
  local inventory = hub.get_inventory(defines.inventory.hub_main)
  if not inventory then
    return true
  end

  -- Determine the platform's current orbit planet name.
  local platform = hub.surface and hub.surface.platform
  local current_planet_name = platform and platform.space_location and platform.space_location.name

  local satisfied = true
  for_each_interplatform_item_request(logistic_point, function(filter, section, si, fi, planet_name)
    -- Skip requests scoped to a different planet — they can't block satisfaction.
    if planet_name and current_planet_name and planet_name ~= current_planet_name then
      return false
    end

    local item_name = filter.value.name
    local quality_name = filter.value.quality or "normal"
    local requested_amount = filter.min or 1
    local current = inventory.get_item_count { name = item_name, quality = quality_name }
    if current < requested_amount then
      satisfied = false
      return true -- stop early
    end
  end)
  return satisfied
end

-- Helper: check if a space-location prototype is an interplatform location.
local function is_interplatform_location(space_location)
  if not space_location then
    return false
  end
  local name = type(space_location) == "string" and space_location or space_location.name
  return name and name:sub(1, 14) == "interplatform-"
end

-- Helper: extract the planet name from an interplatform location name.
-- e.g. "interplatform-nauvis" -> "nauvis"
local function get_planet_name_from_interplatform(space_location)
  if not space_location then
    return nil
  end
  local name = type(space_location) == "string" and space_location or space_location.name
  if name and name:sub(1, 14) == "interplatform-" then
    return name:sub(15)
  end
  return nil
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

-- Helper: compute how many items are being sent *from* a given hub for a
-- specific item+quality pair, and which target platforms they are going to.
local function get_outgoing_for_item(hub, item_name, quality_name)
  local total = 0
  local targets = {}

  if not storage or not storage.active_deliveries then
    return 0, targets
  end

  for _, delivery in ipairs(storage.active_deliveries) do
    if
      delivery.source_hub == hub
      and delivery.item_name == item_name
      and delivery.quality_name == quality_name
    then
      total = total + delivery.count

      if delivery.target_platform and delivery.target_platform.valid then
        local name = delivery.target_platform.name or "(unknown platform)"
        targets[name] = true
      end
    end
  end

  return total, targets
end

-- Helper: get the reserve amount for a specific hub+item+quality pair.
-- Returns the number of items that should be kept on this hub and not
-- made available for interplatform transfers.
local function get_reserve_amount(hub_unit_number, item_name, quality_name)
  if not storage.reserved_items then
    return 0
  end
  local hub_reserves = storage.reserved_items[hub_unit_number]
  if not hub_reserves then
    return 0
  end
  local key = item_name .. "|" .. (quality_name or "normal")
  return hub_reserves[key] or 0
end

-- Helper: set the reserve amount for a specific hub+item+quality pair.
local function set_reserve_amount(hub_unit_number, item_name, quality_name, amount)
  if not storage.reserved_items then
    storage.reserved_items = {}
  end
  if not storage.reserved_items[hub_unit_number] then
    storage.reserved_items[hub_unit_number] = {}
  end
  local key = item_name .. "|" .. (quality_name or "normal")
  if amount and amount > 0 then
    storage.reserved_items[hub_unit_number][key] = amount
  else
    storage.reserved_items[hub_unit_number][key] = nil
    -- Clean up empty hub table
    if next(storage.reserved_items[hub_unit_number]) == nil then
      storage.reserved_items[hub_unit_number] = nil
    end
  end
end

-- Helper: iterate all reserves for a hub. Calls callback(item_name, quality_name, amount).
local function for_each_reserve(hub_unit_number, callback)
  if not storage.reserved_items then
    return
  end
  local hub_reserves = storage.reserved_items[hub_unit_number]
  if not hub_reserves then
    return
  end
  for key, amount in pairs(hub_reserves) do
    local item_name, quality_name = key:match "^(.+)|(.+)$"
    if item_name and quality_name and amount > 0 then
      callback(item_name, quality_name, amount)
    end
  end
end

-- Helper: iterate all logistic filters on a hub that request items from any
-- interplatform-* location. Calls the callback once per matching filter.
--
-- `callback(filter, section, section_index, filter_index, planet_name)`
-- where planet_name is the planet extracted from the interplatform location.
-- If the callback returns true, iteration stops early.
function for_each_interplatform_item_request(logistic_point, callback)
  if not logistic_point then
    return
  end

  local sections = logistic_point.sections
  if not sections or #sections == 0 then
    return
  end

  for section_index = 1, #sections do
    local section = sections[section_index]
    if section and section.active ~= false and section.filters then
      for filter_index, filter in ipairs(section.filters) do
        if
          filter
          and filter.value
          and filter.value.type == "item"
          and filter.import_from
          and is_interplatform_location(filter.import_from)
        then
          local planet_name = get_planet_name_from_interplatform(filter.import_from)
          if callback(filter, section, section_index, filter_index, planet_name) then
            return
          end
        end
      end
    end
  end
end

-- Backward-compatible alias for migration/transition
for_each_planetary_orbit_item_request = for_each_interplatform_item_request

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
      "You must research the Interplatform Requests technology before hub requests can use interplatform imports.",
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

-- Build (or rebuild) the reserves UI inside the given parent flow.
-- Called separately from the status table so the periodic refresh
-- doesn't destroy it (which would close any open item picker).
local function build_reserves_ui(parent_flow, hub)
  parent_flow.clear()

  local reserveFrame = parent_flow.add {
    type = "frame",
    style = "entity_frame",
    direction = "vertical",
  }

  local header_flow = reserveFrame.add { type = "flow", direction = "horizontal" }
  header_flow.add {
    type = "label",
    caption = { "", "[font=default-bold]Reserves[/font]" },
  }
  header_flow.add {
    type = "label",
    caption = "[img=info]",
    tooltip = "Reserve items to keep them on this hub.\nReserved amounts will not be sent to other platforms.\n\nLeft-click an item icon to change it.\nRight-click an item icon to remove the reserve.",
  }

  -- Collect all reserved item names for this hub so we can exclude them from pickers.
  local reserved_items = {}
  for_each_reserve(hub.unit_number, function(item_name, quality_name, amount)
    reserved_items[item_name] = true
  end)

  -- Show existing reserves as a table
  local reserve_table = nil

  for_each_reserve(hub.unit_number, function(item_name, quality_name, amount)
    if not reserve_table then
      reserve_table = reserveFrame.add {
        type = "table",
        name = "platform_reserves_table",
        column_count = 2,
      }
    end

    -- Item button: left-click to change item/quality, right-click to remove.
    -- Exclude other already-reserved items from the picker.
    local item_filters = {}
    for reserved_name, _ in pairs(reserved_items) do
      if reserved_name ~= item_name then
        table.insert(
          item_filters,
          { filter = "name", name = reserved_name, invert = true, mode = "and" }
        )
      end
    end
    reserve_table.add {
      type = "choose-elem-button",
      name = "ipr_reserve_item__" .. hub.unit_number .. "__" .. item_name .. "__" .. quality_name,
      elem_type = "item-with-quality",
      ["item-with-quality"] = { name = item_name, quality = quality_name },
      elem_filters = item_filters,
      tooltip = "Left-click: change item  Right-click: remove reserve",
    }

    -- Amount (editable textfield)
    local field = reserve_table.add {
      type = "textfield",
      name = "ipr_reserve_amount__" .. hub.unit_number .. "__" .. item_name .. "__" .. quality_name,
      text = tostring(amount),
      numeric = true,
      allow_decimal = false,
      allow_negative = false,
      style = "short_number_textfield",
    }
    field.style.width = 60
  end)

  -- Item picker: selecting an item auto-creates a reserve with amount 1.
  -- Exclude all already-reserved items from the picker.
  local picker_filters = {}
  for reserved_name, _ in pairs(reserved_items) do
    table.insert(
      picker_filters,
      { filter = "name", name = reserved_name, invert = true, mode = "and" }
    )
  end
  local add_flow = reserveFrame.add { type = "flow", direction = "horizontal" }
  add_flow.add {
    type = "choose-elem-button",
    name = "ipr_reserve_pick_item__" .. hub.unit_number,
    elem_type = "item-with-quality",
    elem_filters = picker_filters,
    tooltip = "Select an item to reserve on this hub",
  }
  add_flow.add {
    type = "label",
    caption = "[color=gray]Select item to add reserve[/color]",
  }
end

-- Build the incoming requests table (Need / Satisfaction / In transit / Available / From)
-- into the given container element. Only shown when there are active or
-- recently-satisfied incoming requests.
local function build_incoming_table(container, hub, platform)
  local incoming_table = nil
  local any_incoming = false

  local logistic_point = hub.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not logistic_point then
    return false
  end

  for_each_interplatform_item_request(logistic_point, function(filter, section, si, fi, planet_name)
    local item_name = filter.value.name
    local quality_name = filter.value.quality or "normal"
    local requested_amount = filter.min or 1

    -- Resolve the planet's actual space location for platform lookup.
    local planet_location = planet_name
      and prototypes.space_location
      and prototypes.space_location[planet_name]

    local hub_inventory = hub.get_inventory(defines.inventory.hub_main)
    local current_count = 0
    if hub_inventory then
      current_count = hub_inventory.get_item_count {
        name = item_name,
        quality = quality_name,
      }
    end

    local in_transit, in_transit_sources = get_in_transit_for_request(hub, item_name, quality_name)

    local available_on_other_platforms = 0
    local search_location = planet_location or (platform and platform.space_location)
    local other_platforms = search_location and get_platforms_at_location(search_location, platform)
      or {}
    if #other_platforms > 0 then
      for _, other in ipairs(other_platforms) do
        local other_hub = other.hub
        if other_hub and other_hub.valid then
          local inv = other_hub.get_inventory(defines.inventory.hub_main)
          if inv then
            local count = inv.get_item_count {
              name = item_name,
              quality = quality_name,
            }
            local reserve = get_reserve_amount(other_hub.unit_number, item_name, quality_name)
            local requested =
              get_hub_request_amount(other_hub, item_name, quality_name, planet_name)
            available_on_other_platforms = available_on_other_platforms
              + math.max(0, count - reserve - requested)
          end
        end
      end
    end

    local total_on_the_way = in_transit
    local still_needed = math.max(0, requested_amount - current_count)

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
      if game.tick - entry.last_change_tick <= REQUEST_COMPLETED_DISPLAY_TICKS then
        show_row = true
      end
    end

    if show_row then
      any_incoming = true

      if not incoming_table then
        container.add {
          type = "label",
          caption = { "", "[font=default-bold]Incoming[/font]" },
        }
        incoming_table = container.add {
          type = "table",
          name = "platform_requests_incoming_table",
          column_count = 11,
        }
        incoming_table.add { type = "label", caption = "" }
        incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }
        incoming_table.add {
          type = "label",
          caption = { "", "[font=default-bold]Need[/font]" },
        }
        incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }
        incoming_table.add {
          type = "label",
          caption = { "", "[font=default-bold]Satisfaction[/font]" },
        }
        incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }
        incoming_table.add {
          type = "label",
          caption = { "", "[font=default-bold]In transit[/font]" },
        }
        incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }
        incoming_table.add {
          type = "label",
          caption = { "", "[font=default-bold]Available[/font]" },
        }
        incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }
        incoming_table.add {
          type = "label",
          caption = { "", "[font=default-bold]From[/font]" },
        }
      end

      local source_list = {}
      for name, _ in pairs(in_transit_sources) do
        table.insert(source_list, name)
      end
      table.sort(source_list)
      local sources_str = table.concat(source_list, ", ")
      if sources_str == "" then
        sources_str = "-"
      end

      incoming_table.add {
        type = "choose-elem-button",
        elem_type = "item-with-quality",
        ["item-with-quality"] = { name = item_name, quality = quality_name },
        locked = true,
        tooltip = item_name,
        style = "slot_button_in_shallow_frame",
      }

      incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }

      local need_color = (still_needed == 0) and "green" or "orange"
      incoming_table.add {
        type = "label",
        caption = string.format("[color=%s]%d[/color]", need_color, still_needed),
        tooltip = "need: additional items required in this hub to reach the request",
      }

      incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }

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

      incoming_table.add {
        type = "label",
        caption = string.format(
          "[color=%s]%d[/color]/[color=green]%d[/color]",
          sat_color,
          satisfied_count,
          requested_amount
        ),
        tooltip = "satisfaction: items in this hub / requested amount (red <50%, yellow 50-99%, green >=100%)",
      }

      incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }

      incoming_table.add {
        type = "label",
        caption = (total_on_the_way > 0)
            and string.format("[color=yellow]%d[/color]", total_on_the_way)
          or string.format("[color=gray]%d[/color]", total_on_the_way),
        tooltip = "in transit: items already being delivered by Interplatform Requests",
      }

      incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }

      local available_color
      if available_on_other_platforms == 0 then
        available_color = "red"
      elseif still_needed > 0 and available_on_other_platforms < still_needed then
        available_color = "yellow"
      else
        available_color = "green"
      end

      incoming_table.add {
        type = "label",
        caption = string.format(
          "[color=%s]%d[/color]",
          available_color,
          available_on_other_platforms
        ),
        tooltip = "available: items currently stored on other platforms in the same orbit",
      }

      incoming_table.add { type = "label", caption = "[color=gray]|[/color]" }

      incoming_table.add {
        type = "label",
        caption = (sources_str ~= "-") and string.format("[color=cyan]%s[/color]", sources_str)
          or sources_str,
        tooltip = "Platforms currently sending this item",
      }
    end
    return false
  end)

  return any_incoming
end

-- Build the outgoing deliveries table (Item / Count / To) into the given
-- container element. Only shown when this hub is actively sending items.
local function build_outgoing_table(container, hub)
  if not storage.active_deliveries then
    return false
  end

  -- Collect unique outgoing item+quality pairs for this hub.
  local outgoing_items = {}
  local any_outgoing = false
  for _, delivery in ipairs(storage.active_deliveries) do
    if delivery.source_hub == hub then
      local key = delivery.item_name .. "|" .. delivery.quality_name
      if not outgoing_items[key] then
        outgoing_items[key] = {
          item_name = delivery.item_name,
          quality_name = delivery.quality_name,
          count = 0,
          targets = {},
        }
      end
      local entry = outgoing_items[key]
      entry.count = entry.count + delivery.count
      if delivery.target_platform and delivery.target_platform.valid then
        entry.targets[delivery.target_platform.name or "(unknown platform)"] = true
      end
      any_outgoing = true
    end
  end

  if not any_outgoing then
    return false
  end

  container.add {
    type = "label",
    caption = { "", "[font=default-bold]Outgoing[/font]" },
  }
  local outgoing_table = container.add {
    type = "table",
    name = "platform_requests_outgoing_table",
    column_count = 5,
  }
  outgoing_table.add { type = "label", caption = "" }
  outgoing_table.add { type = "label", caption = "[color=gray]|[/color]" }
  outgoing_table.add {
    type = "label",
    caption = { "", "[font=default-bold]Count[/font]" },
  }
  outgoing_table.add { type = "label", caption = "[color=gray]|[/color]" }
  outgoing_table.add {
    type = "label",
    caption = { "", "[font=default-bold]To[/font]" },
  }

  for _, info in pairs(outgoing_items) do
    outgoing_table.add {
      type = "choose-elem-button",
      elem_type = "item-with-quality",
      ["item-with-quality"] = { name = info.item_name, quality = info.quality_name },
      locked = true,
      tooltip = info.item_name,
      style = "slot_button_in_shallow_frame",
    }

    outgoing_table.add { type = "label", caption = "[color=gray]|[/color]" }

    outgoing_table.add {
      type = "label",
      caption = string.format("[color=yellow]%d[/color]", info.count),
      tooltip = "Number of items in transit from this hub",
    }

    outgoing_table.add { type = "label", caption = "[color=gray]|[/color]" }

    local target_list = {}
    for name, _ in pairs(info.targets) do
      table.insert(target_list, name)
    end
    table.sort(target_list)

    outgoing_table.add {
      type = "label",
      caption = string.format("[color=cyan]%s[/color]", table.concat(target_list, ", ")),
      tooltip = "Platforms this item is being sent to",
    }
  end

  return true
end

-- Build both incoming and outgoing status tables into the given container.
-- This is called both on initial GUI open and on periodic refresh.
local function build_status_table(container, hub, platform)
  local has_incoming = build_incoming_table(container, hub, platform)
  local has_outgoing = build_outgoing_table(container, hub)

  if not has_incoming and not has_outgoing then
    container.add {
      type = "label",
      caption = "No active interplatform transfers",
    }
  end
end

-- When a player opens a space platform hub GUI, show a summary of the
-- Interplatform Requests view for that hub so the player can see the true
-- "on the way" / "available on other platforms" values. This is rendered
-- in a small GUI panel next to the main game UI rather than as chat spam.
--
-- The panel structure is:
--   frame "platform_requests_status"
--     flow (vertical)
--       flow "ipr_status_container"   ← cleared & rebuilt every ~1s
--         frame (entity_frame)        ← status table or "all satisfied" label
--       flow "ipr_reserves_container" ← only rebuilt on reserve changes
--         frame (entity_frame)        ← reserves table + item picker
--
-- On first open, both containers are built. On periodic refresh, only the
-- status container is cleared and rebuilt — the reserves container (and any
-- open item picker) is left untouched.
local function on_hub_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == "space-platform-hub") then
    return
  end

  init_storage()

  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  -- Helper: destroy any stale panel left over from a previously viewed hub.
  local function destroy_stale_panel()
    local frame = player.gui.relative.platform_requests_status
    if frame then
      frame.destroy()
    end
  end

  local force = entity.force
  local tech = force and force.valid and force.technologies and force.technologies[TECHNOLOGY_NAME]
  if not (tech and tech.researched) then
    destroy_stale_panel()
    return
  end

  local hub = entity
  local platform = hub.surface and hub.surface.platform

  local anchor = {
    gui = defines.relative_gui_type.space_platform_hub_gui,
    position = defines.relative_gui_position.left,
  }

  -- Check if the panel already exists for this player and is for this hub.
  local frame = player.gui.relative.platform_requests_status

  if frame then
    local tags = frame.tags
    if tags and tags.hub_unit_number == hub.unit_number then
      -- Same hub — just refresh the status table, leave reserves alone.
      local flow_children = frame.children
      if flow_children and #flow_children >= 1 then
        local flow = flow_children[1]
        if flow and flow.valid then
          local containers = flow.children
          if containers and #containers >= 1 and containers[1].valid then
            containers[1].clear()
            local innerFrame = containers[1].add {
              type = "frame",
              style = "entity_frame",
              direction = "vertical",
            }
            build_status_table(innerFrame, hub, platform)

            -- Ensure reserves container exists.
            if not containers[2] or not containers[2].valid then
              local rc = flow.add { type = "flow", direction = "vertical" }
              build_reserves_ui(rc, hub)
            end

            if storage.viewed_hub_by_player then
              storage.viewed_hub_by_player[player.index] = hub.unit_number
            end
            return
          end
        end
      end
    end

    -- Different hub or broken structure — destroy and rebuild.
    frame.destroy()
    frame = nil
  end

  -- Build the full panel from scratch.
  frame = player.gui.relative.add {
    type = "frame",
    name = "platform_requests_status",
    direction = "vertical",
    anchor = anchor,
    caption = "Interplatform Requests",
    tags = { hub_unit_number = hub.unit_number },
  }

  local flow = frame.add { type = "flow", direction = "vertical" }

  -- Status container (refreshed every ~1s).
  local sc = flow.add { type = "flow", direction = "vertical" }
  local innerFrame = sc.add {
    type = "frame",
    style = "entity_frame",
    direction = "vertical",
  }
  build_status_table(innerFrame, hub, platform)

  -- Reserves container (only rebuilt on reserve changes).
  local rc = flow.add { type = "flow", direction = "vertical" }
  build_reserves_ui(rc, hub)

  -- "Hold until satisfied" checkbox.
  local hold_checked = storage.hold_until_satisfied
      and storage.hold_until_satisfied[hub.unit_number]
    or false
  local hold_frame = flow.add {
    type = "frame",
    style = "entity_frame",
    direction = "horizontal",
  }
  hold_frame.add {
    type = "checkbox",
    name = "ipr_hold_until_satisfied__" .. hub.unit_number,
    caption = "Hold until requests satisfied",
    tooltip = "When checked, the platform will be paused while any interplatform request is not fully satisfied.",
    state = hold_checked,
  }

  if storage.viewed_hub_by_player then
    storage.viewed_hub_by_player[player.index] = hub.unit_number
  end
end

-- Refresh the status table for any players currently viewing this hub.
-- Only rebuilds the status portion of the panel; reserves are untouched.
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

-- Helper: refresh the hub GUI for a player after a reserve change.
-- Destroys the entire panel so both status and reserves are rebuilt.
local function refresh_hub_for_player(player_index)
  local player = game.get_player(player_index)
  if player and player.valid then
    -- Destroy the panel so it's fully rebuilt with updated reserves.
    if player.gui.relative.platform_requests_status then
      player.gui.relative.platform_requests_status.destroy()
    end
    local opened = player.opened
    if opened and opened.valid and opened.name == "space-platform-hub" then
      on_hub_gui_opened {
        entity = opened,
        player_index = player_index,
      }
    end
  end
end

-- Handle clicks in our custom UI
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

    refresh_hub_for_player(event.player_index)
    return
  end

  -- Reserve: remove
  hub_id, item_name, quality_name = element.name:match "^ipr_reserve_remove__(%d+)__(.+)__(.+)$"
  if hub_id then
    hub_id = tonumber(hub_id)
    set_reserve_amount(hub_id, item_name, quality_name, 0)
    refresh_hub_for_player(event.player_index)
    return
  end
end

script.on_event(defines.events.on_gui_click, on_gui_click)

-- Handle Enter key in reserve amount textfields
local function on_gui_confirmed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  -- Existing reserve amount field confirmed
  local hub_id, item_name, quality_name =
    element.name:match "^ipr_reserve_amount__(%d+)__(.+)__(.+)$"
  if hub_id then
    hub_id = tonumber(hub_id)
    local amount = tonumber(element.text) or 0
    set_reserve_amount(hub_id, item_name, quality_name, amount)
    refresh_hub_for_player(event.player_index)
    return
  end
end

script.on_event(defines.events.on_gui_confirmed, on_gui_confirmed)

-- When the player selects an item in the reserve picker, immediately
-- create a reserve with amount 1 and rebuild the reserves section.
local function on_gui_elem_changed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  -- New reserve picker: add a reserve with amount 1.
  local hub_id = element.name:match "^ipr_reserve_pick_item__(%d+)$"
  if hub_id then
    hub_id = tonumber(hub_id)
    local picked = element.elem_value
    if picked and type(picked) == "table" and picked.name and picked.name ~= "" then
      local quality = picked.quality or "normal"
      set_reserve_amount(hub_id, picked.name, quality, 1)
      refresh_hub_for_player(event.player_index)
    end
    return
  end

  -- Existing reserve item button: change item (left-click selects new item)
  -- or clear (right-click clears the button, which sets elem_value to nil).
  local hub_id2, old_item, old_quality = element.name:match "^ipr_reserve_item__(%d+)__(.+)__(.+)$"
  if hub_id2 then
    hub_id2 = tonumber(hub_id2)
    local picked = element.elem_value
    if picked and type(picked) == "table" and picked.name and picked.name ~= "" then
      -- Left-click selected a new item: transfer the reserve amount.
      local new_item = picked.name
      local new_quality = picked.quality or "normal"
      if new_item ~= old_item or new_quality ~= old_quality then
        local old_amount = get_reserve_amount(hub_id2, old_item, old_quality)
        set_reserve_amount(hub_id2, old_item, old_quality, 0)
        set_reserve_amount(hub_id2, new_item, new_quality, old_amount > 0 and old_amount or 1)
      end
    else
      -- Right-click cleared the button: remove the reserve.
      set_reserve_amount(hub_id2, old_item, old_quality, 0)
    end
    refresh_hub_for_player(event.player_index)
    return
  end
end

script.on_event(defines.events.on_gui_elem_changed, on_gui_elem_changed)

-- Save reserve amount as the user types (no confirm button needed).
local function on_gui_text_changed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  local hub_id, item_name, quality_name =
    element.name:match "^ipr_reserve_amount__(%d+)__(.+)__(.+)$"
  if hub_id then
    hub_id = tonumber(hub_id)
    local amount = tonumber(element.text) or 0
    set_reserve_amount(hub_id, item_name, quality_name, amount)
  end
end

script.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)

-- Handle "Hold until requests satisfied" checkbox.
local function on_gui_checked_state_changed(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end

  local hub_id = element.name:match "^ipr_hold_until_satisfied__(%d+)$"
  if hub_id then
    hub_id = tonumber(hub_id)
    init_storage()
    storage.hold_until_satisfied[hub_id] = element.state

    -- If unchecked, immediately unpause if we were the ones who paused it.
    if not element.state and storage.mod_paused_platforms[hub_id] then
      storage.mod_paused_platforms[hub_id] = nil
      local hub_data = storage.monitored_hubs[hub_id]
      if hub_data and hub_data.platform and hub_data.platform.valid then
        hub_data.platform.paused = false
      end
    end
  end
end

script.on_event(defines.events.on_gui_checked_state_changed, on_gui_checked_state_changed)

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
  -- an interplatform location before the tech is researched, show a warning.
  local player = game.get_player(event.player_index)
  if player then
    local force = entity.force
    local tech = force
      and force.valid
      and force.technologies
      and force.technologies[TECHNOLOGY_NAME]
    if not (tech and tech.researched) then
      local logistic_point =
        entity.get_logistic_point(defines.logistic_member_index.logistic_container)
      if logistic_point then
        local sections = logistic_point.sections
        if sections then
          local found = false
          for _, section in ipairs(sections) do
            if section and section.filters then
              for _, filter in ipairs(section.filters) do
                if
                  filter
                  and filter.import_from
                  and is_interplatform_location(filter.import_from)
                then
                  found = true
                  break
                end
              end
              if found then
                break
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
      local inventory = hub.get_inventory(defines.inventory.hub_main)
      if inventory then
        local count = inventory.get_item_count { name = item_name, quality = quality_name }
        -- Subtract the reserve amount — items the source hub wants to keep.
        local reserve = get_reserve_amount(hub.unit_number, item_name, quality_name)
        -- Subtract the hub's own interplatform request — don't take items
        -- the source hub is itself trying to accumulate.
        local requested = get_hub_request_amount(hub, item_name, quality_name)
        local available = count - reserve - requested
        if available > 0 then
          return hub, inventory
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

  -- Keep the list of monitored hubs up-to-date.
  --
  -- In theory, new hubs should always be registered via build events
  -- (on_built_entity / on_robot_built_entity / on_space_platform_built_entity),
  -- but in practice some edge cases on servers meant newly created hubs
  -- wouldn't be picked up until the player manually ran
  -- /c remote.call("interplatform-requests", "scan_hubs").
  --
  -- To make this robust, we simply rescan for hubs any time the periodic
  -- processing runs. This is cheap (platform hubs are rare) and ensures that
  -- any hubs missed by build events are discovered automatically within at
  -- most SCAN_INTERVAL ticks.
  if scan_all_hubs then
    scan_all_hubs()
  end

  for unit_number, hub_data in pairs(storage.monitored_hubs) do
    local hub = hub_data.entity

    if not hub or not hub.valid then
      storage.monitored_hubs[unit_number] = nil
      if storage.hold_until_satisfied then
        storage.hold_until_satisfied[unit_number] = nil
      end
      if storage.mod_paused_platforms then
        storage.mod_paused_platforms[unit_number] = nil
      end
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
            for_each_interplatform_item_request(
              logistic_point,
              function(filter, section, si, fi, planet_name)
                if launches_this_scan >= 1 or active_delivery_count >= MAX_CONCURRENT_TRANSFERS then
                  return true -- stop early for this hub
                end

                -- Planet-orbit matching: only process if the hub is orbiting the
                -- planet this request is scoped to.
                if planet_name then
                  local current_planet = platform.space_location and platform.space_location.name
                  if current_planet ~= planet_name then
                    debug_print(
                      string.format(
                        "Interplatform Requests: Skipping %s request on %s (orbiting %s, not %s)",
                        filter.value.name,
                        platform.name,
                        current_planet or "unknown",
                        planet_name
                      )
                    )
                    return false -- skip, check next request
                  end
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
                local in_transit =
                  select(1, get_in_transit_for_request(hub, item_name, quality_name))

                local total_count = current_count + in_transit
                local needed = requested_amount - total_count

                -- If we need more, try to get from other platforms, but respect the per-hub
                -- concurrency limit and rate-limit new launches.
                if total_count >= requested_amount then
                  return false
                end

                -- Resolve the planet's actual space location for platform lookup.
                local planet_location = planet_name
                  and prototypes.space_location
                  and prototypes.space_location[planet_name]
                local search_location = planet_location or platform.space_location
                local other_platforms = get_platforms_at_location(search_location, platform)
                if #other_platforms == 0 then
                  return false
                end

                -- Filter out platforms where the source has a conflicting request
                -- (pairwise conflict detection: skip if source also requests this item+quality+planet).
                local eligible_platforms = {}
                for _, other in ipairs(other_platforms) do
                  local other_hub = other.hub
                  if other_hub and other_hub.valid then
                    if
                      platform_has_request_for_item(other_hub, item_name, quality_name, planet_name)
                    then
                      debug_print(
                        string.format(
                          "Interplatform Requests: Conflict — %s also requests %s (%s) for %s, skipping",
                          other.name or "unknown",
                          item_name,
                          quality_name,
                          planet_name or "any"
                        )
                      )
                    else
                      table.insert(eligible_platforms, other)
                    end
                  else
                    table.insert(eligible_platforms, other)
                  end
                end

                if #eligible_platforms == 0 then
                  return false
                end

                local source_hub, source_inventory =
                  find_item_in_platforms(eligible_platforms, item_name, quality_name)
                if not (source_hub and source_inventory) then
                  return false
                end

                -- Transfer items via cargo pod
                local raw_available = source_inventory.get_item_count {
                  name = item_name,
                  quality = quality_name,
                }
                -- Respect the source hub's reserve and its own interplatform
                -- request — only offer what exceeds both.
                local source_reserve =
                  get_reserve_amount(source_hub.unit_number, item_name, quality_name)
                local source_requested = get_hub_request_amount(source_hub, item_name, quality_name)
                local available = math.max(0, raw_available - source_reserve - source_requested)
                local to_transfer = math.min(needed, available)

                -- Cap each transfer using both the item's stack size and any custom minimum payload.
                local stack_size = get_item_stack_size(item_name)
                local cap = stack_size
                if
                  stack_size
                  and stack_size > 0
                  and min_payload > 0
                  and min_payload < stack_size
                then
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

                -- Launch a cargo pod from the source hub to the target platform
                local source_platform = source_hub.surface.platform
                local pod = source_hub.create_cargo_pod()

                if pod then
                  pod.cargo_pod_destination = {
                    type = defines.cargo_destination.surface,
                    surface = hub.surface,
                    transform_launch_products = false,
                  }

                  local pod_inventory = pod.get_inventory(defines.inventory.cargo_unit)
                  if pod_inventory then
                    pod_inventory.insert {
                      name = item_name,
                      quality = quality_name,
                      count = removed,
                    }
                  end

                  table.insert(storage.active_deliveries, {
                    cargo_pod = pod,
                    source_hub = source_hub,
                    target_hub = hub,
                    target_platform = platform,
                    source_platform = source_platform,
                    start_tick = game.tick,
                    item_name = item_name,
                    quality_name = quality_name,
                    count = removed,
                  })

                  active_delivery_count = active_delivery_count + 1
                  launches_this_scan = launches_this_scan + 1

                  debug_print(
                    string.format(
                      "Interplatform Requests: Sending %dx %s from %s to %s via cargo pod",
                      removed,
                      item_name,
                      source_platform.name,
                      platform.name
                    )
                  )

                  refresh_status_for_hub(hub)
                  refresh_status_for_hub(source_hub)
                else
                  -- Fallback: instant transfer if cargo pod creation fails
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
              end
            )
          end
        end
      end

      -- After processing all requests for this hub, refresh overlays for any
      -- players currently viewing it so that completed requests can age out
      -- and disappear after the configured grace period.
      refresh_status_for_hub(hub)

      -- Hold platform if "Hold until requests satisfied" is enabled.
      if storage.hold_until_satisfied[unit_number] then
        if all_requests_satisfied(hub) then
          -- Requests satisfied — unpause if we were the ones who paused it.
          if storage.mod_paused_platforms[unit_number] then
            storage.mod_paused_platforms[unit_number] = nil
            if platform and platform.valid then
              platform.paused = false
            end
          end
        else
          -- Requests not yet satisfied — pause the platform if not already paused.
          if platform and platform.valid and not platform.paused then
            platform.paused = true
            storage.mod_paused_platforms[unit_number] = true
          end
        end
      end
    end
  end
end

-- Clean up completed cargo pod deliveries
local function process_deliveries()
  init_storage()

  if not storage.active_deliveries then
    return
  end

  for i = #storage.active_deliveries, 1, -1 do
    local delivery = storage.active_deliveries[i]

    if not delivery then
      table.remove(storage.active_deliveries, i)
    elseif not delivery.cargo_pod or not delivery.cargo_pod.valid then
      -- Cargo pod has landed and been consumed; delivery is complete
      debug_print(
        string.format(
          "Interplatform Requests: Delivered %dx %s to %s",
          delivery.count,
          delivery.item_name,
          delivery.target_platform
              and delivery.target_platform.valid
              and delivery.target_platform.name
            or "(unknown)"
        )
      )
      table.remove(storage.active_deliveries, i)
      refresh_status_for_hub(delivery.target_hub)
      refresh_status_for_hub(delivery.source_hub)
    end
  end
end

-- Register the periodic check — process hub requests and clean up deliveries in a single handler
script.on_nth_tick(SCAN_INTERVAL, function(event)
  process_hub_requests()
  process_deliveries()
end)

-- Migrate existing saves from the old "Planetary Orbit" system to per-planet
-- interplatform locations. This runs once on configuration change when an old
-- save is loaded with the updated mod.
function migrate_planetary_orbit_to_per_planet()
  init_storage()

  -- Check if the old planetary-orbit prototype still exists. If it does, we
  -- don't need to migrate (or migration already happened).
  local old_proto = prototypes.space_location and prototypes.space_location["planetary-orbit"]
  if old_proto then
    return -- old prototype still present, no migration needed
  end

  local migrated_count = 0

  for unit_number, hub_data in pairs(storage.monitored_hubs) do
    local hub = hub_data.entity
    local plat = hub_data.platform
    if hub and hub.valid and plat and plat.valid and plat.space_location then
      local current_planet = plat.space_location.name
      local new_proto = prototypes.space_location
        and prototypes.space_location["interplatform-" .. current_planet]

      if new_proto then
        local logistic_point =
          hub.get_logistic_point(defines.logistic_member_index.logistic_container)
        if logistic_point and logistic_point.sections then
          for _, section in ipairs(logistic_point.sections) do
            if section and section.filters then
              for fi, filter in ipairs(section.filters) do
                if
                  filter
                  and filter.import_from
                  and type(filter.import_from) == "table"
                  and filter.import_from.name == "planetary-orbit"
                then
                  filter.import_from = new_proto
                  migrated_count = migrated_count + 1
                  debug_print(
                    string.format(
                      "Interplatform Requests: Migrated request on hub %d → interplatform-%s",
                      unit_number,
                      current_planet
                    )
                  )
                end
              end
            end
          end
        end
      end
    end
  end

  if migrated_count > 0 then
    debug_print(
      string.format(
        "Interplatform Requests: Migration complete — %d request(s) converted to per-planet",
        migrated_count
      )
    )
  end
end

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

-- Remote interface for testing and external access
remote.add_interface("interplatform-requests", {
  process_now = function()
    debug_print "Manually triggering platform request processing..."
    process_hub_requests()
  end,
  scan_hubs = function()
    scan_all_hubs()
  end,
  migrate = function()
    migrate_planetary_orbit_to_per_planet()
  end,
  -- Exposed for automated testing
  get_reserve_amount = get_reserve_amount,
  set_reserve_amount = set_reserve_amount,
  for_each_reserve = for_each_reserve,
  get_hub_request_amount = get_hub_request_amount,
  platform_has_request_for_item = platform_has_request_for_item,
  all_requests_satisfied = all_requests_satisfied,
  get_in_transit_for_request = get_in_transit_for_request,
  get_outgoing_for_item = get_outgoing_for_item,
  find_item_in_platforms = find_item_in_platforms,
  is_interplatform_location = is_interplatform_location,
  get_planet_name_from_interplatform = get_planet_name_from_interplatform,
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
