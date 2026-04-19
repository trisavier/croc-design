// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// I2C Register Package
// Defines register map, types and offsets for the OBI I2C peripheral.

package obi_i2c_reg_pkg;

  // Address width within this peripheral used for address decoding (peripheral occupies 4KB)
  parameter int AddressWidth = 12;

  //-----------------------------------------------------------------------------------------------
  // Register Offsets
  //-----------------------------------------------------------------------------------------------
  parameter logic [AddressWidth-1:0] I2C_PRESCALE_OFFSET = 12'h000; // Clock prescaler (R/W)
  parameter logic [AddressWidth-1:0] I2C_CTRL_OFFSET     = 12'h004; // Control register (R/W)
  parameter logic [AddressWidth-1:0] I2C_TX_DATA_OFFSET  = 12'h008; // Transmit data (R/W)
  parameter logic [AddressWidth-1:0] I2C_RX_DATA_OFFSET  = 12'h00C; // Receive data (R)
  parameter logic [AddressWidth-1:0] I2C_CMD_OFFSET      = 12'h010; // Command register (R/W)
  parameter logic [AddressWidth-1:0] I2C_STATUS_OFFSET   = 12'h014; // Status register (R)

  //-----------------------------------------------------------------------------------------------
  // Control register bits
  //-----------------------------------------------------------------------------------------------
  parameter int CTRL_EN_BIT  = 0; // I2C core enable
  parameter int CTRL_IEN_BIT = 1; // Interrupt enable

  //-----------------------------------------------------------------------------------------------
  // Command register bits
  //-----------------------------------------------------------------------------------------------
  parameter int CMD_START_BIT = 0; // Generate START condition
  parameter int CMD_STOP_BIT  = 1; // Generate STOP condition
  parameter int CMD_READ_BIT  = 2; // Read from slave
  parameter int CMD_WRITE_BIT = 3; // Write to slave
  parameter int CMD_NACK_BIT  = 4; // Send NACK after read (vs ACK)

  //-----------------------------------------------------------------------------------------------
  // Status register bits
  //-----------------------------------------------------------------------------------------------
  parameter int STATUS_TIP_BIT    = 0; // Transfer in progress
  parameter int STATUS_IF_BIT     = 1; // Interrupt flag
  parameter int STATUS_RXACK_BIT  = 2; // Received ACK from slave (0=ACK, 1=NACK)
  parameter int STATUS_AL_BIT     = 3; // Arbitration lost
  parameter int STATUS_BUSY_BIT   = 4; // I2C bus busy (START detected)

  //-----------------------------------------------------------------------------------------------
  // Signals from registers to logic (reg2hw)
  //-----------------------------------------------------------------------------------------------
  typedef struct packed {
    logic [15:0] prescale;  // Clock prescaler value
    logic        ctrl_en;   // Core enable
    logic        ctrl_ien;  // Interrupt enable
    logic [ 7:0] tx_data;   // Transmit data byte
    logic        cmd_start; // START command
    logic        cmd_stop;  // STOP command
    logic        cmd_read;  // READ command
    logic        cmd_write; // WRITE command
    logic        cmd_nack;  // NACK after read
  } i2c_reg2hw_t;

  //-----------------------------------------------------------------------------------------------
  // Signals from logic to registers (hw2reg)
  //-----------------------------------------------------------------------------------------------
  typedef struct packed {
    logic [7:0] rx_data;      // Received data byte
    logic       rx_data_valid;// RX data is valid (update register)
    logic       tip;          // Transfer in progress
    logic       irq_flag;     // Interrupt flag
    logic       irq_flag_valid;
    logic       rx_ack;       // Received ACK (0=ACK, 1=NACK)
    logic       al;           // Arbitration lost
    logic       al_valid;
    logic       busy;         // Bus busy
    logic       cmd_done;     // Command completed (clear CMD register)
  } i2c_hw2reg_t;

endpackage
