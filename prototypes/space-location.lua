-- Space location (Planetary Orbit) and its unlocking technology for Interplatform Requests

data:extend {
  {
    type = "planet",
    name = "planetary-orbit",
	    icon = "__interplatform-requests__/graphics/icons/interplatform-delivery-robot.png",
	    icon_size = 64,
	    order = "z[planetary-orbit]",
	    subgroup = "planets",
    distance = 0, -- At the center (no distance from sun)
    orientation = 0, -- Required field - angle in relation to the sun
    gravity_pull = 0,
    magnitude = 0.1, -- Small size so it doesn't clutter the map
    draw_orbit = false, -- Don't draw an orbital ring
    auto_save_on_first_trip = false,
    starmap_icon = "__interplatform-requests__/graphics/icons/interplatform-delivery-robot.png",
    starmap_icon_size = 64,
    label_orientation = 0.25,
    localised_name = { "space-location-name.planetary-orbit" },
    localised_description = { "space-location-description.planetary-orbit" },
  },
  {
    type = "technology",
    name = "interplatform-requests",
    icon = "__interplatform-requests__/graphics/technology/interplatform-requests.png",
    icon_size = 256,
    essential = true,
    -- Rely on the Space science pack technology, which itself depends on
    -- Space platform. This makes Interplatform Requests appear *after*
    -- Space science pack in the tech tree.
    prerequisites = { "space-science-pack" },
    -- When researched, this technology unlocks the previously hidden
    -- "planetary-orbit" space location so that it becomes selectable as an
    -- import source in platform hub requests.
    effects = {
      {
        type = "unlock-space-location",
        space_location = "planetary-orbit",
        icon = "__interplatform-requests__/graphics/icons/interplatform-delivery-robot.png",
        icon_size = 64,
      },
    },
    unit = {
      count = 200,
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
