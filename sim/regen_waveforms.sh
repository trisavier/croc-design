#!/bin/bash
# =============================================================================
# Task 2: Regenerate Waveform PNGs from VCD
# =============================================================================
# Two methods:
#   Method A: Python/matplotlib (headless, no GUI needed) – PREFERRED
#   Method B: GTKWave batch export (needs X server or xvfb)
#
# Usage: bash sim/regen_waveforms.sh
# =============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="$PROJECT_DIR/sim"
VCD="$SIM_DIR/i2c_waveform.vcd"
DOCS_IMG="$PROJECT_DIR/docs/images"

echo "============================================================"
echo "  Regenerate Waveform Images"
echo "============================================================"

# Check VCD exists
if [ ! -f "$VCD" ]; then
    echo "[ERROR] VCD file not found: $VCD"
    echo "        Run simulation first: bash sim/run_sim.sh"
    exit 1
fi

# ─── Method A: Python/matplotlib (preferred) ─────────────────────
echo ""
echo "[Method A] Python + matplotlib (headless)..."

if python3 -c "import matplotlib" 2>/dev/null; then
    python3 "$SIM_DIR/gen_waveform.py"
    
    # Copy to docs/images/ if exists
    if [ -d "$DOCS_IMG" ]; then
        cp "$SIM_DIR/waveform_overview.png" "$DOCS_IMG/"
        cp "$SIM_DIR/waveform_write.png" "$DOCS_IMG/"
        cp "$SIM_DIR/waveform_read.png" "$DOCS_IMG/"
        echo "  ✅ Copied to docs/images/"
    fi
    
    echo ""
    echo "  ✅ Method A succeeded – images ready"
    exit 0
else
    echo "  ⚠️  matplotlib not available, trying Method B..."
fi

# ─── Method B: GTKWave batch (fallback) ─────────────────────────
echo ""
echo "[Method B] GTKWave batch export..."

# Check if gtkwave is available
if ! command -v gtkwave &>/dev/null; then
    echo "  ❌ gtkwave not found!"
    echo "  Install: sudo apt install gtkwave"
    exit 1
fi

# Check if xvfb is available (for headless)
XVFB=""
if command -v xvfb-run &>/dev/null; then
    XVFB="xvfb-run -a"
    echo "  Using xvfb-run for headless mode"
elif [ -z "$DISPLAY" ]; then
    echo "  ⚠️  No DISPLAY set and xvfb-run not found."
    echo "  Install: sudo apt install xvfb"
    echo "  Then re-run this script."
    exit 1
fi

# Create GTKWave Tcl scripts for each view

# Overview (full time range)
cat > /tmp/gtkwave_overview.tcl << 'TCLEOF'
# GTKWave export: Full overview
set nfacs [gtkwave::getNumFacs]
gtkwave::addSignalsFromList {
    tb_i2c.scl_bus
    tb_i2c.sda_bus
    tb_i2c.dut_master.state
    tb_i2c.dut_master.tip
    tb_i2c.dut_master.busy
    tb_i2c.dut_master.tx_data_reg
    tb_i2c.dut_master.rx_data_reg
}
gtkwave::/Time/Zoom/Zoom_Full
gtkwave::/File/Grab_To_File sim/waveform_overview.png
gtkwave::/File/Quit
TCLEOF

# Write transaction (0 to 13000 ns = 0 to 13000000 ps)
cat > /tmp/gtkwave_write.tcl << 'TCLEOF'
set nfacs [gtkwave::getNumFacs]
gtkwave::addSignalsFromList {
    tb_i2c.scl_bus
    tb_i2c.sda_bus
    tb_i2c.dut_master.state
    tb_i2c.dut_master.tip
    tb_i2c.dut_master.busy
    tb_i2c.dut_master.rx_ack
    tb_i2c.dut_master.shift_reg
}
gtkwave::setZoomRangeTimes 0 13000000000
gtkwave::/File/Grab_To_File sim/waveform_write.png
gtkwave::/File/Quit
TCLEOF

# Read transaction (13000 to 26000 ns)
cat > /tmp/gtkwave_read.tcl << 'TCLEOF'
set nfacs [gtkwave::getNumFacs]
gtkwave::addSignalsFromList {
    tb_i2c.scl_bus
    tb_i2c.sda_bus
    tb_i2c.dut_master.state
    tb_i2c.dut_master.tip
    tb_i2c.dut_master.busy
    tb_i2c.dut_master.rx_data_reg
    tb_i2c.dut_master.shift_reg
}
gtkwave::setZoomRangeTimes 13000000000 26000000000
gtkwave::/File/Grab_To_File sim/waveform_read.png
gtkwave::/File/Quit
TCLEOF

cd "$PROJECT_DIR"

echo "  Exporting overview..."
$XVFB gtkwave "$VCD" -S /tmp/gtkwave_overview.tcl 2>/dev/null && \
    echo "  ✅ waveform_overview.png" || echo "  ❌ Failed"

echo "  Exporting write transaction..."
$XVFB gtkwave "$VCD" -S /tmp/gtkwave_write.tcl 2>/dev/null && \
    echo "  ✅ waveform_write.png" || echo "  ❌ Failed"

echo "  Exporting read transaction..."
$XVFB gtkwave "$VCD" -S /tmp/gtkwave_read.tcl 2>/dev/null && \
    echo "  ✅ waveform_read.png" || echo "  ❌ Failed"

# Copy to docs/images/
if [ -d "$DOCS_IMG" ]; then
    cp "$SIM_DIR/waveform_"*.png "$DOCS_IMG/" 2>/dev/null
    echo "  ✅ Copied to docs/images/"
fi

# Cleanup
rm -f /tmp/gtkwave_overview.tcl /tmp/gtkwave_write.tcl /tmp/gtkwave_read.tcl

echo ""
echo "  ✅ Method B complete"
echo "============================================================"
