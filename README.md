# Interplatform Requests

A Factorio Space Age mod that adds "Planetary Orbit" as a request source for space platforms, allowing platforms to request items from other platforms orbiting the same planet.

## Features

- **New Space Location**: Adds "Planetary Orbit" to the "Import from" grid of buttons in platform hub requests
- **Cargo Pod Delivery**: Items are transferred between platforms via cargo pods
- **Automatic Transfers**: Items are pulled from platform hubs on other platforms at the same orbit
- **Status Panel**: See request satisfaction, in-transit items, and available items on other platforms at a glance
- **Item Reserves**: Reserve items on a hub so they won't be sent to other platforms
- **No New Items**: Uses the existing platform hub request system

## How It Works

When you set a platform hub request with "Planetary Orbit" as the import source:

1. The mod scans other platforms at the same space location
2. Finds the requested items in their platform hubs (respecting reserves)
3. Sends a cargo pod from the source platform to deliver items
4. Items are added to the requesting platform's hub

## Quick Start

1. **Have 2+ platforms** orbiting the same planet (e.g., both at Nauvis orbit)
2. **Open a platform hub** on the platform that needs items
3. **Click the logistics button** to set requests
4. **Set a request** for an item (e.g., Iron Plate, minimum: 100)
5. **Select "Planetary Orbit"** from the "Import from" grid of buttons
6. **Put items in another platform's hub** at the same location
7. Items will transfer automatically via cargo pod

## Status Panel

When you open a platform hub, the Interplatform Requests status panel shows:

- **Need**: How many items are still needed to satisfy the request
- **Satisfaction**: Current amount / requested amount
- **In Transit**: Items currently being delivered via cargo pod
- **Available**: Items available on other platforms at the same location (accounting for reserves)
- **From**: Which platform the items will come from

The status panel updates automatically every second.

## Reserves

Reserves let you keep a minimum number of items on a hub so they won't be sent to other platforms.

- Open a platform hub to see the **Reserves** section below the status table
- Click the item picker to add a new reserve
- Set the amount in the text field (saves automatically as you type)
- **Left-click** an existing reserve's item icon to change the item
- **Right-click** an existing reserve's item icon to remove the reserve
- Reserves are per-hub — each platform hub has its own reserve settings
- An item can only have one reserve entry per hub

## Example Setup

### Platform A (Requester):
- Orbiting Nauvis
- Hub has logistic request: Iron Plate (min: 100), **Import from: Planetary Orbit**
- Currently has: 20 Iron Plates

### Platform B (Provider):
- Orbiting Nauvis
- Hub has: 500 Iron Plates (with 100 reserved)

**Result**: The mod transfers 80 Iron Plates from Platform B to Platform A via cargo pod, respecting Platform B's 100-item reserve.

## Key Features

- **Same Orbit Only**: Only transfers between platforms at the exact same space location
- **Smart Transfer**: Only requests the difference (current + in-transit vs requested)
- **Reserve System**: Keep items on a hub for local use
- **No Duplicates**: Prevents multiple transfers for the same request
- **Performance Friendly**: Checks every 60 ticks (1 second)
- **Works Alongside Vanilla**: Normal planet-to-platform logistics still work

## Technical Details

- **Scan Interval**: 60 ticks (1 second)
- **Delivery Method**: Cargo pods
- **Source**: Platform hubs only
- **Destination**: Platform hubs only
- **Transfer Amount**: Exact amount needed (requested - current - in_transit), capped by available minus reserves
- **Quality Support**: Yes (matches quality in requests)

## Compatibility

- **Factorio Version**: 2.0+
- **Space Age**: Required
- **Other Mods**: Should be compatible with most mods
- **Multiplayer**: Yes, fully supported

## Limitations

- Only works between platforms at the **exact same space location**
- Transfers from platform **hubs only** (not other containers)
- Transfers **to platform hubs only**
- One transfer per request per second (performance optimization)

## FAQ

**Q: How do I use this mod?**
A: Set a platform hub request and select "Planetary Orbit" from the "Import from" grid of buttons.

**Q: Where is "Planetary Orbit" in the list?**
A: It appears in the "Import from" grid of buttons.

**Q: How do I know it's working?**
A: Open the platform hub to see the status panel showing request satisfaction and in-transit items.

**Q: Can I still request from planets?**
A: Yes! Just select the planet name instead of "Planetary Orbit". The mod doesn't interfere with normal logistics.

**Q: What if multiple platforms need the same item?**
A: Each request is processed independently. The mod checks all platforms for available items.

**Q: Does it work with quality items?**
A: Yes! It matches the quality specified in the request.

**Q: How do I prevent a hub from giving away all its items?**
A: Use the Reserves feature to specify how many of each item should be kept on the hub.

## Development & CI

This mod has a GitHub Actions workflow that:

- On **push / pull requests**:
  - Runs **Stylua** to lint/format all Lua sources.
  - Builds a ZIP named `<mod_name>_<version>.zip` where `version` comes directly from `info.json`.
  - Uploads the ZIP as a build artifact.
- On a **manual release run** (using the "Run workflow" button):
  - Reads the **major.minor** baseline from `info.json` (e.g. `0.6`).
  - Looks at existing `vX.Y.Z` tags to find the latest released version.
  - If major/minor are unchanged, increments the patch; otherwise, starts at patch `0`.
  - Ensures versions only ever increase (no going backwards unless major/minor increase).
  - Writes the full `major.minor.patch` into `info.json` for that build only.
  - Creates and pushes a new tag `v<major.minor.patch>`.
  - Builds `<mod_name>_<major.minor.patch>.zip` and creates/updates a GitHub Release for that tag with the ZIP attached.

To cut a new release:

1. Update `version` in `info.json` to the desired **major.minor** baseline (e.g. change `0.6` → `0.7` when you want a new minor line).
2. Commit and push your changes to the default branch (e.g. `main`).
3. In GitHub → **Actions** → "Build Factorio Mod", click **Run workflow** (targeting `main`).
4. The workflow will compute the next full version (e.g. `0.6.7` or `0.7.0`), create tag `v<version>`, build the ZIP, and publish/update a GitHub Release with the ZIP attached.

## License

MIT License - Feel free to modify and distribute

## Credits

Created by jatruman for Factorio 2.0 Space Age

