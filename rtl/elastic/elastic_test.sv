`timescale 1ns/1ps

// TRANSACTION one cycle of stream stimulus
class Transaction #(
	parameter WIDTH_P = 8
);
	rand logic [WIDTH_P-1:0] data_i;
	rand logic [0:0] valid_i;
	rand logic [0:0] ready_i;

	constraint c_valid { valid_i dist { 1'b0 := 30, 1'b1 := 70}; }
	constraint c_ready { ready_i dist { 1'b0 := 30, 1'b1 := 70}; }
endclass

// GENERATOR randomizes a new transaction
class Generator #(
	parameter WIDTH_P = 8
);
	function void randomize_trs(output Transaction #(WIDTH_P) tx);
		tx = new();
		assert (tx.randomize()) else $fatal(1, "transaction randomize failed");
	endfunction
endclass

// SCOREBOARD accepted words in order, compared on each output transfer
class Scoreboard #(
	parameter WIDTH_P = 8
);
	logic [WIDTH_P-1:0] exp_q [$];
	int success_count;
	int error_count;

	function void reset();
		exp_q.delete();
	endfunction

	function void check_write(logic [0:0] valid_i, logic [0:0] ready_o, logic [WIDTH_P-1:0] data_i);
		if (valid_i && ready_o) begin
			exp_q.push_back(data_i);
		end
	endfunction

	function void check_read(logic [0:0] valid_o, logic [0:0] ready_i, logic [WIDTH_P-1:0] data_o);
		logic [WIDTH_P-1:0] expected;
		if (valid_o && ready_i) begin
			if (exp_q.size() == 0) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h with nothing expected", data_o);
				return;
			end
			expected = exp_q.pop_front();
			if (data_o !== expected) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h, expected %h", data_o, expected);
			end else begin
				success_count++;
			end
		end
	endfunction

	function void report();
		$display("-------------------------");
		$display("[TEST] MATCH: %0d", success_count);
		$display("[TEST] MISMATCH: %0d", error_count);
		$display("-------------------------");
	endfunction
endclass

// TEST ENVIRONMENT
module elastic_test #(
	parameter WIDTH_P = 8
);
	logic [0:0] clk_i = 1'b0;
	logic [0:0] rstn_i = 1'b0;
	logic [WIDTH_P-1:0] data_i = '0;
	logic [0:0] valid_i = 1'b0;
	logic [0:0] ready_o;
	logic [0:0] valid_o;
	logic [WIDTH_P-1:0] data_o;
	logic [0:0] ready_i = 1'b0;

	Generator #(WIDTH_P) gen = new();
	Scoreboard #(WIDTH_P) scb = new();
	Transaction #(WIDTH_P) trs;

	elastic #(
		.WIDTH_P(WIDTH_P)
	) dut_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.data_i(data_i),
		.valid_i(valid_i),
		.ready_o(ready_o),
		.valid_o(valid_o),
		.data_o(data_o),
		.ready_i(ready_i)
	);

	// covergroups
	covergroup cg_handshake @(posedge clk_i iff rstn_i);
		cp_write: coverpoint (valid_i && ready_o);
		cp_read: coverpoint (valid_o && ready_i);
		cp_stall: coverpoint (valid_o && !ready_i);

		cp_write_read_cross: cross cp_write, cp_read;
	endgroup

	covergroup cg_sequences @(posedge clk_i iff rstn_i);
		// back to back transfers through the stage
		cp_full_rate: coverpoint (valid_i && ready_o && valid_o && ready_i) {
			bins run = (1[*4:8]);
		}
		// stall then release
		cp_stall_release: coverpoint (valid_o && !ready_i) {
			bins short_stall = (1[*1:2] => 0);
			bins long_stall = (1[*3:6] => 0);
		}
	endgroup

	cg_handshake handshake_cov = new();
	cg_sequences sequences_cov = new();

	// SVA
	// ready follows the elastic rule
	a_ready: assert property (@(posedge clk_i) disable iff (!rstn_i)
		ready_o == (!valid_o || ready_i))
	else $error("ready_o=%b with valid_o=%b ready_i=%b", ready_o, valid_o, ready_i);

	// an accepted word is presented on the next cycle
	property p_latency;
		logic [WIDTH_P-1:0] data_l;
		@(posedge clk_i) disable iff (!rstn_i)
		(valid_i && ready_o, data_l = data_i) |=> (valid_o && data_o == data_l);
	endproperty

	a_latency: assert property (p_latency)
	else $error("accepted word not presented on the next cycle");

	// a stalled output holds valid and data
	a_hold: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i) |=> (valid_o && $stable(data_o)))
	else $error("output changed while stalled");

	// reset clears valid
	a_reset: assert property (@(posedge clk_i)
		!rstn_i |=> !valid_o)
	else $error("valid_o set after reset");

	// stall of 3 cycles released into a transfer
	c_backpressure: cover property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i)[*3] ##1 (valid_o && ready_i));

	always #5 clk_i = ~clk_i;

	// monitor
	always @(posedge clk_i) begin
		if (rstn_i) begin
			scb.check_read(valid_o, ready_i, data_o);
			scb.check_write(valid_i, ready_o, data_i);
		end else begin
			scb.reset();
		end
	end

	// DIRECTED TESTS
	task reset_seq();
		$display("[TEST] Testing reset behavior...");
		rstn_i = 1'b0;
		valid_i = 1'b0;
		ready_i = 1'b0;
		repeat (4) @(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	task test_full_rate();
		$display("[TEST] Testing back to back transfers...");
		ready_i = 1'b1;
		repeat (16) begin
			@(negedge clk_i);
			valid_i = 1'b1;
			data_i = WIDTH_P'($urandom);
		end
		@(negedge clk_i);
		valid_i = 1'b0;
		@(negedge clk_i);
	endtask

	task test_backpressure();
		$display("[TEST] Testing backpressure...");
		@(negedge clk_i);
		valid_i = 1'b1;
		data_i = WIDTH_P'($urandom);
		ready_i = 1'b0;
		@(negedge clk_i);
		data_i = WIDTH_P'($urandom);
		repeat (4) @(negedge clk_i);
		ready_i = 1'b1;
		repeat (2) @(negedge clk_i);
		valid_i = 1'b0;
		@(negedge clk_i);
	endtask

	task test_reset_with_data();
		$display("[TEST] Testing reset while the stage holds data...");
		@(negedge clk_i);
		valid_i = 1'b1;
		ready_i = 1'b0;
		data_i = WIDTH_P'($urandom);
		@(negedge clk_i);
		valid_i = 1'b0;
		rstn_i = 1'b0;
		repeat (2) @(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	task run_random_stream(input int unsigned cycles);
		$display("[TEST] Testing random stream for %0d cycles...", cycles);
		repeat (cycles) begin
			@(negedge clk_i);
			gen.randomize_trs(trs);
			data_i = trs.data_i;
			valid_i = trs.valid_i;
			ready_i = trs.ready_i;
		end
	endtask

	task drain();
		@(negedge clk_i);
		valid_i = 1'b0;
		ready_i = 1'b1;
		repeat (4) @(negedge clk_i);
		if (scb.exp_q.size() != 0) begin
			scb.error_count++;
			$display("[TEST] MISMATCH: %0d words never left the stage", scb.exp_q.size());
		end
	endtask

	initial begin
		reset_seq();
		test_full_rate();
		test_backpressure();
		test_reset_with_data();
		run_random_stream(2000);
		drain();
		scb.report();

		$display("--------------------------------------");
		$display("[TEST] Handshake coverage: %0.2f%%", handshake_cov.get_coverage());
		$display("[TEST] Sequence coverage: %0.2f%%", sequences_cov.get_coverage());
		$display("[TEST] Overall coverage: %0.2f%%", $get_coverage());
		$display("--------------------------------------");
		$finish;
	end
endmodule
