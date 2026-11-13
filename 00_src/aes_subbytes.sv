module aes_subbytes (
    input  logic         i_clk,
    input  logic         i_rst_n,
    input  logic         i_valid,
    input  logic [127:0] i_state,
    output logic         o_valid,
    output logic [127:0] o_state
);

    genvar b;
    generate
        for (b = 0; b < 16; b = b + 1) begin : gen_sbox_units
            aes_sbox u_sbox (
                .i_clk  ( i_clk                    ),
                .i_byte ( i_state[127 - 8*b -: 8]  ),
                .o_byte ( o_state[127 - 8*b -: 8]  )
            );
        end
    endgenerate

    // Valid bit follows the same 1-cycle latency as the ROM output
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) o_valid <= 1'b0;
        else          o_valid <= i_valid;
    end

endmodule
