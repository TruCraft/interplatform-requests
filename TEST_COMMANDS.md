# Interplatform Requests - Useful Commands

## Console Basics

1. **Press `~`** to open console
2. Type commands and press Enter
3. Messages appear on screen

---

## Useful Commands

### Check Mod Version
```lua
/c game.print("Interplatform Requests version: " .. game.active_mods["interplatform-requests"])
```

### Check Monitored Hubs
```lua
/c local count = 0; for _ in pairs(storage.monitored_hubs) do count = count + 1 end; game.print("Monitored hubs: " .. count)
```

### Scan for Platform Hubs
```lua
/c remote.call("interplatform-requests", "scan_hubs")
```
Scans all platforms and registers their hubs.

### Test Robot Creation
```lua
/c remote.call("interplatform-requests", "test_robot")
```
Creates a test robot next to you to verify robots work in space.

### Clean Up Test Robots
```lua
/c for _, robot in pairs(game.player.surface.find_entities_filtered{name="logistic-robot", force=game.player.force}) do robot.destroy() end; game.print("Destroyed all robots")
```

### Check Active Deliveries
```lua
/c game.print("Active deliveries: " .. #storage.active_deliveries)
```

### List Space Locations
```lua
/c for name, _ in pairs(prototypes.space_location) do game.print(name) end
```
Should show "planetary-orbit" in the list.

---

## Troubleshooting Commands

### Reload Mods
```lua
/c game.reload_mods()
```
Reloads all mods without restarting Factorio.

### Initialize Storage
```lua
/c storage.monitored_hubs = {}; storage.active_deliveries = {}; game.print("Storage initialized!")
```
Use if you get errors about nil storage.

### Enable Editor Mode
```
/editor
```
Allows you to manually place/delete entities for testing.

### Check Platform Location
```lua
/c if game.player.surface.platform then game.print("Platform: " .. game.player.surface.platform.name .. " at " .. game.player.surface.platform.space_location.name) else game.print("Not on a platform") end
```

