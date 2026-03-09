# Interplatform Requests - Thumbnail Guide

## Recommended Thumbnail Design

**Size**: 144x144 pixels (Factorio standard)
**Format**: PNG with transparency

## Design Concept

The thumbnail should convey:
1. Space platforms
2. Logistic robots
3. Item transfer between platforms

## Option 1: Simple Icon Composite (Recommended)

**Elements to combine:**
- Background: Dark space/starfield
- Center: Logistic robot icon
- Corners: Small platform hub icons or arrows showing transfer

**Color scheme:**
- Dark blue/black background (space)
- Orange/yellow robot (Factorio logistic robot color)
- White/light blue accents (platform elements)

## Option 2: Screenshot-based

Take a screenshot of:
1. A logistic robot flying between two platform hubs
2. Crop to 144x144
3. Add text overlay: "Interplatform Requests"

## Option 3: Use Online Tools

### Canva (Free)
1. Go to canva.com
2. Create custom size: 144x144 px
3. Use these elements:
   - Dark blue/black background
   - Robot icon (search "robot" or "drone")
   - Arrow icons showing transfer
   - Text: "PR" or robot symbol

### GIMP (Free, Open Source)
1. Download GIMP
2. Create new image: 144x144 px
3. Layer 1: Dark gradient background
4. Layer 2: Robot silhouette (center)
5. Layer 3: Arrows or platform icons
6. Export as PNG

## Quick ASCII Art Concept

```
┌──────────────────────┐
│   ╔═══╗         ╔═══╗│
│   ║ H ║ ←──🤖──→║ H ║│
│   ╚═══╝         ╚═══╝│
│  Platform    Platform│
└──────────────────────┘
```

Where:
- H = Hub
- 🤖 = Robot
- Arrows = Transfer direction

## Simple Text-Based Thumbnail

If you want something quick:

**Background**: Dark blue (#1a1a2e)
**Center text**: 
```
🤖
PR
```
**Font**: Bold, white or light blue

## Using ImageMagick (Command Line)

If you have ImageMagick installed:

```bash
# Create a simple thumbnail
convert -size 144x144 xc:'#1a1a2e' \
  -gravity center \
  -pointsize 60 -fill white -annotate +0-10 '🤖' \
  -pointsize 20 -fill '#00d4ff' -annotate +0+30 'Interplatform\nRequests' \
  thumbnail.png
```

## Recommended Colors

- **Background**: #1a1a2e (dark blue-black)
- **Robot**: #ff9500 (orange, like Factorio logistic robots)
- **Accent**: #00d4ff (light blue, like space/tech)
- **Text**: #ffffff (white)

## Where to Save

Save as: `/Users/jatruman/workspace/personal/interplatform-requests/thumbnail.png`

Factorio will automatically use this file when displaying the mod.

## Testing

After creating the thumbnail:
1. Save it as `thumbnail.png` in the mod directory
2. Restart Factorio
3. Check the mod list - your thumbnail should appear!

## Need Help?

If you want me to generate a simple placeholder, I can create a text-based one using a script, or you can use one of the online tools above.

