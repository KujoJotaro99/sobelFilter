`timescale 1ns/1ps

module sync_ram_1r1w #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 512,
	parameter filename_p = ""
) (
	// write port
	input  logic [0:0] wr_clk_i,
	input  logic [0:0] wr_rstn_i,
	input  logic [0:0] wr_en_i,
	input  logic [WIDTH_P-1:0] wr_data_i,
	input  logic [$clog2(DEPTH_P)-1:0] wr_addr_i,

	// read port
	input  logic [0:0] rd_clk_i,
	input  logic [0:0] rd_rstn_i,
	input  logic [0:0] rd_en_i,
	input  logic [$clog2(DEPTH_P)-1:0] rd_addr_i,
	output logic [WIDTH_P-1:0] rd_data_o
);

	logic [WIDTH_P-1:0] mem_array [DEPTH_P-1:0];

	// write
	always_ff @(posedge wr_clk_i) begin
		if (wr_rstn_i && wr_en_i) begin
			mem_array[wr_addr_i] <= wr_data_i;
		end
	end

	// registered read
	always_ff @(posedge rd_clk_i) begin
		if (!rd_rstn_i) begin
			rd_data_o <= '0;
		end else if (rd_en_i) begin
			rd_data_o <= mem_array[rd_addr_i];
		end
	end

endmodule
