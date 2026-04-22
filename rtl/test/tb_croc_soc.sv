// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

`define TRACE_WAVE

module tb_croc_soc #(
  parameter int unsigned GpioCount = 32
);

  import tb_croc_pkg::*;

  // Signals fully controlled by the VIP
  // use VIP functions/tasks to manipulate these signals
  logic rst_n;
  logic sys_clk;
  logic ref_clk;

  logic jtag_tck;
  logic jtag_trst_n;
  logic jtag_tms;
  logic jtag_tdi;
  logic jtag_tdo;

  logic uart_rx;
  logic uart_tx;

  // Signals partially controlled by the VIP
  logic [GpioCount-1:0] gpio_in;
  logic [GpioCount-1:0] gpio_out;
  logic [GpioCount-1:0] gpio_out_en;

  // I2C signals
  logic i2c_scl_o, i2c_scl_oe_o, i2c_scl_i;
  logic i2c_sda_o, i2c_sda_oe_o, i2c_sda_i;

  // I2C open-drain bus model (passive, no slave)
  // OE=1 means drive LOW, OE=0 means pull-up to HIGH
  wire i2c_scl_bus = i2c_scl_oe_o ? 1'b0 : 1'b1;
  wire i2c_sda_bus = i2c_sda_oe_o ? 1'b0 : 1'b1;

  // Feed bus values back to DUT
  assign i2c_scl_i = i2c_scl_bus;
  assign i2c_sda_i = i2c_sda_bus;

  // Signals controlled by the testbench

  /////////////////////////////
  //  Command Line Arguments //
  /////////////////////////////

  string binary_path;

  initial begin
    // $value$plusargs defines what to look for (here +binary=...)
    if ($value$plusargs("binary=%s", binary_path)) begin
      $display("Running program: %s", binary_path);
    end else begin
      $display("No binary path provided. Running helloworld.");
      binary_path = "../sw/bin/helloworld.hex";
    end
  end

  ////////////
  //  VIP   //
  ////////////
  // Verification IP
  // - drives clocks and resets
  // - provides helper tasks and functions for JTAG, namely:
  //   - jtag_load_hex: loads a hex file into the DUT's memory
  //   - jtag_write_reg32: write 32-bit value to DUT
  //   - jtag_read_reg32: read 32-bit value from DUT
  //   - jtag_halt / jtag_resume: control core execution
  //   - jtag_wait_for_eoc: wait for end of code execution (core writes non-zero to status register)
  // - prints UART output to console (you can also write via uart_write_byte)
  // - internal GPIO loopback for helloworld test

  croc_vip #(
    .GpioCount ( GpioCount )
  ) i_vip (
    .rst_no        ( rst_n       ),
    .sys_clk_o     ( sys_clk     ),
    .ref_clk_o     ( ref_clk     ),
    .jtag_tck_o    ( jtag_tck    ),
    .jtag_trst_no  ( jtag_trst_n ),
    .jtag_tms_o    ( jtag_tms    ),
    .jtag_tdi_o    ( jtag_tdi    ),
    .jtag_tdo_i    ( jtag_tdo    ),
    .uart_rx_o     ( uart_rx     ),
    .uart_tx_i     ( uart_tx     ),
    .gpio_out_en_i ( gpio_out_en ),
    .gpio_out_i    ( gpio_out    ),
    .gpio_in_o     ( gpio_in     )
  );

  ////////////
  //  DUT   //
  ////////////

  `ifdef TARGET_NETLIST_YOSYS
  \croc_soc$croc_chip.i_croc_soc i_croc_soc (
  `else
  croc_soc #(
    .GpioCount ( GpioCount )
  ) i_croc_soc (
  `endif
    .clk_i         ( sys_clk        ),
    .rst_ni        ( rst_n          ),
    .ref_clk_i     ( ref_clk        ),
    .testmode_i    ( 1'b0           ),
    .status_o      (                ),
    .jtag_tck_i    ( jtag_tck       ),
    .jtag_tdi_i    ( jtag_tdi       ),
    .jtag_tdo_o    ( jtag_tdo       ),
    .jtag_tms_i    ( jtag_tms       ),
    .jtag_trst_ni  ( jtag_trst_n    ),
    .uart_rx_i     ( uart_rx        ),
    .uart_tx_o     ( uart_tx        ),
    .i2c_scl_o     ( i2c_scl_o      ),
    .i2c_scl_oe_o  ( i2c_scl_oe_o   ),
    .i2c_scl_i     ( i2c_scl_i      ),
    .i2c_sda_o     ( i2c_sda_o      ),
    .i2c_sda_oe_o  ( i2c_sda_oe_o   ),
    .i2c_sda_i     ( i2c_sda_i      ),
    .gpio_i        ( gpio_in        ),
    .gpio_o        ( gpio_out       ),
    .gpio_out_en_o ( gpio_out_en    )
  );

  /////////////////
  //  Testbench  //
  /////////////////

  logic [31:0] tb_data;

  initial begin
    $timeformat(-9, 0, "ns", 12); // 1: scale (ns=-9), 2: decimals, 3: suffix, 4: print-field width

    // wait for reset
    #ClkPeriodSys;

    // init jtag
    i_vip.jtag_init();

    // write test value to sram
    i_vip.jtag_write_reg32(SramBaseAddr, 32'h1234_5678, 1'b1);

    // load binary to sram
    i_vip.jtag_load_hex(binary_path);

    // wake core from WFI by writing to CLINT msip
    $display("@%t | [CORE] Waking core via CLINT msip", $time);
    i_vip.jtag_write_reg32(ClintBaseAddr, 32'h1);

    // halt core
    i_vip.jtag_halt();

    // resume core
    i_vip.jtag_resume();

    // wait for non-zero return value (written into core status register)
    $display("@%t | [CORE] Wait for end of code...", $time);
    i_vip.jtag_wait_for_eoc(tb_data);

    // finish simulation
    repeat(50) @(posedge sys_clk);
    $finish();
  end

  /////////////////////////
  //  I2C Bus Monitor    //
  /////////////////////////
  // Passive monitor: observes SCL/SDA bus and logs I2C transactions.
  // Does NOT drive the bus. Master will see NACK (expected in simulation).
  // Evidence of I2C working: START/STOP conditions + data byte capture.

  logic i2c_scl_prev, i2c_sda_prev;
  always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
      i2c_scl_prev <= 1'b1;
      i2c_sda_prev <= 1'b1;
    end else begin
      i2c_scl_prev <= i2c_scl_bus;
      i2c_sda_prev <= i2c_sda_bus;
    end
  end

  // START: SDA falls while SCL is high
  wire i2c_start_det = i2c_sda_prev & ~i2c_sda_bus & i2c_scl_bus;
  // STOP: SDA rises while SCL is high
  wire i2c_stop_det  = ~i2c_sda_prev & i2c_sda_bus & i2c_scl_bus;
  // SCL rising edge
  wire i2c_scl_rise  = ~i2c_scl_prev & i2c_scl_bus;

  // Passive byte capture
  logic [3:0] i2c_mon_bit_cnt;
  logic [7:0] i2c_mon_shift;
  logic       i2c_mon_active;
  logic       i2c_mon_first_byte;  // true = address byte

  always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
      i2c_mon_bit_cnt  <= '0;
      i2c_mon_shift    <= '0;
      i2c_mon_active   <= 1'b0;
      i2c_mon_first_byte <= 1'b1;
    end else begin
      if (i2c_start_det) begin
        $display("@%t | [I2C] === START condition ===", $time);
        i2c_mon_bit_cnt  <= '0;
        i2c_mon_shift    <= '0;
        i2c_mon_active   <= 1'b1;
        i2c_mon_first_byte <= 1'b1;
      end else if (i2c_stop_det) begin
        $display("@%t | [I2C] === STOP condition ===", $time);
        i2c_mon_active <= 1'b0;
      end else if (i2c_mon_active && i2c_scl_rise) begin
        if (i2c_mon_bit_cnt < 8) begin
          // Capture data bit (MSB first)
          i2c_mon_shift <= {i2c_mon_shift[6:0], i2c_sda_bus};
          i2c_mon_bit_cnt <= i2c_mon_bit_cnt + 1;
          if (i2c_mon_bit_cnt == 7) begin
            if (i2c_mon_first_byte) begin
              $display("@%t | [I2C] Address byte: 0x%02h (addr=0x%02h %s)",
                $time, {i2c_mon_shift[6:0], i2c_sda_bus},
                {i2c_mon_shift[6:0], i2c_sda_bus} >> 1,
                i2c_sda_bus ? "READ" : "WRITE");
            end else begin
              $display("@%t | [I2C] Data byte: 0x%02h (ASCII '%c')",
                $time, {i2c_mon_shift[6:0], i2c_sda_bus},
                {i2c_mon_shift[6:0], i2c_sda_bus});
            end
          end
        end else begin
          // ACK/NACK bit (9th clock)
          if (i2c_sda_bus)
            $display("@%t | [I2C] NACK received", $time);
          else
            $display("@%t | [I2C] ACK received", $time);
          i2c_mon_bit_cnt <= '0;
          i2c_mon_shift   <= '0;
          i2c_mon_first_byte <= 1'b0;
        end
      end
    end
  end

  ////////////////
  //  Waveform  //
  ////////////////
  // start waveform dump at time 0, independent of stimuli
  initial begin
    `ifdef TRACE_WAVE
      `ifdef VERILATOR
        $dumpfile("croc.fst");
        $dumpvars(1, i_croc_soc);
      `else
        $dumpfile("croc.vcd");
        $dumpvars(1, i_croc_soc);
      `endif
    `endif
  end

  // flush waveform dump when simulation ends
  final begin
    `ifdef TRACE_WAVE
      $dumpflush;
    `endif
  end

endmodule
