import pya
import os

project_dir = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(project_dir, "docs", "images")
os.makedirs(out_dir, exist_ok=True)

lef_dir = os.path.join(project_dir, "ihp13", "pdk", "ihp-sg13g2", "libs.ref")
sram_lef_dir = os.path.join(lef_dir, "sg13g2_sram", "lef")

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
lyp_file = os.path.join(project_dir, "ihp13", "pdk", "ihp-sg13g2", "libs.tech", "klayout", "tech", "sg13g2.lyp")

options = pya.LoadLayoutOptions()
lefdef_config = options.lefdef_config
lefdef_config.lef_files = [f for f in lef_files if os.path.exists(f)]
options.lefdef_config = lefdef_config

mw = pya.Application.instance().main_window()
if mw:
    print("Loading layout...")
    mw.load_layout(def_file, options, 1)
    view = mw.current_view()
    if view:
        if os.path.exists(lyp_file):
            view.load_layer_props(lyp_file)
        
        # Turn on all hierarchy levels to see standard cells/metals
        view.max_hier()
        view.set_config("background-color", "#000000")
        
        # Zoom to I2C pads
        i2c_box = pya.DBox(550.0, 1750.0, 780.0, 1900.0)
        view.zoom_box(i2c_box)
        view.save_image(os.path.join(out_dir, "pnr_i2c_pads.png"), 2400, 1800)
        print("Saved I2C pads image.")
        
        # Zoom to I2C core
        i2c_core_box = pya.DBox(700.0, 1100.0, 800.0, 1400.0)
        view.zoom_box(i2c_core_box)
        view.save_image(os.path.join(out_dir, "pnr_i2c_core.png"), 2400, 1800)
        print("Saved I2C core image.")
        
        pya.Application.instance().exit(0)
    else:
        print("No view found.")
        pya.Application.instance().exit(1)
else:
    print("No main window.")
    pya.Application.instance().exit(1)
