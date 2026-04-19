// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// OBI-to-Register bridge for I2C peripheral.
// Follows the same pattern as gpio_reg_top.sv

`include "common_cells/registers.svh"

module obi_i2c_reg_top import obi_i2c_reg_pkg::*; #(
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

    /// Signals from registers to I2C logic
    output i2c_reg2hw_t reg2hw,
    /// Signals from I2C logic to registers
    input  i2c_hw2reg_t hw2reg
);

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // OBI Preparations
  ////////////////////////////////////////////////////////////////////////////////////////////////////

  // Signals for the OBI response
  logic                           valid_d, valid_q;
  logic                           we_d, we_q;
  logic                           req_d, req_q;
  logic [AddressWidth-1:0]        write_addr;
  logic [AddressWidth-1:0]        read_addr_d, read_addr_q;
  logic [ObiCfg.IdWidth-1:0]      id_d, id_q;
  logic                           obi_err;
  logic                           w_err_d, w_err_q;
  logic [ObiCfg.DataWidth-1:0]    obi_rdata, obi_wdata;
  logic                           obi_read_request, obi_write_request;

  // OBI rsp Assignment
  always_comb begin
    obi_rsp_o              = '0;
    obi_rsp_o.r.rdata      = obi_rdata;
    obi_rsp_o.r.rid        = id_q;
    obi_rsp_o.r.err        = obi_err;
    obi_rsp_o.gnt          = '1; // always ready for request
    obi_rsp_o.rvalid       = valid_q;
  end

  // internally used signals
  assign obi_wdata         = obi_req_i.a.wdata;
  assign obi_read_request  = req_q & ~we_q;                  // in response phase
  assign obi_write_request = obi_req_i.req & obi_req_i.a.we; // in request phase

  // id, valid and address handling
  assign id_d          = obi_req_i.a.aid;
  assign valid_d       = obi_req_i.req;
  assign write_addr    = obi_req_i.a.addr[AddressWidth-1:0];
  assign read_addr_d   = obi_req_i.a.addr[AddressWidth-1:0];
  assign we_d          = obi_req_i.a.we;
  assign req_d         = obi_req_i.req;

  // FF for the OBI rsp signals
  `FF(id_q, id_d, '0, clk_i, rst_ni)
  `FF(valid_q, valid_d, '0, clk_i, rst_ni)
  `FF(read_addr_q, read_addr_d, '0, clk_i, rst_ni)
  `FF(req_q, req_d, '0, clk_i, rst_ni)
  `FF(we_q, we_d, '0, clk_i, rst_ni)
  `FF(w_err_q, w_err_d, '0, clk_i, rst_ni)

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Registers
  ////////////////////////////////////////////////////////////////////////////////////////////////////

  typedef struct packed {
    logic [15:0] prescale;
    logic [ 7:0] ctrl;
    logic [ 7:0] tx_data;
    logic [ 7:0] rx_data;
    logic [ 7:0] cmd;
    logic [ 7:0] status;
  } i2c_reg_fields_t;

  i2c_reg_fields_t reg_d, reg_q;
  `FF(reg_q, reg_d, '0, clk_i, rst_ni)

  // bit enable/strobe
  logic [ObiCfg.DataWidth-1:0] bit_mask;
  for (genvar i = 0; unsigned'(i) < ObiCfg.DataWidth/8; ++i) begin : gen_write_mask
    assign bit_mask[8*i +: 8] = {8{obi_req_i.a.be[i]}};
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Output to HW (reg2hw)
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin
    reg2hw.prescale  = reg_q.prescale;
    reg2hw.ctrl_en   = reg_q.ctrl[CTRL_EN_BIT];
    reg2hw.ctrl_ien  = reg_q.ctrl[CTRL_IEN_BIT];
    reg2hw.tx_data   = reg_q.tx_data;
    reg2hw.cmd_start = reg_q.cmd[CMD_START_BIT];
    reg2hw.cmd_stop  = reg_q.cmd[CMD_STOP_BIT];
    reg2hw.cmd_read  = reg_q.cmd[CMD_READ_BIT];
    reg2hw.cmd_write = reg_q.cmd[CMD_WRITE_BIT];
    reg2hw.cmd_nack  = reg_q.cmd[CMD_NACK_BIT];
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////////
  // Register update logic
  ////////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin
    // defaults
    obi_rdata = 32'h0;
    obi_err   = w_err_q;
    w_err_d   = 1'b0;
    reg_d     = reg_q;

    // Update from HW
    if (hw2reg.rx_data_valid) begin
      reg_d.rx_data = hw2reg.rx_data;
    end

    // Update status from HW
    reg_d.status[STATUS_TIP_BIT]  = hw2reg.tip;
    reg_d.status[STATUS_BUSY_BIT] = hw2reg.busy;
    reg_d.status[STATUS_RXACK_BIT] = hw2reg.rx_ack;

    if (hw2reg.irq_flag_valid) begin
      reg_d.status[STATUS_IF_BIT] = hw2reg.irq_flag;
    end

    if (hw2reg.al_valid) begin
      reg_d.status[STATUS_AL_BIT] = hw2reg.al;
    end

    // Clear command register when command is done
    if (hw2reg.cmd_done) begin
      reg_d.cmd = '0;
    end

    //---------------------------------------------------------------------------------
    // WRITE
    //---------------------------------------------------------------------------------
    if (obi_write_request) begin
      w_err_d = 1'b0;
      case (write_addr)
        I2C_PRESCALE_OFFSET: begin
          reg_d.prescale = (~bit_mask[15:0] & reg_q.prescale) | (bit_mask[15:0] & obi_wdata[15:0]);
        end

        I2C_CTRL_OFFSET: begin
          reg_d.ctrl = (~bit_mask[7:0] & reg_q.ctrl) | (bit_mask[7:0] & obi_wdata[7:0]);
        end

        I2C_TX_DATA_OFFSET: begin
          reg_d.tx_data = (~bit_mask[7:0] & reg_q.tx_data) | (bit_mask[7:0] & obi_wdata[7:0]);
        end

        I2C_CMD_OFFSET: begin
          reg_d.cmd = (~bit_mask[7:0] & reg_q.cmd) | (bit_mask[7:0] & obi_wdata[7:0]);
        end

        I2C_STATUS_OFFSET: begin
          // Writing 1 to IF bit clears the interrupt flag
          if (obi_wdata[STATUS_IF_BIT] & bit_mask[STATUS_IF_BIT]) begin
            reg_d.status[STATUS_IF_BIT] = 1'b0;
          end
          // Writing 1 to AL bit clears arbitration lost
          if (obi_wdata[STATUS_AL_BIT] & bit_mask[STATUS_AL_BIT]) begin
            reg_d.status[STATUS_AL_BIT] = 1'b0;
          end
        end

        default: begin
          w_err_d = 1'b1;
        end
      endcase
    end

    //---------------------------------------------------------------------------------
    // READ
    //---------------------------------------------------------------------------------
    if (obi_read_request) begin
      obi_err = 1'b0;
      case (read_addr_q)
        I2C_PRESCALE_OFFSET: begin
          obi_rdata = {16'b0, reg_q.prescale};
        end

        I2C_CTRL_OFFSET: begin
          obi_rdata = {24'b0, reg_q.ctrl};
        end

        I2C_TX_DATA_OFFSET: begin
          obi_rdata = {24'b0, reg_q.tx_data};
        end

        I2C_RX_DATA_OFFSET: begin
          obi_rdata = {24'b0, reg_q.rx_data};
        end

        I2C_CMD_OFFSET: begin
          obi_rdata = {24'b0, reg_q.cmd};
        end

        I2C_STATUS_OFFSET: begin
          obi_rdata = {24'b0, reg_q.status};
        end

        default: begin
          obi_rdata = 32'hBADCAB1E;
          obi_err   = 1'b1;
        end
      endcase
    end

  end

endmodule
