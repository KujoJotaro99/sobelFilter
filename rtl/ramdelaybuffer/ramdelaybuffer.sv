`timescale 1ns/1ps

module ramdelaybuffer 
#(
    parameter WIDTH_P = 8,
    parameter DELAY_P = 12,
    // obviously will fail same delay test
    parameter DELAY_A_P = 4,
    parameter DELAY_B_P = 5
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    input logic [WIDTH_P-1:0] data_i,
    output logic [WIDTH_P-1:0] data_a_o,
    output logic [WIDTH_P-1:0] data_b_o
);
    initial begin
        if (DELAY_A_P > DELAY_P) begin
            $fatal(1, "DELAY_A_P (%0d) must be <= DELAY_P (%0d)", DELAY_A_P, DELAY_P);
        end
        if (DELAY_B_P > DELAY_P) begin
            $fatal(1, "DELAY_B_P (%0d) must be <= DELAY_P (%0d)", DELAY_B_P, DELAY_P);
        end
    end

    logic [$clog2(DELAY_P+1)-1:0] wr_addr;
    logic [$clog2(DELAY_P+1)-1:0] rd_addr_a;
    logic [$clog2(DELAY_P+1)-1:0] rd_addr_b;

    counter #(
        .WIDTH_P($clog2(DELAY_P+1)),
        .MAX_VAL_P(DELAY_P)
    ) wr_ptr_counter (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i(0),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .en_i(1'b1),
        .count_o(wr_addr)
    );

    counter #(
        .WIDTH_P($clog2(DELAY_P+1)),
        .MAX_VAL_P(DELAY_P)
    ) rd_ptr_counter_a (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i((DELAY_A_P == 0) ? '0 : (DELAY_P+1-DELAY_A_P)),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .en_i(1'b1),
        .count_o(rd_addr_a)
    );

    counter #(
        .WIDTH_P($clog2(DELAY_P+1)),
        .MAX_VAL_P(DELAY_P)
    ) rd_ptr_counter_b (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .rstn_data_i((DELAY_B_P == 0) ? '0 : (DELAY_P+1-DELAY_B_P)),
        .up_i(valid_i & ready_o),
        .down_i(1'b0),
        .en_i(1'b1),
        .count_o(rd_addr_b)
    );

    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(DELAY_P+1)
    ) sync_ram_delay (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .wr_addr_i(wr_addr),
        .rd_addr_a_i(rd_addr_a),
        .rd_addr_b_i(rd_addr_b),
        .wr_en_i(valid_i & ready_o),
        .rd_en_a_i(valid_i & ready_o),
        .rd_en_b_i(valid_i & ready_o),
        .data_a_o(data_a_o),
        .data_b_o(data_b_o)
    );

    elastic #(
        .WIDTH_P(WIDTH_P)
    ) stream_pipe (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i({WIDTH_P{1'b0}}),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(),
        .ready_i(ready_i)
    );

endmodule
