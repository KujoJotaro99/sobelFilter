`timescale 1ns/1ps

module sync2 #(
	parameter WIDTH_P = 8
) (
	input  logic [0:0] clk_sync_i,
	input  logic [0:0] rstn_i,
	input  logic [WIDTH_P-1:0] sync_i,
	output logic [WIDTH_P-1:0] sync_o
);

	// this is a vivado attribute but it will be ignored for other synthesis/pnr tools
	(* ASYNC_REG = "TRUE" *) logic [WIDTH_P-1:0] sync_q1;
	(* ASYNC_REG = "TRUE" *) logic [WIDTH_P-1:0] sync_q2;

	assign sync_o = sync_q2;

	always_ff @(posedge clk_sync_i) begin
		if (!rstn_i) begin
			sync_q1 <= '0;
			sync_q2 <= '0;
		end else begin
			sync_q1 <= sync_i;
			sync_q2 <= sync_q1;
		end
	end
endmodule
