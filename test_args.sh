#!/bin/bash
PROJECT_DIR="/home/minhtri/eda/designs/test1/croc"
LEF_DIR="$PROJECT_DIR/ihp13/pdk/ihp-sg13g2/libs.ref"
SRAM_LEF_DIR="$LEF_DIR/sg13g2_sram/lef"

# Collect all SRAM LEF files dynamically
SRAM_LEFS=""
if [ -d "$SRAM_LEF_DIR" ]; then
    for f in "$SRAM_LEF_DIR"/*.lef; do
        SRAM_LEFS="$SRAM_LEFS $f"
    done
fi

LEF_FILES="
    $LEF_DIR/sg13g2_stdcell/lef/sg13g2_tech.lef
    $LEF_DIR/sg13g2_stdcell/lef/sg13g2_stdcell.lef
    $SRAM_LEFS
    $LEF_DIR/sg13g2_io/lef/sg13g2_io.lef
    $PROJECT_DIR/ihp13/bondpad/lef/bondpad_70x70.lef
"

DEF_FILE="$PROJECT_DIR/openroad/out/croc.def"
LYP_FILE="$PROJECT_DIR/ihp13/pdk/ihp-sg13g2/libs.tech/klayout/tech/sg13g2.lyp"

echo klayout $LEF_FILES $DEF_FILE -l $LYP_FILE
