-- Per-planet interplatform space locations and unlocking technology
-- Generates one "interplatform-{planet}" space location per planet in
-- data.raw["planet"], each with a composited cargo-pod + planet icon.

local cargo_pod_icon = "__interplatform-requests__/graphics/icons/interplatform-cargo-pod.png"

-- Collect generated location names so the technology can unlock them all.
local interplatform_locations = {}

for name, planet in pairs(data.raw["planet"]) do
  local location_name = "interplatform-" .. name

  -- Build layered icon: planet background + cargo pod foreground.
  local icons = {}
  if planet.icon then
    table.insert(icons, {
      icon = planet.icon,
      icon_size = planet.icon_size or 64,
    })
  end
  table.insert(icons, {
    icon = cargo_pod_icon,
    icon_size = 64,
    scale = 0.65,
    shift = { 0, 0 },
  })

  data:extend {
    {
      type = "space-location",
      name = location_name,
      icons = icons,
      order = "z[interplatform]-" .. (planet.order or name),
      subgroup = "planets",
      distance = 0,
      orientation = 0,
      gravity_pull = 0,
      magnitude = 0.1,
      draw_orbit = false,
      auto_save_on_first_trip = false,
      starmap_icon = cargo_pod_icon,
      starmap_icon_size = 64,
      label_orientation = 0.25,
      localised_name = {
        "",
        "Interplatform - ",
        planet.localised_name or { "space-location-name." .. name },
      },
      localised_description = { "space-location-description.interplatform" },
    },
  }

  table.insert(interplatform_locations, location_name)
end

-- Build one unlock-space-location effect per generated interplatform location.
local effects = {}
for _, loc_name in ipairs(interplatform_locations) do
  table.insert(effects, {
    type = "unlock-space-location",
    space_location = loc_name,
    icon = cargo_pod_icon,
    icon_size = 64,
  })
end

data:extend {
  {
    type = "technology",
    name = "interplatform-requests",
    icon = "__interplatform-requests__/graphics/technology/interplatform-requests.png",
    icon_size = 256,
    essential = true,
    prerequisites = { "space-science-pack" },
    effects = effects,
    unit = {
      count = 2000,
      ingredients = {
        { "automation-science-pack", 1 },
        { "logistic-science-pack", 1 },
        { "utility-science-pack", 1 },
        { "space-science-pack", 1 },
      },
      time = 30,
    },
    order = "z[space-platform-hub]-z[interplatform-requests]",
  },
}
