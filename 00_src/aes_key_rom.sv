module aes_key_rom (
    input  logic [3:0]   i_idx_a,
    input  logic [3:0]   i_idx_b,
    output logic [127:0] o_k0,
    output logic [127:0] o_key_a,
    output logic [127:0] o_key_b
);

    localparam logic [127:0] ROUND_KEY_ROM [0:10] = '{
        128'h00010203_04050607_08090a0b_0c0d0e0f, // K0
        128'hd6aa74fd_d2af72fa_daa678f1_d6ab76fe, // K1
        128'hb692cf0b_643dbdf1_be9bc500_6830b3fe, // K2
        128'hb6ff744e_d2c2c9bf_6c590cbf_0469bf41, // K3
        128'h47f7f7bc_95353e03_f96c32bc_fd058dfd, // K4
        128'h3caaa3e8_a99f9deb_50f3af57_adf622aa, // K5
        128'h5e390f7d_f7a69296_a7553dc1_0aa31f6b, // K6
        128'h14f9701a_e35fe28c_440adf4d_4ea9c026, // K7
        128'h47438735_a41c65b9_e016baf4_aebf7ad2, // K8
        128'h549932d1_f0855768_1093ed9c_be2c974e, // K9
        128'h13111d7f_e3944a17_f307a78b_4d2b30c5  // K10
    };

    assign o_k0 = ROUND_KEY_ROM[0];

    always_comb begin
        if (i_idx_a <= 4'd10) o_key_a = ROUND_KEY_ROM[i_idx_a];
        else                  o_key_a = 128'h0;
    end

    always_comb begin
        if (i_idx_b <= 4'd10) o_key_b = ROUND_KEY_ROM[i_idx_b];
        else                  o_key_b = 128'h0;
    end

endmodule
