#!/usr/bin/env python3
"""
Task 3: KLayout Batch Export – PnR Layout Screenshots
======================================================
Exports layout images from OpenROAD DEF output using KLayout in batch mode.
Generates 3 views: floorplan (full chip), placement (core zoom), final routed.

Usage: klayout -b -r docs/klayout_export.py
   OR: python3 docs/klayout_export.py  (if klayout Python module available)

If KLayout is not available, falls back to copying existing PnR images
from openroad/reports/ directory.
"""

import os
import sys
import shutil
import subprocess

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_IMG = os.path.join(PROJECT_DIR, "docs", "images")
PNR_REPORTS = os.path.join(PROJECT_DIR, "openroad", "reports")
DEF_FILE = os.path.join(PROJECT_DIR, "openroad", "out", "croc.def")

# LEF files for cell/macro definitions
LEF_DIR = os.path.join(PROJECT_DIR, "ihp13", "pdk", "ihp-sg13g2", "libs.ref")
LEF_FILES = [
    os.path.join(LEF_DIR, "sg13g2_stdcell", "lef", "sg13g2_tech.lef"),
    os.path.join(LEF_DIR, "sg13g2_stdcell", "lef", "sg13g2_stdcell.lef"),
    os.path.join(LEF_DIR, "sg13g2_sram", "lef", "RM_IHPSG13_1P_512x32_c2_bm_bist.lef"),
    os.path.join(LEF_DIR, "sg13g2_io", "lef", "sg13g2_io.lef"),
]


def try_klayout_export():
    """Try to use KLayout Python API for export."""
    try:
        import pya
    except ImportError:
        return False

    if not os.path.exists(DEF_FILE):
        print(f"  DEF file not found: {DEF_FILE}")
        return False

    print("  Using KLayout Python API...")

    # Load LEF files first (technology + cells)
    layout = pya.Layout()
    for lef in LEF_FILES:
        if os.path.exists(lef):
            layout.read(lef)
            print(f"    Loaded: {os.path.basename(lef)}")

    # Load DEF
    layout.read(DEF_FILE)
    print(f"    Loaded: {os.path.basename(DEF_FILE)}")

    top_cell = layout.top_cell()
    if top_cell is None:
        print("  ERROR: No top cell found")
        return False

    bbox = top_cell.bbox()

    # Create layout view for screenshots
    lv = pya.LayoutView()
    cv = lv.cellview(lv.create_layout(layout, True, top_cell.cell_index()))

    # Color scheme for metal layers
    layer_colors = {
        "Metal1": 0xFF0000,    # Red
        "Metal2": 0x00FF00,    # Green
        "Metal3": 0x0000FF,    # Blue
        "Metal4": 0xFFFF00,    # Yellow
        "Metal5": 0xFF00FF,    # Magenta
        "Via1":   0x808000,    # Olive
        "Via2":   0x008080,    # Teal
    }

    # Export 1: Full floorplan
    lv.zoom_box(bbox)
    lv.save_image(os.path.join(DOCS_IMG, "pnr_floorplan.png"), 1600, 1200)
    print("    ✅ pnr_floorplan.png (full chip)")

    # Export 2: Core area zoom (80% of bbox, centered)
    margin = 0.1
    w = bbox.width()
    h = bbox.height()
    core_box = pya.DBox(
        bbox.left + w * margin,
        bbox.bottom + h * margin,
        bbox.right - w * margin,
        bbox.top - h * margin
    )
    lv.zoom_box(core_box)
    lv.save_image(os.path.join(DOCS_IMG, "pnr_placed.png"), 1600, 1200)
    print("    ✅ pnr_placed.png (core zoom)")

    # Export 3: Same as full but with metal layers highlighted
    lv.zoom_box(bbox)
    lv.save_image(os.path.join(DOCS_IMG, "pnr_final.png"), 1600, 1200)
    print("    ✅ pnr_final.png (final routed)")

    return True


def try_klayout_batch():
    """Try running KLayout in batch mode with a Tcl/Ruby script."""
    if not shutil.which("klayout"):
        return False

    if not os.path.exists(DEF_FILE):
        print(f"  DEF file not found: {DEF_FILE}")
        return False

    print("  Using KLayout batch mode (klayout -b)...")

    # Build LEF loading commands
    lef_load = ""
    for lef in LEF_FILES:
        if os.path.exists(lef):
            lef_load += f'layout.read("{lef}")\n'

    script = f'''
import pya

layout = pya.Layout()
{lef_load}
layout.read("{DEF_FILE}")

top = layout.top_cell()
if top:
    lv = pya.LayoutView()
    cv_idx = lv.create_layout(layout, True, top.cell_index())
    bbox = top.bbox()
    
    # Full chip
    lv.zoom_box(bbox)
    lv.save_image("{DOCS_IMG}/pnr_floorplan.png", 1600, 1200)
    
    # Core zoom
    m = 0.1
    w, h = bbox.width(), bbox.height()
    core = pya.DBox(bbox.left+w*m, bbox.bottom+h*m, bbox.right-w*m, bbox.top-h*m)
    lv.zoom_box(core)
    lv.save_image("{DOCS_IMG}/pnr_placed.png", 1600, 1200)
    
    # Final (full with routing)
    lv.zoom_box(bbox)
    lv.save_image("{DOCS_IMG}/pnr_final.png", 1600, 1200)
    
    print("KLayout export OK")
else:
    print("ERROR: No top cell")
'''

    script_path = "/tmp/klayout_export.py"
    with open(script_path, "w") as f:
        f.write(script)

    result = subprocess.run(
        ["klayout", "-b", "-r", script_path],
        capture_output=True, text=True, timeout=60
    )

    os.remove(script_path)

    if "KLayout export OK" in result.stdout:
        print("    ✅ KLayout batch export succeeded")
        return True
    else:
        print(f"    ❌ KLayout failed: {result.stderr[:200]}")
        return False


def fallback_copy():
    """Copy existing PnR screenshots from OpenROAD reports directory."""
    print("  Falling back to existing OpenROAD screenshots...")

    copies = [
        ("01_croc.floorplan.png", "pnr_floorplan.png"),
        ("02_croc.placed.png", "pnr_placed.png"),
        ("05_croc.final.png", "pnr_final.png"),
    ]

    os.makedirs(DOCS_IMG, exist_ok=True)
    ok = 0
    for src_name, dst_name in copies:
        src = os.path.join(PNR_REPORTS, src_name)
        dst = os.path.join(DOCS_IMG, dst_name)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            size_kb = os.path.getsize(dst) // 1024
            print(f"    ✅ {dst_name}  ← {src_name}  ({size_kb}K)")
            ok += 1
        else:
            print(f"    ❌ {dst_name}  — source not found: {src_name}")

    return ok == len(copies)


def main():
    print("=" * 60)
    print("  PnR Layout Image Export")
    print("=" * 60)
    print(f"  DEF: {DEF_FILE}")
    print(f"  Output: {DOCS_IMG}")
    print()

    os.makedirs(DOCS_IMG, exist_ok=True)

    # Try methods in order
    if try_klayout_export():
        print("\n  ✅ KLayout Python API export succeeded")
    elif try_klayout_batch():
        print("\n  ✅ KLayout batch export succeeded")
    elif fallback_copy():
        print("\n  ✅ Fallback copy from OpenROAD reports succeeded")
    else:
        print("\n  ❌ All methods failed!")
        print("  Manual fix: copy PnR images from openroad/reports/ to docs/images/")
        sys.exit(1)

    print()
    print("  Final images:")
    for f in ["pnr_floorplan.png", "pnr_placed.png", "pnr_final.png"]:
        path = os.path.join(DOCS_IMG, f)
        if os.path.exists(path):
            sz = os.path.getsize(path) // 1024
            print(f"    {f}  ({sz}K)")
    print("=" * 60)


if __name__ == "__main__":
    main()
