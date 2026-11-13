`timescale 1ns/1ps

module tb_aes_sub_shift;

    logic         clk = 1'b0;
    logic         rst_n;
    logic [127:0] st_in;
    logic         st_vin;

    // Chain: aes_subbytes (1-cycle ROM) -> aes_shiftrows (0-cycle wire)
    logic [127:0] b_sb, b_out;
    logic         b_vout;

    int errors = 0;
    int checks = 0;

    always #2.5 clk = ~clk;   // 200 MHz

    aes_subbytes u_b_sb (
        .i_clk   ( clk    ),
        .i_rst_n ( rst_n  ),
        .i_valid ( st_vin ),
        .i_state ( st_in  ),
        .o_valid ( b_vout ),
        .o_state ( b_sb   )
    );

    aes_shiftrows u_b_sr (
        .i_state ( b_sb   ),
        .o_state ( b_out  )
    );

    // ---------------- Reference model ----------------
    function automatic logic [7:0] xtime(input logic [7:0] a);
        xtime = {a[6:0], 1'b0} ^ (a[7] ? 8'h1b : 8'h00);
    endfunction

    function automatic logic [7:0] gmul(input logic [7:0] a_in, input logic [7:0] b_in);
        logic [7:0] a, b, r;
        a = a_in; b = b_in; r = 8'h00;
        for (int i = 0; i < 8; i++) begin
            if (b[0]) r = r ^ a;
            a = xtime(a);
            b = b >> 1;
        end
        return r;
    endfunction

    function automatic logic [7:0] ref_sbox(input logic [7:0] x);
        logic [7:0] inv, y, c;
        c   = 8'h63;
        inv = 8'h00;
        if (x != 8'h00)
            for (int k = 1; k < 256; k++)
                if (gmul(x, k[7:0]) == 8'h01) inv = k[7:0];
        for (int i = 0; i < 8; i++)
            y[i] = inv[i] ^ inv[(i+4)%8] ^ inv[(i+5)%8] ^ inv[(i+6)%8] ^ inv[(i+7)%8] ^ c[i];
        return y;
    endfunction

    function automatic logic [127:0] ref_subbytes(input logic [127:0] s);
        logic [127:0] r;
        for (int b = 0; b < 16; b++)
            r[127 - 8*b -: 8] = ref_sbox(s[127 - 8*b -: 8]);
        return r;
    endfunction

    function automatic logic [127:0] ref_shiftrows(input logic [127:0] s);
        logic [127:0] r;
        for (int c = 0; c < 4; c++)
            for (int row = 0; row < 4; row++)
                r[127 - 8*(4*c + row) -: 8] = s[127 - 8*(4*((c + row) % 4) + row) -: 8];
        return r;
    endfunction

    task automatic check128(input string name, input logic [127:0] got, input logic [127:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL [%0t] %s: got %032h exp %032h", $time, name, got, exp);
        end
    endtask

    task automatic run_vector(input string tag, input logic [127:0] vec);
        logic [127:0] exp_sb, exp_sr;
        exp_sb = ref_subbytes(vec);
        exp_sr = ref_shiftrows(exp_sb);
        @(negedge clk);
        st_in  = vec;
        st_vin = 1'b1;
        @(posedge clk); #1;
        check128({tag, " SubBytes"},  b_sb,  exp_sb);
        check128({tag, " ShiftRows"}, b_out, exp_sr);
        checks++;
        if (b_vout !== 1'b1) begin errors++; $display("FAIL %s: valid not set", tag); end
        $display("[%s]", tag);
        $display("  Input     (st_in) : %032h", vec);
        $display("  SubBytes  (b_sb)  : %032h (Expected: %032h)", b_sb, exp_sb);
        $display("  ShiftRows (b_out) : %032h (Expected: %032h)\n", b_out, exp_sr);
    endtask

    initial begin
        $dumpfile("wave_sub_shift.vcd");
        $dumpvars(0, tb_aes_sub_shift);
        rst_n = 1'b0; st_vin = 1'b0; st_in = '0;
        repeat (3) @(posedge clk);
        #1;
        checks++;
        if (b_vout !== 1'b0) begin errors++; $display("FAIL: valid not 0 in reset"); end
        @(negedge clk) rst_n = 1'b1;

        run_vector("spec_r1", 128'h00102030405060708090a0b0c0d0e0f0);
        check128("spec_r1 SubBytes const",  b_sb,  128'h63cab7040953d051cd60e0e7ba70e18c);
        check128("spec_r1 ShiftRows const", b_out, 128'h6353e08c0960e104cd70b751bacad0e7);

        run_vector("spec_r2", 128'h89d810e8855ace682d1843d8cb128fe4);
        check128("spec_r2 SubBytes const",  b_sb,  128'ha761ca9b97be8b45d8ad1a611fc97369);
        check128("spec_r2 ShiftRows const", b_out, 128'ha7be1a6997ad739bd8c9ca451f618b61);

        run_vector("all_00",  128'h00000000000000000000000000000000);
        run_vector("all_ff",  128'hffffffffffffffffffffffffffffffff);
        run_vector("seq_0_f", 128'h000102030405060708090a0b0c0d0e0f);
        run_vector("seq_f_0", 128'h0f0e0d0c0b0a09080706050403020100);

        for (int b = 0; b < 16; b++) begin
            logic [127:0] v;
            v = '0;
            v[127 - 8*b -: 8] = 8'hA5;
            run_vector($sformatf("onehot_byte%0d", b), v);
        end

        for (int n = 0; n < 2000; n++) begin
            logic [127:0] v, e_sb, e_sr;
            logic         vin;
            v    = {$urandom, $urandom, $urandom, $urandom};
            vin  = ($urandom % 4 != 0);
            e_sb = ref_subbytes(v);
            e_sr = ref_shiftrows(e_sb);
            @(negedge clk);
            st_in  = v;
            st_vin = vin;
            @(posedge clk); #1;
            checks++;
            if (b_vout !== vin) begin errors++; $display("FAIL rand valid @%0d", n); end
            if (vin) check128("rand ShiftRows", b_out, e_sr);
        end

        @(negedge clk) st_vin = 1'b1;
        @(posedge clk);
        @(negedge clk) rst_n = 1'b0;
        #1;
        checks++;
        if (b_vout !== 1'b0) begin errors++; $display("FAIL: reset did not clear valid"); end
        @(negedge clk) begin rst_n = 1'b1; st_vin = 1'b0; end

        $display("----------------------------------------");
        $display("Checks run: %0d", checks);
        if (errors == 0) $display("PASS: SubBytes + ShiftRows chain OK");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
