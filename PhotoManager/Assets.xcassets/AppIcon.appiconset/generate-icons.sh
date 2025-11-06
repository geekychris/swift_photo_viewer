#!/bin/zsh

# Script to generate all required app icon sizes from SVG
# Requires: rsvg-convert (install via: brew install librsvg)

SCRIPT_DIR="${0:a:h}"
SVG_FILE="$SCRIPT_DIR/app-icon.svg"
OUTPUT_DIR="$SCRIPT_DIR"

# Check if rsvg-convert is installed
if ! command -v rsvg-convert &> /dev/null; then
    echo "Error: rsvg-convert not found. Install with: brew install librsvg"
    exit 1
fi

# Generate 1024x1024 for iOS (universal)
echo "Generating icon-1024.png..."
rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$OUTPUT_DIR/icon-1024.png"

# Generate macOS icons
echo "Generating macOS icons..."
rsvg-convert -w 16 -h 16 "$SVG_FILE" -o "$OUTPUT_DIR/icon-16.png"
rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$OUTPUT_DIR/icon-32.png"
rsvg-convert -w 64 -h 64 "$SVG_FILE" -o "$OUTPUT_DIR/icon-64.png"
rsvg-convert -w 128 -h 128 "$SVG_FILE" -o "$OUTPUT_DIR/icon-128.png"
rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$OUTPUT_DIR/icon-256.png"
rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$OUTPUT_DIR/icon-512.png"
rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$OUTPUT_DIR/icon-1024-mac.png"

echo "All icons generated successfully!"
echo ""
echo "Note: Update Contents.json to reference all generated PNG files if needed."
