# Interplatform Requests - Changelog

## 0.8.3

- Move per-planet interplatform location generation from data stage to data-final-fixes stage so that planets added by other mods are included.
- Add custom "interplatform" item subgroup so interplatform locations appear on their own row in the space locations list instead of mixed in with planets.

## 0.8.1

- Add "Do not fulfill from this platform" per-hub checkbox: when enabled, other platforms will not take items from this hub to fulfill their requests. The hub's inventory is also excluded from the "Available" count in the status panel.

## 0.8.0

- **Per-planet interplatform requests**: Replaced the single "Planetary Orbit" request source with one per planet (e.g., "Interplatform - Nauvis", "Interplatform - Vulcanus"). Each button displays a composited cargo pod + planet icon.
- **Pairwise conflict detection**: The system no longer transfers items between two platforms that both have an active request for the same item and quality. This prevents circular transfers. The check is pairwise — other platforms without the conflicting request can still participate.
- **Planet-scoped filtering**: Requests are only active when the platform orbits the matching planet. A hub can hold requests for multiple planets; only the one matching the current orbit is evaluated.
- **Multi-planet request support**: A single hub can define requests scoped to different planets simultaneously. Requests for non-current orbits remain dormant until the platform travels there.
- **Save migration**: Existing saves using the old "Planetary Orbit" system are automatically migrated to per-planet format based on each platform's current orbit location. In-flight deliveries complete normally.
- **Mod compatibility**: Per-planet locations are generated dynamically from all planets at data stage, including planets added by other mods.
- Expanded test coverage from 55 to 72 tests, covering per-planet iteration, conflict detection, planet filtering, migration, and new helper functions.

## 0.7.1

- Reserve item picker now supports quality selection (uses item-with-quality chooser).
- Deselected request groups (unchecked checkbox) are no longer treated as active interplatform requests.
- Add "Hold until requests satisfied" per-hub option: pauses the platform while any interplatform request is not fully satisfied, and automatically unpauses once all requests are met. Does not interfere with manual pausing.
- Expanded test coverage from 5 to 55 tests, covering reserves, request amounts, satisfaction checks, in-transit/outgoing tracking, availability calculations, inactive sections, hold-until-satisfied, and hub cleanup.

## 0.7.0

- Fix items being taken from platforms that have their own interplatform request for the same item. Source hubs now only offer surplus above their own requested amount (instead of being skipped entirely or fully exposed).
- Split status panel into separate Incoming and Outgoing tables, each shown only when relevant.
- Outgoing table shows item, count, and destination platform for items being sent from this hub.
- Refresh source hub status panel when deliveries are created and completed.

## 0.6.9

- Fix status panel not showing on platforms that are not currently orbiting a planet.
- Fix stale status panel persisting when switching between hubs with and without the technology researched.
- Fix item icons in the status table not reflecting item quality.

## 0.6.8

- Add per-hub item reserve system: reserve items on a hub so they won't be sent to other platforms.
- Reserves UI integrated into the status panel with choose-elem-button item pickers.
- Left-click a reserve icon to change the item, right-click to remove it.
- Reserve amounts save automatically as you type (no confirm button needed).
- Already-reserved items are filtered out of the item picker to prevent duplicates.
- Status panel "Available" column now accounts for reserves on source hubs.
- Transfer logic respects reserves — reserved items are never sent to other platforms.
- Add info icon next to Reserves header with usage instructions tooltip.

## 0.6.7

- Replace robot-based delivery animation with cargo pods for item transfers between platforms.
- Remove custom delivery robot prototype and cinematic robot code.
- Add status panel anchored to the hub GUI showing pending interplatform requests.
- Release workflow now only triggers on code/graphics changes, skipping doc-only updates.
- Add auto-merge workflow for PRs that pass CI.

## 0.6.6

- Fix issue with newly built platform hubs not being recognized until a manual rescan.
  Hubs are now periodically rediscovered during normal processing, so missed build events
  are automatically corrected.
- Allow players to preconfigure Planetary Orbit imports before researching the technology.
  The warning popup still appears, but the import setting is no longer cleared.
- Add CI workflow with StyLua linting and Lua unit tests.
- Restructure release workflow: automatic releases on push to main, publish to
  Factorio Mod Portal.
- Update GitHub Actions to latest versions.

## 0.6.5

- Increase Interplatform Requests technology cost from 200 to 2000 research units.
- Automatically rescan and register all existing platform hubs on configuration change
  (fixes servers that previously required a manual `/c remote.call("interplatform-requests", "scan_hubs")`).
- Fix bug with platforms not being registered in pre-existing game saves.
- Documentation cleanup for Planetary Orbit import option location ("Import from" grid wording, removed outdated
  "Unsorted" references).

## 0.6.4 - Initial release

- First public release of Interplatform Requests.
- Adds the **Planetary Orbit** space location as a request source in the platform hub "Import from" grid.
- Implements cross-platform item transfers between hubs in the same orbit using a 9-second logistic robot
  delivery animation (pickup → transit → delivery).
- Tracks in-transit items to avoid over-requesting and duplicate transfers.
- Works alongside vanilla planet-to-platform logistics without interfering.

## Known Limitations

- Only transfers from platform hubs (not other containers).
- Only transfers to platform hubs.
- Platforms must be at the exact same space location.
- One transfer per request per second (per hub).
