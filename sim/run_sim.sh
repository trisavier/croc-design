#!/bin/bash
# =============================================================================
# I2C Master Simulation Script
# =============================================================================
# Tools: Icarus Verilog (iverilog/vvp) + GTKWave
# Usage: cd croc/ && bash sim/run_sim.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIM_DIR="$SCRIPT_DIR"

echo "=============================================="
echo "  I2C Master – Icarus Verilog Simulation"
echo "=============================================="
echo "  Project: $PROJECT_DIR"
echo "  Sim dir: $SIM_DIR"
echo ""

# Step 1: Compile
echo "[1/3] Compiling with iverilog..."
iverilog -g2012 -Wall \
    -o "$SIM_DIR/tb_i2c.vvp" \
    "$SIM_DIR/i2c_master.v" \
    "$SIM_DIR/i2c_slave_model.v" \
    "$SIM_DIR/tb_i2c.v"
echo "  -> Compiled successfully: $SIM_DIR/tb_i2c.vvp"

# Step 2: Run simulation
echo ""
echo "[2/3] Running simulation..."
cd "$PROJECT_DIR"
vvp "$SIM_DIR/tb_i2c.vvp" | tee "$SIM_DIR/sim_results.log"
echo "  -> Simulation log: $SIM_DIR/sim_results.log"

# Step 3: Check results
echo ""
echo "[3/3] Checking results..."
if [ -f "$SIM_DIR/i2c_waveform.vcd" ]; then
    VCD_SIZE=$(du -h "$SIM_DIR/i2c_waveform.vcd" | cut -f1)
    echo "  -> Waveform file: $SIM_DIR/i2c_waveform.vcd ($VCD_SIZE)"
    echo ""
    echo "  To view waveforms:"
    echo "    gtkwave $SIM_DIR/i2c_waveform.vcd"
else
    echo "  [WARNING] No VCD waveform file generated!"
fi

# Print pass/fail summary
echo ""
if grep -q "ALL TESTS PASSED" "$SIM_DIR/sim_results.log" 2>/dev/null; then
    echo "  ✅ ALL TESTS PASSED!"
elif grep -q "SOME TESTS FAILED" "$SIM_DIR/sim_results.log" 2>/dev/null; then
    echo "  ❌ SOME TESTS FAILED – check sim_results.log"
else
    echo "  ⚠️  Test summary not found – check sim_results.log"
fi
echo ""
echo "=============================================="
