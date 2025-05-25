`timescale 1ns/1ps

// TRANSACTION one cycle of port stimulus with edge addresses weighted up
class Transaction #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 16
);
	rand logic [0:0] en;
	rand logic [$clog2(DEPTH_P)-1:0] addr;
	rand logic [WIDTH_P-1:0] data;

	constraint c_en { en dist { 1'b0 := 30, 1'b1 := 70}; }
	constraint c_addr { addr dist { 0 := 15, DEPTH_P-1 := 15, [1:DEPTH_P-2] :/ 70}; }
endclass

// GENERATOR randomizes a new transaction
class Generator #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 16
);
	function void randomize_trs(output Transaction #(WIDTH_P, DEPTH_P) tx);
		tx = new();
		assert (tx.randomize()) else $fatal(1, "transaction randomize failed");
	endfunction
endclass

// TEST ENVIRONMENT
module sync_ram_1r1w_test #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 16
);
	logic [0:0] wr_clk_i = 1'b0;
	logic [0:0] wr_rstn_i = 1'b0;
	logic [0:0] wr_en_i = 1'b0;
	logic [WIDTH_P-1:0] wr_data_i = '0;
	logic [$clog2(DEPTH_P)-1:0] wr_addr_i = '0;

	logic [0:0] rd_clk_i = 1'b0;
	logic [0:0] rd_rstn_i = 1'b0;
	logic [0:0] rd_en_i = 1'b0;
	logic [$clog2(DEPTH_P)-1:0] rd_addr_i = '0;
	logic [WIDTH_P-1:0] rd_data_o;

	logic [WIDTH_P-1:0] shadow_q [DEPTH_P];

	Generator #(WIDTH_P, DEPTH_P) gen = new();
	Transaction #(WIDTH_P, DEPTH_P) wr_trs;
	Transaction #(WIDTH_P, DEPTH_P) rd_trs;

	sync_ram_1r1w #(
		.WIDTH_P(WIDTH_P),
		.DEPTH_P(DEPTH_P),
		.filename_p("")
	) dut_inst (
		.wr_clk_i(wr_clk_i),
		.wr_rstn_i(wr_rstn_i),
		.wr_en_i(wr_en_i),
		.wr_data_i(wr_data_i),
		.wr_addr_i(wr_addr_i),
		.rd_clk_i(rd_clk_i),
		.rd_rstn_i(rd_rstn_i),
		.rd_en_i(rd_en_i),
		.rd_addr_i(rd_addr_i),
		.rd_data_o(rd_data_o)
	);

	always #5 wr_clk_i = ~wr_clk_i;
	always #7 rd_clk_i = ~rd_clk_i;

	// reference memory written on the same edge as the ram
	always_ff @(posedge wr_clk_i) begin
		if (wr_rstn_i && wr_en_i) shadow_q[wr_addr_i] <= wr_data_i;
	end

	// covergroups
	covergroup cg_write @(posedge wr_clk_i iff wr_rstn_i);
		cp_en: coverpoint wr_en_i;
		cp_addr: coverpoint wr_addr_i {
			bins first = {0};
			bins last = {DEPTH_P-1};
			bins mid = {[1:DEPTH_P-2]};
		}

		cp_en_addr_cross: cross cp_en, cp_addr;
	endgroup

	covergroup cg_read @(posedge rd_clk_i iff rd_rstn_i);
		cp_en: coverpoint rd_en_i;
		cp_addr: coverpoint rd_addr_i {
			bins first = {0};
			bins last = {DEPTH_P-1};
			bins mid = {[1:DEPTH_P-2]};
		}
		// read of the address the write port currently targets
		cp_collide: coverpoint (rd_en_i && wr_en_i && (rd_addr_i == wr_addr_i));

		cp_en_addr_cross: cross cp_en, cp_addr;
	endgroup

	cg_write write_cov = new();
	cg_read read_cov = new();

	// SVA
	// a read returns the memory contents at the read edge
	a_read: assert property (@(posedge rd_clk_i) disable iff (!rd_rstn_i)
		rd_en_i |=> rd_data_o == $past(shadow_q[rd_addr_i]))
	else $error("read: rd_data_o=%0h", rd_data_o);

	// output holds with read disabled
	a_hold: assert property (@(posedge rd_clk_i) disable iff (!rd_rstn_i)
		!rd_en_i |=> $stable(rd_data_o))
	else $error("hold: rd_data_o changed with rd_en low");

	// read reset clears the output
	a_reset: assert property (@(posedge rd_clk_i)
		!rd_rstn_i |=> rd_data_o == '0)
	else $error("reset: rd_data_o=%0h not cleared", rd_data_o);

	// back to back reads of 4 or more cycles
	c_read_burst: cover property (@(posedge rd_clk_i) disable iff (!rd_rstn_i)
		rd_en_i[*4:$] ##1 !rd_en_i);

	// a word written then read back within 1 to 3 read cycles
	property p_write_read;
		logic [$clog2(DEPTH_P)-1:0] addr_l;
		@(posedge wr_clk_i) disable iff (!wr_rstn_i)
		(wr_en_i, addr_l = wr_addr_i) ##[1:3] (rd_en_i && rd_addr_i == addr_l);
	endproperty

	c_write_read: cover property (p_write_read);

	// DIRECTED TESTS
	task test_write_all();
		$display("[TEST] Writing every address...");
		for (int unsigned i = 0; i < DEPTH_P; i++) begin
			@(negedge wr_clk_i);
			wr_en_i = 1'b1;
			wr_addr_i = ($clog2(DEPTH_P))'(i);
			wr_data_i = WIDTH_P'($urandom);
		end
		@(negedge wr_clk_i);
		wr_en_i = 1'b0;
	endtask

	task test_read_all();
		$display("[TEST] Reading every address back to back...");
		for (int unsigned i = 0; i < DEPTH_P; i++) begin
			@(negedge rd_clk_i);
			rd_en_i = 1'b1;
			rd_addr_i = ($clog2(DEPTH_P))'(i);
		end
	endtask

	task test_hold();
		$display("[TEST] Testing hold with read disabled...");
		@(negedge rd_clk_i);
		rd_en_i = 1'b0;
		repeat (4) begin
			@(negedge rd_clk_i);
			rd_addr_i = ($clog2(DEPTH_P))'($urandom);
		end
	endtask

	task test_write_during_reset();
		$display("[TEST] Testing writes blocked during write reset...");
		@(negedge wr_clk_i);
		wr_rstn_i = 1'b0;
		wr_en_i = 1'b1;
		wr_addr_i = '0;
		wr_data_i = ~shadow_q[0];
		@(negedge wr_clk_i);
		wr_en_i = 1'b0;
		wr_rstn_i = 1'b1;
		@(negedge rd_clk_i);
		rd_en_i = 1'b1;
		rd_addr_i = '0;
		@(negedge rd_clk_i);
		rd_en_i = 1'b0;
	endtask

	task test_read_reset();
		$display("[TEST] Testing read reset during idle...");
		@(negedge rd_clk_i);
		rd_rstn_i = 1'b0;
		@(negedge rd_clk_i);
		rd_rstn_i = 1'b1;
		repeat (2) @(negedge rd_clk_i);
	endtask

	task run_random(input int unsigned cycles);
		$display("[TEST] Testing random writes and reads on both clocks for %0d cycles...", cycles);
		fork
			repeat (cycles) begin
				@(negedge wr_clk_i);
				gen.randomize_trs(wr_trs);
				wr_en_i = wr_trs.en;
				wr_addr_i = wr_trs.addr;
				wr_data_i = wr_trs.data;
			end
			repeat (cycles) begin
				@(negedge rd_clk_i);
				gen.randomize_trs(rd_trs);
				rd_en_i = rd_trs.en;
				rd_addr_i = rd_trs.addr;
			end
		join
		@(negedge wr_clk_i);
		wr_en_i = 1'b0;
		@(negedge rd_clk_i);
		rd_en_i = 1'b0;
	endtask

	initial begin
		repeat (2) @(negedge wr_clk_i);
		wr_rstn_i = 1'b1;
		repeat (2) @(negedge rd_clk_i);
		rd_rstn_i = 1'b1;

		test_write_all();
		test_read_all();
		test_hold();
		test_write_during_reset();
		test_read_reset();
		run_random(2000);
		repeat (2) @(negedge rd_clk_i);

		$display("--------------------------------------");
		$display("[TEST] Write coverage: %0.2f%%", write_cov.get_coverage());
		$display("[TEST] Read coverage: %0.2f%%", read_cov.get_coverage());
		$display("[TEST] Overall coverage: %0.2f%%", $get_coverage());
		$display("--------------------------------------");
		$finish;
	end
endmodule
