# Interplatform Requests - Status

## ACTIVE AND WORKING

**Current Version**: 0.6.8
**Factorio Version**: 2.0+

---

## Installation

### Mod Location:
```
/Users/jatruman/workspace/personal/interplatform-requests
```

### Symlink:
```
~/Library/Application Support/factorio/mods/interplatform-requests
→ /Users/jatruman/workspace/personal/interplatform-requests
```

### Files:
- info.json (mod metadata)
- data.lua (prototypes)
- control.lua (main logic)
- README.md (full documentation)
- QUICKSTART.md (quick start guide)
- CHANGELOG.md (version history)
- STATUS.md (this file)

---

## What's Running

The mod actively monitors all platform hubs. Every 60 ticks (1 second), it:

1. Checks platform hubs for requests with "Planetary Orbit" as import source
2. Looks for requested items in other platform hubs at the same location
3. Respects per-hub item reserves (reserved items are not sent)
4. Sends cargo pods to deliver items between platforms
5. Updates the status panel with current request satisfaction

---

## Technical Info

- **Scan Interval**: 60 ticks (1 second)
- **Transfer Method**: Cargo pods
- **Source**: Platform hubs only
- **Destination**: Platform hubs only
- **Quality Support**: Yes
- **Multiplayer**: Supported
- **Reserves**: Per-hub, stored in `storage.reserved_items`
