`timescale 1ns/1ps

module conv2d_box
#(
    parameter WIDTH_P = 8,
    parameter DEPTH_P = 16
)(
    input logic [0:0] clk_i,
    input logic [0:0] rstn_i,
    input logic [0:0] valid_i,
    input logic [0:0] ready_i,
    input logic [WIDTH_P-1:0] data_i,
    output logic [0:0] valid_o,
    output logic [0:0] ready_o,
    output logic signed [(2*WIDTH_P)-1:0] gx_o,
    output logic signed [(2*WIDTH_P)-1:0] gy_o
);

    logic [WIDTH_P-1:0] ram_row0;
    logic [WIDTH_P-1:0] ram_row1;

    logic [0:0] box_valid;
    logic [0:0] box_ready;

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(2*DEPTH_P-1),
        .DELAY_A_P(2*DEPTH_P-1),
        .DELAY_B_P(DEPTH_P-1)
    ) line_buffer (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(box_ready),
        .valid_o(box_valid),
        .ready_o(ready_o),
        .data_i(data_i),
        .data_a_o(ram_row0),
        .data_b_o(ram_row1)
    );

    logic [WIDTH_P-1:0] conv_window [2:0][2:0];

    integer r;
    integer c;

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            for (r = 0; r < 3; r = r + 1) begin
                for (c = 0; c < 3; c = c + 1) begin
                    conv_window[r][c] <= '0;
                end
            end
        end else if (valid_i & ready_o) begin
            for (r = 0; r < 3; r = r + 1) begin
                conv_window[r][0] <= conv_window[r][1];
                conv_window[r][1] <= conv_window[r][2];
            end

            conv_window[0][2] <= ram_row0;
            conv_window[1][2] <= ram_row1;
            conv_window[2][2] <= data_i;
        end
    end

    logic [WIDTH_P+3:0] sum_all;
    logic [WIDTH_P+3:0] sum_pair;
    logic [WIDTH_P-1:0] blur_val;

    logic [WIDTH_P+2:0] sum_row0;
    logic [WIDTH_P+2:0] sum_row1;
    logic [WIDTH_P+2:0] sum_row2;

    assign sum_row0 =
        {1'b0, conv_window[0][0]} +
        ({1'b0, conv_window[0][1]} << 1) +
        {1'b0, conv_window[0][2]};

    assign sum_row1 =
        ({1'b0, conv_window[1][0]} << 1) +
        ({1'b0, conv_window[1][1]} << 2) +
        ({1'b0, conv_window[1][2]} << 1);

    assign sum_row2 =
        {1'b0, conv_window[2][0]} +
        ({1'b0, conv_window[2][1]} << 1) +
        {1'b0, conv_window[2][2]};

    assign sum_pair = sum_row0 + sum_row2;
    assign sum_all = sum_pair + sum_row1;

    assign blur_val = sum_all[WIDTH_P+3:4];

    logic [WIDTH_P-1:0] blur_pipe;

    elastic #(
        .WIDTH_P(WIDTH_P)
    ) blur_elastic (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(blur_val),
        .valid_i(box_valid),
        .ready_o(box_ready),
        .valid_o(valid_o),
        .data_o(blur_pipe),
        .ready_i(ready_i)
    );

    always_ff @(posedge clk_i) begin
        if (!rstn_i) begin
            gx_o <= '0;
            gy_o <= '0;
        end else if (valid_o & ready_i) begin
            gx_o <= {{WIDTH_P{1'b0}}, blur_pipe};
            gy_o <= {{WIDTH_P{1'b0}}, blur_pipe};
        end
    end

endmodule
