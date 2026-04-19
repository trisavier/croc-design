// =============================================================================
// I2C Master Controller – Standalone Verilog Module
// =============================================================================
// Functionally equivalent to rtl/obi_i2c/obi_i2c.sv but with a simple
// memory-mapped bus interface for verification with Icarus Verilog.
//
// Features:
//   - I2C Master with START, STOP, WRITE, READ, ACK/NACK support
//   - Configurable SCL frequency via prescaler register
//   - Arbitration lost detection
//   - Bus busy detection
//   - Open-drain I/O model (output-enable based)
//   - Interrupt output
//
// Register Map (byte address):
//   0x00  PRESCALE  [15:0]  RW   SCL freq = clk / (2 * (prescale + 1))
//   0x04  CTRL      [1:0]   RW   {IEN, EN}
//   0x08  TX_DATA   [7:0]   RW   Transmit data
//   0x0C  RX_DATA   [7:0]   RO   Received data
//   0x10  CMD       [4:0]   WO   {NACK, WRITE, READ, STOP, START}
//   0x14  STATUS    [4:0]   RO   {BUSY, AL, RXACK, IF, TIP}
// =============================================================================

module i2c_master (
    input  wire        clk,
    input  wire        rst_n,

    // Simple memory-mapped bus interface
    input  wire [4:0]  addr,       // Byte address (0x00..0x14)
    input  wire [31:0] wdata,      // Write data
    output reg  [31:0] rdata,      // Read data
    input  wire        we,         // Write enable

    // Interrupt
    output wire        irq_o,

    // I2C open-drain interface
    output wire        scl_o,      // SCL output (always 0)
    output wire        scl_oe_o,   // SCL output enable (1 = drive low)
    input  wire        scl_i,      // SCL input
    output wire        sda_o,      // SDA output (always 0)
    output wire        sda_oe_o,   // SDA output enable (1 = drive low)
    input  wire        sda_i       // SDA input
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_START_A    = 4'd1,    // Prepare START (ensure SCL & SDA high)
        S_START_B    = 4'd2,    // Execute START (SDA low while SCL high)
        S_WRITE_BIT  = 4'd3,    // Setup write bit (SCL low, SDA = data)
        S_WRITE_WAIT = 4'd4,    // Clock write bit (SCL high, slave samples)
        S_READ_BIT   = 4'd5,    // Prepare read (SCL low, release SDA)
        S_READ_WAIT  = 4'd6,    // Clock read bit (SCL high, sample SDA)
        S_ACK_SEND   = 4'd7,    // Send ACK/NACK after read (SCL low)
        S_ACK_WAIT   = 4'd8,    // Clock ACK (SCL high)
        S_ACK_READ   = 4'd9,    // Prepare read ACK after write (SCL low)
        S_ACK_RWAIT  = 4'd10,   // Sample slave ACK (SCL high)
        S_STOP_A     = 4'd11,   // Prepare STOP (SCL low, SDA low)
        S_STOP_B     = 4'd12,   // Release SCL (SCL high, SDA still low)
        S_STOP_C     = 4'd13;   // Execute STOP (release SDA while SCL high)

    // =========================================================================
    // Registers
    // =========================================================================
    reg [15:0] prescale_reg;
    reg        ctrl_en, ctrl_ien;
    reg  [7:0] tx_data_reg;
    reg  [7:0] rx_data_reg;

    // Command register bits (set by bus write, cleared by FSM)
    reg        cmd_start, cmd_stop, cmd_read, cmd_write, cmd_nack;

    // Status
    reg        irq_flag;
    reg        rx_ack;
    reg        al;           // Arbitration lost
    reg        busy;         // Bus busy
    reg        cmd_done_r;   // Pulse: command done

    // FSM
    reg  [3:0] state;
    reg  [2:0] bit_cnt;
    reg  [7:0] shift_reg;
    reg        scl_out;      // Internal SCL value (1=release, 0=drive low)
    reg        sda_out;      // Internal SDA value (1=release, 0=drive low)

    // Latched command intent (captured when leaving IDLE)
    reg        pending_write, pending_read, pending_nack, pending_stop;

    // Prescale counter
    reg [15:0] prescale_cnt;
    wire       prescale_tick = (prescale_cnt == 16'd0) & ctrl_en;

    // SDA/SCL input synchronizers (2-stage)
    reg        sda_s1, sda_s2;
    reg        scl_s1, scl_s2;
    wire       sda_sync = sda_s2;
    wire       scl_sync = scl_s2;

    // Previous SDA for edge detection
    reg        sda_prev;

    // START/STOP detection
    wire       start_detect = sda_prev & ~sda_sync & scl_sync;
    wire       stop_detect  = ~sda_prev & sda_sync & scl_sync;

    // Arbitration lost: we want SDA high but it's read as low while SCL high
    // Only check during write-data and start states when master drives SDA
    wire       arb_lost_check = (state == S_WRITE_WAIT) | (state == S_START_B);
    wire       arb_lost = sda_out & ~sda_sync & scl_sync & arb_lost_check;

    // Transfer in progress
    wire       tip = (state != S_IDLE);

    // =========================================================================
    // Open-drain outputs
    // =========================================================================
    assign scl_o    = 1'b0;
    assign scl_oe_o = ~scl_out & ctrl_en;   // Drive low when scl_out=0
    assign sda_o    = 1'b0;
    assign sda_oe_o = ~sda_out & ctrl_en;   // Drive low when sda_out=0

    // =========================================================================
    // Interrupt output
    // =========================================================================
    assign irq_o = irq_flag & ctrl_ien;

    // =========================================================================
    // Register read (combinational)
    // =========================================================================
    always @(*) begin
        rdata = 32'd0;
        case (addr)
            5'h00: rdata = {16'd0, prescale_reg};
            5'h04: rdata = {30'd0, ctrl_ien, ctrl_en};
            5'h08: rdata = {24'd0, tx_data_reg};
            5'h0C: rdata = {24'd0, rx_data_reg};
            5'h10: rdata = {27'd0, cmd_nack, cmd_write, cmd_read, cmd_stop, cmd_start};
            5'h14: rdata = {27'd0, busy, al, rx_ack, irq_flag, tip};
            default: rdata = 32'd0;
        endcase
    end

    // =========================================================================
    // Main sequential logic (single always block)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            prescale_reg <= 16'd0;
            ctrl_en      <= 1'b0;
            ctrl_ien     <= 1'b0;
            tx_data_reg  <= 8'd0;
            rx_data_reg  <= 8'd0;
            cmd_start    <= 1'b0;
            cmd_stop     <= 1'b0;
            cmd_read     <= 1'b0;
            cmd_write    <= 1'b0;
            cmd_nack     <= 1'b0;
            irq_flag     <= 1'b0;
            rx_ack       <= 1'b0;
            al           <= 1'b0;
            busy         <= 1'b0;
            cmd_done_r   <= 1'b0;
            state        <= S_IDLE;
            bit_cnt      <= 3'd0;
            shift_reg    <= 8'd0;
            scl_out      <= 1'b1;
            sda_out      <= 1'b1;
            pending_write <= 1'b0;
            pending_read  <= 1'b0;
            pending_nack  <= 1'b0;
            pending_stop  <= 1'b0;
            prescale_cnt <= 16'd0;
            sda_s1       <= 1'b1;
            sda_s2       <= 1'b1;
            scl_s1       <= 1'b1;
            scl_s2       <= 1'b1;
            sda_prev     <= 1'b1;
        end else begin
            // ---- Default: clear one-shot signals ----
            cmd_done_r <= 1'b0;

            // ---- Input synchronizers ----
            sda_s1   <= sda_i;
            sda_s2   <= sda_s1;
            scl_s1   <= scl_i;
            scl_s2   <= scl_s1;
            sda_prev <= sda_sync;

            // ---- Prescale counter ----
            if (!ctrl_en) begin
                prescale_cnt <= 16'd0;
            end else if (prescale_cnt == 16'd0) begin
                prescale_cnt <= prescale_reg;
            end else begin
                prescale_cnt <= prescale_cnt - 16'd1;
            end

            // ---- Bus busy tracking ----
            if (start_detect) busy <= 1'b1;
            if (stop_detect)  busy <= 1'b0;

            // ================================================================
            // FSM (placed BEFORE register writes so bus writes take priority
            // for cmd bits via non-blocking assignment last-write-wins)
            // ================================================================
            if (!ctrl_en) begin
                state   <= S_IDLE;
                scl_out <= 1'b1;
                sda_out <= 1'b1;
            end else if (arb_lost) begin
                // Arbitration lost – abort
                al         <= 1'b1;
                state      <= S_IDLE;
                scl_out    <= 1'b1;
                sda_out    <= 1'b1;
                cmd_done_r <= 1'b1;
                irq_flag   <= ctrl_ien;
            end else begin
                case (state)
                    // ---------------------------------------------------------
                    S_IDLE: begin
                        // NOTE: Do NOT force scl_out/sda_out high here.
                        // They are set to appropriate values when entering IDLE
                        // from ACK or STOP states. Only release both lines
                        // when no active transaction.

                        if (cmd_start & (cmd_write | cmd_read)) begin
                            // START + WRITE or READ
                            state         <= S_START_A;
                            pending_write <= cmd_write;
                            pending_read  <= cmd_read;
                            pending_nack  <= cmd_nack;
                            pending_stop  <= cmd_stop;
                            // Clear consumed commands
                            cmd_start <= 1'b0;
                            cmd_stop  <= 1'b0;
                            cmd_read  <= 1'b0;
                            cmd_write <= 1'b0;
                        end else if (cmd_write) begin
                            // Standalone WRITE (no START) – SCL stays low
                            state     <= S_WRITE_BIT;
                            shift_reg <= tx_data_reg;
                            bit_cnt   <= 3'd7;
                            scl_out   <= 1'b0;
                            pending_stop <= cmd_stop;
                            cmd_write <= 1'b0;
                            cmd_stop  <= 1'b0;
                        end else if (cmd_read) begin
                            // Standalone READ (no START) – SCL stays low
                            state     <= S_READ_BIT;
                            bit_cnt   <= 3'd7;
                            sda_out   <= 1'b1;
                            scl_out   <= 1'b0;
                            pending_nack <= cmd_nack;
                            pending_stop <= cmd_stop;
                            cmd_read  <= 1'b0;
                            cmd_stop  <= 1'b0;
                            cmd_nack  <= 1'b0;
                        end else if (cmd_stop) begin
                            // Standalone STOP
                            state   <= S_STOP_A;
                            sda_out <= 1'b0;
                            scl_out <= 1'b0;
                            cmd_stop <= 1'b0;
                        end
                    end

                    // ---------------------------------------------------------
                    // START condition
                    // ---------------------------------------------------------
                    S_START_A: begin
                        // Ensure SCL and SDA are high (for repeated START)
                        scl_out <= 1'b1;
                        sda_out <= 1'b1;
                        if (prescale_tick)
                            state <= S_START_B;
                    end

                    S_START_B: begin
                        // Pull SDA low while SCL stays high → START condition
                        sda_out <= 1'b0;
                        if (prescale_tick) begin
                            scl_out <= 1'b0;
                            busy    <= 1'b1;
                            if (pending_write) begin
                                state     <= S_WRITE_BIT;
                                shift_reg <= tx_data_reg;
                                bit_cnt   <= 3'd7;
                            end else if (pending_read) begin
                                state   <= S_READ_BIT;
                                bit_cnt <= 3'd7;
                                sda_out <= 1'b1;
                            end else begin
                                state      <= S_IDLE;
                                cmd_done_r <= 1'b1;
                                irq_flag   <= ctrl_ien;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // WRITE bits (MSB first)
                    // ---------------------------------------------------------
                    S_WRITE_BIT: begin
                        scl_out <= 1'b0;
                        sda_out <= shift_reg[7];
                        if (prescale_tick)
                            state <= S_WRITE_WAIT;
                    end

                    S_WRITE_WAIT: begin
                        scl_out <= 1'b1; // SCL high – slave samples data
                        if (prescale_tick) begin
                            scl_out <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                // All 8 bits sent → read ACK from slave
                                state   <= S_ACK_READ;
                                sda_out <= 1'b1; // Release SDA for slave ACK
                            end else begin
                                state     <= S_WRITE_BIT;
                                bit_cnt   <= bit_cnt - 3'd1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // READ bits
                    // ---------------------------------------------------------
                    S_READ_BIT: begin
                        scl_out <= 1'b0;
                        sda_out <= 1'b1; // Release SDA for slave to drive
                        if (prescale_tick)
                            state <= S_READ_WAIT;
                    end

                    S_READ_WAIT: begin
                        scl_out <= 1'b1; // SCL high – sample SDA
                        if (prescale_tick) begin
                            scl_out   <= 1'b0;
                            shift_reg <= {shift_reg[6:0], sda_sync};
                            if (bit_cnt == 3'd0) begin
                                // All 8 bits read
                                state       <= S_ACK_SEND;
                                rx_data_reg <= {shift_reg[6:0], sda_sync};
                            end else begin
                                state   <= S_READ_BIT;
                                bit_cnt <= bit_cnt - 3'd1;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // ACK send (master → slave, after read)
                    // ---------------------------------------------------------
                    S_ACK_SEND: begin
                        scl_out <= 1'b0;
                        sda_out <= pending_nack; // 0=ACK, 1=NACK
                        if (prescale_tick)
                            state <= S_ACK_WAIT;
                    end

                    S_ACK_WAIT: begin
                        scl_out <= 1'b1; // SCL high for ACK clock
                        if (prescale_tick) begin
                            scl_out <= 1'b0;
                            sda_out <= 1'b1;
                            if (pending_stop) begin
                                state   <= S_STOP_A;
                                sda_out <= 1'b0;
                            end else begin
                                // Return to IDLE but KEEP SCL low
                                state      <= S_IDLE;
                                scl_out    <= 1'b0;  // Hold SCL low
                                cmd_done_r <= 1'b1;
                                irq_flag   <= ctrl_ien;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // ACK read (slave → master, after write)
                    // ---------------------------------------------------------
                    S_ACK_READ: begin
                        scl_out <= 1'b0;
                        sda_out <= 1'b1; // Release SDA
                        if (prescale_tick)
                            state <= S_ACK_RWAIT;
                    end

                    S_ACK_RWAIT: begin
                        scl_out <= 1'b1; // SCL high – sample slave ACK
                        if (prescale_tick) begin
                            scl_out <= 1'b0;  // Keep SCL low
                            rx_ack  <= sda_sync; // 0=ACK, 1=NACK
                            if (pending_stop) begin
                                state   <= S_STOP_A;
                                sda_out <= 1'b0;
                            end else begin
                                // Return to IDLE but KEEP SCL low
                                // so slave doesn't see false STOP
                                state      <= S_IDLE;
                                scl_out    <= 1'b0;  // Hold SCL low
                                cmd_done_r <= 1'b1;
                                irq_flag   <= ctrl_ien;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // STOP condition
                    // ---------------------------------------------------------
                    S_STOP_A: begin
                        sda_out <= 1'b0;
                        scl_out <= 1'b0;
                        if (prescale_tick) begin
                            state   <= S_STOP_B;
                            scl_out <= 1'b1; // Release SCL
                        end
                    end

                    S_STOP_B: begin
                        scl_out <= 1'b1;
                        sda_out <= 1'b0;
                        if (prescale_tick) begin
                            state   <= S_STOP_C;
                            sda_out <= 1'b1; // Release SDA → STOP
                        end
                    end

                    S_STOP_C: begin
                        scl_out <= 1'b1;
                        sda_out <= 1'b1;
                        busy    <= 1'b0;
                        if (prescale_tick) begin
                            state      <= S_IDLE;
                            cmd_done_r <= 1'b1;
                            irq_flag   <= ctrl_ien;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end

            // ================================================================
            // Register writes (AFTER FSM so bus writes take priority
            // via non-blocking last-write-wins semantics)
            // ================================================================
            if (we) begin
                case (addr)
                    5'h00: prescale_reg <= wdata[15:0];
                    5'h04: begin
                        ctrl_en  <= wdata[0];
                        ctrl_ien <= wdata[1];
                    end
                    5'h08: tx_data_reg <= wdata[7:0];
                    5'h10: begin
                        cmd_start <= wdata[0];
                        cmd_stop  <= wdata[1];
                        cmd_read  <= wdata[2];
                        cmd_write <= wdata[3];
                        cmd_nack  <= wdata[4];
                    end
                    5'h14: begin
                        // Write-1-to-clear for status flags
                        if (wdata[1]) irq_flag <= 1'b0;
                        if (wdata[3]) al       <= 1'b0;
                    end
                    default: ;
                endcase
            end

        end // !rst_n
    end // always

endmodule
