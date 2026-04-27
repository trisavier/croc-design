#!/usr/bin/env python3
"""
KLayout batch script to load croc SoC layout with all LEF/DEF files
and export screenshots highlighting the I2C module.

Usage (batch - export images):
  klayout -b -r docs/klayout_view.py

Usage (GUI - interactive viewing):
  klayout -r docs/klayout_view.py
"""

import pya
import os

# === Paths ===
project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out_dir = os.path.join(project_dir, "docs", "images")
os.makedirs(out_dir, exist_ok=True)

lef_dir = os.path.join(project_dir, "ihp13", "pdk", "ihp-sg13g2", "libs.ref")
sram_lef_dir = os.path.join(lef_dir, "sg13g2_sram", "lef")

# Collect all SRAM LEF files dynamically
sram_lefs = []
if os.path.isdir(sram_lef_dir):
    sram_lefs = sorted([
        os.path.join(sram_lef_dir, f)
        for f in os.listdir(sram_lef_dir) if f.endswith(".lef")
    ])

lef_files = [
    os.path.join(lef_dir, "sg13g2_stdcell", "lef", "sg13g2_tech.lef"),
    os.path.join(lef_dir, "sg13g2_stdcell", "lef", "sg13g2_stdcell.lef"),
] + sram_lefs + [
    os.path.join(lef_dir, "sg13g2_io", "lef", "sg13g2_io.lef"),
    os.path.join(project_dir, "ihp13", "bondpad", "lef", "bondpad_70x70.lef"),
]

def_file = os.path.join(project_dir, "openroad", "out", "croc.def")

lyp_file = os.path.join(project_dir, "ihp13", "pdk", "ihp-sg13g2",
                        "libs.tech", "klayout", "tech", "sg13g2.lyp")

print("=" * 60)
print("  KLayout: CROC SoC Layout Viewer (with I2C)")
print("=" * 60)

# === Check files exist ===
for lef in lef_files:
    if os.path.exists(lef):
        print(f"  ✅ Found LEF: {os.path.basename(lef)}")
    else:
        print(f"  ❌ Missing LEF: {lef}")

if not os.path.exists(def_file):
    print(f"  ❌ DEF file not found: {def_file}")
    raise SystemExit(1)

print(f"  ✅ Found DEF: {os.path.basename(def_file)}")
print()

# === Load layout using LEFDEFReaderConfiguration ===
print("  Loading layout...")
ly = pya.Layout()

# Configure LEF/DEF reader with LEF files
options = pya.LoadLayoutOptions()
lefdef_config = options.lefdef_config

# Set the LEF files so DEF reader can resolve all macros
lefdef_config.lef_files = [f for f in lef_files if os.path.exists(f)]

# Apply configuration
options.lefdef_config = lefdef_config

# Read DEF with the configured options (LEFs will be loaded automatically)
ly.read(def_file, options)
print(f"  ✅ Layout loaded successfully")

# === Find top cell ===
top_cell = ly.top_cell()
if top_cell is None:
    print("  ❌ No top cell found!")
    raise SystemExit(1)

print(f"  📦 Top cell: {top_cell.name}")
bbox = top_cell.bbox()
print(f"  📐 Bounding box: {bbox}")
print(f"  📊 Total cells: {ly.cells()}")

# === Export screenshots ===
print()
print("  Exporting layout images...")

lv = pya.LayoutView()
cv_idx = lv.create_layout(ly, True, top_cell.cell_index())

# Load layer properties if available
if os.path.exists(lyp_file):
    lv.load_layer_props(lyp_file)
    print(f"  ✅ Loaded layer props: {os.path.basename(lyp_file)}")

# Expand hierarchy so we see the actual logic/metal layers!
lv.max_hier()
lv.set_config("background-color", "#000000")

# 1. Full chip floorplan
lv.zoom_box(bbox)
fp_path = os.path.join(out_dir, "pnr_floorplan.png")
lv.save_image(fp_path, 2400, 1800)
print(f"  📸 pnr_floorplan.png  ({os.path.getsize(fp_path)//1024}K)")

# 2. Core area zoom (80% of bbox, centered)
margin = 0.1
w, h = bbox.width(), bbox.height()
core_box = pya.DBox(
    bbox.left + w * margin,
    bbox.bottom + h * margin,
    bbox.right - w * margin,
    bbox.top - h * margin
)
lv.zoom_box(core_box)
placed_path = os.path.join(out_dir, "pnr_placed.png")
lv.save_image(placed_path, 2400, 1800)
print(f"  📸 pnr_placed.png     ({os.path.getsize(placed_path)//1024}K)")

# 3. Full chip final routed view
lv.zoom_box(bbox)
final_path = os.path.join(out_dir, "pnr_final.png")
lv.save_image(final_path, 2400, 1800)
print(f"  📸 pnr_final.png      ({os.path.getsize(final_path)//1024}K)")

# 4. Zoom to I2C pads area (SCL at 701000,1846000 and SDA at 612000,1846000)
i2c_box = pya.DBox(550000, 1750000, 780000, 1900000)
lv.zoom_box(i2c_box)
i2c_path = os.path.join(out_dir, "pnr_i2c_pads.png")
lv.save_image(i2c_path, 2400, 1800)
print(f"  📸 pnr_i2c_pads.png   ({os.path.getsize(i2c_path)//1024}K)")

# 5. Zoom to I2C core logic area
# I2C cells placed around x=742000-766000, y=1175000-1342000
i2c_core_box = pya.DBox(700000, 1100000, 800000, 1400000)
lv.zoom_box(i2c_core_box)
i2c_core_path = os.path.join(out_dir, "pnr_i2c_core.png")
lv.save_image(i2c_core_path, 2400, 1800)
print(f"  📸 pnr_i2c_core.png   ({os.path.getsize(i2c_core_path)//1024}K)")

print()
print("=" * 60)
print("  ✅ Export complete! Images saved to docs/images/")
print("=" * 60)
