`timescale 1ns/1ps

module magnitude 
#(
    parameter WIDTH_P = 8
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    input logic [WIDTH_P-1:0] gx_i,
    input logic [WIDTH_P-1:0] gy_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic [WIDTH_P-1:0] mag_o
);

    logic [WIDTH_P:0] mag_sum;
    logic [WIDTH_P:0] mag_pre;
    assign mag_sum = {1'b0, gx_i} + {1'b0, gy_i};
    
    elastic #(
        .WIDTH_P(WIDTH_P+1)
    ) mag_elastic (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(mag_sum),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .valid_o(valid_o),
        .data_o(mag_pre),
        .ready_i(ready_i)
    );

    assign mag_o = mag_pre[WIDTH_P] ? {WIDTH_P{1'b1}} : mag_pre[WIDTH_P-1:0];

endmodule
