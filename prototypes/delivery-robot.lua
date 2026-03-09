-- Custom cinematic delivery robot used for interplatform transfer animation

data:extend {
  {
    type = "simple-entity-with-force",
    name = "interplatform-delivery-robot",
    icon = "__interplatform-requests__/graphics/icons/interplatform-requests.png",
    icon_size = 64,
    flags = { "placeable-off-grid", "not-on-map" },
    selectable_in_game = false,
    is_military_target = false,
    render_layer = "air-object",
    secondary_draw_order = 10,
    collision_box = { { 0, 0 }, { 0, 0 } },
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    picture = {
      filename = "__interplatform-requests__/graphics/icons/interplatform-requests.png",
      width = 64,
      height = 64,
    },
  },
}
