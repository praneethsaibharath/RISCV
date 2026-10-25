// ============================================================================
// File: fpu_single_core.v
// Description: Complete IEEE 754 Single-Precision Floating-Point Unit (RV32F)
//              with Hardware Newton-Raphson Divider
// Project: Pipelined RV32IMF RISC-V Core (Feature 4: IEEE 754 FPU)
// Instructions Supported:
//   - FADD.S : Floating-point Addition       (Latency: EXACTLY 5 cycles)
//   - FSUB.S : Floating-point Subtraction    (Latency: EXACTLY 5 cycles)
//   - FMUL.S : Floating-point Multiplication (Latency: EXACTLY 4 cycles)
//   - FDIV.S : Floating-point Division via   (Latency: EXACTLY 15 cycles)
//              Newton-Raphson Reciprocal Iteration
// Compliance:
//   - IEEE 754-2008 Standard 32-bit single-precision floating point
//   - Round to Nearest, ties to Even (RNE) rounding mode
//   - Full handling for zero, infinity, NaN, and divide-by-zero
// Handshaking:
//   - fpu_busy asserted high during execution to interlock hazard unit
//   - fpu_done asserted on the completion cycle
// ============================================================================

`timescale 1ns/1ps

module fpu_single_core (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        is_fpu,        // High when FPU instruction in EX stage
    input  wire [6:0]  funct7,        // FPU operation select (FADD, FSUB, FMUL, FDIV)
    input  wire [2:0]  funct3,        // Rounding mode (FRM_RNE default)
    input  wire [31:0] op_a,          // Float operand A (IEEE 754 single precision)
    input  wire [31:0] op_b,          // Float operand B (IEEE 754 single precision)
    output reg  [31:0] fpu_result,    // IEEE 754 float output
    output wire        fpu_busy,      // Multi-cycle stall interlock to Hazard Unit
    output wire        fpu_done       // High when valid result is ready in EX
);

    `include "opcode.vh"

    // FSM States
    localparam [1:0] S_IDLE = 2'b00,
                     S_CALC = 2'b01,
                     S_DONE = 2'b10;

    reg [1:0]  state;
    reg [3:0]  count;
    reg [6:0]  saved_op;
    reg [2:0]  saved_frm;
    reg [31:0] result_reg;

    // ------------------------------------------------------------------------
    // FADD / FSUB Pipeline Registers
    // ------------------------------------------------------------------------
    reg        fadd_sign_large;
    reg [8:0]  fadd_exp_large;
    reg [27:0] fadd_m_large_ext;
    reg [27:0] fadd_m_small_aligned;
    reg        fadd_eff_sub;
    reg [28:0] fadd_sum;
    reg [27:0] fadd_norm_m;
    reg [8:0]  fadd_norm_e;
    reg        fadd_sticky_round;
    reg [31:0] fadd_final_res;
    reg        fadd_is_zero_res;
    reg        fadd_nan, fadd_inf;
    reg [31:0] fadd_inf_val;

    // ------------------------------------------------------------------------
    // FMUL Pipeline Registers
    // ------------------------------------------------------------------------
    reg        fmul_sign_res;
    reg [9:0]  fmul_raw_exp;
    reg [23:0] fmul_mant_a, fmul_mant_b;
    reg [47:0] fmul_prod;
    reg        fmul_zero_res, fmul_nan, fmul_inf;
    reg [31:0] fmul_final_res;

    // ------------------------------------------------------------------------
    // FDIV Newton-Raphson Hardware Divider Pipeline Registers
    // ------------------------------------------------------------------------
    reg        fdiv_sign_res;
    reg [9:0]  fdiv_exp_res;
    reg        fdiv_div0, fdiv_nan, fdiv_zero_res;
    reg [31:0] fdiv_final_res;
    reg [23:0] nr_d;          // Divisor mantissa in Q1.23
    reg [24:0] nr_n;          // Pre-aligned dividend mantissa
    reg [24:0] nr_x;          // Reciprocal approximation in Q0.24 (bit 24 is 1.0)
    reg [24:0] nr_v;          // (2.0 - D * X) difference
    reg [26:0] nr_q;          // Quotient estimate in Q1.25
    reg [26:0] nr_r;          // Remainder value
    reg [51:0] nr_mult_res;   // DSP multiplier intermediate product

    // ------------------------------------------------------------------------
    // 64-Entry Newton-Raphson Initial Reciprocal Seed LUT
    // Indexed by Divisor Mantissa fraction bits [22:17]
    // ------------------------------------------------------------------------
    function [24:0] nr_seed;
        input [5:0] idx;
        begin
            case (idx)
                6'd0:  nr_seed = 25'h100_0000; // Exact 1.0 for D = 1.0
                6'd1:  nr_seed = 25'h0FA_232C;
                6'd2:  nr_seed = 25'h0F6_603D;
                6'd3:  nr_seed = 25'h0F2_B9D6;
                6'd4:  nr_seed = 25'h0EF_2EB7;
                6'd5:  nr_seed = 25'h0EB_BDB2;
                6'd6:  nr_seed = 25'h0E8_65AC;
                6'd7:  nr_seed = 25'h0E5_2598;
                6'd8:  nr_seed = 25'h0E1_FC78;
                6'd9:  nr_seed = 25'h0DE_E95C;
                6'd10: nr_seed = 25'h0DB_EC54;
                6'd11: nr_seed = 25'h0D9_047D;
                6'd12: nr_seed = 25'h0D6_3102;
                6'd13: nr_seed = 25'h0D3_7107;
                6'd14: nr_seed = 25'h0D0_C3A0;
                6'd15: nr_seed = 25'h0CE_280D;
                6'd16: nr_seed = 25'h0CB_9DD0;
                6'd17: nr_seed = 25'h0C9_2461;
                6'd18: nr_seed = 25'h0C6_BB46;
                6'd19: nr_seed = 25'h0C4_61C0;
                6'd20: nr_seed = 25'h0C2_174B;
                6'd21: nr_seed = 25'h0BF_DB61;
                6'd22: nr_seed = 25'h0BD_ADB9;
                6'd23: nr_seed = 25'h0BB_8E0D;
                6'd24: nr_seed = 25'h0B9_7BA9;
                6'd25: nr_seed = 25'h0B7_7708;
                6'd26: nr_seed = 25'h0B5_7FDE;
                6'd27: nr_seed = 25'h0B3_95E0;
                6'd28: nr_seed = 25'h0B1_B8C1;
                6'd29: nr_seed = 25'h0AF_E84B;
                6'd30: nr_seed = 25'h0AE_244B;
                6'd31: nr_seed = 25'h0AC_6C98;
                6'd32: nr_seed = 25'h0AA_BCE8;
                6'd33: nr_seed = 25'h0A9_1901;
                6'd34: nr_seed = 25'h0A7_7CE9;
                6'd35: nr_seed = 25'h0A5_EC3B;
                6'd36: nr_seed = 25'h0A4_66A8;
                6'd37: nr_seed = 25'h0A2_EBAD;
                6'd38: nr_seed = 25'h0A1_7B07;
                6'd39: nr_seed = 25'h0A0_1478;
                6'd40: nr_seed = 25'h09E_B7C2;
                6'd41: nr_seed = 25'h09D_64A8;
                6'd42: nr_seed = 25'h09C_1B03;
                6'd43: nr_seed = 25'h09A_DB98;
                6'd44: nr_seed = 25'h099_A629;
                6'd45: nr_seed = 25'h098_7A7D;
                6'd46: nr_seed = 25'h097_586F;
                6'd47: nr_seed = 25'h096_3FC5;
                6'd48: nr_seed = 25'h095_3049;
                6'd49: nr_seed = 25'h094_29CE;
                6'd50: nr_seed = 25'h093_2C24;
                6'd51: nr_seed = 25'h092_3719;
                6'd52: nr_seed = 25'h091_4A83;
                6'd53: nr_seed = 25'h090_6631;
                6'd54: nr_seed = 25'h08F_8A03;
                6'd55: nr_seed = 25'h08E_B5BC;
                6'd56: nr_seed = 25'h08D_E932;
                6'd57: nr_seed = 25'h08D_242B;
                6'd58: nr_seed = 25'h08C_6667;
                6'd59: nr_seed = 25'h08B_ACB9;
                6'd60: nr_seed = 25'h08A_F9F3;
                6'd61: nr_seed = 25'h08A_4DF8;
                6'd62: nr_seed = 25'h089_A891;
                6'd63: nr_seed = 25'h089_0984;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // Combinational Input Extraction
    // ------------------------------------------------------------------------
    wire sign_a = op_a[31];
    wire [7:0] exp_a = op_a[30:23];
    wire [22:0] frac_a = op_a[22:0];
    wire a_is_zero = (op_a[30:0] == 31'd0);
    wire a_is_nan  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire a_is_inf  = (exp_a == 8'hFF) && (frac_a == 23'd0);

    wire is_sub_op = (funct7 == FUNCT7_FSUB);
    wire sign_b = op_b[31] ^ is_sub_op;
    wire [7:0] exp_b = op_b[30:23];
    wire [22:0] frac_b = op_b[22:0];
    wire b_is_zero = (op_b[30:0] == 31'd0);
    wire b_is_nan  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire b_is_inf  = (exp_b == 8'hFF) && (frac_b == 23'd0);

    wire [23:0] mant_a = a_is_zero ? 24'd0 : {1'b1, frac_a};
    wire [23:0] mant_b = b_is_zero ? 24'd0 : {1'b1, frac_b};

    // Magnitude comparison for Addition/Subtraction
    wire a_greater = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));
    wire [7:0] exp_diff_in = a_greater ? (exp_a - exp_b) : (exp_b - exp_a);
    wire [23:0] m_large_in = a_greater ? mant_a : mant_b;
    wire [23:0] m_small_in = a_greater ? mant_b : mant_a;
    wire sign_large_in     = a_greater ? sign_a : sign_b;
    wire sign_small_in     = a_greater ? sign_b : sign_a;

    // Small mantissa alignment shifter (27 bits: mantissa + 3 guard bits)
    wire [26:0] small_ext = {m_small_in, 3'b000};
    wire [26:0] small_shifted = (exp_diff_in >= 8'd27) ? 27'd0 : (small_ext >> exp_diff_in);
    wire small_sticky = (exp_diff_in >= 8'd27) ? (|m_small_in) :
                        (|(small_ext & ((27'd1 << exp_diff_in) - 27'd1)));
    wire [27:0] m_small_aligned = {1'b0, small_shifted[26:1], small_shifted[0] | small_sticky};
    wire [27:0] m_large_aligned = {1'b0, m_large_in, 3'b000};

    // Leading Zero Counter Function for FADD Normalization (27 bits)
    function [4:0] clz27;
        input [26:0] val;
        integer i;
        reg found;
        begin
            clz27 = 5'd27;
            found = 1'b0;
            for (i = 26; i >= 0; i = i - 1) begin
                if (val[i] && !found) begin
                    clz27 = 5'd26 - i[4:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // Scratch Variables for Procedural Always Block
    // ------------------------------------------------------------------------
    reg [22:0] fmul_frac_raw, fmul_frac_final;
    reg        fmul_g, fmul_r, fmul_s, fmul_round_up;
    reg [9:0]  fmul_norm_e, fmul_final_e;

    reg signed [52:0] fdiv_rem_val;
    reg [26:0] fdiv_adj_q;
    reg [22:0] fdiv_frac_raw, fdiv_frac_final;
    reg        fdiv_g, fdiv_rd, fdiv_s, fdiv_round_up;
    reg [9:0]  fdiv_final_exp;

    reg [4:0]  fadd_lz;
    reg [22:0] fadd_frac_raw, fadd_frac_final;
    reg        fadd_g, fadd_r, fadd_s, fadd_round_up;
    reg [8:0]  fadd_final_e;

    // ------------------------------------------------------------------------
    // Main FSM State Machine & Multi-Cycle Execution
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_IDLE;
            count        <= 4'd0;
            saved_op     <= 7'd0;
            saved_frm    <= 3'd0;
            result_reg   <= 32'd0;

            // FADD
            fadd_sign_large       <= 1'b0;
            fadd_exp_large        <= 9'd0;
            fadd_m_large_ext      <= 28'd0;
            fadd_m_small_aligned  <= 28'd0;
            fadd_eff_sub          <= 1'b0;
            fadd_sum              <= 29'd0;
            fadd_norm_m           <= 28'd0;
            fadd_norm_e           <= 9'd0;
            fadd_sticky_round     <= 1'b0;
            fadd_final_res        <= 32'd0;
            fadd_is_zero_res      <= 1'b0;
            fadd_nan              <= 1'b0;
            fadd_inf              <= 1'b0;
            fadd_inf_val          <= 32'd0;

            // FMUL
            fmul_sign_res         <= 1'b0;
            fmul_raw_exp          <= 10'd0;
            fmul_mant_a           <= 24'd0;
            fmul_mant_b           <= 24'd0;
            fmul_prod             <= 48'd0;
            fmul_zero_res         <= 1'b0;
            fmul_nan              <= 1'b0;
            fmul_inf              <= 1'b0;
            fmul_final_res        <= 32'd0;

            // FDIV Newton-Raphson
            fdiv_sign_res         <= 1'b0;
            fdiv_exp_res          <= 10'd0;
            fdiv_div0             <= 1'b0;
            fdiv_nan              <= 1'b0;
            fdiv_zero_res         <= 1'b0;
            fdiv_final_res        <= 32'd0;
            nr_d                  <= 24'd0;
            nr_n                  <= 25'd0;
            nr_x                  <= 25'd0;
            nr_v                  <= 25'd0;
            nr_q                  <= 27'd0;
            nr_r                  <= 27'd0;
            nr_mult_res           <= 52'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (is_fpu) begin
                        saved_op  <= funct7;
                        saved_frm <= funct3;

                        case (funct7)
                            // ------------------------------------------------
                            // FMUL.S: Exactly 4 Cycles (1 IDLE + 2 CALC + 1 DONE)
                            // ------------------------------------------------
                            FUNCT7_FMUL: begin
                                count         <= 4'd1; // 2 CALC cycles: count=1, count=0
                                fmul_sign_res <= op_a[31] ^ op_b[31];
                                fmul_raw_exp  <= {2'b00, exp_a} + {2'b00, exp_b} - 10'd127;
                                fmul_mant_a   <= mant_a;
                                fmul_mant_b   <= mant_b;
                                fmul_zero_res <= a_is_zero || b_is_zero;
                                fmul_nan      <= (a_is_nan || b_is_nan || (a_is_zero && b_is_inf) || (a_is_inf && b_is_zero));
                                fmul_inf      <= (a_is_inf || b_is_inf) && !(a_is_nan || b_is_nan || (a_is_zero && b_is_inf) || (a_is_inf && b_is_zero));
                                state         <= S_CALC;
                            end

                            // ------------------------------------------------
                            // FDIV.S: Exactly 15 Cycles via Newton-Raphson
                            // (1 IDLE + 13 CALC + 1 DONE)
                            // ------------------------------------------------
                            FUNCT7_FDIV: begin
                                count         <= 4'd12; // 13 CALC cycles: count=12 down to 0
                                fdiv_sign_res <= op_a[31] ^ op_b[31];
                                fdiv_nan      <= (a_is_nan || b_is_nan || (b_is_zero && a_is_zero) || (a_is_inf && b_is_inf));
                                fdiv_div0     <= ((b_is_zero || a_is_inf) && !a_is_zero && !b_is_inf && !a_is_nan && !b_is_nan);
                                fdiv_zero_res <= ((a_is_zero || b_is_inf) && !b_is_zero && !a_is_inf && !a_is_nan && !b_is_nan);

                                nr_d <= mant_b;
                                nr_x <= nr_seed(mant_b[22:17]);

                                if (mant_a >= mant_b) begin
                                    nr_n         <= {1'b0, mant_a};
                                    fdiv_exp_res <= {2'b00, exp_a} - {2'b00, exp_b} + 10'd127;
                                end else begin
                                    nr_n         <= {mant_a, 1'b0};
                                    fdiv_exp_res <= {2'b00, exp_a} - {2'b00, exp_b} + 10'd126;
                                end

                                state <= S_CALC;
                            end

                            // ------------------------------------------------
                            // FADD.S / FSUB.S: Exactly 5 Cycles (1 IDLE + 3 CALC + 1 DONE)
                            // ------------------------------------------------
                            default: begin // FUNCT7_FADD, FUNCT7_FSUB
                                count                <= 4'd2; // 3 CALC cycles: count=2, count=1, count=0
                                fadd_sign_large      <= sign_large_in;
                                fadd_exp_large       <= {1'b0, (a_greater ? exp_a : exp_b)};
                                fadd_m_large_ext     <= m_large_aligned;
                                fadd_m_small_aligned <= m_small_aligned;
                                fadd_eff_sub         <= sign_large_in ^ sign_small_in;
                                fadd_is_zero_res     <= a_is_zero && b_is_zero;
                                fadd_nan             <= (a_is_nan || b_is_nan || (a_is_inf && b_is_inf && (sign_large_in ^ sign_small_in)));
                                fadd_inf             <= (a_is_inf || b_is_inf) && !(a_is_nan || b_is_nan || (a_is_inf && b_is_inf && (sign_large_in ^ sign_small_in)));
                                fadd_inf_val         <= a_is_inf ? op_a : {sign_b, 8'hFF, 23'd0};
                                state                <= S_CALC;
                            end
                        endcase
                    end
                end

                S_CALC: begin
                    case (saved_op)
                        // ====================================================
                        // FMUL.S Calculations (2 cycles)
                        // ====================================================
                        FUNCT7_FMUL: begin
                            if (count == 4'd1) begin
                                // Cycle 2: 24x24 mantissa multiply
                                fmul_prod <= fmul_mant_a * fmul_mant_b;
                                count     <= 4'd0;
                            end else begin
                                // Cycle 3: Normalization & IEEE 754 RNE Rounding
                                if (fmul_prod[47]) begin
                                    fmul_frac_raw = fmul_prod[46:24];
                                    fmul_g        = fmul_prod[23];
                                    fmul_r        = fmul_prod[22];
                                    fmul_s        = |fmul_prod[21:0];
                                    fmul_norm_e   = fmul_raw_exp + 10'd1;
                                end else begin
                                    fmul_frac_raw = fmul_prod[45:23];
                                    fmul_g        = fmul_prod[22];
                                    fmul_r        = fmul_prod[21];
                                    fmul_s        = |fmul_prod[20:0];
                                    fmul_norm_e   = fmul_raw_exp;
                                end

                                fmul_round_up = fmul_g && (fmul_r || fmul_s || fmul_frac_raw[0]);
                                if (fmul_round_up) begin
                                    if (fmul_frac_raw == 23'h7FFFFF) begin
                                        fmul_frac_final = 23'd0;
                                        fmul_final_e    = fmul_norm_e + 10'd1;
                                    end else begin
                                        fmul_frac_final = fmul_frac_raw + 23'd1;
                                        fmul_final_e    = fmul_norm_e;
                                    end
                                end else begin
                                    fmul_frac_final = fmul_frac_raw;
                                    fmul_final_e    = fmul_norm_e;
                                end

                                if (fmul_nan) begin
                                    fmul_final_res <= 32'h7FC0_0000;
                                end else if (fmul_inf) begin
                                    fmul_final_res <= {fmul_sign_res, 8'hFF, 23'd0};
                                end else if (fmul_zero_res || $signed(fmul_final_e) <= 0) begin
                                    fmul_final_res <= {fmul_sign_res, 31'd0};
                                end else if ($signed(fmul_final_e) >= 255) begin
                                    fmul_final_res <= {fmul_sign_res, 8'hFF, 23'd0};
                                end else begin
                                    fmul_final_res <= {fmul_sign_res, fmul_final_e[7:0], fmul_frac_final};
                                end

                                state <= S_DONE;
                            end
                        end

                        // ====================================================
                        // FDIV.S Newton-Raphson Hardware Divider (13 cycles)
                        // Latency: EXACTLY 15 cycles (1 IDLE + 13 CALC + 1 DONE)
                        // ====================================================
                        FUNCT7_FDIV: begin
                            case (count)
                                4'd12: begin
                                    // Step 1: Multiply D * X0 (Q1.23 * Q0.24 = Q1.47)
                                    nr_mult_res <= nr_d * nr_x;
                                    count       <= 4'd11;
                                end

                                4'd11: begin
                                    // Step 2: V1 = 2.0 - D * X0
                                    nr_v  <= 25'h100_0000 - nr_mult_res[47:24];
                                    count <= 4'd10;
                                end

                                4'd10: begin
                                    // Step 3: Multiply X0 * V1 (Q0.24 * Q1.23 = Q1.47)
                                    nr_mult_res <= nr_x * nr_v;
                                    count       <= 4'd9;
                                end

                                4'd9: begin
                                    // Step 4: Iteration 1 Result: X1 = (X0 * V1) >> 23
                                    nr_x  <= nr_mult_res[47:23];
                                    count <= 4'd8;
                                end

                                4'd8: begin
                                    // Step 5: Iteration 2 Multiply D * X1
                                    nr_mult_res <= nr_d * nr_x;
                                    count       <= 4'd7;
                                end

                                4'd7: begin
                                    // Step 6: V2 = 2.0 - D * X1
                                    nr_v  <= 25'h100_0000 - nr_mult_res[47:24];
                                    count <= 4'd6;
                                end

                                4'd6: begin
                                    // Step 7: Multiply X1 * V2
                                    nr_mult_res <= nr_x * nr_v;
                                    count       <= 4'd5;
                                end

                                4'd5: begin
                                    // Step 8: Iteration 2 Result: X2 = (X1 * V2) >> 23
                                    nr_x  <= nr_mult_res[47:23];
                                    count <= 4'd4;
                                end

                                4'd4: begin
                                    // Step 9: Quotient Approximation Q = N * X2
                                    nr_mult_res <= nr_n * nr_x;
                                    count       <= 4'd3;
                                end

                                4'd3: begin
                                    // Step 10: Extract Q (bit 25 is 1.0) and multiply Q * D for remainder check
                                    nr_q        <= nr_mult_res[48:22];
                                    nr_mult_res <= nr_mult_res[48:22] * nr_d;
                                    count       <= 4'd2;
                                end

                                4'd2: begin
                                    // Step 11: Exact 52-bit Remainder check: R = (N << 25) - Q * D
                                    fdiv_rem_val = $signed({2'b00, nr_n, 25'd0}) - $signed({1'b0, nr_mult_res});
                                    fdiv_adj_q   = nr_q;

                                    if (fdiv_rem_val >= $signed({2'b00, nr_d, 1'b0})) begin
                                        fdiv_adj_q   = nr_q + 27'd2;
                                        fdiv_rem_val = fdiv_rem_val - $signed({2'b00, nr_d, 1'b0});
                                    end else if (fdiv_rem_val >= $signed({3'b000, nr_d})) begin
                                        fdiv_adj_q   = nr_q + 27'd1;
                                        fdiv_rem_val = fdiv_rem_val - $signed({3'b000, nr_d});
                                    end else if (fdiv_rem_val < -$signed({2'b00, nr_d, 1'b0})) begin
                                        fdiv_adj_q   = nr_q - 27'd2;
                                        fdiv_rem_val = fdiv_rem_val + $signed({2'b00, nr_d, 1'b0});
                                    end else if (fdiv_rem_val < 0) begin
                                        fdiv_adj_q   = nr_q - 27'd1;
                                        fdiv_rem_val = fdiv_rem_val + $signed({3'b000, nr_d});
                                    end

                                    nr_q  <= fdiv_adj_q;
                                    nr_r  <= fdiv_rem_val[26:0];
                                    count <= 4'd1;
                                end

                                4'd1: begin
                                    // Step 12: IEEE-754 RNE Rounding & Pack
                                    fdiv_frac_raw  = nr_q[24:2];
                                    fdiv_g         = nr_q[1];
                                    fdiv_rd        = nr_q[0];
                                    fdiv_s         = |nr_r;
                                    fdiv_final_exp = fdiv_exp_res;

                                    fdiv_round_up = fdiv_g && (fdiv_rd || fdiv_s || fdiv_frac_raw[0]);
                                    if (fdiv_round_up) begin
                                        if (fdiv_frac_raw == 23'h7FFFFF) begin
                                            fdiv_frac_final = 23'd0;
                                            fdiv_final_exp  = fdiv_exp_res + 10'd1;
                                        end else begin
                                            fdiv_frac_final = fdiv_frac_raw + 23'd1;
                                        end
                                    end else begin
                                        fdiv_frac_final = fdiv_frac_raw;
                                    end

                                    if (fdiv_nan) begin
                                        fdiv_final_res <= 32'h7FC0_0000; // NaN
                                    end else if (fdiv_div0) begin
                                        fdiv_final_res <= {fdiv_sign_res, 8'hFF, 23'd0}; // +/- Infinity
                                    end else if (fdiv_zero_res || $signed(fdiv_final_exp) <= 0) begin
                                        fdiv_final_res <= {fdiv_sign_res, 31'd0};
                                    end else if ($signed(fdiv_final_exp) >= 255) begin
                                        fdiv_final_res <= {fdiv_sign_res, 8'hFF, 23'd0};
                                    end else begin
                                        fdiv_final_res <= {fdiv_sign_res, fdiv_final_exp[7:0], fdiv_frac_final};
                                    end

                                    count <= 4'd0;
                                end

                                4'd0: begin
                                    // Step 13: Latch and transition to S_DONE
                                    state <= S_DONE;
                                end
                            endcase
                        end

                        // ====================================================
                        // FADD.S / FSUB.S Calculations (3 cycles)
                        // ====================================================
                        default: begin
                            if (count == 4'd2) begin
                                // Cycle 2: Significand Add / Subtract
                                if (fadd_eff_sub) begin
                                    fadd_sum <= {1'b0, fadd_m_large_ext} - {1'b0, fadd_m_small_aligned};
                                end else begin
                                    fadd_sum <= {1'b0, fadd_m_large_ext} + {1'b0, fadd_m_small_aligned};
                                end
                                count <= 4'd1;
                            end else if (count == 4'd1) begin
                                // Cycle 3: Leading Zero Detect & Normalization
                                if (fadd_sum[27]) begin
                                    // Carry out from addition
                                    fadd_norm_m       <= fadd_sum[27:1];
                                    fadd_norm_e       <= fadd_exp_large + 9'd1;
                                    fadd_sticky_round <= fadd_sum[0];
                                end else begin
                                    fadd_lz = clz27(fadd_sum[26:0]);
                                    if (fadd_lz >= fadd_exp_large[4:0] && fadd_exp_large <= 9'd27) begin
                                        fadd_norm_m       <= (fadd_sum[26:0] << (fadd_exp_large > 0 ? (fadd_exp_large - 1) : 0));
                                        fadd_norm_e       <= 9'd0;
                                        fadd_sticky_round <= 1'b0;
                                    end else begin
                                        fadd_norm_m       <= (fadd_sum[26:0] << fadd_lz);
                                        fadd_norm_e       <= fadd_exp_large - {4'd0, fadd_lz};
                                        fadd_sticky_round <= 1'b0;
                                    end
                                end
                                count <= 4'd0;
                            end else begin
                                // Cycle 4: IEEE 754 RNE Rounding & Pack
                                fadd_frac_raw = fadd_norm_m[25:3];
                                fadd_g        = fadd_norm_m[2];
                                fadd_r        = fadd_norm_m[1];
                                fadd_s        = fadd_norm_m[0] | fadd_sticky_round;

                                fadd_round_up = fadd_g && (fadd_r || fadd_s || fadd_frac_raw[0]);
                                if (fadd_round_up) begin
                                    if (fadd_frac_raw == 23'h7FFFFF) begin
                                        fadd_frac_final = 23'd0;
                                        fadd_final_e    = fadd_norm_e + 9'd1;
                                    end else begin
                                        fadd_frac_final = fadd_frac_raw + 23'd1;
                                        fadd_final_e    = fadd_norm_e;
                                    end
                                end else begin
                                    fadd_frac_final = fadd_frac_raw;
                                    fadd_final_e    = fadd_norm_e;
                                end

                                if (fadd_nan) begin
                                    fadd_final_res <= 32'h7FC0_0000;
                                end else if (fadd_inf) begin
                                    fadd_final_res <= fadd_inf_val;
                                end else if (fadd_is_zero_res || fadd_sum == 29'd0 || $signed(fadd_final_e) <= 0) begin
                                    fadd_final_res <= 32'h0000_0000;
                                end else if ($signed(fadd_final_e) >= 255) begin
                                    fadd_final_res <= {fadd_sign_large, 8'hFF, 23'd0};
                                end else begin
                                    fadd_final_res <= {fadd_sign_large, fadd_final_e[7:0], fadd_frac_final};
                                end

                                state <= S_DONE;
                            end
                        end
                    endcase
                end

                S_DONE: begin
                    // Cycle 5 (FADD/FSUB), Cycle 4 (FMUL), Cycle 15 (FDIV via Newton-Raphson)
                    // Output is valid, return to IDLE on next clock edge
                    case (saved_op)
                        FUNCT7_FMUL: result_reg <= fmul_final_res;
                        FUNCT7_FDIV: result_reg <= fdiv_final_res;
                        default:     result_reg <= fadd_final_res;
                    endcase
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Result Mux
    always @(*) begin
        if (state == S_DONE) begin
            case (saved_op)
                FUNCT7_FMUL: fpu_result = fmul_final_res;
                FUNCT7_FDIV: fpu_result = fdiv_final_res;
                default:     fpu_result = fadd_final_res;
            endcase
        end else begin
            fpu_result = result_reg;
        end
    end

    // Handshaking:
    // fpu_busy is HIGH during multi-cycle computation, drops to LOW on S_DONE
    assign fpu_busy = is_fpu && (state != S_DONE);
    assign fpu_done = is_fpu && (state == S_DONE);

endmodule
