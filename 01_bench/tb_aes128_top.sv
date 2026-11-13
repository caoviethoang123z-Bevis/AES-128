`timescale 1ns/1ps
//=============================================================================
// Testbench: tb_aes128_top
// Source of the main vector: spec Example 1.1 / FIPS 197 Appendix C.1
//   P = 00112233445566778899aabbccddeeff
//   K = 000102030405060708090a0b0c0d0e0f
//   C = 69c4e0d86a7b0430d8cdb78070b4c55a
// The other 15 plaintext/ciphertext pairs (same key) were generated with an
// independent Python AES-128 model that was first checked against the vector
// above.
// NOTE: the key ROM stub supports only this one key.
// Parameter EXP_II: expected initiation interval (6 for the 2-round top,
//   12 for the 1-round top; e.g. verilator -GEXP_II=12).
// Checks: key-before-data, single block, output backpressure (hold + no
//         loss), initiation interval = 6 under continuous traffic, random
//         input gaps and random output stalls (no loss / duplicate /
//         reorder), reset in the middle of an operation.
//=============================================================================
module tb_aes128_top #(parameter int EXP_II = 12);

    logic         clk = 1'b0;
    logic         rst_n;
    logic         key_valid, key_ready;
    logic [127:0] key;
    logic         data_valid, data_ready;
    logic [127:0] plaintext;
    logic         cipher_valid, cipher_ready;
    logic [127:0] ciphertext;

    always #2.5 clk = ~clk;   // 200 MHz

    aes128_top dut (
        .i_clk          ( clk          ),
        .i_rst_n        ( rst_n        ),
        .i_key_valid    ( key_valid    ),
        .o_key_ready    ( key_ready    ),
        .i_key          ( key          ),
        .i_data_valid   ( data_valid   ),
        .o_data_ready   ( data_ready   ),
        .i_plaintext    ( plaintext    ),
        .o_cipher_valid ( cipher_valid ),
        .i_cipher_ready ( cipher_ready ),
        .o_ciphertext   ( ciphertext   )
    );

    localparam logic [127:0] PT [0:15] = '{
        128'h00112233445566778899aabbccddeeff,
        128'h00000000000000000000000000000000,
        128'hffffffffffffffffffffffffffffffff,
        128'hbcbaecd82eccff3bd9fbcb84d7f50c72,
        128'h421934dbf048f6753ee9f080cd9df5cd,
        128'hdd67968904104ceafab86685f8eefede,
        128'h1194a2ea32e084e75dd9f52088ffbd31,
        128'h63d24ae6072f00e72a657e3d1689b64f,
        128'h02a0fb4572f243942bd551459cd2c74c,
        128'h64c00736c7251ab1b40d0df3a79be6a6,
        128'h3efeee574e69deacea7723cc11645817,
        128'h18e760f70a426f46525fc78bd9d428c4,
        128'h9c5fb05986edfed493ef5aa6f6e33d8c,
        128'h306d76022fe8a9d05d0db450b46e388f,
        128'h6d968943338731df57361eb65e36a08d,
        128'h2095a15285832007d283d4071d31780b
    };
    localparam logic [127:0] CT [0:15] = '{
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'hc6a13b37878f5b826f4f8162a1c8d879,
        128'h3c441f32ce07822364d7a2990e50bb13,
        128'h01a89d7142b67eaa749464d52eed13a1,
        128'h240f68135b99335c2af87d89b4315051,
        128'h5790216884daa89ce656199d1d24b803,
        128'h1cbf37346a26704efc7ad7a023059e6e,
        128'h9d342d7fb333343cad939c2d7e06d19d,
        128'h21471ba8cf3d4304338eb3641c739976,
        128'hadfd7408e619f997e96a547594fd70a5,
        128'h1942c091fa5e5838e8db438511792148,
        128'h5b8db379217ea14c81f8881d02992336,
        128'h8e583f60734f05a203b2eb9a2fcd65ad,
        128'hcb32cda98a00e3b5fe8ff068371bec25,
        128'hf8b8ddc3a0530ce00e93fefb8eafb92a,
        128'hf78737df8bc4d9f59b6187c81e121cfc
    };

    localparam logic [127:0] TEST_KEY = 128'h000102030405060708090a0b0c0d0e0f;

    // ---------------- Scoreboard / monitors ----------------
    logic [127:0] exp_q [$];
    int           errors     = 0;
    int           acc_cnt    = 0;    // accepted plaintext blocks
    int           out_cnt    = 0;    // consumed ciphertext blocks
    int           cyc        = 0;
    int           last_acc   = -1;
    bit           ii_check   = 0;
    int           ii_min     = 1000;
    int           ii_max     = 0;
    logic         acc_data, acc_key;
    logic         prev_stall;
    logic [127:0] prev_ct;
    int           out_mode   = 0;    // 0: always ready, 1: random, 2: never ready

    function automatic logic [127:0] ct_of(input logic [127:0] p);
        for (int j = 0; j < 16; j++)
            if (PT[j] == p) return CT[j];
        return 128'hx;
    endfunction

    always @(posedge clk) begin
        cyc <= cyc + 1;
        acc_data <= 1'b0;
        acc_key  <= 1'b0;
        if (rst_n) begin
            if (key_valid && key_ready) acc_key <= 1'b1;

            if (data_valid && data_ready) begin
                acc_data <= 1'b1;
                exp_q.push_back(ct_of(plaintext));
                acc_cnt <= acc_cnt + 1;
                if (ii_check && last_acc >= 0) begin
                    if (cyc - last_acc < ii_min) ii_min <= cyc - last_acc;
                    if (cyc - last_acc > ii_max) ii_max <= cyc - last_acc;
                end
                last_acc <= cyc;
            end

            if (cipher_valid && cipher_ready) begin
                out_cnt <= out_cnt + 1;
                if (exp_q.size() == 0) begin
                    errors++; $display("FAIL [%0t] unexpected output", $time);
                end else begin
                    logic [127:0] e;
                    e = exp_q.pop_front();
                    if (ciphertext !== e) begin
                        errors++;
                        $display("FAIL [%0t] block %0d: got %032h exp %032h", $time, out_cnt, ciphertext, e);
                    end
                end
            end

            // Backpressure: data must be held while the receiver is not ready
            if (prev_stall) begin
                if (!cipher_valid || ciphertext !== prev_ct) begin
                    errors++; $display("FAIL [%0t] output not held during stall", $time);
                end
            end
            prev_stall <= cipher_valid && !cipher_ready;
            prev_ct    <= ciphertext;
        end else begin
            prev_stall <= 1'b0;
        end
    end

    // Receiver side
    always @(posedge clk) begin
        #1;
        case (out_mode)
            0: cipher_ready = 1'b1;
            1: cipher_ready = ($urandom % 2);
            default: cipher_ready = 1'b0;
        endcase
    end

    // ---------------- Tasks ----------------
    task automatic send(input int idx);
        data_valid = 1'b1;
        plaintext  = PT[idx];
        do begin @(posedge clk); #1; end while (!acc_data);
        data_valid = 1'b0;
    endtask

    task automatic drain();
        int guard;
        guard = 0;
        while (out_cnt != acc_cnt && guard < 2000) begin
            @(posedge clk); #1; guard++;
        end
        if (guard >= 2000) begin errors++; $display("FAIL: drain timeout"); end
    endtask

    task automatic send_key();
        key = TEST_KEY;
        key_valid = 1'b1;
        do begin @(posedge clk); #1; end while (!acc_key);
        key_valid = 1'b0;
    endtask

    // ---------------- Main test ----------------
    initial begin
        rst_n = 1'b0; key_valid = 1'b0; data_valid = 1'b0;
        key = '0; plaintext = '0; cipher_ready = 1'b1;
        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        #1;

        // (0) after reset: ready for key, not for data, no output
        if (key_ready !== 1'b1 || data_ready !== 1'b0 || cipher_valid !== 1'b0) begin
            errors++; $display("FAIL: wrong status after reset (kr=%b dr=%b cv=%b)", key_ready, data_ready, cipher_valid);
        end

        // (1) plaintext offered before any key must not be accepted
        data_valid = 1'b1; plaintext = PT[0];
        repeat (3) begin @(posedge clk); #1; end
        if (acc_cnt != 0) begin errors++; $display("FAIL: data accepted before key"); end
        data_valid = 1'b0;

        // (2) key, then single known-answer block
        send_key();
        out_mode = 0;
        send(0);
        drain();
        $display("INFO: single block done, out_cnt=%0d", out_cnt);

        // (3) output backpressure: hold output for 20 cycles, then release
        out_mode = 2;
        send(1);
        repeat (20) begin @(posedge clk); #1; end
        if (cipher_valid !== 1'b1) begin errors++; $display("FAIL: output lost during stall"); end
        if (data_ready !== 1'b0)   begin errors++; $display("FAIL: new data accepted while output is stalled"); end
        out_mode = 0;
        drain();

        // (4) continuous traffic, no output stalls: II must be 6 cycles
        ii_check = 1; last_acc = -1;
        for (int i = 0; i < 16; i++) send(i);
        drain();
        ii_check = 0;
        $display("INFO: initiation interval min=%0d max=%0d cycles", ii_min, ii_max);
        if (ii_min != EXP_II || ii_max != EXP_II) begin errors++; $display("FAIL: II is not %0d", EXP_II); end

        // (5) random input gaps + random output stalls
        out_mode = 1;
        for (int n = 0; n < 200; n++) begin
            repeat ($urandom % 4) begin @(posedge clk); #1; end
            send($urandom % 16);
        end
        drain();

        // (6) reset in the middle of an operation, then recover
        out_mode = 2;
        send(3);
        repeat (3) begin @(posedge clk); #1; end
        rst_n = 1'b0;
        repeat (2) begin @(posedge clk); #1; end
        exp_q.delete();
        out_cnt = acc_cnt;
        rst_n = 1'b1; #1;
        if (cipher_valid !== 1'b0 || data_ready !== 1'b0) begin
            errors++; $display("FAIL: wrong status after mid-operation reset");
        end
        out_mode = 0;
        send_key();
        send(4);
        send(0);
        drain();

        repeat (5) @(posedge clk);
        $display("----------------------------------------");
        $display("Blocks accepted: %0d, consumed: %0d", acc_cnt, out_cnt);
        if (errors == 0 && exp_q.size() == 0) $display("PASS: aes128_top OK");
        else                                  $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule
