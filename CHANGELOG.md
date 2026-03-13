# Interplatform Requests - Changelog

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
