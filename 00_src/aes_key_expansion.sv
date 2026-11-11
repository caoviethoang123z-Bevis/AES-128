//=============================================================================
// Module: aes_key_expansion
// Description: AES-128 Key Expansion using Precompute & Store architecture.
//              Generates and stores all 11 round keys (K0..K10) sequentially
//              over 10 clock cycles using only 4 S-Box units.
//              Strictly adheres to Ready-Valid handshake (Section 2.2) and
//              safe key-update protocol (Section 2.5.4).
//=============================================================================
module aes_key_expansion (
    input  logic              i_clk,
    input  logic              i_rst_n,

    // Top-level Key Interface (Ready-Valid)
    input  logic              i_key_valid,
    output logic              o_key_ready,
    input  logic [127:0]      i_key,

    // Handshake / Status with Encryption Control Unit & Datapath
    input  logic              i_dp_busy,     // 1: Datapath is encrypting a block (cannot overwrite keys)
    output logic              o_keys_valid,  // 1: All 11 round keys (K0..K10) are valid and ready
    /* verilator lint_off ASCRANGE */
    output logic [0:10][127:0] o_round_keys  // Precomputed Round Keys K0 to K10
    /* verilator lint_off ASCRANGE */
);

    //-------------------------------------------------------------------------
    // FSM State Declaration
    //-------------------------------------------------------------------------
    typedef enum logic {
        S_READY  = 1'b0,
        S_EXPAND = 1'b1
    } state_e;

    state_e      r_state, w_next_state;
    logic [3:0]  r_round_cnt, w_next_round_cnt; // Tracks round 1..10 during expansion
    logic        r_keys_valid, w_next_keys_valid;

    // Storage for 11 Round Keys (K0 .. K10)
    logic [127:0] r_round_keys [0:10];

    //-------------------------------------------------------------------------
    // Round Constant (Rcon) Lookup Function (Section 1.8)
    // Only the MSB of the 32-bit Rcon word is non-zero.
    //-------------------------------------------------------------------------
    function automatic logic [7:0] get_rcon_msb (input logic [3:0] round_idx);
        unique case (round_idx)
            4'd1:    return 8'h01;
            4'd2:    return 8'h02;
            4'd3:    return 8'h04;
            4'd4:    return 8'h08;
            4'd5:    return 8'h10;
            4'd6:    return 8'h20;
            4'd7:    return 8'h40;
            4'd8:    return 8'h80;
            4'd9:    return 8'h1b;
            4'd10:   return 8'h36;
            default: return 8'h00;
        endcase
    endfunction

    //-------------------------------------------------------------------------
    // Datapath for Next Round Key Generation (Combinational)
    // Computes K_{r} from K_{r-1}
    //-------------------------------------------------------------------------
    logic [127:0] w_prev_key;
    logic [31:0]  w0_prev, w1_prev, w2_prev, w3_prev;
    logic [31:0]  w_rotword;
    logic [31:0]  w_subword;
    logic [31:0]  w_rcon;
    logic [31:0]  w0_next, w1_next, w2_next, w3_next;
    logic [127:0] w_next_key;

    // Select previous round key K_{r-1}
    assign w_prev_key = r_round_keys[r_round_cnt - 4'd1];

    // Unpack K_{r-1} into four 32-bit words
    assign w0_prev = w_prev_key[127:96];
    assign w1_prev = w_prev_key[95:64];
    assign w2_prev = w_prev_key[63:32];
    assign w3_prev = w_prev_key[31:0];

    // RotWord([a0, a1, a2, a3]) = [a1, a2, a3, a0]
    assign w_rotword = {w3_prev[23:0], w3_prev[31:24]};

    // SubWord: Instantiate 4 parallel S-Boxes
    genvar b;
    generate
        for (b = 0; b < 4; b++) begin : gen_key_sbox
            aes_sbox u_key_sbox (
                .i_byte ( w_rotword[31 - 8*b -: 8] ),
                .o_byte ( w_subword[31 - 8*b -: 8] )
            );
        end
    endgenerate

    // Form 32-bit Rcon[r] word
    assign w_rcon = {get_rcon_msb(r_round_cnt), 24'h000000};

    // XOR chain to generate the four 32-bit words of K_{r}
    assign w0_next = w0_prev ^ w_subword ^ w_rcon;
    assign w1_next = w1_prev ^ w0_next;
    assign w2_next = w2_prev ^ w1_next;
    assign w3_next = w3_prev ^ w2_next;

    assign w_next_key = {w0_next, w1_next, w2_next, w3_next};

    //-------------------------------------------------------------------------
    // Ready-Valid Handshake & Control FSM (Combinational)
    //-------------------------------------------------------------------------
    logic w_key_handshake;

    // Can accept a new key only when in S_READY and Datapath is not busy
    assign o_key_ready     = (r_state == S_READY) && (!i_dp_busy);
    assign w_key_handshake = i_key_valid && o_key_ready;

    always_comb begin
        w_next_state      = r_state;
        w_next_round_cnt  = r_round_cnt;
        w_next_keys_valid = r_keys_valid;

        unique case (r_state)
            S_READY: begin
                if (w_key_handshake) begin
                    w_next_state      = S_EXPAND;
                    w_next_round_cnt  = 4'd1;  // Start computing K1 next cycle
                    w_next_keys_valid = 1'b0;  // Invalidate keys while expanding
                end
            end

            S_EXPAND: begin
                if (r_round_cnt == 4'd10) begin
                    w_next_state      = S_READY;
                    w_next_round_cnt  = 4'd1;
                    w_next_keys_valid = 1'b1;  // All K0..K10 are now ready!
                end else begin
                    w_next_round_cnt  = r_round_cnt + 4'd1;
                end
            end

            default: begin
                w_next_state      = S_READY;
                w_next_round_cnt  = 4'd1;
                w_next_keys_valid = 1'b0;
            end
        endcase
    end

    //-------------------------------------------------------------------------
    // Sequential Logic (Registers)
    //-------------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state      <= S_READY;
            r_round_cnt  <= 4'd1;
            r_keys_valid <= 1'b0;
            for (int k = 0; k <= 10; k++) begin
                r_round_keys[k] <= 128'h0;
            end
        end else begin
            r_state      <= w_next_state;
            r_round_cnt  <= w_next_round_cnt;
            r_keys_valid <= w_next_keys_valid;

            // Load K0 upon key handshake
            if (w_key_handshake) begin
                r_round_keys[0] <= i_key;
            end
            // Store K1..K10 sequentially during S_EXPAND
            else if (r_state == S_EXPAND) begin
                r_round_keys[r_round_cnt] <= w_next_key;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Output Assignments
    //-------------------------------------------------------------------------
    assign o_keys_valid = r_keys_valid;

    genvar k_idx;
    generate
        for (k_idx = 0; k_idx <= 10; k_idx++) begin : gen_out_keys
            assign o_round_keys[k_idx] = r_round_keys[k_idx];
        end
    endgenerate

endmodule
