# Interplatform Requests

A Factorio Space Age mod that adds "Planetary Orbit" as a request source for space platforms, allowing platforms to request items from other platforms orbiting the same planet.

## Features

- **New Space Location**: Adds "Planetary Orbit" to the import_from grid of buttons in platform hub requests
- **Robot Delivery Animation**: Watch logistic robots fly between platforms delivering items
- **Automatic Transfers**: Items are pulled from platform hubs on other platforms at the same orbit
- **No New Items**: Uses the existing platform hub request system
- **Cinematic**: 9-second delivery animation with robots flying off one platform and arriving at another

## How It Works

When you set a platform hub request with "Planetary Orbit" as the import source:

1. The mod scans other platforms at the same space location
2. Finds the requested items in their platform hubs
3. Creates a logistic robot on the source platform
4. Robot picks up items and flies off screen
5. Robot appears on the target platform and delivers items
6. Items are added to the requesting platform's hub

## Quick Start

1. **Have 2+ platforms** orbiting the same planet (e.g., both at Nauvis orbit)
2. **Open a platform hub** on the platform that needs items
3. **Click the logistics button** to set requests
4. **Set a request** for an item (e.g., Iron Plate, minimum: 100)
5. **Select "Planetary Orbit"** from the "Import from" grid of buttons
6. **Put items in another platform's hub** at the same location
7. **Watch the robot delivery!** A robot will fly between platforms

## Example Setup

### Platform A (Requester):
- Orbiting Nauvis
- Hub has logistic request: Iron Plate (min: 100), **Import from: Planetary Orbit**
- Currently has: 20 Iron Plates

### Platform B (Provider):
- Orbiting Nauvis
- Hub has: 500 Iron Plates

**Result**:
1. A logistic robot appears on Platform B
2. Robot picks up 80 Iron Plates and flies off screen
3. Robot appears on Platform A and delivers the items
4. Platform A now has 100 Iron Plates!

## Delivery Animation Timeline

**Total Time: 9 seconds**

**Source Platform (3 seconds):**
- Robot appears at source hub
- Hovers for 1 second (picking up items)
- Flies off screen in a random direction for 2 seconds (could be left, right, up, down, or diagonal)

**Transit (3 seconds):**
- No visible robot (items in transit between platforms)

**Target Platform (3 seconds):**
- Robot appears just off-screen coming from the opposite direction
- Flies toward hub for 2 seconds
- Hovers at hub for 1 second (delivering items)
- Disappears

## Key Features

- **Same Orbit Only**: Only transfers between platforms at the exact same space location
- **Smart Transfer**: Only requests the difference (current + in-transit vs requested)
- **No Duplicates**: Prevents multiple robots for the same request
- **Visual Feedback**: Watch robots fly between platforms
- **Performance Friendly**: Checks every 60 ticks (1 second)
- **Works Alongside Vanilla**: Normal planet-to-platform logistics still work

## Technical Details

- **Scan Interval**: 60 ticks (1 second)
- **Delivery Method**: Logistic robots with teleportation animation
- **Source**: Platform hubs only
- **Destination**: Platform hubs only
- **Transfer Amount**: Exact amount needed (requested - current - in_transit)
- **Quality Support**: Yes (matches quality in requests)
- **Animation**: 9 seconds total (3s pickup, 3s transit, 3s delivery)

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

## Future Ideas

- Transfer from other container types on platforms
- Visual transfer effects
- Statistics and monitoring
- Priority system for multiple source platforms
- Transfer speed settings

## FAQ

**Q: How do I use this mod?**
A: Set a platform hub request and select "Planetary Orbit" from the "Import from" grid of buttons.

**Q: Where is "Planetary Orbit" in the list?**
A: It appears in the import_from grid of buttons, usually under the "Unsorted" section.

**Q: How do I know it's working?**
A: You'll see messages like "Interplatform Requests: Sending Xx item from Platform A to Platform B" and you'll see a robot flying between platforms.

**Q: Can I still request from planets?**
A: Yes! Just select the planet name instead of "Planetary Orbit". The mod doesn't interfere with normal logistics.

**Q: What if multiple platforms need the same item?**
A: Each request is processed independently. The mod checks all platforms for available items.

**Q: Does it work with quality items?**
A: Yes! It matches the quality specified in the request.

**Q: Why don't I see a robot?**
A: Make sure you're watching the correct platform (the one receiving items). The robot flies TO that platform from off-screen, coming from the opposite direction it flew when leaving the source platform.

## License

MIT License - Feel free to modify and distribute

## Credits

Created by jatruman for Factorio 2.0 Space Age

