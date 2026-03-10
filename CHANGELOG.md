# Interplatform Requests - Changelog

## 0.6.4

- Increase Interplatform Requests technology cost from 200 to 2000 research units.
- Automatically rescan and register all existing platform hubs on configuration change
  (fixes servers that previously required a manual `/c remote.call("interplatform-requests", "scan_hubs")`).
- Documentation cleanup for Planetary Orbit import option location ("Import from" grid wording, removed outdated
  "Unsorted" references).

## 0.6.3 - Initial release

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