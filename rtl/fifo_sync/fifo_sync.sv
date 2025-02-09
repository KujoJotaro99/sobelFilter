`timescale 1ns/1ps

module fifo_sync 
#(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [WIDTH_P-1:0] data_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic [WIDTH_P-1:0] data_o
);

    logic [$clog2(DEPTH_P):0] wr_ptr_l, rd_ptr_l, rd_ptr_next_w;
    logic [WIDTH_P-1:0] data_o_bypass_l, data_o_l;
    logic [0:0] bypass_w;

    // full empty and bypass logic
    assign ready_o = ~((wr_ptr_l[$clog2(DEPTH_P)] != rd_ptr_l[$clog2(DEPTH_P)]) && (wr_ptr_l[$clog2(DEPTH_P)-1:0] == rd_ptr_l[$clog2(DEPTH_P)-1:0])); // not full
    assign valid_o = (wr_ptr_l[$clog2(DEPTH_P):0] != rd_ptr_l[$clog2(DEPTH_P):0]); // not empty
    assign bypass_w = (wr_ptr_l[$clog2(DEPTH_P):0] == rd_ptr_next_w[$clog2(DEPTH_P):0]);

    // next ptr logic
    always_comb begin
        if (!rstn_i) begin
            rd_ptr_next_w = '0;
        end else if (valid_o & ready_i) begin
            rd_ptr_next_w = rd_ptr_l + 1'b1;
        end else begin
            rd_ptr_next_w = rd_ptr_l;
        end
    end

    // curr ptr logic
    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            wr_ptr_l <= '0;
        end else if (valid_i & ready_o) begin
            wr_ptr_l <= wr_ptr_l + 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            rd_ptr_l <= '0;
        end else if (valid_o & ready_i) begin
            rd_ptr_l <= rd_ptr_l + 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            data_o_bypass_l <= '0;
        end else if (valid_i & ready_o) begin
            data_o_bypass_l <= data_i;
        end
    end

    // sync ram
    sync_ram_block #(
        .WIDTH_P(WIDTH_P),
        .DEPTH_P(DEPTH_P)
    ) sync_fifo_ram (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(data_i),
        .wr_addr_i(wr_ptr_l[$clog2(DEPTH_P)-1:0]),
        .rd_addr_a_i(rd_ptr_next_w[$clog2(DEPTH_P)-1:0]),
        .rd_addr_b_i('0),
        .wr_en_i(valid_i & ready_o),
        .rd_en_a_i('1),
        .rd_en_b_i(1'b0),
        .data_a_o(data_o_l),
        .data_b_o()
    );

    assign data_o = bypass_w ? data_o_bypass_l : data_o_l;

endmodule
