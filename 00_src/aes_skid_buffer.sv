//=============================================================================
// Module: aes_skid_buffer
// Description: Registered Ready-Valid Skid Buffer (Decoupled Output Stage).
//              Prevents data loss or duplication under arbitrary output stalls
//              (i_cipher_ready = 0) while isolating critical timing paths.
//=============================================================================
module aes_skid_buffer #(
    parameter int DATA_WIDTH = 128
) (
    input  logic                  i_clk,
    input  logic                  i_rst_n,

    // Upstream Interface (from AES Datapath / Controller)
    input  logic                  i_in_valid,
    output logic                  o_in_ready,
    input  logic [DATA_WIDTH-1:0] i_in_data,

    // Downstream Interface (Top-level Ciphertext Output)
    output logic                  o_out_valid,
    input  logic                  i_out_ready,
    output logic [DATA_WIDTH-1:0] o_out_data
);

    //-------------------------------------------------------------------------
    // State Encoding for 2-entry Skid Buffer
    // S_EMPTY : 0 items stored (Both main reg and skid reg empty)
    // S_BUSY  : 1 item stored  (Main output reg holds valid data)
    // S_FULL  : 2 items stored (Main reg and skid reg both hold valid data)
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_EMPTY = 2'b00,
        S_BUSY  = 2'b01,
        S_FULL  = 2'b10
    } buf_state_e;

    buf_state_e            r_state, w_next_state;
    logic [DATA_WIDTH-1:0] r_data_out, r_skid_buf;

    logic w_push, w_pop;
    assign w_push = i_in_valid  && o_in_ready;
    assign w_pop  = o_out_valid && i_out_ready;

    // Ready-Valid status outputs driven directly from state
    assign o_in_ready  = (r_state != S_FULL);
    assign o_out_valid = (r_state != S_EMPTY);
    assign o_out_data  = r_data_out;

    //-------------------------------------------------------------------------
    // Next-State Logic
    //-------------------------------------------------------------------------
    always_comb begin
        w_next_state = r_state;
        unique case (r_state)
            S_EMPTY: begin
                if (w_push) w_next_state = S_BUSY;
            end
            S_BUSY: begin
                if (w_push && !w_pop)      w_next_state = S_FULL;
                else if (!w_push && w_pop) w_next_state = S_EMPTY;
            end
            S_FULL: begin
                if (w_pop) w_next_state = S_BUSY;
            end
            default: w_next_state = S_EMPTY;
        endcase
    end

    //-------------------------------------------------------------------------
    // Datapath Registers (No latches, glitch-free output)
    //-------------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state    <= S_EMPTY;
            r_data_out <= '0;
            r_skid_buf <= '0;
        end else begin
            r_state <= w_next_state;

            unique case (r_state)
                S_EMPTY: begin
                    if (w_push) begin
                        r_data_out <= i_in_data;
                    end
                end

                S_BUSY: begin
                    if (w_push && w_pop) begin
                        // Simultaneous push and pop: replace output directly
                        r_data_out <= i_in_data;
                    end else if (w_push && !w_pop) begin
                        // Output stalled (i_out_ready=0), park incoming data in skid reg
                        r_skid_buf <= i_in_data;
                    end
                end

                S_FULL: begin
                    if (w_pop) begin
                        // Downstream accepted data, move skid buffer to main output
                        r_data_out <= r_skid_buf;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
