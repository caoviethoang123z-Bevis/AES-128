//=============================================================================
// Module: aes_round
// Description: Single Combinational AES Encryption Round.
//              Executes: SubBytes -> ShiftRows -> [MixColumns] -> AddRoundKey.
//              When i_is_final_round = 1, MixColumns is bypassed (Round 10).
//=============================================================================
module aes_round (
    input  logic [127:0] i_state,
    input  logic [127:0] i_round_key,
    input  logic         i_is_final_round,
    output logic [127:0] o_state
);

    logic [127:0] w_after_subbytes;
    logic [127:0] w_after_shiftrows;
    logic [127:0] w_after_mixcolumns;
    logic [127:0] w_mux_mixcolumns;

    // 1. SubBytes (16 S-Boxes)
    aes_subbytes u_subbytes (
        .i_state ( i_state          ),
        .o_state ( w_after_subbytes )
    );

    // 2. ShiftRows (Pure wiring)
    aes_shiftrows u_shiftrows (
        .i_state ( w_after_subbytes  ),
        .o_state ( w_after_shiftrows )
    );

    // 3. MixColumns (4 parallel 32-bit column units)
    aes_mixcolumns u_mixcolumns (
        .i_state ( w_after_shiftrows  ),
        .o_state ( w_after_mixcolumns )
    );

    // Bypass MixColumns in Final Round (Round 10)
    assign w_mux_mixcolumns = i_is_final_round ? w_after_shiftrows : w_after_mixcolumns;

    // 4. AddRoundKey (Round-Key XOR)
    assign o_state = w_mux_mixcolumns ^ i_round_key;

endmodule