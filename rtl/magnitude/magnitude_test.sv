`timescale 1ns/1ps

// TRANSACTION one cycle of gradient stimulus with corner values weighted up
class Transaction #(
	parameter WIDTH_P = 8
);
	rand logic [WIDTH_P-1:0] gx_i;
	rand logic [WIDTH_P-1:0] gy_i;
	rand logic [0:0] valid_i;
	rand logic [0:0] ready_i;

	constraint c_gx { gx_i dist { '0 := 10, {WIDTH_P{1'b1}} := 10, [1:(1 << WIDTH_P) - 2] :/ 80}; }
	constraint c_gy { gy_i dist { '0 := 10, {WIDTH_P{1'b1}} := 10, [1:(1 << WIDTH_P) - 2] :/ 80}; }
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

// MODEL saturating sum of the two gradients
class Model #(
	parameter WIDTH_P = 8
);
	static function logic [WIDTH_P-1:0] mag(logic [WIDTH_P-1:0] gx, logic [WIDTH_P-1:0] gy);
		logic [WIDTH_P:0] sum_l;
		sum_l = {1'b0, gx} + {1'b0, gy};
		return sum_l[WIDTH_P] ? {WIDTH_P{1'b1}} : sum_l[WIDTH_P-1:0];
	endfunction
endclass

// SCOREBOARD expected magnitudes in order of acceptance
class Scoreboard #(
	parameter WIDTH_P = 8
);
	logic [WIDTH_P-1:0] exp_q [$];
	int success_count;
	int error_count;

	function void reset();
		exp_q.delete();
	endfunction

	function void check_write(logic [0:0] valid_i, logic [0:0] ready_o, logic [WIDTH_P-1:0] gx_i, logic [WIDTH_P-1:0] gy_i);
		if (valid_i && ready_o) begin
			exp_q.push_back(Model#(WIDTH_P)::mag(gx_i, gy_i));
		end
	endfunction

	function void check_read(logic [0:0] valid_o, logic [0:0] ready_i, logic [WIDTH_P-1:0] mag_o);
		logic [WIDTH_P-1:0] expected;
		if (valid_o && ready_i) begin
			if (exp_q.size() == 0) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h with nothing expected", mag_o);
				return;
			end
			expected = exp_q.pop_front();
			if (mag_o !== expected) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h, expected %h", mag_o, expected);
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
module magnitude_test #(
	parameter WIDTH_P = 8
);
	logic [0:0] clk_i = 1'b0;
	logic [0:0] rstn_i = 1'b0;
	logic [0:0] valid_i = 1'b0;
	logic [0:0] ready_i = 1'b0;
	logic [WIDTH_P-1:0] gx_i = '0;
	logic [WIDTH_P-1:0] gy_i = '0;
	logic [0:0] valid_o;
	logic [0:0] ready_o;
	logic [WIDTH_P-1:0] mag_o;

	Generator #(WIDTH_P) gen = new();
	Scoreboard #(WIDTH_P) scb = new();
	Transaction #(WIDTH_P) trs;

	magnitude #(
		.WIDTH_P(WIDTH_P)
	) dut_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(valid_i),
		.ready_i(ready_i),
		.gx_i(gx_i),
		.gy_i(gy_i),
		.valid_o(valid_o),
		.ready_o(ready_o),
		.mag_o(mag_o)
	);

	// covergroups
	covergroup cg_inputs @(posedge clk_i iff (rstn_i && valid_i && ready_o));
		cp_gx: coverpoint gx_i {
			bins zero = {0};
			bins max = {(1 << WIDTH_P) - 1};
			bins mid = {[1:(1 << WIDTH_P) - 2]};
		}
		cp_gy: coverpoint gy_i {
			bins zero = {0};
			bins max = {(1 << WIDTH_P) - 1};
			bins mid = {[1:(1 << WIDTH_P) - 2]};
		}
		cp_saturate: coverpoint ({1'b0, gx_i} + {1'b0, gy_i} > (1 << WIDTH_P) - 1) {
			bins pass = {0};
			bins clip = {1};
		}

		cp_gx_gy_cross: cross cp_gx, cp_gy;
	endgroup

	covergroup cg_handshake @(posedge clk_i iff rstn_i);
		cp_write: coverpoint (valid_i && ready_o);
		cp_read: coverpoint (valid_o && ready_i);

		cp_write_read_cross: cross cp_write, cp_read;
	endgroup

	cg_inputs inputs_cov = new();
	cg_handshake handshake_cov = new();

	// SVA
	// an accepted pair produces its saturated sum on the next cycle
	property p_latency;
		logic [WIDTH_P-1:0] exp_l;
		@(posedge clk_i) disable iff (!rstn_i)
		(valid_i && ready_o, exp_l = Model#(WIDTH_P)::mag(gx_i, gy_i)) |=> (valid_o && mag_o == exp_l);
	endproperty

	a_latency: assert property (p_latency)
	else $error("magnitude wrong or late, got %h", mag_o);

	// a stalled output holds valid and data
	a_hold: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i) |=> (valid_o && $stable(mag_o)))
	else $error("output changed while stalled");

	// reset clears valid
	a_reset: assert property (@(posedge clk_i)
		!rstn_i |=> !valid_o)
	else $error("valid_o set after reset");

	// saturation reached under a stall
	c_clip_stall: cover property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i && mag_o == {WIDTH_P{1'b1}})[*2]);

	always #5 clk_i = ~clk_i;

	// monitor
	always @(posedge clk_i) begin
		if (rstn_i) begin
			scb.check_read(valid_o, ready_i, mag_o);
			scb.check_write(valid_i, ready_o, gx_i, gy_i);
		end else begin
			scb.reset();
		end
	end

	// DIRECTED TESTS
	task reset_seq();
		$display("[TEST] Testing reset behavior...");
		rstn_i = 1'b0;
		repeat (4) @(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	task send(input logic [WIDTH_P-1:0] gx, input logic [WIDTH_P-1:0] gy);
		@(negedge clk_i);
		valid_i = 1'b1;
		ready_i = 1'b1;
		gx_i = gx;
		gy_i = gy;
	endtask

	task test_corners();
		$display("[TEST] Testing corner values...");
		send('0, '0);
		send('0, {WIDTH_P{1'b1}});
		send({WIDTH_P{1'b1}}, '0);
		send({WIDTH_P{1'b1}}, {WIDTH_P{1'b1}});
		// sum exactly at the maximum
		send(WIDTH_P'(1 << (WIDTH_P - 1)), WIDTH_P'((1 << (WIDTH_P - 1)) - 1));
		// sum one past the maximum
		send(WIDTH_P'(1 << (WIDTH_P - 1)), WIDTH_P'(1 << (WIDTH_P - 1)));
		@(negedge clk_i);
		valid_i = 1'b0;
		@(negedge clk_i);
	endtask

	task run_random_stream(input int unsigned cycles);
		$display("[TEST] Testing random stream for %0d cycles...", cycles);
		repeat (cycles) begin
			@(negedge clk_i);
			gen.randomize_trs(trs);
			gx_i = trs.gx_i;
			gy_i = trs.gy_i;
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
			$display("[TEST] MISMATCH: %0d results never left the stage", scb.exp_q.size());
		end
	endtask

	initial begin
		reset_seq();
		test_corners();
		run_random_stream(2000);
		drain();
		scb.report();

		$display("--------------------------------------");
		$display("[TEST] Input coverage: %0.2f%%", inputs_cov.get_coverage());
		$display("[TEST] Handshake coverage: %0.2f%%", handshake_cov.get_coverage());
		$display("[TEST] Overall coverage: %0.2f%%", $get_coverage());
		$display("--------------------------------------");
		$finish;
	end
endmodule
