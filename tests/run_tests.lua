-- Simple Lua unit tests for Interplatform Requests.
-- These run in CI on GitHub Actions using a stubbed Factorio runtime.

local failures = 0

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values are not equal") .. string.format(" (expected %s, got %s)", tostring(expected), tostring(actual)), 2)
  end
end

local function assert_true(condition, message)
  if not condition then
    error(message or "assert_true failed", 2)
  end
end

local function test(name, fn)
  io.stdout:write("TEST " .. name .. " ... ")
  local ok, err = pcall(fn)
  if ok then
    io.stdout:write("OK\n")
  else
    io.stdout:write("FAIL\n")
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
}

prototypes = {
  space_location = {
    ["planetary-orbit"] = { name = "planetary-orbit" },
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
dofile("control.lua")

-- ---------------------------------------------------------------------------
-- Tests for for_each_planetary_orbit_item_request
-- ---------------------------------------------------------------------------

test("for_each_planetary_orbit_item_request filters and invokes callback", function()
  local calls = {}
  local planetary_proto = prototypes.space_location["planetary-orbit"]

  local logistic_point = {
    sections = {
      {
        filters = {
          { value = { type = "item", name = "iron-plate" }, import_from = planetary_proto, min = 10 },
          { value = { type = "item", name = "copper-plate" }, import_from = nil, min = 5 },
        },
      },
      {
        filters = {
          { value = { type = "fluid", name = "water" }, import_from = planetary_proto, min = 1 },
        },
      },
    },
  }

  for_each_planetary_orbit_item_request(logistic_point, function(filter, section, section_index, filter_index, proto)
    table.insert(calls, {
      item = filter.value.name,
      section_index = section_index,
      filter_index = filter_index,
      proto = proto,
    })
    return false
  end)

  assert_equal(#calls, 1, "expected exactly one matching filter")
  assert_equal(calls[1].item, "iron-plate", "expected to see iron-plate request")
  assert_equal(calls[1].section_index, 1)
  assert_equal(calls[1].filter_index, 1)
  assert_equal(calls[1].proto, planetary_proto)
end)

test("for_each_planetary_orbit_item_request stops when callback returns true", function()
  local planetary_proto = prototypes.space_location["planetary-orbit"]

  local logistic_point = {
    sections = {
      {
        filters = {
          { value = { type = "item", name = "iron-plate" }, import_from = planetary_proto, min = 10 },
          { value = { type = "item", name = "steel-plate" }, import_from = planetary_proto, min = 15 },
        },
      },
    },
  }

  local seen = {}
  for_each_planetary_orbit_item_request(logistic_point, function(filter)
    table.insert(seen, filter.value.name)
    return true -- stop after first match
  end)

  assert_equal(#seen, 1, "expected early stop after first callback returning true")
  assert_equal(seen[1], "iron-plate")
end)

test("for_each_planetary_orbit_item_request handles empty or missing sections", function()
  local calls = 0

  for_each_planetary_orbit_item_request({ sections = {} }, function()
    calls = calls + 1
  end)

  for_each_planetary_orbit_item_request({ sections = nil }, function()
    calls = calls + 1
  end)

  assert_equal(calls, 0, "expected no callbacks for empty/missing sections")
end)

-- ---------------------------------------------------------------------------
-- Tests for storage initialization and hub scanning
-- ---------------------------------------------------------------------------

test("scan_all_hubs initializes storage and registers hubs on platform surfaces", function()
  -- Reset globals for this test
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

  -- scan_all_hubs calls init_storage(), so all storage tables should exist
  assert_true(storage.monitored_hubs ~= nil, "monitored_hubs should be initialized")
  assert_true(storage.active_deliveries ~= nil, "active_deliveries should be initialized")
  assert_true(storage.request_directions ~= nil, "request_directions should be initialized")
  assert_true(storage.viewed_hub_by_player ~= nil, "viewed_hub_by_player should be initialized")
  assert_true(storage.request_status ~= nil, "request_status should be initialized")
  assert_equal(storage.debug_logging, false, "debug_logging should default to false")

  -- And the two hubs on the platform surface should have been registered
  assert_true(storage.monitored_hubs[1] ~= nil, "hub 1 should be registered")
  assert_true(storage.monitored_hubs[2] ~= nil, "hub 2 should be registered")
  assert_equal(storage.monitored_hubs[1].platform, platform, "hub platform should match surface.platform")
end)

test("script.on_init handler is registered and initializes storage", function()
  -- script.on_init should have been called from control.lua and stored as _on_init
  assert_true(type(script._on_init) == "function", "script.on_init handler should be registered")

  storage = {}
  game.surfaces = {}

  script._on_init()

  assert_true(storage.monitored_hubs ~= nil, "monitored_hubs should be initialized on on_init")
  assert_true(storage.active_deliveries ~= nil, "active_deliveries should be initialized on on_init")
  assert_true(storage.request_directions ~= nil, "request_directions should be initialized on on_init")
  assert_true(storage.viewed_hub_by_player ~= nil, "viewed_hub_by_player should be initialized on on_init")
  assert_true(storage.request_status ~= nil, "request_status should be initialized on on_init")
end)

-- ---------------------------------------------------------------------------
-- Tests for create_cinematic_robot
-- ---------------------------------------------------------------------------

test("create_cinematic_robot prefers custom robot when creation succeeds", function()
  local created = {}
  local surface = {}

  function surface.create_entity(def)
    table.insert(created, def)
    return { valid = true, name = def.name }
  end

  local robot = create_cinematic_robot(surface, { 0, 0 }, { name = "test-force" })

  assert_equal(#created, 1, "expected exactly one create_entity call")
  assert_equal(created[1].name, "interplatform-delivery-robot")
  assert_true(robot ~= nil and robot.valid, "robot should be created and valid")
  assert_equal(robot.name, "interplatform-delivery-robot")
end)

test("create_cinematic_robot falls back to logistic robot when custom creation fails", function()
  local calls = {}
  local surface = {}

  function surface.create_entity(def)
    table.insert(calls, def.name)
    if def.name == "interplatform-delivery-robot" then
      error("no such entity")
    else
      return { valid = true, name = def.name }
    end
  end

  local robot = create_cinematic_robot(surface, { 1, 1 }, { name = "test-force" })

  assert_equal(#calls, 2, "expected two create_entity calls (custom then fallback)")
  assert_equal(calls[1], "interplatform-delivery-robot")
  assert_equal(calls[2], "logistic-robot")
  assert_true(robot ~= nil and robot.valid, "fallback robot should be created and valid")
  assert_equal(robot.name, "logistic-robot")
end)

test("create_cinematic_robot returns nil when both creations fail", function()
  local calls = {}
  local surface = {}

  function surface.create_entity(def)
    table.insert(calls, def.name)
    error("all creations fail")
  end

  local robot = create_cinematic_robot(surface, { 2, 2 }, { name = "test-force" })

  assert_equal(#calls, 2, "expected two create_entity calls even when both fail")
  assert_equal(calls[1], "interplatform-delivery-robot")
  assert_equal(calls[2], "logistic-robot")
  assert_equal(robot, nil, "robot should be nil when both creations fail")
end)

-- ---------------------------------------------------------------------------
-- Test summary / exit code
-- ---------------------------------------------------------------------------

if failures > 0 then
  io.stderr:write(string.format("\n%d test(s) failed\n", failures))
  os.exit(1)
else
  io.stdout:write("\nAll tests passed\n")
end
