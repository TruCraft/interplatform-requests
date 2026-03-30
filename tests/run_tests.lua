-- Simple Lua unit tests for Interplatform Requests.
-- These run in CI on GitHub Actions using a stubbed Factorio runtime.

local failures = 0

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      (message or "values are not equal")
        .. string.format(" (expected %s, got %s)", tostring(expected), tostring(actual)),
      2
    )
  end
end

local function assert_true(condition, message)
  if not condition then
    error(message or "assert_true failed", 2)
  end
end

local function assert_nil(value, message)
  if value ~= nil then
    error((message or "expected nil") .. string.format(" (got %s)", tostring(value)), 2)
  end
end

local function test(name, fn)
  io.stdout:write("TEST " .. name .. " ... ")
  local ok, err = pcall(fn)
  if ok then
    io.stdout:write "OK\n"
  else
    io.stdout:write "FAIL\n"
    io.stderr:write("  " .. tostring(err) .. "\n")
    failures = failures + 1
  end
end

-- ---------------------------------------------------------------------------
-- Stub Factorio runtime globals so we can require control.lua in plain Lua
-- ---------------------------------------------------------------------------

storage = {}

game = {
  tick = 0,
  surfaces = {},
  print = function(_) end,
  get_player = function(_)
    return nil
  end,
}

-- Per-planet interplatform prototypes + planet prototypes
prototypes = {
  space_location = {
    ["nauvis"] = { name = "nauvis" },
    ["vulcanus"] = { name = "vulcanus" },
    ["fulgora"] = { name = "fulgora" },
    ["interplatform-nauvis"] = { name = "interplatform-nauvis" },
    ["interplatform-vulcanus"] = { name = "interplatform-vulcanus" },
    ["interplatform-fulgora"] = { name = "interplatform-fulgora" },
  },
  item = {
    ["iron-plate"] = { stack_size = 100 },
    ["copper-plate"] = { stack_size = 100 },
    ["steel-plate"] = { stack_size = 100 },
  },
}

local events_mt = {
  __index = function(t, k)
    local v = k
    rawset(t, k, v)
    return v
  end,
}

defines = {
  logistic_member_index = { logistic_container = 1 },
  inventory = { hub_main = 1, cargo_unit = 2 },
  relative_gui_type = { space_platform_hub_gui = 1 },
  relative_gui_position = { left = 1 },
  cargo_destination = { surface = 1 },
  events = setmetatable({}, events_mt),
}

-- Script stub: capture registered handlers so tests can invoke them.
script = {
  _on_init = nil,
  _on_configuration_changed = nil,
  _events = {},
  _nth_tick = {},
}

function script.on_init(handler)
  script._on_init = handler
end

function script.on_configuration_changed(handler)
  script._on_configuration_changed = handler
end

function script.on_event(event_id, handler, filter)
  script._events[event_id] = { handler = handler, filter = filter }
end

function script.on_nth_tick(tick, handler)
  script._nth_tick[tick] = handler
end

-- Remote stub: store interfaces so tests can call them if needed.
remote = {
  interfaces = {},
}

-- Commands stub: capture registered commands.
commands = {}

function commands.add_command(name, help, handler)
  commands[name] = { help = help, handler = handler }
end

function remote.add_interface(name, iface)
  remote.interfaces[name] = iface
end

-- Load the actual mod control script in this stubbed environment.
dofile "control.lua"

-- ---------------------------------------------------------------------------
-- Shorthand access to remote-exposed functions
-- ---------------------------------------------------------------------------

local ipr = remote.interfaces["interplatform-requests"]

-- Per-planet prototype references for tests
local nauvis_proto = prototypes.space_location["interplatform-nauvis"]
local vulcanus_proto = prototypes.space_location["interplatform-vulcanus"]
local fulgora_proto = prototypes.space_location["interplatform-fulgora"]

-- ---------------------------------------------------------------------------
-- Helper: reset storage to a clean state
-- ---------------------------------------------------------------------------

local function reset_storage()
  storage = {}
  game.surfaces = {}
  game.tick = 0
  script._on_init()
end

-- ---------------------------------------------------------------------------
-- Helper: create a fake inventory backed by a contents table
-- ---------------------------------------------------------------------------

local function make_inventory(contents)
  contents = contents or {}
  return {
    get_item_count = function(filter)
      local key = filter.name .. "|" .. (filter.quality or "normal")
      return contents[key] or 0
    end,
    insert = function(item)
      local key = item.name .. "|" .. (item.quality or "normal")
      contents[key] = (contents[key] or 0) + item.count
      return item.count
    end,
    remove = function(item)
      local key = item.name .. "|" .. (item.quality or "normal")
      local have = contents[key] or 0
      local removed = math.min(have, item.count)
      contents[key] = have - removed
      return removed
    end,
    _contents = contents,
  }
end

-- ---------------------------------------------------------------------------
-- Helper: create a fake logistic point with sections
-- ---------------------------------------------------------------------------

local function make_logistic_point(sections)
  return { sections = sections }
end

-- ---------------------------------------------------------------------------
-- Helper: create a fake hub entity
-- ---------------------------------------------------------------------------

local function make_hub(unit_number, opts)
  opts = opts or {}
  local inv = opts.inventory or make_inventory()
  local lp = opts.logistic_point
  local platform = opts.platform
  local surface = opts.surface or { platform = platform }
  return {
    valid = true,
    name = "space-platform-hub",
    unit_number = unit_number,
    surface = surface,
    force = opts.force or {
      valid = true,
      technologies = {
        ["interplatform-requests"] = { researched = true },
      },
    },
    get_logistic_point = function(idx)
      return lp
    end,
    get_inventory = function(idx)
      return inv
    end,
    create_cargo_pod = function()
      return nil
    end,
  }
end

-- ---------------------------------------------------------------------------
-- Tests for for_each_interplatform_item_request
-- ---------------------------------------------------------------------------

test("for_each_interplatform_item_request filters and invokes callback", function()
  local calls = {}

  local logistic_point = {
    sections = {
      {
        filters = {
          {
            value = { type = "item", name = "iron-plate" },
            import_from = nauvis_proto,
            min = 10,
          },
          { value = { type = "item", name = "copper-plate" }, import_from = nil, min = 5 },
        },
      },
      {
        filters = {
          { value = { type = "fluid", name = "water" }, import_from = nauvis_proto, min = 1 },
        },
      },
    },
  }

  for_each_interplatform_item_request(
    logistic_point,
    function(filter, section, section_index, filter_index, planet_name)
      table.insert(calls, {
        item = filter.value.name,
        section_index = section_index,
        filter_index = filter_index,
        planet_name = planet_name,
      })
      return false
    end
  )

  assert_equal(#calls, 1, "expected exactly one matching filter")
  assert_equal(calls[1].item, "iron-plate", "expected to see iron-plate request")
  assert_equal(calls[1].section_index, 1)
  assert_equal(calls[1].filter_index, 1)
  assert_equal(calls[1].planet_name, "nauvis")
end)

test("for_each_interplatform_item_request stops when callback returns true", function()
  local logistic_point = {
    sections = {
      {
        filters = {
          {
            value = { type = "item", name = "iron-plate" },
            import_from = nauvis_proto,
            min = 10,
          },
          {
            value = { type = "item", name = "steel-plate" },
            import_from = nauvis_proto,
            min = 15,
          },
        },
      },
    },
  }

  local seen = {}
  for_each_interplatform_item_request(logistic_point, function(filter)
    table.insert(seen, filter.value.name)
    return true -- stop after first match
  end)

  assert_equal(#seen, 1, "expected early stop after first callback returning true")
  assert_equal(seen[1], "iron-plate")
end)

test("for_each_interplatform_item_request handles empty or missing sections", function()
  local calls = 0

  for_each_interplatform_item_request({ sections = {} }, function()
    calls = calls + 1
  end)

  for_each_interplatform_item_request({ sections = nil }, function()
    calls = calls + 1
  end)

  assert_equal(calls, 0, "expected no callbacks for empty/missing sections")
end)

-- ---------------------------------------------------------------------------
-- Tests for inactive section filtering
-- ---------------------------------------------------------------------------

test("inactive sections are skipped", function()
  local calls = {}

  local logistic_point = {
    sections = {
      {
        active = false,
        filters = {
          {
            value = { type = "item", name = "iron-plate" },
            import_from = nauvis_proto,
            min = 10,
          },
        },
      },
    },
  }

  for_each_interplatform_item_request(logistic_point, function(filter)
    table.insert(calls, filter.value.name)
  end)

  assert_equal(#calls, 0, "inactive section should be skipped")
end)

test("active sections are processed", function()
  local calls = {}

  local logistic_point = {
    sections = {
      {
        active = true,
        filters = {
          {
            value = { type = "item", name = "iron-plate" },
            import_from = nauvis_proto,
            min = 10,
          },
        },
      },
    },
  }

  for_each_interplatform_item_request(logistic_point, function(filter)
    table.insert(calls, filter.value.name)
  end)

  assert_equal(#calls, 1, "active section should be processed")
  assert_equal(calls[1], "iron-plate")
end)

test("section.active nil treated as active", function()
  local calls = {}

  local logistic_point = {
    sections = {
      {
        -- active field absent (nil)
        filters = {
          {
            value = { type = "item", name = "copper-plate" },
            import_from = nauvis_proto,
            min = 5,
          },
        },
      },
    },
  }

  for_each_interplatform_item_request(logistic_point, function(filter)
    table.insert(calls, filter.value.name)
  end)

  assert_equal(#calls, 1, "nil active should be treated as active")
  assert_equal(calls[1], "copper-plate")
end)

test("mix of active and inactive sections", function()
  local calls = {}

  local logistic_point = {
    sections = {
      {
        active = true,
        filters = {
          {
            value = { type = "item", name = "iron-plate" },
            import_from = nauvis_proto,
            min = 10,
          },
        },
      },
      {
        active = false,
        filters = {
          {
            value = { type = "item", name = "copper-plate" },
            import_from = nauvis_proto,
            min = 5,
          },
        },
      },
      {
        filters = {
          {
            value = { type = "item", name = "steel-plate" },
            import_from = vulcanus_proto,
            min = 20,
          },
        },
      },
    },
  }

  for_each_interplatform_item_request(logistic_point, function(filter)
    table.insert(calls, filter.value.name)
  end)

  assert_equal(#calls, 2, "expected 2 matches (skipping inactive)")
  assert_equal(calls[1], "iron-plate")
  assert_equal(calls[2], "steel-plate")
end)

-- ---------------------------------------------------------------------------
-- Tests for per-planet request iteration (T013)
-- ---------------------------------------------------------------------------

test("for_each_interplatform_item_request iterates requests from different planets", function()
  local calls = {}

  local logistic_point = {
    sections = {
      {
        filters = {
          {
            value = { type = "item", name = "iron-plate" },
            import_from = nauvis_proto,
            min = 10,
          },
          {
            value = { type = "item", name = "copper-plate" },
            import_from = vulcanus_proto,
            min = 20,
          },
        },
      },
    },
  }

  for_each_interplatform_item_request(logistic_point, function(filter, s, si, fi, planet_name)
    table.insert(calls, { item = filter.value.name, planet = planet_name })
  end)

  assert_equal(#calls, 2, "expected two matching filters from different planets")
  assert_equal(calls[1].item, "iron-plate")
  assert_equal(calls[1].planet, "nauvis")
  assert_equal(calls[2].item, "copper-plate")
  assert_equal(calls[2].planet, "vulcanus")
end)

-- ---------------------------------------------------------------------------
-- Tests for is_interplatform_location / get_planet_name_from_interplatform
-- ---------------------------------------------------------------------------

test("is_interplatform_location returns true for interplatform protos", function()
  assert_true(ipr.is_interplatform_location(nauvis_proto))
  assert_true(ipr.is_interplatform_location(vulcanus_proto))
end)

test("is_interplatform_location returns false for non-interplatform protos", function()
  assert_true(not ipr.is_interplatform_location { name = "nauvis" })
  assert_true(not ipr.is_interplatform_location(nil))
end)

test("get_planet_name_from_interplatform extracts planet name", function()
  assert_equal(ipr.get_planet_name_from_interplatform(nauvis_proto), "nauvis")
  assert_equal(ipr.get_planet_name_from_interplatform(vulcanus_proto), "vulcanus")
end)

test("get_planet_name_from_interplatform returns nil for non-interplatform", function()
  assert_nil(ipr.get_planet_name_from_interplatform { name = "nauvis" })
  assert_nil(ipr.get_planet_name_from_interplatform(nil))
end)

-- ---------------------------------------------------------------------------
-- Tests for storage initialization and hub scanning
-- ---------------------------------------------------------------------------

test("scan_all_hubs initializes storage and registers hubs on platform surfaces", function()
  storage = {}

  local platform = { valid = true, name = "test-platform" }
  local surface = {}

  function surface.find_entities_filtered(opts)
    assert_equal(opts.name, "space-platform-hub", "expected filter by space-platform-hub name")
    return {
      { name = "space-platform-hub", valid = true, unit_number = 1, surface = surface },
      { name = "space-platform-hub", valid = true, unit_number = 2, surface = surface },
    }
  end

  surface.platform = platform

  game.surfaces = { surface }

  scan_all_hubs()

  assert_true(storage.monitored_hubs ~= nil, "monitored_hubs should be initialized")
  assert_true(storage.active_deliveries ~= nil, "active_deliveries should be initialized")
  assert_true(storage.viewed_hub_by_player ~= nil, "viewed_hub_by_player should be initialized")
  assert_true(storage.request_status ~= nil, "request_status should be initialized")
  assert_true(storage.hold_until_satisfied ~= nil, "hold_until_satisfied should be initialized")
  assert_true(storage.mod_paused_platforms ~= nil, "mod_paused_platforms should be initialized")
  assert_true(storage.do_not_fulfill_from ~= nil, "do_not_fulfill_from should be initialized")
  assert_equal(storage.debug_logging, false, "debug_logging should default to false")

  assert_true(storage.monitored_hubs[1] ~= nil, "hub 1 should be registered")
  assert_true(storage.monitored_hubs[2] ~= nil, "hub 2 should be registered")
  assert_equal(
    storage.monitored_hubs[1].platform,
    platform,
    "hub platform should match surface.platform"
  )
end)

test("script.on_init handler is registered and initializes storage", function()
  assert_true(type(script._on_init) == "function", "script.on_init handler should be registered")

  storage = {}
  game.surfaces = {}

  script._on_init()

  assert_true(storage.monitored_hubs ~= nil, "monitored_hubs should be initialized on on_init")
  assert_true(
    storage.active_deliveries ~= nil,
    "active_deliveries should be initialized on on_init"
  )
  assert_true(
    storage.viewed_hub_by_player ~= nil,
    "viewed_hub_by_player should be initialized on on_init"
  )
  assert_true(storage.request_status ~= nil, "request_status should be initialized on on_init")
  assert_true(
    storage.hold_until_satisfied ~= nil,
    "hold_until_satisfied should be initialized on on_init"
  )
  assert_true(
    storage.mod_paused_platforms ~= nil,
    "mod_paused_platforms should be initialized on on_init"
  )
  assert_true(
    storage.do_not_fulfill_from ~= nil,
    "do_not_fulfill_from should be initialized on on_init"
  )
end)

-- ---------------------------------------------------------------------------
-- Tests for reserve system
-- ---------------------------------------------------------------------------

test("set_reserve_amount stores value and get_reserve_amount retrieves it", function()
  reset_storage()
  ipr.set_reserve_amount(42, "iron-plate", "normal", 50)
  assert_equal(ipr.get_reserve_amount(42, "iron-plate", "normal"), 50)
end)

test("get_reserve_amount returns 0 for unset item", function()
  reset_storage()
  assert_equal(ipr.get_reserve_amount(42, "copper-plate", "normal"), 0)
end)

test("get_reserve_amount returns 0 when reserved_items is nil", function()
  reset_storage()
  storage.reserved_items = nil
  assert_equal(ipr.get_reserve_amount(42, "iron-plate", "normal"), 0)
end)

test("set_reserve_amount with 0 removes entry and cleans up empty hub table", function()
  reset_storage()
  ipr.set_reserve_amount(42, "iron-plate", "normal", 10)
  assert_equal(ipr.get_reserve_amount(42, "iron-plate", "normal"), 10)

  ipr.set_reserve_amount(42, "iron-plate", "normal", 0)
  assert_equal(ipr.get_reserve_amount(42, "iron-plate", "normal"), 0)
  assert_nil(storage.reserved_items[42], "empty hub table should be cleaned up")
end)

test("set_reserve_amount with nil amount removes entry", function()
  reset_storage()
  ipr.set_reserve_amount(42, "iron-plate", "normal", 10)
  ipr.set_reserve_amount(42, "iron-plate", "normal", nil)
  assert_equal(ipr.get_reserve_amount(42, "iron-plate", "normal"), 0)
end)

test("reserve quality defaults to normal when nil", function()
  reset_storage()
  ipr.set_reserve_amount(1, "iron-plate", nil, 10)
  assert_equal(ipr.get_reserve_amount(1, "iron-plate", nil), 10)
  assert_equal(ipr.get_reserve_amount(1, "iron-plate", "normal"), 10)
end)

test("for_each_reserve iterates all reserves for a hub", function()
  reset_storage()
  ipr.set_reserve_amount(1, "iron-plate", "normal", 10)
  ipr.set_reserve_amount(1, "copper-plate", "normal", 20)
  ipr.set_reserve_amount(1, "steel-plate", "uncommon", 30)

  local results = {}
  ipr.for_each_reserve(1, function(item_name, quality_name, amount)
    results[item_name .. "|" .. quality_name] = amount
  end)

  assert_equal(results["iron-plate|normal"], 10)
  assert_equal(results["copper-plate|normal"], 20)
  assert_equal(results["steel-plate|uncommon"], 30)
end)

test("for_each_reserve skips other hubs", function()
  reset_storage()
  ipr.set_reserve_amount(1, "iron-plate", "normal", 10)
  ipr.set_reserve_amount(2, "copper-plate", "normal", 20)

  local count = 0
  ipr.for_each_reserve(1, function()
    count = count + 1
  end)

  assert_equal(count, 1, "should only iterate hub 1's reserves")
end)

test("for_each_reserve handles nil reserved_items", function()
  reset_storage()
  storage.reserved_items = nil

  local count = 0
  ipr.for_each_reserve(1, function()
    count = count + 1
  end)

  assert_equal(count, 0, "should not error or invoke callback")
end)

test("for_each_reserve handles empty hub table", function()
  reset_storage()
  -- Set and then remove a reserve to get an empty (nil) hub entry
  ipr.set_reserve_amount(1, "iron-plate", "normal", 10)
  ipr.set_reserve_amount(1, "iron-plate", "normal", 0)

  local count = 0
  ipr.for_each_reserve(1, function()
    count = count + 1
  end)

  assert_equal(count, 0)
end)

-- ---------------------------------------------------------------------------
-- Tests for get_hub_request_amount / platform_has_request_for_item
-- ---------------------------------------------------------------------------

test("get_hub_request_amount returns total for matching item", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal"), 10)
end)

test("get_hub_request_amount returns 0 for non-matching item", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_equal(ipr.get_hub_request_amount(hub, "copper-plate", "normal"), 0)
end)

test("get_hub_request_amount sums across multiple sections", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 5,
        },
      },
    },
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 7,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal"), 12)
end)

test("get_hub_request_amount ignores inactive sections", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      active = false,
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal"), 0)
end)

test("get_hub_request_amount returns 0 for invalid hub", function()
  reset_storage()
  local hub = { valid = false }
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal"), 0)
end)

test("get_hub_request_amount returns 0 when logistic_point is nil", function()
  reset_storage()
  local hub = make_hub(1, {}) -- no logistic_point
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal"), 0)
end)

test("get_hub_request_amount filters by planet_name when provided", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = vulcanus_proto,
          min = 20,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  -- Without planet filter: sums both
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal"), 30)
  -- With planet filter: only matching planet
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal", "nauvis"), 10)
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal", "vulcanus"), 20)
  assert_equal(ipr.get_hub_request_amount(hub, "iron-plate", "normal", "fulgora"), 0)
end)

test("platform_has_request_for_item returns true when request exists", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_true(ipr.platform_has_request_for_item(hub, "iron-plate", "normal"))
end)

test("platform_has_request_for_item returns false when no request", function()
  reset_storage()
  local hub = make_hub(1, {})
  assert_true(not ipr.platform_has_request_for_item(hub, "iron-plate", "normal"))
end)

test("platform_has_request_for_item filters by planet_name", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_true(ipr.platform_has_request_for_item(hub, "iron-plate", "normal", "nauvis"))
  assert_true(not ipr.platform_has_request_for_item(hub, "iron-plate", "normal", "vulcanus"))
end)

-- ---------------------------------------------------------------------------
-- Tests for all_requests_satisfied
-- ---------------------------------------------------------------------------

test("all_requests_satisfied returns true when no requests exist", function()
  reset_storage()
  local hub = make_hub(1, {})
  assert_true(ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied returns true when all requests met", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 10 }
  local hub = make_hub(1, { logistic_point = lp, inventory = inv })
  assert_true(ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied returns true when inventory exceeds request", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 50 }
  local hub = make_hub(1, { logistic_point = lp, inventory = inv })
  assert_true(ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied returns false when any request is short", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 10,
        },
        {
          value = { type = "item", name = "copper-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 5,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 10, ["copper-plate|normal"] = 3 }
  local hub = make_hub(1, { logistic_point = lp, inventory = inv })
  assert_true(not ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied returns true for invalid hub", function()
  reset_storage()
  assert_true(ipr.all_requests_satisfied { valid = false })
end)

test("all_requests_satisfied returns true when no logistic point", function()
  reset_storage()
  local hub = make_hub(1, {})
  assert_true(ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied returns true when no inventory", function()
  reset_storage()
  local lp = make_logistic_point { { filters = {} } }
  local hub = {
    valid = true,
    unit_number = 1,
    get_logistic_point = function()
      return lp
    end,
    get_inventory = function()
      return nil
    end,
  }
  assert_true(ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied skips inactive sections", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      active = false,
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 100,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 0 }
  local hub = make_hub(1, { logistic_point = lp, inventory = inv })
  -- Despite having 0 items and a request for 100, the section is inactive
  assert_true(ipr.all_requests_satisfied(hub))
end)

test("all_requests_satisfied ignores requests for non-current planet", function()
  reset_storage()
  -- Hub is orbiting nauvis but has a vulcanus-scoped request
  local nauvis_location = prototypes.space_location["nauvis"]
  local platform = { valid = true, name = "test", space_location = nauvis_location }
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = vulcanus_proto,
          min = 100,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 0 }
  local hub = make_hub(1, {
    logistic_point = lp,
    inventory = inv,
    platform = platform,
    surface = { platform = platform },
  })
  -- 0 iron plates with request for 100 from vulcanus, but hub is at nauvis
  -- so this request should not block satisfaction
  assert_true(ipr.all_requests_satisfied(hub))
end)

-- ---------------------------------------------------------------------------
-- Tests for get_in_transit_for_request / get_outgoing_for_item
-- ---------------------------------------------------------------------------

test("get_in_transit_for_request returns 0 with no deliveries", function()
  reset_storage()
  storage.active_deliveries = {}
  local hub = make_hub(1, {})
  local total, sources = ipr.get_in_transit_for_request(hub, "iron-plate", "normal")
  assert_equal(total, 0)
  assert_equal(next(sources), nil)
end)

test("get_in_transit_for_request sums matching deliveries", function()
  reset_storage()
  local hub = make_hub(1, {})
  local source_platform = { valid = true, name = "SourceA" }
  storage.active_deliveries = {
    {
      target_hub = hub,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 5,
      source_platform = source_platform,
    },
    {
      target_hub = hub,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 3,
      source_platform = source_platform,
    },
  }

  local total, sources = ipr.get_in_transit_for_request(hub, "iron-plate", "normal")
  assert_equal(total, 8)
  assert_true(sources["SourceA"] == true)
end)

test("get_in_transit_for_request ignores different hub", function()
  reset_storage()
  local hub_a = make_hub(1, {})
  local hub_b = make_hub(2, {})
  storage.active_deliveries = {
    {
      target_hub = hub_b,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 10,
      source_platform = { valid = true, name = "X" },
    },
  }

  local total, _ = ipr.get_in_transit_for_request(hub_a, "iron-plate", "normal")
  assert_equal(total, 0)
end)

test("get_in_transit_for_request ignores different item", function()
  reset_storage()
  local hub = make_hub(1, {})
  storage.active_deliveries = {
    {
      target_hub = hub,
      item_name = "copper-plate",
      quality_name = "normal",
      count = 10,
      source_platform = { valid = true, name = "X" },
    },
  }

  local total, _ = ipr.get_in_transit_for_request(hub, "iron-plate", "normal")
  assert_equal(total, 0)
end)

test("get_in_transit_for_request ignores different quality", function()
  reset_storage()
  local hub = make_hub(1, {})
  storage.active_deliveries = {
    {
      target_hub = hub,
      item_name = "iron-plate",
      quality_name = "rare",
      count = 10,
      source_platform = { valid = true, name = "X" },
    },
  }

  local total, _ = ipr.get_in_transit_for_request(hub, "iron-plate", "normal")
  assert_equal(total, 0)
end)

test("get_in_transit_for_request handles nil active_deliveries", function()
  reset_storage()
  storage.active_deliveries = nil
  local hub = make_hub(1, {})
  local total, sources = ipr.get_in_transit_for_request(hub, "iron-plate", "normal")
  assert_equal(total, 0)
  assert_equal(next(sources), nil)
end)

test("get_in_transit_for_request collects multiple source platforms", function()
  reset_storage()
  local hub = make_hub(1, {})
  storage.active_deliveries = {
    {
      target_hub = hub,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 5,
      source_platform = { valid = true, name = "PlatformA" },
    },
    {
      target_hub = hub,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 3,
      source_platform = { valid = true, name = "PlatformB" },
    },
  }

  local total, sources = ipr.get_in_transit_for_request(hub, "iron-plate", "normal")
  assert_equal(total, 8)
  assert_true(sources["PlatformA"] == true)
  assert_true(sources["PlatformB"] == true)
end)

test("get_outgoing_for_item sums outgoing deliveries", function()
  reset_storage()
  local hub = make_hub(1, {})
  local target_platform = { valid = true, name = "TargetA" }
  storage.active_deliveries = {
    {
      source_hub = hub,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 7,
      target_platform = target_platform,
    },
    {
      source_hub = hub,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 3,
      target_platform = target_platform,
    },
  }

  local total, targets = ipr.get_outgoing_for_item(hub, "iron-plate", "normal")
  assert_equal(total, 10)
  assert_true(targets["TargetA"] == true)
end)

test("get_outgoing_for_item ignores deliveries from other hubs", function()
  reset_storage()
  local hub_a = make_hub(1, {})
  local hub_b = make_hub(2, {})
  storage.active_deliveries = {
    {
      source_hub = hub_b,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 10,
      target_platform = { valid = true, name = "X" },
    },
  }

  local total, _ = ipr.get_outgoing_for_item(hub_a, "iron-plate", "normal")
  assert_equal(total, 0)
end)

test("get_outgoing_for_item handles nil active_deliveries", function()
  reset_storage()
  storage.active_deliveries = nil
  local hub = make_hub(1, {})
  local total, targets = ipr.get_outgoing_for_item(hub, "iron-plate", "normal")
  assert_equal(total, 0)
  assert_equal(next(targets), nil)
end)

-- ---------------------------------------------------------------------------
-- Tests for find_item_in_platforms
-- ---------------------------------------------------------------------------

test("find_item_in_platforms finds hub with available items", function()
  reset_storage()
  local inv = make_inventory { ["iron-plate|normal"] = 50 }
  local hub = make_hub(1, { inventory = inv })
  local platforms = { { hub = hub } }

  local found_hub, found_inv = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_equal(found_hub, hub)
  assert_equal(found_inv, inv)
end)

test("find_item_in_platforms returns nil when no items available", function()
  reset_storage()
  local inv = make_inventory { ["iron-plate|normal"] = 0 }
  local hub = make_hub(1, { inventory = inv })
  local platforms = { { hub = hub } }

  local found_hub, _ = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_nil(found_hub)
end)

test("find_item_in_platforms respects reserves", function()
  reset_storage()
  local inv = make_inventory { ["iron-plate|normal"] = 50 }
  local hub = make_hub(1, { inventory = inv })
  ipr.set_reserve_amount(1, "iron-plate", "normal", 50)
  local platforms = { { hub = hub } }

  local found_hub, _ = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_nil(found_hub, "should not find items when all are reserved")
end)

test("find_item_in_platforms respects source hub own request", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 50,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 50 }
  local hub = make_hub(1, { inventory = inv, logistic_point = lp })
  local platforms = { { hub = hub } }

  local found_hub, _ = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_nil(found_hub, "should not find items when source has its own request for same amount")
end)

test("find_item_in_platforms reserve + request both subtracted", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 40,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 100 }
  local hub = make_hub(1, { inventory = inv, logistic_point = lp })
  ipr.set_reserve_amount(1, "iron-plate", "normal", 30)
  local platforms = { { hub = hub } }

  -- available = 100 - 30 (reserve) - 40 (request) = 30 > 0
  local found_hub, _ = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_equal(found_hub, hub, "should find hub when excess exists beyond reserve + request")
end)

test("find_item_in_platforms skips first hub, finds second", function()
  reset_storage()
  local inv_a = make_inventory { ["iron-plate|normal"] = 10 }
  local hub_a = make_hub(1, { inventory = inv_a })
  ipr.set_reserve_amount(1, "iron-plate", "normal", 10)

  local inv_b = make_inventory { ["iron-plate|normal"] = 20 }
  local hub_b = make_hub(2, { inventory = inv_b })

  local platforms = { { hub = hub_a }, { hub = hub_b } }

  local found_hub, _ = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_equal(found_hub, hub_b, "should skip hub_a (all reserved) and find hub_b")
end)

test("find_item_in_platforms skips invalid hub", function()
  reset_storage()
  local hub = { valid = false }
  local platforms = { { hub = hub } }

  local found_hub, _ = ipr.find_item_in_platforms(platforms, "iron-plate", "normal")
  assert_nil(found_hub)
end)

-- ---------------------------------------------------------------------------
-- Tests for hold until satisfied checkbox
-- ---------------------------------------------------------------------------

test("hold until satisfied checkbox sets storage", function()
  reset_storage()
  local handler = script._events[defines.events.on_gui_checked_state_changed].handler
  handler {
    element = {
      valid = true,
      name = "ipr_hold_until_satisfied__42",
      state = true,
    },
    player_index = 1,
  }
  assert_true(storage.hold_until_satisfied[42] == true)
end)

test("unchecking hold clears storage and unpauses if mod paused", function()
  reset_storage()
  local platform = { valid = true, paused = true }
  storage.hold_until_satisfied[42] = true
  storage.mod_paused_platforms[42] = true
  storage.monitored_hubs[42] = { entity = make_hub(42, {}), platform = platform }

  local handler = script._events[defines.events.on_gui_checked_state_changed].handler
  handler {
    element = {
      valid = true,
      name = "ipr_hold_until_satisfied__42",
      state = false,
    },
    player_index = 1,
  }

  assert_true(not storage.hold_until_satisfied[42], "hold should be cleared")
  assert_nil(storage.mod_paused_platforms[42], "mod_paused should be cleared")
  assert_true(platform.paused == false, "platform should be unpaused")
end)

test("unchecking hold does not unpause if mod did not pause it", function()
  reset_storage()
  local platform = { valid = true, paused = true }
  storage.hold_until_satisfied[42] = true
  -- mod_paused_platforms[42] is NOT set (player paused it manually)
  storage.monitored_hubs[42] = { entity = make_hub(42, {}), platform = platform }

  local handler = script._events[defines.events.on_gui_checked_state_changed].handler
  handler {
    element = {
      valid = true,
      name = "ipr_hold_until_satisfied__42",
      state = false,
    },
    player_index = 1,
  }

  assert_true(platform.paused == true, "platform should remain paused (player paused it)")
end)

-- ---------------------------------------------------------------------------
-- Tests for hub unregistration cleanup
-- ---------------------------------------------------------------------------

test("unregistering hub clears monitored_hubs, hold, and mod_paused entries", function()
  reset_storage()
  local platform = { valid = true, name = "test" }
  local surface = {
    platform = platform,
    find_entities_filtered = function()
      return {
        {
          name = "space-platform-hub",
          valid = true,
          unit_number = 99,
          surface = { platform = platform },
        },
      }
    end,
  }
  game.surfaces = { surface }
  scan_all_hubs()

  assert_true(storage.monitored_hubs[99] ~= nil, "hub should be registered")

  -- Set hold, mod_paused, and do_not_fulfill_from
  storage.hold_until_satisfied[99] = true
  storage.mod_paused_platforms[99] = true
  storage.do_not_fulfill_from[99] = true
  ipr.set_reserve_amount(99, "iron-plate", "normal", 10)

  -- Fire the destruction event
  local destroy_event_id = defines.events.on_entity_died
  local handler = script._events[destroy_event_id] and script._events[destroy_event_id].handler
  if handler then
    handler {
      entity = {
        name = "space-platform-hub",
        valid = true,
        unit_number = 99,
        surface = { platform = platform },
      },
    }
  end

  assert_nil(storage.monitored_hubs[99], "hub should be unregistered")
  assert_nil(storage.hold_until_satisfied[99], "hold should be cleaned up")
  assert_nil(storage.mod_paused_platforms[99], "mod_paused should be cleaned up")
  assert_nil(storage.do_not_fulfill_from[99], "do_not_fulfill_from should be cleaned up")
end)

-- ---------------------------------------------------------------------------
-- Tests for pairwise conflict detection (US2: T024-T028)
-- ---------------------------------------------------------------------------

test(
  "conflict: source with same item+quality+planet request is skipped by platform_has_request_for_item",
  function()
    reset_storage()
    local lp = make_logistic_point {
      {
        filters = {
          {
            value = { type = "item", name = "iron-plate", quality = "normal" },
            import_from = nauvis_proto,
            min = 50,
          },
        },
      },
    }
    local hub = make_hub(1, { logistic_point = lp })
    -- Source hub also requests iron-plate normal from nauvis
    assert_true(
      ipr.platform_has_request_for_item(hub, "iron-plate", "normal", "nauvis"),
      "source should have conflicting request"
    )
  end
)

test("conflict: different quality means no conflict", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "copper-plate", quality = "rare" },
          import_from = fulgora_proto,
          min = 50,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  -- Checking for normal quality — should not conflict with rare
  assert_true(
    not ipr.platform_has_request_for_item(hub, "copper-plate", "normal", "fulgora"),
    "different quality should not conflict"
  )
end)

test("conflict: different item means no conflict", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 50,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_true(
    not ipr.platform_has_request_for_item(hub, "copper-plate", "normal", "nauvis"),
    "different item should not conflict"
  )
end)

test("conflict: inactive section means no conflict", function()
  reset_storage()
  local lp = make_logistic_point {
    {
      active = false,
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 50,
        },
      },
    },
  }
  local hub = make_hub(1, { logistic_point = lp })
  assert_true(
    not ipr.platform_has_request_for_item(hub, "iron-plate", "normal", "nauvis"),
    "inactive section should not create conflict"
  )
end)

test("conflict: pairwise — C without request can still receive from A or B", function()
  reset_storage()
  -- Hub A requests iron from nauvis
  local lp_a = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 50,
        },
      },
    },
  }
  local hub_a = make_hub(1, { logistic_point = lp_a })

  -- Hub B requests iron from nauvis (conflict with A)
  local lp_b = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 50,
        },
      },
    },
  }
  local hub_b = make_hub(2, { logistic_point = lp_b })

  -- Hub C has no request for iron
  local hub_c = make_hub(3, {})

  -- A conflicts with B (both request iron/normal/nauvis)
  assert_true(ipr.platform_has_request_for_item(hub_a, "iron-plate", "normal", "nauvis"))
  assert_true(ipr.platform_has_request_for_item(hub_b, "iron-plate", "normal", "nauvis"))

  -- C does NOT conflict
  assert_true(not ipr.platform_has_request_for_item(hub_c, "iron-plate", "normal", "nauvis"))
end)

-- ---------------------------------------------------------------------------
-- Tests for planet-specific filtering (US3: T032-T034)
-- ---------------------------------------------------------------------------

test("planet filtering: nauvis-scoped request only finds nauvis platforms", function()
  reset_storage()
  -- Hub A at nauvis with iron
  local inv_a = make_inventory { ["iron-plate|normal"] = 50 }
  local hub_a = make_hub(1, { inventory = inv_a })
  local platform_a = { hub = hub_a, name = "PlatformA" }

  -- Hub B at vulcanus with iron
  local inv_b = make_inventory { ["iron-plate|normal"] = 50 }
  local hub_b = make_hub(2, { inventory = inv_b })
  local platform_b = { hub = hub_b, name = "PlatformB" }

  -- Only nauvis platforms should be searched for a nauvis-scoped request
  local nauvis_platforms = { platform_a } -- only nauvis platform
  local found_hub, _ = ipr.find_item_in_platforms(nauvis_platforms, "iron-plate", "normal")
  assert_equal(found_hub, hub_a, "should find items from nauvis platform")

  -- Vulcanus platforms should not include nauvis platform
  local vulcanus_platforms = { platform_b }
  local found_hub2, _ = ipr.find_item_in_platforms(vulcanus_platforms, "iron-plate", "normal")
  assert_equal(found_hub2, hub_b, "should find items from vulcanus platform separately")
end)

test("planet filtering: hub with multi-planet requests only activates matching orbit", function()
  reset_storage()
  local nauvis_location = prototypes.space_location["nauvis"]
  local platform = { valid = true, name = "test", space_location = nauvis_location }

  -- Hub has requests for both nauvis and vulcanus
  local lp = make_logistic_point {
    {
      filters = {
        {
          value = { type = "item", name = "iron-plate", quality = "normal" },
          import_from = nauvis_proto,
          min = 50,
        },
        {
          value = { type = "item", name = "copper-plate", quality = "normal" },
          import_from = vulcanus_proto,
          min = 30,
        },
      },
    },
  }
  local inv = make_inventory { ["iron-plate|normal"] = 0, ["copper-plate|normal"] = 0 }
  local hub = make_hub(1, {
    logistic_point = lp,
    inventory = inv,
    platform = platform,
    surface = { platform = platform },
  })

  -- all_requests_satisfied should only consider nauvis requests (current orbit)
  -- nauvis iron request: 0/50 = not satisfied → false
  assert_true(not ipr.all_requests_satisfied(hub), "nauvis request unsatisfied")

  -- Give enough iron
  inv._contents["iron-plate|normal"] = 50
  -- Now nauvis is satisfied, vulcanus is ignored (not at vulcanus)
  assert_true(ipr.all_requests_satisfied(hub), "should be satisfied — vulcanus request ignored")
end)

test("planet filtering: no error when planet has zero other platforms", function()
  reset_storage()
  -- Empty platform list — should return nil without error
  local found_hub, _ = ipr.find_item_in_platforms({}, "iron-plate", "normal")
  assert_nil(found_hub, "should return nil for empty platform list")
end)

-- ---------------------------------------------------------------------------
-- Tests for migration (T037-T038)
-- ---------------------------------------------------------------------------

test("migration converts old planetary-orbit requests to per-planet", function()
  reset_storage()

  -- Create a fake old prototype reference
  local old_proto = { name = "planetary-orbit" }

  local nauvis_location = prototypes.space_location["nauvis"]
  local platform = { valid = true, name = "test", space_location = nauvis_location }

  -- Create a hub with old-style planetary-orbit import_from
  local section_filters = {
    {
      value = { type = "item", name = "iron-plate", quality = "normal" },
      import_from = old_proto,
      min = 50,
    },
  }
  local lp = make_logistic_point { { filters = section_filters } }
  local hub =
    make_hub(1, { logistic_point = lp, platform = platform, surface = { platform = platform } })

  storage.monitored_hubs[1] = { entity = hub, platform = platform }

  -- Ensure old proto is NOT in prototypes (simulates removal)
  -- (it's already not there since we replaced it with per-planet)

  -- Run migration
  migrate_planetary_orbit_to_per_planet()

  -- Check that import_from was updated
  local new_import = section_filters[1].import_from
  assert_equal(
    new_import.name,
    "interplatform-nauvis",
    "should be migrated to interplatform-nauvis"
  )
end)

test("migration preserves in-flight deliveries", function()
  reset_storage()
  local hub_a = make_hub(1, {})
  local hub_b = make_hub(2, {})
  local source_platform = { valid = true, name = "Source" }

  storage.active_deliveries = {
    {
      cargo_pod = { valid = true },
      source_hub = hub_a,
      target_hub = hub_b,
      source_platform = source_platform,
      target_platform = { valid = true, name = "Target" },
      start_tick = 0,
      item_name = "iron-plate",
      quality_name = "normal",
      count = 50,
    },
  }

  -- Run migration — should not touch active_deliveries
  migrate_planetary_orbit_to_per_planet()

  assert_equal(#storage.active_deliveries, 1, "deliveries should be preserved")
  assert_equal(storage.active_deliveries[1].count, 50, "delivery count should be unchanged")
end)

-- ---------------------------------------------------------------------------
-- Tests for "do not fulfill from this platform" checkbox
-- ---------------------------------------------------------------------------

test("do not fulfill from checkbox sets storage", function()
  reset_storage()
  local handler = script._events[defines.events.on_gui_checked_state_changed].handler
  handler {
    element = {
      valid = true,
      name = "ipr_do_not_fulfill_from__42",
      state = true,
    },
    player_index = 1,
  }
  assert_true(storage.do_not_fulfill_from[42] == true, "do_not_fulfill_from should be set")
end)

test("unchecking do not fulfill from clears storage", function()
  reset_storage()
  storage.do_not_fulfill_from[42] = true

  local handler = script._events[defines.events.on_gui_checked_state_changed].handler
  handler {
    element = {
      valid = true,
      name = "ipr_do_not_fulfill_from__42",
      state = false,
    },
    player_index = 1,
  }
  assert_true(storage.do_not_fulfill_from[42] == false, "do_not_fulfill_from should be cleared")
end)

-- ---------------------------------------------------------------------------
-- Test summary / exit code
-- ---------------------------------------------------------------------------

if failures > 0 then
  io.stderr:write(string.format("\n%d test(s) failed\n", failures))
  os.exit(1)
else
  io.stdout:write "\nAll tests passed\n"
end
