`timescale 1ns/1ps
module conv2d 
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
    logic [WIDTH_P-1:0] ram_row0, ram_row1;
    logic [0:0] line_valid;
    logic [0:0] sobel_ready;

    ramdelaybuffer #(
        .WIDTH_P(WIDTH_P),
        .DELAY_P(2*DEPTH_P-1),
        .DELAY_A_P(2*DEPTH_P-1),
        .DELAY_B_P(DEPTH_P-1)
    ) line_buffer (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(valid_i),
        .ready_i(sobel_ready),
        .valid_o(line_valid),
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

    logic signed [WIDTH_P:0] dx0, dx1, dx2, dy0, dy1, dy2;
    logic signed [WIDTH_P:0] dx0_pipe, dx1_pipe, dx2_pipe;
    logic signed [WIDTH_P:0] dy0_pipe, dy1_pipe, dy2_pipe;
    logic signed [WIDTH_P+1:0] gx_sum0, gy_sum0;
    logic signed [WIDTH_P+2:0] gx_comb, gy_comb;

    assign dx0 = $signed({1'b0, conv_window[0][2]}) - $signed({1'b0, conv_window[0][0]});
    assign dx1 = $signed({1'b0, conv_window[1][2]}) - $signed({1'b0, conv_window[1][0]});
    assign dx2 = $signed({1'b0, conv_window[2][2]}) - $signed({1'b0, conv_window[2][0]});
    assign dy0 = $signed({1'b0, conv_window[2][0]}) - $signed({1'b0, conv_window[0][0]});
    assign dy1 = $signed({1'b0, conv_window[2][1]}) - $signed({1'b0, conv_window[0][1]});
    assign dy2 = $signed({1'b0, conv_window[2][2]}) - $signed({1'b0, conv_window[0][2]});

    elastic #(
        .WIDTH_P(6*(WIDTH_P+1))
    ) sobel_pipe (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i({dx0, dx1, dx2, dy0, dy1, dy2}),
        .valid_i(line_valid),
        .ready_o(sobel_ready),
        .valid_o(valid_o),
        .data_o({dx0_pipe, dx1_pipe, dx2_pipe, dy0_pipe, dy1_pipe, dy2_pipe}),
        .ready_i(ready_i)
    );

    assign gx_sum0 = dx0_pipe + dx2_pipe;
    assign gy_sum0 = dy0_pipe + dy2_pipe;
    assign gx_comb = gx_sum0 + (dx1_pipe <<< 1);
    assign gy_comb = gy_sum0 + (dy1_pipe <<< 1);
    assign gx_o = {{(2*WIDTH_P-(WIDTH_P+3)){gx_comb[WIDTH_P+2]}}, gx_comb};
    assign gy_o = {{(2*WIDTH_P-(WIDTH_P+3)){gy_comb[WIDTH_P+2]}}, gy_comb};

endmodule