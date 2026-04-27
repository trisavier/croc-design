import pya
import os

project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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

# Configure LEF/DEF reader with LEF files
options = pya.LoadLayoutOptions()
lefdef_config = options.lefdef_config
lefdef_config.lef_files = [f for f in lef_files if os.path.exists(f)]
options.lefdef_config = lefdef_config

mw = pya.Application.instance().main_window()
if mw:
    print("Loading layout into Main Window...")
    # Load layout (mode 1 = new view)
    mw.load_layout(def_file, options, 1)
    view = mw.current_view()
    if view:
        if os.path.exists(lyp_file):
            view.load_layer_props(lyp_file)
        view.zoom_fit()
        view.max_hier() # Expand all hierarchy levels so the user sees the details
        print("Done!")
    else:
        print("Failed to get current view")
else:
    print("Error: No main window found. Are you running in GUI mode?")
