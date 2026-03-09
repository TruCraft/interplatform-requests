# Interplatform Requests - Changelog

## Version 0.6.6 (Current)

### Summary

0.6.5 and 0.6.6 are small internal / bugfix releases. The current feature set is the
same as 0.6.4; see the detailed 0.6.4 notes below.

### 0.6.4 Feature Set

#### Features
- ✅ "Planetary Orbit" space location in import_from dropdown
- ✅ Logistic robot delivery animation (9 seconds)
- ✅ Smart transfer (only requests difference: requested - current - in_transit)
- ✅ Prevents duplicate requests
- ✅ Works alongside vanilla planet-to-platform logistics

#### Animation Sequence
1. **Source Platform (3s)**: Robot picks up, then flies off screen in a random direction
2. **Transit (3s)**: No visible robot (items in transit)
3. **Target Platform (3s)**: Robot flies in from the opposite direction, hovers, delivers

#### Code Cleanup
- Removed unused constants (DELIVERY_TIME, POD_START_OFFSET)
- Removed unused field (last_check_tick)
- Removed debug spam
- Updated all documentation

---

## Version History

### 0.6.6
- Internal improvements and bug fixes
- No gameplay-visible changes compared to 0.6.4

### 0.6.5
- Internal improvements and bug fixes
- No gameplay-visible changes compared to 0.6.4

### 0.6.4
- Introduced current logistic robot delivery system and Planetary Orbit features
- See detailed notes in the section above

### 0.6.3
- Slowed down robot flight animation (2 seconds instead of 1)
- Added 1-second hover at destination before delivery

### 0.6.2
- Increased delivery time to 7 seconds total
- Added hover at destination hub

### 0.6.1
- Robot flies off screen on source platform (right edge)
- Robot flies in from screen on target platform (left edge)

### 0.6.0
- Switched from cargo pods to logistic robots
- Separate robots on source and target platforms (can't teleport between surfaces)
- 3-phase delivery: pickup, transit, deliver

### 0.5.x
- Fixed robot creation and movement
- Added debug messages
- Fixed storage initialization

### 0.4.0
- Attempted cargo pod delivery system (replaced in 0.6.0)

### 0.3.x
- Fixed cargo pod inventory access
- Added in-transit tracking to prevent over-requesting
- Fixed amount calculation

### 0.2.x
- Added "planetary-orbit" space location prototype
- Fixed prototype comparison (userdata vs string)
- Added circuit network detection

### 0.1.0
- Initial release
- Basic platform-to-platform transfer
- No visual effects

---

## Known Limitations

- Only transfers from platform hubs (not other containers)
- Only transfers to platform hubs
- Platforms must be at exact same space location
- One transfer per request per second

