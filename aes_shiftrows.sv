//=============================================================================
// Module: aes_shiftrows
// Description: AES-128 ShiftRows transformation (Section 1.5).
//              Implemented purely by fixed wire permutation (0 logic gates).
//              Follows column-major State representation (Section 1.2).
//=============================================================================
module aes_shiftrows (
    input  logic [127:0] i_state,
    output logic [127:0] o_state
);

    //-------------------------------------------------------------------------
    // Extract individual bytes p[0]..p[15] for readability (pure wiring)
    // p[0] is MSB [127:120], p[15] is LSB [7:0]
    //-------------------------------------------------------------------------
    logic [7:0] p [0:15];

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_unpack_bytes
            assign p[i] = i_state[127 - 8*i -: 8];
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Fixed Byte Permutation (Column-by-Column Serialization)
    // Row 0: no shift        -> p[0],  p[4],  p[8],  p[12]
    // Row 1: left shift by 1 -> p[5],  p[9],  p[13], p[1]
    // Row 2: left shift by 2 -> p[10], p[14], p[2],  p[6]
    // Row 3: left shift by 3 -> p[15], p[3],  p[7],  p[11]
    //-------------------------------------------------------------------------
    assign o_state = {
        // Column 0 (bits [127:96])
        p[0],  p[5],  p[10], p[15],
        // Column 1 (bits [95:64])
        p[4],  p[9],  p[14], p[3],
        // Column 2 (bits [63:32])
        p[8],  p[13], p[2],  p[7],
        // Column 3 (bits [31:0])
        p[12], p[1],  p[6],  p[11]
    };

endmodule
