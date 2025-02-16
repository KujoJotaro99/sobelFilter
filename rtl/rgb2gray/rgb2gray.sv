`timescale 1ns/1ps
module rgb2gray 
#(
    parameter WIDTH_P = 8
) (
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    input logic [WIDTH_P-1:0] red_i,
    input logic [WIDTH_P-1:0] blue_i,
    input logic [WIDTH_P-1:0] green_i,
    output logic [WIDTH_P-1:0] gray_o
);
    // formula y = 0.299*red + 0.587*green + 0.114*blue
    // refer: https://www.sciencedirect.com/science/article/pii/S187705092031200X
    // 0.299 approximated with 0.28125 
    // (red*0.25 + red*0.03125) = (red >> 2) + (red >> 5)
    localparam integer RED_SHIFT_1 = 2;
    localparam integer RED_SHIFT_2 = 5;
    // 0.587 approximated with 0.5625
    // (green*0.5 + green*0.0625) = (green >> 1) + (green >> 4)
    localparam integer GREEN_SHIFT_1 = 1;
    localparam integer GREEN_SHIFT_2 = 4;
    // 0.114 approximated with 0.09375
    // (blue*0.0625 + blue*0.03125) = (blue >> 4) + (blue >> 5)
    localparam integer BLUE_SHIFT_1 = 4;
    localparam integer BLUE_SHIFT_2 = 5;
        logic [WIDTH_P-1:0] red_term, green_term, blue_term;
        logic [3*WIDTH_P-1:0] terms_data;
        logic [3*WIDTH_P-1:0] terms_data_o;
        logic [0:0] valid_mid;
        logic [0:0] ready_mid;
    // approximate shifts as a mac shift operation
    assign red_term = (red_i >> RED_SHIFT_1) + (red_i >> RED_SHIFT_2);
    assign green_term = (green_i >> GREEN_SHIFT_1) + (green_i >> GREEN_SHIFT_2);
    assign blue_term = (blue_i >> BLUE_SHIFT_1) + (blue_i >> BLUE_SHIFT_2);
    assign terms_data = {red_term, green_term, blue_term};
    elastic #(
            .WIDTH_P(3*WIDTH_P)
        ) terms_elastic (
            .clk_i(clk_i),
            .rstn_i(rstn_i),
            .data_i(terms_data),
            .valid_i(valid_i),
            .ready_o(ready_o),
            .valid_o(valid_mid),
            .data_o(terms_data_o),
            .ready_i(ready_mid)
        );
        logic [WIDTH_P:0] rg_sum;
        logic [WIDTH_P+1:0] gray_sum;
    assign rg_sum = terms_data_o[3*WIDTH_P-1:2*WIDTH_P] + terms_data_o[2*WIDTH_P-1:WIDTH_P];
    assign gray_sum = rg_sum + terms_data_o[WIDTH_P-1:0];
        logic [WIDTH_P+1:0] gray_sum_pipe;
    elastic #(
            .WIDTH_P(WIDTH_P+2)
        ) sum_elastic (
            .clk_i(clk_i),
            .rstn_i(rstn_i),
            .data_i(gray_sum),
            .valid_i(valid_mid),
            .ready_o(ready_mid),
            .valid_o(valid_o),
            .data_o(gray_sum_pipe),
            .ready_i(ready_i)
        );
    assign gray_o = gray_sum_pipe[WIDTH_P-1:0];
endmodule