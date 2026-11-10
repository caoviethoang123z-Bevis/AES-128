//=============================================================================
// Module 2: aes_subbytes
// Description: Full 128-bit State SubBytes transformation.
//              Instantiates 16 parallel aes_sbox units to substitute all
//              16 bytes of the AES State in a single combinational step.
//=============================================================================
module aes_subbytes (
    input  logic [127:0] i_state,
    output logic [127:0] o_state
);

    // Instantiate 16 parallel S-Box units for bytes 0..15
    genvar b;
    generate
        for (b = 0; b < 16; b++) begin : gen_sbox_units
            aes_sbox u_sbox (
                .i_byte ( i_state[127 - 8*b -: 8] ),
                .o_byte ( o_state[127 - 8*b -: 8] )
            );
        end
    endgenerate

endmodule
