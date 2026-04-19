// =============================================================================
// I2C Slave Behavioral Model – for Simulation/Verification
// =============================================================================
// A clocked FSM-based I2C slave model that responds to a configurable
// 7-bit address. Uses oversampling of SCL/SDA for edge and condition
// detection. Compatible with Icarus Verilog.
//
// Features:
//   - Responds to programmable 7-bit address
//   - Supports both write and read transactions
//   - 16-byte internal memory with auto-increment pointer
//   - START/STOP/Repeated-START detection
//   - ACK generation for matching address and write data
//   - Data output for read operations
// =============================================================================

module i2c_slave_model #(
    parameter [6:0] I2C_ADDR = 7'h48
)(
    input  wire clk,
    input  wire rst_n,
    input  wire scl_i,       // SCL bus value
    input  wire sda_i,       // SDA bus value (after pull-up)
    output reg  sda_oe_o     // 1 = drive SDA low (open-drain)
);

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_ADDR_RECV  = 4'd1,   // Receiving address byte (8 bits)
        S_ADDR_CHECK = 4'd2,   // Wait for SCL fall after last bit, then check
        S_ADDR_ACK   = 4'd3,   // Sending ACK for address (hold SDA low)
        S_WR_DATA    = 4'd4,   // Receiving write data
        S_WR_CHECK   = 4'd5,   // Wait for SCL fall after last data bit
        S_WR_ACK     = 4'd6,   // Sending ACK for write data
        S_RD_DATA    = 4'd7,   // Sending read data
        S_RD_WAIT    = 4'd8,   // Wait for SCL fall after last read bit
        S_RD_ACK     = 4'd9;   // Waiting for master ACK/NACK

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [3:0]  state;
    reg [3:0]  bit_cnt;       // Bit counter (7 downto 0)
    reg [7:0]  shift_reg;     // Shift register
    reg        rw_bit;        // 0=write, 1=read
    reg [3:0]  mem_ptr;       // Memory pointer (auto-increment)

    // 16-byte internal memory
    reg [7:0]  mem [0:15];

    // Edge detection registers
    reg        scl_d, sda_d;
    wire       scl_rise = scl_i & ~scl_d;
    wire       scl_fall = ~scl_i & scl_d;

    // I2C condition detection
    wire       start_det = ~sda_i & sda_d & scl_i;   // SDA falls while SCL high
    wire       stop_det  = sda_i & ~sda_d & scl_i;    // SDA rises while SCL high

    // =========================================================================
    // Memory Initialization
    // =========================================================================
    integer k;
    initial begin
        for (k = 0; k < 16; k = k + 1)
            mem[k] = 8'h00;
        // Pre-load test data for read operations
        mem[0] = 8'h5A;
        mem[1] = 8'hA5;
        mem[2] = 8'h42;
        mem[3] = 8'hBD;
    end

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            sda_oe_o     <= 1'b0;
            bit_cnt      <= 4'd0;
            shift_reg    <= 8'd0;
            rw_bit       <= 1'b0;
            mem_ptr      <= 4'd0;
            scl_d        <= 1'b1;
            sda_d        <= 1'b1;
        end else begin
            // Edge detection
            scl_d <= scl_i;
            sda_d <= sda_i;

            // ---- START condition → always resets to address phase ----
            if (start_det) begin
                state     <= S_ADDR_RECV;
                bit_cnt   <= 4'd7;
                shift_reg <= 8'd0;
                sda_oe_o  <= 1'b0;
                $display("[I2C_SLAVE @ %0t ns] START condition detected", $time/1000);
            end
            // ---- STOP condition → return to idle ----
            else if (stop_det) begin
                state    <= S_IDLE;
                sda_oe_o <= 1'b0;
                $display("[I2C_SLAVE @ %0t ns] STOP condition detected", $time/1000);
            end
            else begin
                case (state)
                    // ---------------------------------------------------------
                    S_IDLE: begin
                        sda_oe_o <= 1'b0;
                    end

                    // ---------------------------------------------------------
                    // Receive address byte (8 bits: 7-bit addr + R/W)
                    // ---------------------------------------------------------
                    S_ADDR_RECV: begin
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], sda_i};
                            if (bit_cnt == 4'd0) begin
                                // Last bit shifted in - go to CHECK state
                                state <= S_ADDR_CHECK;
                            end else begin
                                bit_cnt <= bit_cnt - 4'd1;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Check address after shift_reg is updated (1 cycle delay)
                    // ---------------------------------------------------------
                    S_ADDR_CHECK: begin
                        if (scl_fall) begin
                            rw_bit <= shift_reg[0];
                            if (shift_reg[7:1] == I2C_ADDR) begin
                                sda_oe_o <= 1'b1;        // Drive ACK (SDA low)
                                state    <= S_ADDR_ACK;
                                mem_ptr  <= 4'd0;
                                $display("[I2C_SLAVE @ %0t ns] Address 0x%02h MATCH, R/W=%b",
                                         $time/1000, shift_reg[7:1], shift_reg[0]);
                            end else begin
                                sda_oe_o <= 1'b0;        // NACK
                                state    <= S_IDLE;
                                $display("[I2C_SLAVE @ %0t ns] Address 0x%02h NO MATCH (expected 0x%02h)",
                                         $time/1000, shift_reg[7:1], I2C_ADDR);
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Address ACK phase – hold SDA low through SCL high
                    // ---------------------------------------------------------
                    S_ADDR_ACK: begin
                        if (scl_fall) begin
                            sda_oe_o <= 1'b0;  // Release SDA after ACK
                            if (rw_bit == 1'b0) begin
                                // WRITE: prepare to receive data
                                state   <= S_WR_DATA;
                                bit_cnt <= 4'd7;
                            end else begin
                                // READ: prepare to send data
                                state     <= S_RD_DATA;
                                bit_cnt   <= 4'd7;
                                shift_reg <= mem[mem_ptr];
                                // Drive MSB (bit 7) immediately
                                sda_oe_o  <= (mem[mem_ptr][7] == 1'b0) ? 1'b1 : 1'b0;
                                $display("[I2C_SLAVE @ %0t ns] Sending byte 0x%02h from mem[%0d]",
                                         $time/1000, mem[mem_ptr], mem_ptr);
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Write data reception
                    // ---------------------------------------------------------
                    S_WR_DATA: begin
                        if (scl_rise) begin
                            shift_reg <= {shift_reg[6:0], sda_i};
                            if (bit_cnt == 4'd0) begin
                                // Last bit shifted in
                                state <= S_WR_CHECK;
                            end else begin
                                bit_cnt <= bit_cnt - 4'd1;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Check write data after shift_reg is updated
                    // ---------------------------------------------------------
                    S_WR_CHECK: begin
                        if (scl_fall) begin
                            // Store received byte
                            mem[mem_ptr] <= shift_reg;
                            mem_ptr      <= mem_ptr + 4'd1;
                            sda_oe_o     <= 1'b1;  // Drive ACK
                            state        <= S_WR_ACK;
                            $display("[I2C_SLAVE @ %0t ns] Received byte 0x%02h -> mem[%0d]",
                                     $time/1000, shift_reg, mem_ptr);
                        end
                    end

                    // ---------------------------------------------------------
                    // Write ACK phase
                    // ---------------------------------------------------------
                    S_WR_ACK: begin
                        if (scl_fall) begin
                            sda_oe_o <= 1'b0;  // Release SDA
                            state    <= S_WR_DATA;
                            bit_cnt  <= 4'd7;
                        end
                    end

                    // ---------------------------------------------------------
                    // Read data transmission
                    // ---------------------------------------------------------
                    S_RD_DATA: begin
                        if (scl_fall) begin
                            if (bit_cnt == 4'd0) begin
                                // All 8 bits sent, release SDA for master ACK/NACK
                                sda_oe_o <= 1'b0;
                                state    <= S_RD_WAIT;
                            end else begin
                                bit_cnt  <= bit_cnt - 4'd1;
                                // Drive next bit (bit_cnt-1 because we just decremented)
                                sda_oe_o <= (shift_reg[bit_cnt - 1] == 1'b0) ? 1'b1 : 1'b0;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Wait for SCL cycle to complete after last read bit
                    // ---------------------------------------------------------
                    S_RD_WAIT: begin
                        if (scl_fall) begin
                            sda_oe_o <= 1'b0;
                            state    <= S_RD_ACK;
                        end
                    end

                    // ---------------------------------------------------------
                    // Read ACK/NACK from master
                    // ---------------------------------------------------------
                    S_RD_ACK: begin
                        if (scl_rise) begin
                            if (sda_i == 1'b1) begin
                                // NACK – master done reading
                                $display("[I2C_SLAVE @ %0t ns] Master sent NACK, ending read",
                                         $time/1000);
                                state <= S_IDLE;
                            end else begin
                                // ACK – master wants more data
                                $display("[I2C_SLAVE @ %0t ns] Master sent ACK, continuing read",
                                         $time/1000);
                            end
                        end
                        if (scl_fall && state != S_IDLE) begin
                            // Prepare next byte
                            mem_ptr   <= mem_ptr + 4'd1;
                            state     <= S_RD_DATA;
                            bit_cnt   <= 4'd7;
                            shift_reg <= mem[mem_ptr + 4'd1];
                            sda_oe_o  <= (mem[mem_ptr + 4'd1][7] == 1'b0) ? 1'b1 : 1'b0;
                            $display("[I2C_SLAVE @ %0t ns] Sending byte 0x%02h from mem[%0d]",
                                     $time/1000, mem[mem_ptr + 4'd1], mem_ptr + 4'd1);
                        end
                    end

                    default: begin
                        state    <= S_IDLE;
                        sda_oe_o <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
