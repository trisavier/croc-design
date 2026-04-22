#!/bin/bash
# =============================================================================
# Task 1: Fix Image Paths in Final Report
# =============================================================================
# Copies all 6 images into docs/images/ and updates final_report.md
# to use relative paths (images/filename.png) instead of absolute paths.
#
# Usage: bash docs/fix_images.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="$SCRIPT_DIR/final_report.md"
IMG_DIR="$SCRIPT_DIR/images"

# Source locations (ordered by priority: sim/gen_waveform.py output → .gemini → openroad)
GEMINI_DIR="/home/minhtri/.gemini/antigravity/brain/49fa3db7-a216-4bbd-b90e-a809112acd90"
SIM_DIR="/home/minhtri/eda/designs/test1/croc/sim"
PNR_DIR="/home/minhtri/eda/designs/test1/croc/openroad/reports"

echo "============================================================"
echo "  Fix Image Paths – Final Report"
echo "============================================================"
echo "  Report: $REPORT"
echo "  Images: $IMG_DIR"
echo ""

# ─── Step 1: Verify report exists ────────────────────────────────
if [ ! -f "$REPORT" ]; then
    echo "[ERROR] Report not found: $REPORT"
    exit 1
fi

# ─── Step 2: Create images directory ─────────────────────────────
mkdir -p "$IMG_DIR"
echo "[1/3] Created directory: $IMG_DIR"

# ─── Step 3: Copy images ────────────────────────────────────────
copy_image() {
    local filename="$1"
    shift
    local sources=("$@")

    for src in "${sources[@]}"; do
        if [ -f "$src" ]; then
            cp "$src" "$IMG_DIR/$filename"
            echo "  ✅ $filename  ← $(basename $(dirname $src))/$(basename $src)"
            return 0
        fi
    done

    echo "  ❌ $filename  — NOT FOUND in any source location!"
    return 1
}

echo ""
echo "[2/3] Copying images..."

ERRORS=0

# Waveform images (prefer sim/ generated versions, fallback to .gemini/)
copy_image "waveform_overview.png" \
    "$SIM_DIR/waveform_overview.png" \
    "$GEMINI_DIR/waveform_overview.png" || ERRORS=$((ERRORS+1))

copy_image "waveform_write.png" \
    "$SIM_DIR/waveform_write.png" \
    "$GEMINI_DIR/waveform_write.png" || ERRORS=$((ERRORS+1))

copy_image "waveform_read.png" \
    "$SIM_DIR/waveform_read.png" \
    "$GEMINI_DIR/waveform_read.png" || ERRORS=$((ERRORS+1))

# PnR layout images (prefer openroad/reports/ originals, fallback to .gemini/)
copy_image "pnr_floorplan.png" \
    "$PNR_DIR/01_croc.floorplan.png" \
    "$GEMINI_DIR/pnr_floorplan.png" || ERRORS=$((ERRORS+1))

copy_image "pnr_placed.png" \
    "$PNR_DIR/02_croc.placed.png" \
    "$GEMINI_DIR/pnr_placed.png" || ERRORS=$((ERRORS+1))

copy_image "pnr_final.png" \
    "$PNR_DIR/05_croc.final.png" \
    "$GEMINI_DIR/pnr_final.png" || ERRORS=$((ERRORS+1))

# ─── Step 4: Fix paths in report ────────────────────────────────
echo ""
echo "[3/3] Fixing image paths in report..."

# Backup original
cp "$REPORT" "$REPORT.bak"
echo "  📋 Backup: $REPORT.bak"

# Replace all absolute .gemini paths with relative images/ paths
sed -i \
    -e "s|/home/minhtri/.gemini/antigravity/brain/[^)]*waveform_overview\.png|images/waveform_overview.png|g" \
    -e "s|/home/minhtri/.gemini/antigravity/brain/[^)]*waveform_write\.png|images/waveform_write.png|g" \
    -e "s|/home/minhtri/.gemini/antigravity/brain/[^)]*waveform_read\.png|images/waveform_read.png|g" \
    -e "s|/home/minhtri/.gemini/antigravity/brain/[^)]*pnr_floorplan\.png|images/pnr_floorplan.png|g" \
    -e "s|/home/minhtri/.gemini/antigravity/brain/[^)]*pnr_placed\.png|images/pnr_placed.png|g" \
    -e "s|/home/minhtri/.gemini/antigravity/brain/[^)]*pnr_final\.png|images/pnr_final.png|g" \
    "$REPORT"

# Verify replacements
REMAINING=$(grep -c "/home/minhtri/.gemini" "$REPORT" 2>/dev/null || true)
FIXED=$(grep -c "images/" "$REPORT" 2>/dev/null || true)

echo "  ✅ Fixed $FIXED image references"
if [ "$REMAINING" -gt 0 ]; then
    echo "  ⚠️  $REMAINING absolute paths still remain (non-image references)"
else
    echo "  ✅ No broken absolute paths remain"
fi

# ─── Summary ────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Summary"
echo "============================================================"
echo "  Images copied:   $(ls -1 "$IMG_DIR"/*.png 2>/dev/null | wc -l) / 6"
echo "  Errors:          $ERRORS"
echo "  Report updated:  $REPORT"
echo "  Backup:          $REPORT.bak"
echo ""
echo "  docs/"
echo "  ├── final_report.md"
echo "  ├── final_report.md.bak"
echo "  └── images/"
ls -1 "$IMG_DIR"/*.png 2>/dev/null | while read f; do
    SIZE=$(du -h "$f" | cut -f1)
    echo "      ├── $(basename $f)  ($SIZE)"
done
echo ""

if [ "$ERRORS" -eq 0 ]; then
    echo "  ✅ ALL DONE – Report is ready for PDF export"
else
    echo "  ⚠️  $ERRORS image(s) missing – see regeneration scripts below"
fi
echo "============================================================"
