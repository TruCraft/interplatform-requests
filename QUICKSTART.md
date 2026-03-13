# Interplatform Requests - Quick Start Guide

## What This Mod Does

Adds "Planetary Orbit" as a request source for space platforms, allowing platforms to request items from other platforms orbiting the same planet. Items are delivered via cargo pods.

---

## Setup (3 Minutes)

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

### Step 4: Watch It Work

Within a few seconds, a cargo pod will deliver the needed items from Platform B to Platform A.

---

## Status Panel

When you open a platform hub, the **Interplatform Requests** panel appears showing:

- **Need** — how many items are still needed
- **Satisfaction** — current / requested amounts
- **In Transit** — items currently in cargo pods
- **Available** — items on other platforms (minus reserves)
- **From** — which platform will provide the items

The panel updates automatically every second.

---

## Reserves

Want to keep some items on a hub and prevent them from being sent away?

1. Open the platform hub
2. In the **Reserves** section, click the item picker to add a reserve
3. Set the amount — it saves automatically as you type
4. **Left-click** a reserve icon to change the item
5. **Right-click** a reserve icon to remove it

Reserves are per-hub. Each platform hub has its own independent reserve settings.

---

## Tips

- **Keep hubs stocked** — The mod can only transfer what exists in other platform hubs
- **Same orbit required** — Platforms must be at the exact same space location
- **Quality matters** — Requests match quality (normal, uncommon, etc.)
- **Use reserves** — Prevent a hub from giving away items it needs locally

---

## Troubleshooting

**Don't see "Planetary Orbit" in the grid of buttons?**
- Make sure you've researched the Interplatform Requests technology
- Check the mod is loaded: Main menu > Mods > look for "Interplatform Requests"

**Items not transferring?**
- Both platforms must be at the **exact same space location** (check the map)
- Source platform must have items in its **hub** (not in chests)
- Request must have "Planetary Orbit" selected as import source
- Check if the source hub has reserves that reduce available amounts

**Status panel not showing?**
- Open the platform hub — the panel appears automatically alongside it
