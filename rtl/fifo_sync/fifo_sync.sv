`timescale 1ns/1ps

module fifo_sync #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 16
) (
	input  logic [0:0] clk_i,
	input  logic [0:0] rstn_i,

	// input stream
	input  logic [WIDTH_P-1:0] data_i,
	input  logic [0:0] valid_i,
	output logic [0:0] ready_o,

	// output stream
	output logic [WIDTH_P-1:0] data_o,
	output logic [0:0] valid_o,
	input  logic [0:0] ready_i
);

	logic [$clog2(DEPTH_P):0] wr_ptr_q;
	logic [$clog2(DEPTH_P):0] rd_ptr_q;
	logic [$clog2(DEPTH_P):0] rd_ptr_next_l;
	logic [WIDTH_P-1:0] ram_data_l;
	logic [WIDTH_P-1:0] bypass_data_q;
	logic [0:0] bypass_q;
	logic [0:0] wr_en_l;
	logic [0:0] rd_en_l;

	assign wr_en_l = valid_i && ready_o;
	assign rd_en_l = valid_o && ready_i;

	// full and empty
	assign ready_o = !((wr_ptr_q[$clog2(DEPTH_P)] != rd_ptr_q[$clog2(DEPTH_P)]) && (wr_ptr_q[$clog2(DEPTH_P)-1:0] == rd_ptr_q[$clog2(DEPTH_P)-1:0]));
	assign valid_o = (wr_ptr_q != rd_ptr_q);

	// first word fall through
	assign data_o = bypass_q ? bypass_data_q : ram_data_l;

	// ram reads the next head every cycle so data_o is ready one cycle ahead
	sync_ram_1r1w #(
		.WIDTH_P(WIDTH_P),
		.DEPTH_P(DEPTH_P)
	) ram_inst (
		.wr_clk_i(clk_i),
		.wr_rstn_i(rstn_i),
		.wr_en_i(wr_en_l),
		.wr_data_i(data_i),
		.wr_addr_i(wr_ptr_q[$clog2(DEPTH_P)-1:0]),
		.rd_clk_i(clk_i),
		.rd_rstn_i(rstn_i),
		.rd_en_i(1'b1),
		.rd_addr_i(rd_ptr_next_l[$clog2(DEPTH_P)-1:0]),
		.rd_data_o(ram_data_l)
	);

	// next read pointer
	always_comb begin
		rd_ptr_next_l = rd_ptr_q;
		if (rd_en_l) begin
			rd_ptr_next_l = rd_ptr_q + 1'b1;
		end
	end

	// write pointer
	always_ff @(posedge clk_i) begin
		if (!rstn_i) begin
			wr_ptr_q <= '0;
		end else if (wr_en_l) begin
			wr_ptr_q <= wr_ptr_q + 1'b1;
		end
	end

	// read pointer
	always_ff @(posedge clk_i) begin
		if (!rstn_i) begin
			rd_ptr_q <= '0;
		end else begin
			rd_ptr_q <= rd_ptr_next_l;
		end
	end

	// a write to the address being read returns stale ram data so bypass it
	always_ff @(posedge clk_i) begin
		if (!rstn_i) begin
			bypass_q <= 1'b0;
			bypass_data_q <= '0;
		end else begin
			bypass_q <= wr_en_l && (wr_ptr_q == rd_ptr_next_l);
			if (wr_en_l) begin
				bypass_data_q <= data_i;
			end
		end
	end

endmodule
