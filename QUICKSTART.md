# Interplatform Requests - Quick Start Guide

## ✅ Mod Active!

The Interplatform Requests mod adds "Planetary Orbit" as a request source for space platforms.

---

## What You'll See

**Robot Delivery Animation:**
- Logistic robots fly between platforms delivering items
- 9-second cinematic delivery sequence
- Robot picks up from source platform, flies off screen
- Robot appears on target platform, delivers items

**New Request Option:**
	- "Planetary Orbit" appears in the "Import from" grid of buttons
- Select it to request items from other platforms in the same orbit

---

## Quick Test (3 Minutes)

### Step 1: Set Up Platforms

You need 2 platforms orbiting the same planet (e.g., both at Nauvis orbit).

### Step 2: Platform A (Requester)

1. Open the **Platform Hub**
2. Click the **logistics button** (chest icon)
3. Add a request: **Iron Plate** (minimum: 100)
4. **Select "Planetary Orbit"** from the "Import from" grid of buttons
5. Make sure the hub has **less than 100 iron plates**

### Step 3: Platform B (Provider)

1. Open the **Platform Hub**
2. Put **200 Iron Plates** in the hub inventory

### Step 4: Watch the Show!

Within a few seconds, you'll see:
1. Message: "Interplatform Requests: Sending 80x iron-plate from Platform B to Platform A"
2. A robot appears on Platform B, picks up items, flies off screen
3. A robot appears on Platform A, flies in, delivers items
4. Message: "Interplatform Requests: Delivered 80x iron-plate to Platform A"

**Total animation time: 9 seconds**

---

## How It Works

The mod monitors all platform hubs and:
1. Checks their logistic requests every second
2. Looks for those items on other platforms at the same location
3. Transfers items directly between platform hubs
4. Prints a message when transfers happen

---

## Normal Usage

Once you've verified it works, just use it naturally:

1. **Set requests on your platform hubs** (like you normally would)
2. **Stock items on other platforms** (in their hubs)
3. **Let the mod handle the rest!**

The mod works transparently alongside normal planet-to-platform logistics.

---

## Example Scenarios

### Scenario 1: Resource Distribution
- **Mining Platform**: Collects asteroids, has excess iron
- **Manufacturing Platform**: Needs iron for production
- **Solution**: Manufacturing platform requests iron, mod transfers it automatically

### Scenario 2: Shared Supplies
- **Platform A**: Has 1000 copper plates
- **Platform B**: Needs 200 copper plates
- **Platform C**: Needs 300 copper plates
- **Solution**: Both B and C request copper, mod distributes from A

### Scenario 3: Emergency Supplies
- **Main Platform**: Well-stocked with everything
- **New Platform**: Just arrived, needs basic supplies
- **Solution**: New platform requests items, mod pulls from main platform

---

## Tips

✅ **Keep hubs stocked** - The mod can only transfer what exists in other platform hubs
✅ **Use requests liberally** - Set requests for everything you might need
✅ **Same orbit required** - Platforms must be at the exact same space location
✅ **Quality matters** - Requests match quality (normal, uncommon, etc.)

---

## Troubleshooting

**Don't see "Planetary Orbit" in the grid of buttons?**
- Check the mod is loaded: `/c game.print(game.active_mods["interplatform-requests"])`
- Try reloading: `/c game.reload_mods()`

**Items not transferring?**
- Both platforms must be at the **exact same space location** (check the map)
- Source platform must have items in its **hub** (not in chests)
- Request must have "Planetary Orbit" selected as import source
- Wait at least 1 second (mod checks every 60 ticks)

**Don't see the robot?**
- Watch the **target platform** (the one receiving items)
- Robot flies IN from the left edge
- Also check the **source platform** - robot flies OFF to the right
- Animation takes 9 seconds total

---

## What's Next?

Now that you have inter-platform logistics:
- Build specialized platforms (mining, manufacturing, defense)
- Share resources efficiently across your fleet
- Reduce trips back to planets for supplies
- Create self-sufficient platform networks!

---

Enjoy your new inter-platform logistics system! 🚀

