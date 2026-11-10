//=============================================================================
// Module 2: aes_mixcolumns
// Description: Full 128-bit State MixColumns transformation.
//              Instantiates 4 parallel 32-bit column MixColumns units.
//              Follows column-major byte ordering defined in Section 1.2:
//              - Column 0: [127:96]
//              - Column 1: [95:64]
//              - Column 2: [63:32]
//              - Column 3: [31:0]
//=============================================================================
module aes_mixcolumns (
    input  logic [127:0] i_state,
    output logic [127:0] o_state
);

    // Generate 4 parallel MixColumns units for the 4 columns of the AES State
    genvar c;
    generate
        for (c = 0; c < 4; c++) begin : gen_mixcol_units
            aes_mixcolumn_32b u_mixcol_col (
                .i_col ( i_state[127 - 32*c -: 32] ),
                .o_col ( o_state[127 - 32*c -: 32] )
            );
        end
    endgenerate

endmodule
