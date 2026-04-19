// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// OBI I2C Master Peripheral
// Top-level module integrating register file and I2C bit/byte controllers.
// Supports Standard Mode (100kHz) and Fast Mode (400kHz) via prescaler.

`include "common_cells/registers.svh"

module obi_i2c import obi_i2c_reg_pkg::*; #(
    /// The OBI configuration for all ports.
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    /// OBI request type
    parameter type obi_req_t = logic,
    /// OBI response type
    parameter type obi_rsp_t = logic
) (
    /// Clock
    input  logic clk_i,
    /// Active-low reset
    input  logic rst_ni,

    /// OBI request interface
    input  obi_req_t  obi_req_i,
    /// OBI response interface
    output obi_rsp_t  obi_rsp_o,

    /// Interrupt output
    output logic irq_o,

    /// I2C interface - directly active signals, directly active for open-drain usage
    /// Active-high for driving signal low on the pin via open-drain (active-low on wire)
    output logic scl_o,     // SCL output value (active-low drive)
    output logic scl_oe_o,  // SCL output enable (active-high = drive low)
    input  logic scl_i,     // SCL input (directly from pad)
    output logic sda_o,     // SDA output value (active-low drive)
    output logic sda_oe_o,  // SDA output enable (active-high = drive low)
    input  logic sda_i      // SDA input (directly from pad)
);

  //-----------------------------------------------------------------------------------------------
  // Register file
  //-----------------------------------------------------------------------------------------------
  i2c_reg2hw_t reg2hw;
  i2c_hw2reg_t hw2reg;

  obi_i2c_reg_top #(
    .ObiCfg    ( ObiCfg    ),
    .obi_req_t ( obi_req_t ),
    .obi_rsp_t ( obi_rsp_t )
  ) i_reg_top (
    .clk_i,
    .rst_ni,
    .obi_req_i,
    .obi_rsp_o,
    .reg2hw,
    .hw2reg
  );

  //-----------------------------------------------------------------------------------------------
  // I2C Master Controller
  //-----------------------------------------------------------------------------------------------

  // Internal signals
  logic        i2c_en;
  logic        irq_en;

  // Command signals (active for one cycle only when cmd is set and core is idle)
  logic        cmd_start;
  logic        cmd_stop;
  logic        cmd_read;
  logic        cmd_write;
  logic        cmd_nack;

  // Status signals
  logic        tip;          // Transfer in progress
  logic        irq_flag;
  logic        rx_ack;       // Received ACK from slave
  logic        al;           // Arbitration lost
  logic        busy;         // Bus busy

  // Bit controller signals
  logic [7:0]  rx_data;
  logic        rx_data_valid;
  logic        cmd_done;

  assign i2c_en   = reg2hw.ctrl_en;
  assign irq_en   = reg2hw.ctrl_ien;

  // Command decoding - only valid when core is enabled and not busy
  assign cmd_start = reg2hw.cmd_start & i2c_en & ~tip;
  assign cmd_stop  = reg2hw.cmd_stop  & i2c_en & ~tip;
  assign cmd_read  = reg2hw.cmd_read  & i2c_en & ~tip;
  assign cmd_write = reg2hw.cmd_write & i2c_en & ~tip;
  assign cmd_nack  = reg2hw.cmd_nack;

  //-----------------------------------------------------------------------------------------------
  // SCL Clock Generation (Bit Controller)
  //-----------------------------------------------------------------------------------------------

  // Prescale counter for SCL generation
  // SCL frequency = clk_i / (5 * (prescale + 1))
  // For 20MHz clk:
  //   100kHz SCL -> prescale = 39  (20e6 / (5*40) = 100kHz)
  //   400kHz SCL -> prescale = 9   (20e6 / (5*10) = 400kHz)

  logic [15:0] prescale_cnt;
  logic        prescale_tick;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prescale_cnt <= '0;
    end else if (!i2c_en) begin
      prescale_cnt <= '0;
    end else if (prescale_cnt == '0) begin
      prescale_cnt <= reg2hw.prescale;
    end else begin
      prescale_cnt <= prescale_cnt - 1'b1;
    end
  end

  assign prescale_tick = (prescale_cnt == '0) & i2c_en;

  //-----------------------------------------------------------------------------------------------
  // SCL Phase Counter (4 phases per SCL cycle: low-hold, rise, high-hold, fall)
  //-----------------------------------------------------------------------------------------------
  logic [2:0] scl_phase;  // 0..4 phases

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      scl_phase <= '0;
    end else if (!i2c_en) begin
      scl_phase <= '0;
    end else if (prescale_tick & tip) begin
      if (scl_phase == 3'd4) begin
        scl_phase <= '0;
      end else begin
        scl_phase <= scl_phase + 1'b1;
      end
    end
  end

  //-----------------------------------------------------------------------------------------------
  // Byte Transfer State Machine
  //-----------------------------------------------------------------------------------------------

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_START_A,     // Pull SDA low while SCL high -> START condition
    ST_START_B,
    ST_WRITE_BIT,   // Clock out bits
    ST_WRITE_WAIT,  // Wait for SCL cycle
    ST_READ_BIT,    // Clock in bits
    ST_READ_WAIT,   // Wait for SCL cycle
    ST_ACK_SEND,    // Send ACK/NACK
    ST_ACK_WAIT,
    ST_ACK_READ,    // Read ACK from slave
    ST_ACK_RWAIT,
    ST_STOP_A,      // Pull SDA low
    ST_STOP_B,      // Release SDA while SCL high -> STOP condition
    ST_STOP_C
  } i2c_state_e;

  i2c_state_e state_d, state_q;
  `FF(state_q, state_d, ST_IDLE, clk_i, rst_ni)

  logic [2:0] bit_cnt_d, bit_cnt_q;  // Bit counter (0..7)
  `FF(bit_cnt_q, bit_cnt_d, '0, clk_i, rst_ni)

  logic [7:0] shift_reg_d, shift_reg_q;  // Shift register for byte
  `FF(shift_reg_q, shift_reg_d, '0, clk_i, rst_ni)

  logic scl_out_d, scl_out_q;  // SCL output register
  `FF(scl_out_q, scl_out_d, 1'b1, clk_i, rst_ni)

  logic sda_out_d, sda_out_q;  // SDA output register
  `FF(sda_out_q, sda_out_d, 1'b1, clk_i, rst_ni)

  logic rx_ack_d, rx_ack_q;
  `FF(rx_ack_q, rx_ack_d, 1'b0, clk_i, rst_ni)

  logic irq_flag_d, irq_flag_q;
  `FF(irq_flag_q, irq_flag_d, 1'b0, clk_i, rst_ni)

  logic al_d, al_q;
  `FF(al_q, al_d, 1'b0, clk_i, rst_ni)

  logic busy_d, busy_q;
  `FF(busy_q, busy_d, 1'b0, clk_i, rst_ni)

  // Synchronized SDA input (2-stage synchronizer)
  logic sda_sync;
  sync #(
    .STAGES(2)
  ) i_sda_sync (
    .clk_i,
    .rst_ni,
    .serial_i (sda_i),
    .serial_o (sda_sync)
  );

  // Synchronized SCL input
  logic scl_sync;
  sync #(
    .STAGES(2)
  ) i_scl_sync (
    .clk_i,
    .rst_ni,
    .serial_i (scl_i),
    .serial_o (scl_sync)
  );

  // Arbitration lost detection
  logic arb_lost;
  assign arb_lost = sda_out_q & ~sda_sync & scl_sync; // We want SDA high but it's low

  // Bus busy detection (between START and STOP)
  logic sda_prev_d, sda_prev_q;
  `FF(sda_prev_q, sda_prev_d, 1'b1, clk_i, rst_ni)
  assign sda_prev_d = sda_sync;

  logic start_detect, stop_detect;
  assign start_detect = sda_prev_q & ~sda_sync & scl_sync; // SDA falls while SCL high
  assign stop_detect  = ~sda_prev_q & sda_sync & scl_sync; // SDA rises while SCL high

  //-----------------------------------------------------------------------------------------------
  // Main State Machine
  //-----------------------------------------------------------------------------------------------
  always_comb begin
    // Defaults - hold current values
    state_d     = state_q;
    bit_cnt_d   = bit_cnt_q;
    shift_reg_d = shift_reg_q;
    scl_out_d   = scl_out_q;
    sda_out_d   = sda_out_q;
    rx_ack_d    = rx_ack_q;
    irq_flag_d  = irq_flag_q;
    al_d        = al_q;
    busy_d      = busy_q;

    rx_data       = '0;
    rx_data_valid = 1'b0;
    cmd_done      = 1'b0;
    tip           = 1'b0;

    // Bus busy tracking
    if (start_detect) busy_d = 1'b1;
    if (stop_detect)  busy_d = 1'b0;

    // Arbitration lost handling
    if (arb_lost && state_q != ST_IDLE) begin
      al_d      = 1'b1;
      state_d   = ST_IDLE;
      scl_out_d = 1'b1;
      sda_out_d = 1'b1;
      cmd_done  = 1'b1;
      irq_flag_d = irq_en;
    end else begin

      case (state_q)
        ST_IDLE: begin
          scl_out_d = 1'b1;
          sda_out_d = 1'b1;

          if (cmd_start && (cmd_write || cmd_read)) begin
            state_d   = ST_START_A;
            sda_out_d = 1'b1;
            scl_out_d = 1'b1;
          end else if (cmd_write) begin
            state_d     = ST_WRITE_BIT;
            shift_reg_d = reg2hw.tx_data;
            bit_cnt_d   = 3'd7;
            scl_out_d   = 1'b0;  // SCL low to start bit clocking
          end else if (cmd_read) begin
            state_d   = ST_READ_BIT;
            bit_cnt_d = 3'd7;
            sda_out_d = 1'b1;    // Release SDA for slave to drive
            scl_out_d = 1'b0;
          end else if (cmd_stop) begin
            state_d   = ST_STOP_A;
            sda_out_d = 1'b0;
            scl_out_d = 1'b0;
          end
        end

        // ----- START condition -----
        ST_START_A: begin
          tip = 1'b1;
          // Ensure SCL and SDA are high first (repeated start handling)
          scl_out_d = 1'b1;
          sda_out_d = 1'b1;
          if (prescale_tick) begin
            state_d = ST_START_B;
          end
        end

        ST_START_B: begin
          tip = 1'b1;
          // Pull SDA low while SCL stays high -> START condition
          sda_out_d = 1'b0;
          if (prescale_tick) begin
            scl_out_d = 1'b0;  // Then pull SCL low
            busy_d    = 1'b1;
            // Begin write or read after START
            if (cmd_write) begin
              state_d     = ST_WRITE_BIT;
              shift_reg_d = reg2hw.tx_data;
              bit_cnt_d   = 3'd7;
            end else if (cmd_read) begin
              state_d   = ST_READ_BIT;
              bit_cnt_d = 3'd7;
              sda_out_d = 1'b1;
            end else begin
              state_d = ST_IDLE;
              cmd_done = 1'b1;
              irq_flag_d = irq_en;
            end
          end
        end

        // ----- WRITE bits -----
        ST_WRITE_BIT: begin
          tip = 1'b1;
          scl_out_d = 1'b0;  // SCL low
          sda_out_d = shift_reg_q[7]; // MSB first
          if (prescale_tick) begin
            state_d = ST_WRITE_WAIT;
          end
        end

        ST_WRITE_WAIT: begin
          tip = 1'b1;
          scl_out_d = 1'b1;  // SCL high - slave samples data
          if (prescale_tick) begin
            scl_out_d = 1'b0;
            if (bit_cnt_q == '0) begin
              // All 8 bits sent, read ACK from slave
              state_d   = ST_ACK_READ;
              sda_out_d = 1'b1; // Release SDA for slave ACK
            end else begin
              state_d     = ST_WRITE_BIT;
              bit_cnt_d   = bit_cnt_q - 1'b1;
              shift_reg_d = {shift_reg_q[6:0], 1'b0};
            end
          end
        end

        // ----- READ bits -----
        ST_READ_BIT: begin
          tip = 1'b1;
          scl_out_d = 1'b0;  // SCL low
          sda_out_d = 1'b1;  // Release SDA for slave
          if (prescale_tick) begin
            state_d = ST_READ_WAIT;
          end
        end

        ST_READ_WAIT: begin
          tip = 1'b1;
          scl_out_d = 1'b1;  // SCL high - sample SDA from slave
          if (prescale_tick) begin
            scl_out_d   = 1'b0;
            shift_reg_d = {shift_reg_q[6:0], sda_sync};
            if (bit_cnt_q == '0) begin
              // All 8 bits read, need to send ACK/NACK
              state_d       = ST_ACK_SEND;
              rx_data       = {shift_reg_q[6:0], sda_sync};
              rx_data_valid = 1'b1;
            end else begin
              state_d   = ST_READ_BIT;
              bit_cnt_d = bit_cnt_q - 1'b1;
            end
          end
        end

        // ----- ACK send (after read) -----
        ST_ACK_SEND: begin
          tip = 1'b1;
          scl_out_d = 1'b0;
          sda_out_d = cmd_nack; // 0=ACK, 1=NACK
          if (prescale_tick) begin
            state_d = ST_ACK_WAIT;
          end
        end

        ST_ACK_WAIT: begin
          tip = 1'b1;
          scl_out_d = 1'b1;  // SCL high for ACK clock
          if (prescale_tick) begin
            scl_out_d  = 1'b0;
            state_d    = ST_IDLE;
            cmd_done   = 1'b1;
            irq_flag_d = irq_en;
            sda_out_d  = 1'b1;
          end
        end

        // ----- ACK read (after write) -----
        ST_ACK_READ: begin
          tip = 1'b1;
          scl_out_d = 1'b0;
          sda_out_d = 1'b1;  // Release SDA
          if (prescale_tick) begin
            state_d = ST_ACK_RWAIT;
          end
        end

        ST_ACK_RWAIT: begin
          tip = 1'b1;
          scl_out_d = 1'b1;  // SCL high, sample slave ACK
          if (prescale_tick) begin
            scl_out_d  = 1'b0;
            rx_ack_d   = sda_sync; // 0=ACK, 1=NACK from slave
            state_d    = ST_IDLE;
            cmd_done   = 1'b1;
            irq_flag_d = irq_en;
          end
        end

        // ----- STOP condition -----
        ST_STOP_A: begin
          tip = 1'b1;
          sda_out_d = 1'b0;  // SDA low
          scl_out_d = 1'b0;  // SCL low
          if (prescale_tick) begin
            state_d   = ST_STOP_B;
            scl_out_d = 1'b1;  // Release SCL high
          end
        end

        ST_STOP_B: begin
          tip = 1'b1;
          scl_out_d = 1'b1;  // SCL high
          sda_out_d = 1'b0;  // SDA still low
          if (prescale_tick) begin
            state_d   = ST_STOP_C;
            sda_out_d = 1'b1;  // Release SDA -> STOP condition
          end
        end

        ST_STOP_C: begin
          tip = 1'b1;
          scl_out_d = 1'b1;
          sda_out_d = 1'b1;
          busy_d     = 1'b0;
          if (prescale_tick) begin
            state_d    = ST_IDLE;
            cmd_done   = 1'b1;
            irq_flag_d = irq_en;
          end
        end

        default: begin
          state_d = ST_IDLE;
        end
      endcase

    end // else (not arb_lost)

    // Disable handling
    if (!i2c_en) begin
      state_d   = ST_IDLE;
      scl_out_d = 1'b1;
      sda_out_d = 1'b1;
    end
  end

  //-----------------------------------------------------------------------------------------------
  // Output assignments
  //-----------------------------------------------------------------------------------------------

  // Open-drain: output enable drives the pin LOW
  // When scl_out_q = 0, drive SCL low (oe=1, out=0)
  // When scl_out_q = 1, release SCL (oe=0, let pull-up take over)
  assign scl_o    = 1'b0;               // Always drive low when enabled
  assign scl_oe_o = ~scl_out_q & i2c_en; // Enable drive when we want low

  assign sda_o    = 1'b0;               // Always drive low when enabled
  assign sda_oe_o = ~sda_out_q & i2c_en; // Enable drive when we want low

  //-----------------------------------------------------------------------------------------------
  // HW -> Register feedback
  //-----------------------------------------------------------------------------------------------
  assign hw2reg.rx_data       = rx_data;
  assign hw2reg.rx_data_valid = rx_data_valid;
  assign hw2reg.tip           = tip;
  assign hw2reg.irq_flag      = irq_flag_d;
  assign hw2reg.irq_flag_valid = cmd_done | arb_lost;
  assign hw2reg.rx_ack        = rx_ack_q;
  assign hw2reg.al            = al_d;
  assign hw2reg.al_valid      = arb_lost;
  assign hw2reg.busy          = busy_q;
  assign hw2reg.cmd_done      = cmd_done;

  //-----------------------------------------------------------------------------------------------
  // Interrupt output
  //-----------------------------------------------------------------------------------------------
  assign irq_o = irq_flag_q & irq_en;

endmodule
