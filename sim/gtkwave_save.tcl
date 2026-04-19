#!/usr/bin/env tclsh
# =============================================================================
# GTKWave Script – Automated waveform display and screenshot
# Usage: gtkwave -S sim/gtkwave_save.tcl sim/i2c_waveform.vcd
# =============================================================================

# Add I2C bus signals
set nfacs [ gtkwave::getNumFacs ]

# Core signals
gtkwave::addSignalsFromList {
    tb_i2c.clk
    tb_i2c.rst_n
}

# I2C Bus signals
gtkwave::addSignalsFromList {
    tb_i2c.scl_bus
    tb_i2c.sda_bus
}

# Master internal signals
gtkwave::addSignalsFromList {
    tb_i2c.dut_master.state
    tb_i2c.dut_master.scl_out
    tb_i2c.dut_master.sda_out
    tb_i2c.dut_master.shift_reg
    tb_i2c.dut_master.bit_cnt
    tb_i2c.dut_master.rx_data_reg
    tb_i2c.dut_master.tx_data_reg
    tb_i2c.dut_master.rx_ack
    tb_i2c.dut_master.cmd_done_r
    tb_i2c.master_irq
}

# Master control
gtkwave::addSignalsFromList {
    tb_i2c.dut_master.cmd_start
    tb_i2c.dut_master.cmd_write
    tb_i2c.dut_master.cmd_read
    tb_i2c.dut_master.cmd_stop
    tb_i2c.dut_master.ctrl_en
    tb_i2c.dut_master.prescale_cnt
}

# Slave signals
gtkwave::addSignalsFromList {
    tb_i2c.dut_slave.state
    tb_i2c.dut_slave.shift_reg
    tb_i2c.dut_slave.sda_oe_o
    tb_i2c.dut_slave.bit_cnt
    tb_i2c.dut_slave.rw_bit
    tb_i2c.dut_slave.addr_matched
}

# Zoom to fit
gtkwave::/Time/Zoom/Zoom_Full

# Set time format to ns
gtkwave::/Time/Timescale/1ns
