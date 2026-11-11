//=============================================================================
// Module 1: aes_mixcolumn_32b
// Description: Single 32-bit column MixColumns unit in GF(2^8).
//              Purely combinational logic using xtime() and bitwise XORs.
//=============================================================================
module aes_mixcolumn_32b (
    input  logic [31:0] i_col,
    output logic [31:0] o_col
);

    //-------------------------------------------------------------------------
    // Function: xtime
    // Implements multiplication by {02} in GF(2^8) modulo m(x) = x^8+x^4+x^3+x+1
    // xtime(x) = (x << 1) ^ (x[7] ? 8'h1b : 8'h00)
    //-------------------------------------------------------------------------
    function automatic logic [7:0] xtime (input logic [7:0] x);
        return {x[6:0], 1'b0} ^ (8'h1b & {8{x[7]}});
    endfunction

    // Byte extraction for the column: s0 is top row (MSB), s3 is bottom row (LSB)
    logic [7:0] s0, s1, s2, s3;
    logic [7:0] s0_x2, s1_x2, s2_x2, s3_x2; // 02 * s_i
    logic [7:0] s0_x3, s1_x3, s2_x3, s3_x3; // 03 * s_i
    logic [7:0] s0_out, s1_out, s2_out, s3_out;

    always_comb begin
        // Unpack 32-bit column into four 8-bit bytes
        s0 = i_col[31:24];
        s1 = i_col[23:16];
        s2 = i_col[15:8];
        s3 = i_col[7:0];

        // Multiply by {02} using xtime
        s0_x2 = xtime(s0);
        s1_x2 = xtime(s1);
        s2_x2 = xtime(s2);
        s3_x2 = xtime(s3);

        // Multiply by {03}: {03}*x = xtime(x) ^ x
        s0_x3 = s0_x2 ^ s0;
        s1_x3 = s1_x2 ^ s1;
        s2_x3 = s2_x2 ^ s2;
        s3_x3 = s3_x2 ^ s3;

        // Matrix multiplication in GF(2^8) via XOR network
        s0_out = s0_x2 ^ s1_x3 ^ s2    ^ s3;
        s1_out = s0    ^ s1_x2 ^ s2_x3 ^ s3;
        s2_out = s0    ^ s1    ^ s2_x2 ^ s3_x3;
        s3_out = s0_x3 ^ s1    ^ s2    ^ s3_x2;

        // Pack output column
        o_col  = {s0_out, s1_out, s2_out, s3_out};
    end

endmodule
