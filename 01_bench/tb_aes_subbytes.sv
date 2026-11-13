`timescale 1ns/1ps
//=============================================================================
// Testbench: tb_aes_subbytes_rom
// Checks   : (1) all 256 S-box entries vs. a reference computed from
//                GF(2^8) inverse + affine transform (FIPS 197, Sec. 5.1.1)
//            (2) FIPS 197 Appendix B round-1 SubBytes vector
//            (3) 1-cycle latency and valid propagation, random streaming
//            (4) reset behaviour of o_valid
//=============================================================================
module tb_aes_subbytes;

    logic         clk = 1'b0;
    logic         rst_n;
    logic [7:0]   sb_in,  sb_out;
    logic [127:0] st_in,  st_out;
    logic         st_vin, st_vout;
    int           errors = 0;

    always #2.5 clk = ~clk;   // 200 MHz

    aes_sbox u_dut_sbox (
        .i_clk  ( clk    ),
        .i_byte ( sb_in  ),
        .o_byte ( sb_out )
    );

    aes_subbytes u_dut_sub (
        .i_clk   ( clk     ),
        .i_rst_n ( rst_n   ),
        .i_valid ( st_vin  ),
        .i_state ( st_in   ),
        .o_valid ( st_vout ),
        .o_state ( st_out  )
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
        logic [7:0] inv, y;
        logic [7:0] c;
        c   = 8'h63;
        inv = 8'h00;
        if (x != 8'h00) begin
            for (int k = 1; k < 256; k++)
                if (gmul(x, k[7:0]) == 8'h01) inv = k[7:0];
        end
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

    // ---------------- Stimulus ----------------
    initial begin
        rst_n = 1'b0; st_vin = 1'b0; st_in = '0; sb_in = '0;
        repeat (3) @(posedge clk);
        #1 if (st_vout !== 1'b0) begin errors++; $display("FAIL: o_valid not 0 in reset"); end
        @(negedge clk) rst_n = 1'b1;

        // (1) exhaustive S-box test
        for (int i = 0; i < 256; i++) begin
            @(negedge clk) sb_in = i[7:0];
            @(posedge clk); #1;
            if (sb_out !== ref_sbox(i[7:0])) begin
                errors++;
                $display("FAIL sbox[%02h]: got %02h exp %02h", i[7:0], sb_out, ref_sbox(i[7:0]));
            end
        end

        // (2) FIPS 197 known vector (round 1, SubBytes input/output)
        @(negedge clk) begin st_in = 128'h00102030405060708090a0b0c0d0e0f0; st_vin = 1'b1; end
        @(posedge clk); #1;
        if (st_out !== 128'h63cab7040953d051cd60e0e7ba70e18c || st_vout !== 1'b1) begin
            errors++;
            $display("FAIL known vector: got %032h valid=%b", st_out, st_vout);
        end
        @(negedge clk) st_vin = 1'b0;
        @(posedge clk); #1;
        if (st_vout !== 1'b0) begin errors++; $display("FAIL: o_valid should drop"); end

        // (3) random streaming, 1 State per cycle, random gaps
        for (int n = 0; n < 1000; n++) begin
            @(negedge clk) begin
                st_in  = {$urandom, $urandom, $urandom, $urandom};
                st_vin = ($urandom % 4 != 0);
            end
            @(posedge clk); #1;
            if (st_vout !== st_vin) begin errors++; $display("FAIL valid @%0d", n); end
            if (st_vin && st_out !== ref_subbytes(st_in)) begin
                errors++;
                $display("FAIL data @%0d: got %032h exp %032h", n, st_out, ref_subbytes(st_in));
            end
        end

        // (4) reset clears valid
        @(negedge clk) st_vin = 1'b1;
        @(posedge clk);
        @(negedge clk) rst_n = 1'b0;
        #1 if (st_vout !== 1'b0) begin errors++; $display("FAIL: reset did not clear o_valid"); end
        @(negedge clk) begin rst_n = 1'b1; st_vin = 1'b0; end

        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule