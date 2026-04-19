// =============================================================================
// Self-Checking Testbench for I2C Master Module
// =============================================================================
// Verifies:
//   Test 1: Register access (prescaler, control, TX data)
//   Test 2: I2C Write transaction – write byte 0xA5 to slave 0x48
//   Test 3: I2C Read transaction  – read byte from slave 0x48
//   Test 4: Verify read data matches slave memory (0x5A)
//
// Tools: Icarus Verilog + GTKWave
// Usage: iverilog -o tb_i2c sim/tb_i2c.v sim/i2c_master.v sim/i2c_slave_model.v
//        vvp tb_i2c
//        gtkwave sim/i2c_waveform.vcd
// =============================================================================

`timescale 1ns / 1ps

module tb_i2c;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_PERIOD  = 50;      // 20 MHz
    parameter PRESCALE    = 16'd4;   // SCL = 20MHz / (2*5) = 2MHz (fast for sim)
    parameter SLAVE_ADDR  = 7'h48;
    parameter TIMEOUT_US  = 200;     // Simulation timeout in microseconds

    // =========================================================================
    // Signals
    // =========================================================================
    reg         clk;
    reg         rst_n;

    // Bus interface to I2C master
    reg  [4:0]  bus_addr;
    reg  [31:0] bus_wdata;
    wire [31:0] bus_rdata;
    reg         bus_we;

    // I2C master interface
    wire        master_scl_oe;
    wire        master_sda_oe;
    wire        master_irq;

    // I2C slave interface
    wire        slave_sda_oe;

    // I2C bus (open-drain with pull-ups)
    wire        scl_bus;
    wire        sda_bus;

    // Pull-ups (default high)
    pullup (scl_bus);
    pullup (sda_bus);

    // Open-drain: drive low when OE=1
    assign scl_bus = master_scl_oe ? 1'b0 : 1'bz;
    assign sda_bus = master_sda_oe ? 1'b0 : 1'bz;
    assign sda_bus = slave_sda_oe  ? 1'b0 : 1'bz;

    // =========================================================================
    // Test result tracking
    // =========================================================================
    integer pass_count;
    integer fail_count;
    integer test_num;

    // =========================================================================
    // DUT: I2C Master
    // =========================================================================
    i2c_master dut_master (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (bus_addr),
        .wdata    (bus_wdata),
        .rdata    (bus_rdata),
        .we       (bus_we),
        .irq_o    (master_irq),
        .scl_o    (),
        .scl_oe_o (master_scl_oe),
        .scl_i    (scl_bus),
        .sda_o    (),
        .sda_oe_o (master_sda_oe),
        .sda_i    (sda_bus)
    );

    // =========================================================================
    // I2C Slave Model
    // =========================================================================
    i2c_slave_model #(
        .I2C_ADDR (SLAVE_ADDR)
    ) dut_slave (
        .clk      (clk),
        .rst_n    (rst_n),
        .scl_i    (scl_bus),
        .sda_i    (sda_bus),
        .sda_oe_o (slave_sda_oe)
    );

    // =========================================================================
    // Clock Generation (20 MHz)
    // =========================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("sim/i2c_waveform.vcd");
        $dumpvars(0, tb_i2c);
    end

    // =========================================================================
    // Simulation Timeout
    // =========================================================================
    initial begin
        #(TIMEOUT_US * 1000);
        $display("\n[TIMEOUT] Simulation timed out after %0d us!", TIMEOUT_US);
        $display("[RESULT] PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        $finish;
    end

    // =========================================================================
    // Bus Access Tasks
    // =========================================================================
    task bus_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            bus_addr  <= addr;
            bus_wdata <= data;
            bus_we    <= 1'b1;
            @(posedge clk);
            bus_we    <= 1'b0;
        end
    endtask

    task bus_read;
        input  [4:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            bus_addr <= addr;
            bus_we   <= 1'b0;
            @(posedge clk);
            data = bus_rdata;
        end
    endtask

    // =========================================================================
    // Wait for Transfer In Progress (TIP) to clear
    // =========================================================================
    task wait_tip;
        output integer result; // 0=ok, -1=timeout
        reg [31:0] status;
        integer timeout;
        begin
            result  = 0;
            timeout = 0;
            status  = 32'h1; // TIP bit set initially
            while (status & 32'h1) begin
                bus_read(5'h14, status);
                timeout = timeout + 1;
                if (timeout > 5000) begin
                    $display("[ERROR] wait_tip timeout!");
                    result = -1;
                    status = 32'h0; // force exit
                end
            end
        end
    endtask

    // =========================================================================
    // Check helper
    // =========================================================================
    task check;
        input [255:0] test_name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0s: got 0x%08h", test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: expected 0x%08h, got 0x%08h",
                         test_name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Register address constants
    // =========================================================================
    localparam ADDR_PRESCALE = 5'h00;
    localparam ADDR_CTRL     = 5'h04;
    localparam ADDR_TX_DATA  = 5'h08;
    localparam ADDR_RX_DATA  = 5'h0C;
    localparam ADDR_CMD      = 5'h10;
    localparam ADDR_STATUS   = 5'h14;

    // Command bits
    localparam CMD_START = 32'h01;
    localparam CMD_STOP  = 32'h02;
    localparam CMD_READ  = 32'h04;
    localparam CMD_WRITE = 32'h08;
    localparam CMD_NACK  = 32'h10;

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    reg [31:0] read_data;
    integer    tip_result;

    initial begin
        // Initialize
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        bus_addr   = 5'd0;
        bus_wdata  = 32'd0;
        bus_we     = 1'b0;
        rst_n      = 1'b0;

        $display("==========================================================");
        $display("  I2C Master Self-Checking Testbench");
        $display("  Clock: %0d MHz, Prescale: %0d", 1000/CLK_PERIOD, PRESCALE);
        $display("  Slave Address: 0x%02h", SLAVE_ADDR);
        $display("==========================================================");

        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        // ==============================================================
        // Test 1: Register Access
        // ==============================================================
        $display("\n--- Test 1: Register Access ---");

        // Write prescaler
        bus_write(ADDR_PRESCALE, {16'd0, PRESCALE});
        bus_read(ADDR_PRESCALE, read_data);
        check("Prescaler write/read", read_data[15:0], {16'd0, PRESCALE});

        // Enable I2C core with interrupts
        bus_write(ADDR_CTRL, 32'h03);  // EN=1, IEN=1
        bus_read(ADDR_CTRL, read_data);
        check("CTRL EN+IEN", read_data[1:0], 2'b11);

        // Write TX data
        bus_write(ADDR_TX_DATA, 32'hA5);
        bus_read(ADDR_TX_DATA, read_data);
        check("TX_DATA write/read", read_data[7:0], 8'hA5);

        // Check idle status (TIP should be 0)
        bus_read(ADDR_STATUS, read_data);
        check("Status idle (TIP=0)", read_data[0], 1'b0);

        #(CLK_PERIOD * 10);

        // ==============================================================
        // Test 2: I2C Write Transaction
        //   Write byte 0xA5 to slave at address 0x48
        // ==============================================================
        $display("\n--- Test 2: I2C Write Transaction ---");
        $display("    Writing 0xA5 to slave 0x%02h...", SLAVE_ADDR);

        // Step 1: Load slave address + write bit (0x48 << 1 | 0 = 0x90)
        bus_write(ADDR_TX_DATA, {24'd0, SLAVE_ADDR, 1'b0});

        // Step 2: Issue START + WRITE command
        bus_write(ADDR_CMD, CMD_START | CMD_WRITE);

        // Step 3: Wait for address phase to complete
        wait_tip(tip_result);
        if (tip_result != 0) begin
            $display("[FAIL] Timeout during address write phase");
            fail_count = fail_count + 1;
        end

        // Step 4: Check slave ACK (RXACK should be 0 = ACK)
        bus_read(ADDR_STATUS, read_data);
        check("Write addr ACK", read_data[2], 1'b0);

        // Step 5: Load data byte
        bus_write(ADDR_TX_DATA, 32'hA5);

        // Step 6: Issue WRITE + STOP command
        bus_write(ADDR_CMD, CMD_WRITE | CMD_STOP);

        // Step 7: Wait for data write to complete
        wait_tip(tip_result);
        if (tip_result != 0) begin
            $display("[FAIL] Timeout during data write phase");
            fail_count = fail_count + 1;
        end

        // Step 8: Check slave ACK
        bus_read(ADDR_STATUS, read_data);
        check("Write data ACK", read_data[2], 1'b0);

        // Step 9: Verify slave received the correct data
        check("Slave mem[0] after write", {24'd0, dut_slave.mem[0]}, 32'hA5);

        #(CLK_PERIOD * 20);

        // ==============================================================
        // Test 3: I2C Read Transaction
        //   Read byte from slave at address 0x48 (slave mem[0] = 0xA5)
        // ==============================================================
        $display("\n--- Test 3: I2C Read Transaction ---");
        $display("    Reading from slave 0x%02h...", SLAVE_ADDR);

        // Pre-load slave memory for read (mem[0] was overwritten by write test)
        // Re-set it to known value for read test
        dut_slave.mem[0] = 8'h5A;

        // Step 1: Load slave address + read bit (0x48 << 1 | 1 = 0x91)
        bus_write(ADDR_TX_DATA, {24'd0, SLAVE_ADDR, 1'b1});

        // Step 2: Issue START + WRITE (address phase uses WRITE to clock out address)
        bus_write(ADDR_CMD, CMD_START | CMD_WRITE);

        // Step 3: Wait for address phase
        wait_tip(tip_result);
        if (tip_result != 0) begin
            $display("[FAIL] Timeout during address phase for read");
            fail_count = fail_count + 1;
        end

        // Step 4: Check slave ACK
        bus_read(ADDR_STATUS, read_data);
        check("Read addr ACK", read_data[2], 1'b0);

        // Step 5: Issue READ + NACK + STOP (single byte read, NACK last byte)
        bus_write(ADDR_CMD, CMD_READ | CMD_NACK | CMD_STOP);

        // Step 6: Wait for read to complete
        wait_tip(tip_result);
        if (tip_result != 0) begin
            $display("[FAIL] Timeout during data read phase");
            fail_count = fail_count + 1;
        end

        // Step 7: Read received data
        bus_read(ADDR_RX_DATA, read_data);
        check("Read data = 0x5A", read_data[7:0], 8'h5A);

        #(CLK_PERIOD * 20);

        // ==============================================================
        // Test 4: Bus Status after transactions
        // ==============================================================
        $display("\n--- Test 4: Final Status Check ---");

        bus_read(ADDR_STATUS, read_data);
        check("Final TIP=0 (idle)", read_data[0], 1'b0);
        check("Final BUSY=0",       read_data[4], 1'b0);
        check("Final AL=0",         read_data[3], 1'b0);

        // ==============================================================
        // Summary
        // ==============================================================
        #(CLK_PERIOD * 10);
        $display("\n==========================================================");
        $display("  TEST SUMMARY");
        $display("==========================================================");
        $display("  PASSED: %0d", pass_count);
        $display("  FAILED: %0d", fail_count);
        $display("==========================================================");

        if (fail_count == 0) begin
            $display("  >> ALL TESTS PASSED! <<");
        end else begin
            $display("  >> SOME TESTS FAILED! <<");
        end

        $display("==========================================================\n");
        $finish;
    end

    // =========================================================================
    // Optional: Monitor I2C bus activity
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && dut_master.cmd_done_r) begin
            $display("[MASTER @ %0t ns] Command done (state was %0d)",
                     $time/1000, dut_master.state);
        end
    end

endmodule
