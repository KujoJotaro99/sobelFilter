`timescale 1ns/1ps

module sobel #(
	parameter WIDTH_P = 8,
	parameter LINE_W_P = 640
) (
	input  logic [0:0] clk_i,
	input  logic [0:0] rstn_i,

	// input stream
	input  logic [WIDTH_P-1:0] red_i,
	input  logic [WIDTH_P-1:0] green_i,
	input  logic [WIDTH_P-1:0] blue_i,
	input  logic [0:0] valid_i,
	output logic [0:0] ready_o,

	// output stream
	output logic [WIDTH_P-1:0] mag_o,
	output logic [0:0] valid_o,
	input  logic [0:0] ready_i
);

	logic [0:0] gray_valid;
	logic [0:0] gray_ready;
	logic [WIDTH_P-1:0] gray_data;

	logic [0:0] box1_valid;
	logic [0:0] box1_ready;
	logic signed [(2*WIDTH_P)-1:0] box1_gx;
	logic signed [(2*WIDTH_P)-1:0] box1_gy;

	logic [0:0] conv_valid;
	logic [0:0] conv_ready;
	logic signed [(2*WIDTH_P)-1:0] conv_gx;
	logic signed [(2*WIDTH_P)-1:0] conv_gy;

	logic [0:0] grad_valid;
	logic [0:0] grad_ready;
	logic signed [(2*WIDTH_P)-1:0] grad_gx;
	logic signed [(2*WIDTH_P)-1:0] grad_gy;

	logic [WIDTH_P-1:0] gx_abs;
	logic [WIDTH_P-1:0] gy_abs;

	// absolute gradient
	assign gx_abs = grad_gx[2*WIDTH_P-1] ? -grad_gx : grad_gx;
	assign gy_abs = grad_gy[2*WIDTH_P-1] ? -grad_gy : grad_gy;

	// grayscale
	rgb2gray #(
		.WIDTH_P(WIDTH_P)
	) rgb2gray_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(valid_i),
		.ready_i(gray_ready),
		.valid_o(gray_valid),
		.ready_o(ready_o),
		.red_i(red_i),
		.blue_i(blue_i),
		.green_i(green_i),
		.gray_o(gray_data)
	);

	// gaussian blur
	conv2d_box #(
		.WIDTH_P(WIDTH_P),
		.DEPTH_P(LINE_W_P)
	) sobel_box_1 (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(gray_valid),
		.ready_i(box1_ready),
		.data_i(gray_data),
		.valid_o(box1_valid),
		.ready_o(gray_ready),
		.gx_o(box1_gx),
		.gy_o(box1_gy)
	);

	// sobel gradients
	conv2d #(
		.WIDTH_P(WIDTH_P),
		.DEPTH_P(LINE_W_P)
	) sobel_conv2d (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(box1_valid),
		.ready_i(conv_ready),
		.data_i(box1_gx[WIDTH_P-1:0]),
		.valid_o(conv_valid),
		.ready_o(box1_ready),
		.gx_o(conv_gx),
		.gy_o(conv_gy)
	);

	// register the gradients to split the sobel sum from the magnitude add
	elastic #(
		.WIDTH_P(4*WIDTH_P)
	) grad_pipe_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.data_i({conv_gx, conv_gy}),
		.valid_i(conv_valid),
		.ready_o(conv_ready),
		.valid_o(grad_valid),
		.data_o({grad_gx, grad_gy}),
		.ready_i(grad_ready)
	);

	// gradient magnitude
	magnitude #(
		.WIDTH_P(WIDTH_P)
	) magnitude_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(grad_valid),
		.ready_i(ready_i),
		.gx_i(gx_abs),
		.gy_i(gy_abs),
		.valid_o(valid_o),
		.ready_o(grad_ready),
		.mag_o(mag_o)
	);

endmodule
