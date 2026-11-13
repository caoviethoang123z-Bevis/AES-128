module aes128_top (
    input  logic         i_clk,
    input  logic         i_rst_n,

    input  logic         i_key_valid,
    output logic         o_key_ready,
    input  logic [127:0] i_key,

    input  logic         i_data_valid,
    output logic         o_data_ready,
    input  logic [127:0] i_plaintext,

    output logic         o_cipher_valid,
    input  logic         i_cipher_ready,
    output logic [127:0] o_ciphertext
);

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;

    state_t       st_q;
    logic [3:0]   cnt_q;          // 0..9 (tương ứng Round 1..Round 10)
    logic         key_loaded_q;
    logic [127:0] state_q;        // Giữ kết quả Ciphertext ổn định ở trạng thái S_DONE

    logic key_acc, data_acc;

    assign o_key_ready    = (st_q == S_IDLE);
    assign key_acc        = i_key_valid & o_key_ready;
    assign o_data_ready   = key_loaded_q & (st_q == S_IDLE);
    assign data_acc       = i_data_valid & o_data_ready;
    assign o_cipher_valid = (st_q == S_DONE);

    // ---------------- FSM & Counter ----------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            st_q         <= S_IDLE;
            cnt_q        <= 4'd0;
            key_loaded_q <= 1'b0;
        end else begin
            if (key_acc) key_loaded_q <= 1'b1;
            case (st_q)
                S_IDLE: if (data_acc) begin
                            st_q  <= S_RUN;
                            cnt_q <= 4'd0;
                        end
                S_RUN:  if (cnt_q == 4'd9) st_q  <= S_DONE;
                        else               cnt_q <= cnt_q + 4'd1;
                S_DONE: if (i_cipher_ready) st_q <= S_IDLE;
                default: st_q <= S_IDLE;
            endcase
        end
    end

    // ---------------- Round Key ROM (r = cnt_q + 1) ----------------
    logic [127:0] k0, round_key, unused_key_b;

    aes_key_rom u_key_rom (
        .i_idx_a ( cnt_q + 4'd1 ),
        .i_idx_b ( 4'd0         ),
        .o_k0    ( k0           ),
        .o_key_a ( round_key    ),
        .o_key_b ( unused_key_b )
    );

    // ---------------- Datapath (Synchronous ROM SubBytes) ----------------
    logic [127:0] sbox_in;
    logic [127:0] sb, sr, mc, round_out;
    logic         sb_valid_unused;

    // Chọn dữ liệu đưa vào địa chỉ của S-Box ROM trước sườn lên i_clk:
    // - Khi bắt đầu nhận dữ liệu (data_acc = 1): đưa (i_plaintext ^ k0) vào ROM
    // - Khi đang chạy các vòng (st_q == S_RUN): đưa kết quả vòng hiện tại (round_out) quay lại ROM
    assign sbox_in = data_acc ? (i_plaintext ^ k0) : round_out;

    aes_subbytes u_sb (
        .i_clk   ( i_clk                    ),
        .i_rst_n ( i_rst_n                  ),
        .i_valid ( data_acc | (st_q == S_RUN) ),
        .i_state ( sbox_in                  ),
        .o_valid ( sb_valid_unused          ),
        .o_state ( sb                       )
    );

    aes_shiftrows  u_sr (.i_state(sb), .o_state(sr));
    aes_mixcolumns u_mc (.i_state(sr), .o_state(mc));

    // Vòng 10 (cnt_q == 9) bỏ qua MixColumns
    assign round_out = ((cnt_q == 4'd9) ? sr : mc) ^ round_key;

    // Chốt kết quả cuối cùng của Vòng 10 vào thanh ghi state_q để giữ cho S_DONE
    always_ff @(posedge i_clk) begin
        if (st_q == S_RUN && cnt_q == 4'd9) begin
            state_q <= round_out;
        end
    end

    assign o_ciphertext = state_q;

    // Tránh cảnh báo biến không sử dụng từ Verilator
    logic _unused_ok;
    assign _unused_ok = &{1'b0, i_key, unused_key_b, sb_valid_unused};

endmodule
