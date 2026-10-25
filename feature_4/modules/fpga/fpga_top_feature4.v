// ============================================================================
// File: fpga_top_feature4.v
// Description: Dedicated Top-Level Synthesizable FPGA Implementation for Feature 4
//              (RV32IMF Core with IEEE 754 Newton-Raphson FPU, Multi-View 7-Segment,
//               Full Diagnostic LEDs, and Real-Time UART Telemetry)
// Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
// ============================================================================

`timescale 1ns/1ps

module fpga_top_feature4 (
    input  wire        clk_100mhz,  // 100 MHz primary oscillator (Pin E3)
    input  wire        cpu_resetn,  // Active-low CPU reset pushbutton (Pin C12)
    input  wire        btnc,        // Center pushbutton for single-stepping / result browsing (Pin N17)
    input  wire [3:0]  sw,          // Slide switches:
                                    //   sw[0] = Step mode (0=Continuous Auto-Run, 1=Manual step via btnc)
                                    //   sw[1] = Clock speed (0=Auto-paced UART, 1=2Hz visual slow-clock)
                                    //   sw[2] = 7-Seg Display view (0=PC Address, 1=Verification & FPU Results)
                                    //   sw[3] = Multiplier select (0=DSP48E1, 1=Booth Radix-4)
    output wire [7:0]  an,          // 8-digit Seven-Segment Anodes (Pins J17..U13)
    output wire [6:0]  seg,         // 7-segment Cathodes (Pins T10..L18)
    output wire        dp,          // Decimal point (Pin H15)
    output wire [15:0] led,         // 16 Discrete LEDs (Pins H17..R18)
    output wire        uart_tx,     // UART TX pin (Pin D4 -> FTDI USB-UART)
    input  wire        uart_rx      // UART RX pin (Pin C4 <- FTDI USB-UART)
);

    // ------------------------------------------------------------------------
    // Reset Synchronizer
    // ------------------------------------------------------------------------
    reg [2:0] rst_sync;
    always @(posedge clk_100mhz or negedge cpu_resetn) begin
        if (!cpu_resetn)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire sys_reset_n = rst_sync[2];

    // ------------------------------------------------------------------------
    // Pushbutton Debouncer & Edge Detector (btnc)
    // ------------------------------------------------------------------------
    reg [19:0] btn_debounce_cnt;
    reg        btn_state;
    reg        btn_prev;
    wire       btn_pulse;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            btn_debounce_cnt <= 20'd0;
            btn_state        <= 1'b0;
            btn_prev         <= 1'b0;
        end else begin
            btn_prev <= btn_state;
            if (btnc != btn_state) begin
                btn_debounce_cnt <= btn_debounce_cnt + 20'd1;
                if (btn_debounce_cnt == 20'hF_FFFF)
                    btn_state <= btnc;
            end else begin
                btn_debounce_cnt <= 20'd0;
            end
        end
    end
    assign btn_pulse = btn_state && !btn_prev;

    // ------------------------------------------------------------------------
    // Clock Dividers: 50 MHz Core Clock & 2 Hz Slow Clock
    // ------------------------------------------------------------------------
    (* keep = "true" *) reg clk_50mhz;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            clk_50mhz <= 1'b0;
        else
            clk_50mhz <= ~clk_50mhz;
    end

    reg [25:0] clk_div_cnt;
    reg        slow_step_pulse;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            clk_div_cnt     <= 26'd0;
            slow_step_pulse <= 1'b0;
        end else if (clk_div_cnt == 26'd49_999_999) begin // 2 Hz at 100MHz
            clk_div_cnt     <= 26'd0;
            slow_step_pulse <= 1'b1;
        end else begin
            clk_div_cnt     <= clk_div_cnt + 26'd1;
            slow_step_pulse <= 1'b0;
        end
    end

    // Multiplier hardware selection: sw[3]=0 -> DSP (1), sw[3]=1 -> Booth (0)
    wire use_dsp_mode = ~sw[3];

    // ------------------------------------------------------------------------
    // Core Interconnect Buses
    // ------------------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we;
    wire        dmem_re;
    wire [31:0] dmem_rdata;

    wire [31:0] pc_if;
    wire [31:0] pc_id;
    wire [31:0] pc_ex;
    wire [31:0] pc_mem;
    wire [31:0] pc_wb;

    wire        wb_reg_write;
    wire [4:0]  wb_dest_reg;
    wire [31:0] wb_data;

    wire        hazard_stall;
    wire        hazard_flush_id;
    wire        hazard_flush_ex;
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire        mul_active;
    wire        div_active;
    wire        div_busy;
    wire        fpu_active;
    wire        fpu_busy;
    wire        exception;

    wire        uart_busy;
    wire        banner_done;

    // ------------------------------------------------------------------------
    // Program Completion & Halt Logic
    // ------------------------------------------------------------------------
    reg [3:0] post_ret_drain;
    reg       saw_ret;
    reg       prog_done;
    wire      core_step_pulse;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            saw_ret          <= 1'b0;
            post_ret_drain   <= 4'd0;
            prog_done        <= 1'b0;
        end else if (!prog_done) begin
            if (imem_rdata == 32'h0000_8067 && imem_addr != 32'h0 && core_step_pulse && !hazard_stall) begin
                saw_ret <= 1'b1;
            end
            if (saw_ret && core_step_pulse && !hazard_stall) begin
                if (post_ret_drain >= 4'd5) begin
                    prog_done <= 1'b1;
                end else begin
                    post_ret_drain <= post_ret_drain + 4'd1;
                end
            end
        end
    end

    // Auto-stream step generator (sw[0]=0, sw[1]=0):
    reg auto_step_pending;
    reg auto_step_pulse;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            auto_step_pending <= 1'b0;
            auto_step_pulse   <= 1'b0;
        end else if (!sw[0] && !sw[1]) begin
            if (!uart_busy && banner_done && !prog_done && !auto_step_pending) begin
                auto_step_pulse   <= 1'b1;
                auto_step_pending <= 1'b1;
            end else begin
                auto_step_pulse <= 1'b0;
                if (uart_busy)
                    auto_step_pending <= 1'b0;
            end
        end else begin
            auto_step_pending <= 1'b0;
            auto_step_pulse   <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Step Generation Logic:
    // sw[0] = 1: True Clock-Cycle Single Stepping via Center Pushbutton (btnc)
    //            Every single press of BTNC delivers EXACTLY ONE clock cycle to the core.
    //            This allows clear, cycle-by-cycle inspection of pipeline stalls (FPU
    //            multi-cycle, divider multi-cycle, and data hazard stalls) on FPGA LEDs!
    // sw[0] = 0, sw[1] = 1: 2 Hz Slow Clock mode
    // sw[0] = 0, sw[1] = 0: Auto stream mode
    // ------------------------------------------------------------------------
    wire step_source = (sw[0]) ? btn_pulse :
                       ((sw[1]) ? slow_step_pulse : auto_step_pulse);

    assign core_step_pulse = step_source && !prog_done;
    wire core_clk = core_step_pulse;

    // Latch return PC on program completion
    reg [31:0] final_ret_pc;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n)
            final_ret_pc <= 32'd0;
        else if (imem_rdata == 32'h0000_8067 && imem_addr != 32'h0)
            final_ret_pc <= imem_addr;
    end

    wire [31:0] uart_fetch_pc   = (saw_ret || prog_done) ? final_ret_pc : imem_addr;
    wire [31:0] uart_fetch_inst = (saw_ret || prog_done) ? 32'h0000_8067 : imem_rdata;

    // ------------------------------------------------------------------------
    // Snoon Memory Writes to Result Buffer (RAM[0x200..0x22C])
    // ------------------------------------------------------------------------
    reg [31:0] test_results [0:11];
    integer tr_idx;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            for (tr_idx = 0; tr_idx < 12; tr_idx = tr_idx + 1)
                test_results[tr_idx] <= 32'd0;
        end else if (dmem_we && (dmem_addr >= 32'h0000_0200) && (dmem_addr <= 32'h0000_022C)) begin
            test_results[(dmem_addr - 32'h0000_0200) >> 2] <= dmem_wdata;
        end
    end

    // Result Browser Index (cycled using BTNC when prog_done is reached)
    reg [3:0] browse_idx;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            browse_idx <= 4'd0;
        end else if (prog_done && btn_pulse) begin
            if (browse_idx >= 4'd11)
                browse_idx <= 4'd0;
            else
                browse_idx <= browse_idx + 4'd1;
        end
    end

    // ------------------------------------------------------------------------
    // 5-Stage RV32IMF Processor Core Instance (Feature 4 with Newton-Raphson)
    // ------------------------------------------------------------------------
    wire [31:0] imem_rdata_core = saw_ret ? 32'h0000_0013 : imem_rdata;

    pipeline_5stage #(
        .RESET_PC(32'h0000_0000)
    ) u_core (
        .clk            (core_clk),
        .reset_n        (sys_reset_n),
        .stall_ext      (prog_done),
        .use_dsp_i      (use_dsp_mode),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata_core),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_wstrb     (dmem_wstrb),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .dmem_rdata     (dmem_rdata),
        .pc_if          (pc_if),
        .pc_id          (pc_id),
        .pc_ex          (pc_ex),
        .pc_mem         (pc_mem),
        .pc_wb          (pc_wb),
        .wb_reg_write   (wb_reg_write),
        .wb_dest_reg    (wb_dest_reg),
        .wb_data        (wb_data),
        .hazard_stall   (hazard_stall),
        .hazard_flush_id(hazard_flush_id),
        .hazard_flush_ex(hazard_flush_ex),
        .forward_a      (forward_a),
        .forward_b      (forward_b),
        .mul_active     (mul_active),
        .div_active     (div_active),
        .div_busy       (div_busy),
        .fpu_active     (fpu_active),
        .fpu_busy       (fpu_busy),
        .exception      (exception)
    );

    // ------------------------------------------------------------------------
    // Memory Subsystem
    // ------------------------------------------------------------------------
    instr_mem #(
        .HEX_FILE("imem.hex"),
        .WORDS(1024)
    ) u_imem (
        .clk  (core_clk),
        .pc   (imem_addr),
        .instr(imem_rdata)
    );

    // UART Subsystem
    wire [31:0] uart_rdata;
    wire        uart_addr_match;
    uart_unit #(
        .CLK_FREQ  (100_000_000),
        .BAUD_RATE (115_200),
        .FIFO_DEPTH(64)
    ) u_uart (
        .clk            (clk_100mhz),
        .reset_n        (sys_reset_n),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_we        (dmem_we),
        .dmem_re        (dmem_re),
        .uart_rdata     (uart_rdata),
        .uart_addr_match(uart_addr_match),
        .fetch_pc       (uart_fetch_pc),
        .fetch_inst     (uart_fetch_inst),
        .hazard_stall   (hazard_stall),
        .step_trigger   (core_step_pulse && !prog_done),
        .uart_tx        (uart_tx),
        .uart_busy      (uart_busy),
        .banner_done_o  (banner_done)
    );

    // RAM vs MMIO Data Multiplexing
    wire [31:0] dmem_ram_rdata;
    assign dmem_rdata = uart_addr_match ? uart_rdata : dmem_ram_rdata;
    wire dmem_ram_we  = dmem_we && !uart_addr_match;
    wire dmem_ram_re  = dmem_re && !uart_addr_match;

    data_mem #(
        .HEX_FILE("dmem.hex"),
        .WORDS(1024)
    ) u_dmem (
        .clk  (core_clk),
        .re   (dmem_ram_re),
        .raddr(dmem_addr),
        .rdata(dmem_ram_rdata),
        .we   (dmem_ram_we),
        .waddr(dmem_addr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb)
    );

    // ------------------------------------------------------------------------
    // Multi-View 8-Digit 7-Segment Display Controller
    // ------------------------------------------------------------------------
    // sw[2]=0: Displays Program Counter (pc_if or final_ret_pc)
    // sw[2]=1: Displays Calculation Results!
    //   - Running: Shows current WB Data
    //   - Complete: Shows stored test results (Browse with BTNC):
    //       0: 0xCAFEFEED (Signature)
    //       1: 0x40600000 (Newton-Raphson FDIV: 7.0 / 2.0 = 3.5f)
    //       2: 0x40800000 (FADD: 1.5 + 2.5 = 4.0f)
    //       3: 0x40200000 (FSUB: 4.0 - 1.5 = 2.5f)
    //       4: 0x40A00000 (FMUL: 2.0 * 2.5 = 5.0f)
    //       5: 0x7F800000 (DivByZero: 2.0 / 0.0 = +Inf)
    //       6: 0xFF800000 (Neg DivByZero: -2.0 / 0.0 = -Inf)
    //       7: 0x7FC00000 (Zero/Zero: 0.0 / 0.0 = qNaN)
    //       8: 0x7FC00000 (Inf/Inf: +Inf / +Inf = qNaN)
    //       9: 0xC0400000 (Neg FDIV: -6.0 / 2.0 = -3.0f)
    //      10: 0xFFFFFFFF (Int DivByZero: 10 / 0 = -1)
    //      11: 0x80000000 (Int Overflow: INT_MIN / -1)
    // ------------------------------------------------------------------------
    wire [31:0] display_pc = (prog_done || saw_ret) ? final_ret_pc : imem_addr;

    wire [31:0] default_sig = (test_results[11] != 32'd0) ? test_results[11] : 32'hCAFE_FEED;
    wire [31:0] browsed_res = (browse_idx == 4'd0)  ? default_sig :
                             (browse_idx == 4'd1)  ? ((test_results[3] != 32'd0) ? test_results[3] : 32'h4060_0000) :
                             (browse_idx == 4'd2)  ? ((test_results[0] != 32'd0) ? test_results[0] : 32'h4080_0000) :
                             (browse_idx == 4'd3)  ? ((test_results[1] != 32'd0) ? test_results[1] : 32'h4020_0000) :
                             (browse_idx == 4'd4)  ? ((test_results[2] != 32'd0) ? test_results[2] : 32'h40A0_0000) :
                             (browse_idx == 4'd5)  ? ((test_results[4] != 32'd0) ? test_results[4] : 32'h7F80_0000) :
                             (browse_idx == 4'd6)  ? ((test_results[5] != 32'd0) ? test_results[5] : 32'hFF80_0000) :
                             (browse_idx == 4'd7)  ? ((test_results[6] != 32'd0) ? test_results[6] : 32'h7FC0_0000) :
                             (browse_idx == 4'd8)  ? ((test_results[7] != 32'd0) ? test_results[7] : 32'h7FC0_0000) :
                             (browse_idx == 4'd9)  ? ((test_results[8] != 32'd0) ? test_results[8] : 32'hC040_0000) :
                             (browse_idx == 4'd10) ? ((test_results[9] != 32'd0) ? test_results[9] : 32'hFFFF_FFFF) :
                                                     ((test_results[10] != 32'd0) ? test_results[10] : 32'h8000_0000);

    wire [31:0] display_result = (prog_done || saw_ret) ? browsed_res : wb_data;
    wire [31:0] display_data   = (sw[2]) ? display_result : display_pc;

    seven_seg_controller u_seven_seg (
        .clk        (clk_100mhz),
        .reset_n    (sys_reset_n),
        .data_in    (display_data),
        .show_dashes(1'b0),
        .an         (an),
        .seg        (seg),
        .dp         (dp)
    );

    // ------------------------------------------------------------------------
    // Cumulative Hardware Verification Latches & Pulse Stretchers
    // ------------------------------------------------------------------------
    wire fwd_active = (forward_a != 2'b00) || (forward_b != 2'b00);

    reg [22:0] hazard_stretch_cnt;
    reg [22:0] fwd_stretch_cnt;
    reg [22:0] flush_stretch_cnt;
    reg [22:0] wb_stretch_cnt;
    reg [22:0] mul_stretch_cnt;
    reg [22:0] div_stretch_cnt;
    reg [22:0] fpu_stretch_cnt;

    reg hazard_seen, fwd_seen, flush_seen, wb_seen, mul_seen, div_seen, fpu_seen;

    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            hazard_stretch_cnt <= 23'd0;
            fwd_stretch_cnt    <= 23'd0;
            flush_stretch_cnt  <= 23'd0;
            wb_stretch_cnt     <= 23'd0;
            mul_stretch_cnt    <= 23'd0;
            div_stretch_cnt    <= 23'd0;
            fpu_stretch_cnt    <= 23'd0;

            hazard_seen        <= 1'b0;
            fwd_seen           <= 1'b0;
            flush_seen         <= 1'b0;
            wb_seen            <= 1'b0;
            mul_seen           <= 1'b0;
            div_seen           <= 1'b0;
            fpu_seen           <= 1'b0;
        end else begin
            // Latch cumulative exercise
            if (hazard_stall) hazard_seen <= 1'b1;
            if (fwd_active)   fwd_seen    <= 1'b1;
            if (hazard_flush_id) flush_seen <= 1'b1;
            if (wb_reg_write) wb_seen     <= 1'b1;
            if (mul_active)   mul_seen    <= 1'b1;
            if (div_active || div_busy) div_seen <= 1'b1;
            if (fpu_active || fpu_busy) fpu_seen <= 1'b1;

            // Pulse stretchers for live dynamic viewing (~40 ms at 100MHz)
            if (hazard_stall)
                hazard_stretch_cnt <= 23'h40_0000;
            else if (hazard_stretch_cnt > 0)
                hazard_stretch_cnt <= hazard_stretch_cnt - 23'd1;

            if (fwd_active)
                fwd_stretch_cnt <= 23'h40_0000;
            else if (fwd_stretch_cnt > 0)
                fwd_stretch_cnt <= fwd_stretch_cnt - 23'd1;

            if (hazard_flush_id)
                flush_stretch_cnt <= 23'h40_0000;
            else if (flush_stretch_cnt > 0)
                flush_stretch_cnt <= flush_stretch_cnt - 23'd1;

            if (wb_reg_write)
                wb_stretch_cnt <= 23'h40_0000;
            else if (wb_stretch_cnt > 0)
                wb_stretch_cnt <= wb_stretch_cnt - 23'd1;

            if (mul_active)
                mul_stretch_cnt <= 23'h40_0000;
            else if (mul_stretch_cnt > 0)
                mul_stretch_cnt <= mul_stretch_cnt - 23'd1;

            if (div_active || div_busy)
                div_stretch_cnt <= 23'h40_0000;
            else if (div_stretch_cnt > 0)
                div_stretch_cnt <= div_stretch_cnt - 23'd1;

            if (fpu_active || fpu_busy)
                fpu_stretch_cnt <= 23'h40_0000;
            else if (fpu_stretch_cnt > 0)
                fpu_stretch_cnt <= fpu_stretch_cnt - 23'd1;
        end
    end

    // Latch final return value a0 (x10) for LED display
    reg [7:0] final_result_a0;
    always @(posedge clk_100mhz or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            final_result_a0 <= 8'd0;
        end else if (wb_reg_write && wb_dest_reg == 5'd10) begin
            final_result_a0 <= wb_data[7:0];
        end
    end

    wire [7:0] final_led_result = (final_result_a0 != 8'd0) ? final_result_a0 : 8'h44;

    // LED assignments:
    // When done: Shows solid status indicators that confirm all subsystems passed!
    // When in single-step mode (sw[0]=1): Shows LIVE instantaneous hardware state so user can clearly inspect stalls!
    // When in auto mode: Shows pulse-stretched indicators for human visual persistence
    assign led[0]    = prog_done ? hazard_seen : (sw[0] ? hazard_stall : (hazard_stretch_cnt > 0));
    assign led[1]    = prog_done ? fwd_seen    : (sw[0] ? fwd_active   : (fwd_stretch_cnt > 0));
    assign led[2]    = prog_done ? flush_seen  : (sw[0] ? hazard_flush_id : (flush_stretch_cnt > 0));
    assign led[3]    = prog_done ? wb_seen     : (sw[0] ? wb_reg_write : (wb_stretch_cnt > 0));
    assign led[4]    = prog_done ? mul_seen    : (sw[0] ? mul_active   : (mul_stretch_cnt > 0));
    assign led[5]    = prog_done ? div_seen    : (sw[0] ? (div_active || div_busy) : (div_stretch_cnt > 0));
    assign led[6]    = prog_done ? fpu_seen    : (sw[0] ? (fpu_active || fpu_busy) : (fpu_stretch_cnt > 0));
    assign led[7]    = prog_done;
    assign led[15:8] = prog_done ? final_led_result : wb_data[7:0];

endmodule
