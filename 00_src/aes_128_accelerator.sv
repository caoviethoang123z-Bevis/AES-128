//=============================================================================
// Module: aes_128_accelerator (TOP-LEVEL MODULE)
// Description: AES-128 Encryption Accelerator (4.0+ Gb/s @ 200 MHz, 45-nm).
//              Architecture: 2-Round Partially Unrolled Iterative Datapath
//                            (5 cycles/block, II_block = 5, TP = 5.12 Gb/s).
//              Port interface strictly matches Table 2 (Section 2.2).
//=============================================================================
module aes_128_accelerator (
    input  logic         i_clk,
    input  logic         i_rst_n,

    // Key Interface (Ready-Valid)
    input  logic         i_key_valid,
    output logic         o_key_ready,
    input  logic [127:0] i_key,

    // Plaintext Input Interface (Ready-Valid)
    input  logic         i_data_valid,
    output logic         o_data_ready,
    input  logic [127:0] i_plaintext,

    // Ciphertext Output Interface (Ready-Valid)
    output logic         o_cipher_valid,
    input  logic         i_cipher_ready,
    output logic [127:0] o_ciphertext
);

    //-------------------------------------------------------------------------
    // 1. Key Expansion Instance (Precompute & Store K0..K10)
    //-------------------------------------------------------------------------
    logic               w_dp_busy;
    logic               w_keys_valid;
    /* verilator lint_off ASCRANGE */
    logic [0:10][127:0] w_round_keys;
    /* verilator lint_on ASCRANGE */   // FIX #1: was lint_off (missing lint_on)

    aes_key_expansion u_key_expansion (
        .i_clk        ( i_clk        ),
        .i_rst_n      ( i_rst_n      ),
        .i_key_valid  ( i_key_valid  ),
        .o_key_ready  ( o_key_ready  ),
        .i_key        ( i_key        ),
        .i_dp_busy    ( w_dp_busy    ),
        .o_keys_valid ( w_keys_valid ),
        .o_round_keys ( w_round_keys )
    );

    //-------------------------------------------------------------------------
    // 2. Main Encryption Controller & 2-Round Unrolled Datapath
    //    Step 0 (Cycle 1): (Plaintext ^ K0) -> Round 1 (K1) -> Round 2 (K2)
    //    Step 1 (Cycle 2): State            -> Round 3 (K3) -> Round 4 (K4)
    //    Step 2 (Cycle 3): State            -> Round 5 (K5) -> Round 6 (K6)
    //    Step 3 (Cycle 4): State            -> Round 7 (K7) -> Round 8 (K8)
    //    Step 4 (Cycle 5): State            -> Round 9 (K9) -> Round 10 (K10, final)
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        DP_IDLE = 2'b00, // Waiting for plaintext (or executing Step 0 on handshake)
        DP_RUN  = 2'b01, // Executing Steps 1..4
        DP_HOLD = 2'b10  // Stalled at end of Step 4 if Skid Buffer is full
    } dp_state_e;

    dp_state_e    r_dp_state, w_next_dp_state;
    logic [2:0]   r_step_cnt, w_next_step_cnt; // 0..4 (5 steps total)
    logic [127:0] r_aes_state;

    // Skid buffer handshake signals
    logic         w_skid_in_valid;
    logic         w_skid_in_ready;
    logic [127:0] w_skid_in_data;

    // Handshake at Plaintext input
    // Note: Do not accept new plaintext if a new key is being presented (i_key_valid)
    //       so key updates take clean precedence when idle.
    logic w_data_handshake;
    assign o_data_ready     = (r_dp_state == DP_IDLE) && w_keys_valid && (!i_key_valid);
    assign w_data_handshake = i_data_valid && o_data_ready;

    // Datapath is busy whenever it is not idle or is currently accepting a block
    assign w_dp_busy = (r_dp_state != DP_IDLE) || w_data_handshake;

    // Active step index: 0 during initial handshake in DP_IDLE, otherwise r_step_cnt (1..4)
    logic [2:0] w_active_step;
    assign w_active_step = (r_dp_state == DP_IDLE) ? 3'd0 : r_step_cnt;

    logic [127:0] w_round_odd_in;
    logic [127:0] w_round_odd_out;
    logic [127:0] w_round_even_out;
    logic [127:0] w_key_odd, w_key_even;
    logic         w_is_final_round;

    // Round input select:
    //   DP_IDLE : Step 0 -> (i_plaintext ^ K0)
    //   DP_RUN  : Steps 1..4 -> r_aes_state
    //   DP_HOLD : operand isolation (round output is discarded in this state)
    always_comb begin
        unique case (r_dp_state)
            DP_IDLE: w_round_odd_in = i_plaintext ^ w_round_keys[0];
            DP_RUN : w_round_odd_in = r_aes_state;
            default: w_round_odd_in = '0;
        endcase
    end

    // FIX #2/#4: explicit key mux (no arithmetic index) -> no out-of-range
    //            access for invalid step values (5..7), maps to a clean mux.
    always_comb begin
        unique case (w_active_step)
            3'd0:    begin w_key_odd = w_round_keys[1]; w_key_even = w_round_keys[2];  end
            3'd1:    begin w_key_odd = w_round_keys[3]; w_key_even = w_round_keys[4];  end
            3'd2:    begin w_key_odd = w_round_keys[5]; w_key_even = w_round_keys[6];  end
            3'd3:    begin w_key_odd = w_round_keys[7]; w_key_even = w_round_keys[8];  end
            3'd4:    begin w_key_odd = w_round_keys[9]; w_key_even = w_round_keys[10]; end
            default: begin w_key_odd = '0;              w_key_even = '0;               end
        endcase
    end

    assign w_is_final_round = (w_active_step == 3'd4); // Round 10 omits MixColumns

    // Odd Round (Rounds 1, 3, 5, 7, 9 - always includes MixColumns)
    aes_round u_round_odd (
        .i_state          ( w_round_odd_in  ),
        .i_round_key      ( w_key_odd       ),
        .i_is_final_round ( 1'b0            ),
        .o_state          ( w_round_odd_out )
    );

    // Even Round (Rounds 2, 4, 6, 8, 10 - omits MixColumns on step 4)
    aes_round u_round_even (
        .i_state          ( w_round_odd_out  ),
        .i_round_key      ( w_key_even       ),
        .i_is_final_round ( w_is_final_round ),
        .o_state          ( w_round_even_out )
    );

    //-------------------------------------------------------------------------
    // Datapath Control FSM & Output Push Logic
    //-------------------------------------------------------------------------
    always_comb begin
        w_next_dp_state = r_dp_state;
        w_next_step_cnt = r_step_cnt;
        w_skid_in_valid = 1'b0;
        w_skid_in_data  = w_round_even_out;

        unique case (r_dp_state)
            DP_IDLE: begin
                if (w_data_handshake) begin
                    w_next_dp_state = DP_RUN;
                    w_next_step_cnt = 3'd1;
                end
            end

            DP_RUN: begin
                if (r_step_cnt == 3'd4) begin
                    // Cycle 5 (Step 4): Round 10 output is ready on w_round_even_out
                    w_skid_in_valid = 1'b1;
                    w_skid_in_data  = w_round_even_out;

                    if (w_skid_in_ready) begin
                        w_next_dp_state = DP_IDLE;
                        w_next_step_cnt = 3'd0;
                    end else begin
                        // Skid buffer full: ciphertext latched into r_aes_state, wait in DP_HOLD
                        w_next_dp_state = DP_HOLD;
                    end
                end else begin
                    w_next_step_cnt = r_step_cnt + 3'd1;
                end
            end

            DP_HOLD: begin
                w_skid_in_valid = 1'b1;
                w_skid_in_data  = r_aes_state;

                if (w_skid_in_ready) begin
                    w_next_dp_state = DP_IDLE;
                    w_next_step_cnt = 3'd0;
                end
            end

            default: begin
                w_next_dp_state = DP_IDLE;
                w_next_step_cnt = 3'd0;
            end
        endcase
    end

    //-------------------------------------------------------------------------
    // Sequential: FSM (async reset)
    //-------------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_dp_state <= DP_IDLE;
            r_step_cnt <= 3'd0;
        end else begin
            r_dp_state <= w_next_dp_state;
            r_step_cnt <= w_next_step_cnt;
        end
    end

    //-------------------------------------------------------------------------
    // Sequential: AES state register (no reset - datapath only, saves area).
    // Contents are only consumed after being loaded (DP_RUN / DP_HOLD).
    //-------------------------------------------------------------------------
    logic w_state_load;
    assign w_state_load = (r_dp_state == DP_IDLE && w_data_handshake) ||
                          (r_dp_state == DP_RUN);

    always_ff @(posedge i_clk) begin
        if (w_state_load) begin
            r_aes_state <= w_round_even_out;
        end
    end

    //-------------------------------------------------------------------------
    // 3. Output Skid Buffer Instance (Backpressure & Ready-Valid Handler)
    //-------------------------------------------------------------------------
    aes_skid_buffer #(
        .DATA_WIDTH ( 128 )
    ) u_output_skid_buffer (
        .i_clk       ( i_clk           ),
        .i_rst_n     ( i_rst_n         ),
        .i_in_valid  ( w_skid_in_valid ),
        .o_in_ready  ( w_skid_in_ready ),
        .i_in_data   ( w_skid_in_data  ),
        .o_out_valid ( o_cipher_valid  ),
        .i_out_ready ( i_cipher_ready  ),
        .o_out_data  ( o_ciphertext    )
    );

endmodule
