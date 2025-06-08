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

// MODEL history of accepted words, each tap reads the word accepted DELAY taps earlier
class Model #(
	parameter WIDTH_P = 8,
	parameter DELAY_P = 12
);
	logic [WIDTH_P-1:0] hist_q [$];

	function void reset();
		hist_q.delete();
	endfunction

	function void push(logic [WIDTH_P-1:0] data);
		hist_q.push_back(data);
		if (hist_q.size() > DELAY_P + 1) begin
			void'(hist_q.pop_front());
		end
	endfunction

	// the word accepted delay transfers before the newest one
	function logic [0:0] known(int unsigned delay);
		return hist_q.size() > delay;
	endfunction

	function logic [WIDTH_P-1:0] tap(int unsigned delay);
		return hist_q[hist_q.size() - 1 - delay];
	endfunction
endclass

// SCOREBOARD expected tap pair per accepted word, compared on each output transfer
class Scoreboard #(
	parameter WIDTH_P = 8,
	parameter DELAY_P = 12,
	parameter DELAY_A_P = 11,
	parameter DELAY_B_P = 5
);
	typedef struct {
		logic [0:0] known_a;
		logic [WIDTH_P-1:0] data_a;
		logic [0:0] known_b;
		logic [WIDTH_P-1:0] data_b;
	} expect_t;

	Model #(WIDTH_P, DELAY_P) model;
	expect_t exp_q [$];
	int success_count;
	int error_count;

	function new();
		model = new();
	endfunction

	function void reset();
		model.reset();
		exp_q.delete();
	endfunction

	function void check_write(logic [0:0] valid_i, logic [0:0] ready_o, logic [WIDTH_P-1:0] data_i);
		expect_t exp_l;
		if (valid_i && ready_o) begin
			model.push(data_i);
			exp_l.known_a = model.known(DELAY_A_P);
			exp_l.data_a = exp_l.known_a ? model.tap(DELAY_A_P) : '0;
			exp_l.known_b = model.known(DELAY_B_P);
			exp_l.data_b = exp_l.known_b ? model.tap(DELAY_B_P) : '0;
			exp_q.push_back(exp_l);
		end
	endfunction

	function void check_read(logic [0:0] valid_o, logic [0:0] ready_i, logic [WIDTH_P-1:0] data_a_o, logic [WIDTH_P-1:0] data_b_o);
		expect_t exp_l;
		if (valid_o && ready_i) begin
			if (exp_q.size() == 0) begin
				error_count++;
				$display("[TEST] MISMATCH: output transfer with nothing expected");
				return;
			end
			exp_l = exp_q.pop_front();
			compare("a", exp_l.known_a, data_a_o, exp_l.data_a);
			compare("b", exp_l.known_b, data_b_o, exp_l.data_b);
		end
	endfunction

	function void compare(string tap, logic [0:0] known, logic [WIDTH_P-1:0] got, logic [WIDTH_P-1:0] expected);
		if (!known) begin
			return;
		end
		if (got !== expected) begin
			error_count++;
			$display("[TEST] MISMATCH: tap %s got %h, expected %h", tap, got, expected);
		end else begin
			success_count++;
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
module ramdelaybuffer_test #(
	parameter WIDTH_P = 8,
	parameter DELAY_P = 11,
	parameter DELAY_A_P = 11,
	parameter DELAY_B_P = 5
);
	logic [0:0] clk_i = 1'b0;
	logic [0:0] rstn_i = 1'b0;
	logic [0:0] valid_i = 1'b0;
	logic [0:0] ready_i = 1'b0;
	logic [0:0] valid_o;
	logic [0:0] ready_o;
	logic [WIDTH_P-1:0] data_i = '0;
	logic [WIDTH_P-1:0] data_a_o;
	logic [WIDTH_P-1:0] data_b_o;

	Generator #(WIDTH_P) gen = new();
	Scoreboard #(WIDTH_P, DELAY_P, DELAY_A_P, DELAY_B_P) scb = new();
	Transaction #(WIDTH_P) trs;

	ramdelaybuffer #(
		.WIDTH_P(WIDTH_P),
		.DELAY_P(DELAY_P),
		.DELAY_A_P(DELAY_A_P),
		.DELAY_B_P(DELAY_B_P)
	) dut_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(valid_i),
		.ready_i(ready_i),
		.valid_o(valid_o),
		.ready_o(ready_o),
		.data_i(data_i),
		.data_a_o(data_a_o),
		.data_b_o(data_b_o)
	);

	// covergroups
	covergroup cg_handshake @(posedge clk_i iff rstn_i);
		cp_write: coverpoint (valid_i && ready_o);
		cp_read: coverpoint (valid_o && ready_i);
		cp_stall: coverpoint (valid_o && !ready_i);

		cp_write_read_cross: cross cp_write, cp_read;
	endgroup

	covergroup cg_pointers @(posedge clk_i iff (rstn_i && valid_i && ready_o));
		cp_wr_addr: coverpoint dut_inst.wr_addr {
			bins low = {0};
			bins high = {DELAY_P};
			bins mid = {[1:DELAY_P-1]};
			bins wrap = (DELAY_P => 0);
		}
		cp_rd_addr_a: coverpoint dut_inst.rd_addr_a {
			bins wrap = (DELAY_P => 0);
		}
		cp_rd_addr_b: coverpoint dut_inst.rd_addr_b {
			bins wrap = (DELAY_P => 0);
		}
	endgroup

	cg_handshake handshake_cov = new();
	cg_pointers pointers_cov = new();

	// SVA
	// ready follows the output stage
	a_ready: assert property (@(posedge clk_i) disable iff (!rstn_i)
		ready_o == (!valid_o || ready_i))
	else $error("ready_o=%b with valid_o=%b ready_i=%b", ready_o, valid_o, ready_i);

	// a stalled output holds valid and both taps
	a_hold: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i) |=> (valid_o && $stable(data_a_o) && $stable(data_b_o)))
	else $error("output changed while stalled");

	// tap a and tap b keep a fixed address distance
	a_tap_spacing: assert property (@(posedge clk_i) disable iff (!rstn_i)
		((dut_inst.rd_addr_b + (DELAY_P + 1) - dut_inst.rd_addr_a) % (DELAY_P + 1)) == (DELAY_A_P - DELAY_B_P))
	else $error("read taps lost their spacing");

	// write pointer leads tap a by its delay
	a_tap_a_delay: assert property (@(posedge clk_i) disable iff (!rstn_i)
		((dut_inst.wr_addr + (DELAY_P + 1) - dut_inst.rd_addr_a) % (DELAY_P + 1)) == DELAY_A_P)
	else $error("tap a lost its delay");

	// reset clears valid
	a_reset: assert property (@(posedge clk_i)
		!rstn_i |=> !valid_o)
	else $error("valid_o set after reset");

	// the write pointer wraps at least twice
	c_two_wraps: cover property (@(posedge clk_i) disable iff (!rstn_i)
		(dut_inst.wr_addr == DELAY_P) ##[1:$] (dut_inst.wr_addr == 0) ##[1:$] (dut_inst.wr_addr == DELAY_P) ##[1:$] (dut_inst.wr_addr == 0));

	always #5 clk_i = ~clk_i;

	// monitor
	always @(posedge clk_i) begin
		if (rstn_i) begin
			scb.check_read(valid_o, ready_i, data_a_o, data_b_o);
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
		ready_i = 1'b1;
		repeat (4) @(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	task test_idle_after_reset();
		$display("[TEST] Testing idle output after reset...");
		repeat (10) begin
			@(negedge clk_i);
			if (valid_o) begin
				scb.error_count++;
				$display("[TEST] MISMATCH: valid_o high with no input");
			end
		end
	endtask

	task test_full_rate();
		$display("[TEST] Testing a full rate stream over several wraps...");
		ready_i = 1'b1;
		repeat (4 * (DELAY_P + 1)) begin
			@(negedge clk_i);
			valid_i = 1'b1;
			data_i = WIDTH_P'($urandom);
		end
		@(negedge clk_i);
		valid_i = 1'b0;
		@(negedge clk_i);
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

	task test_reset_mid_stream();
		$display("[TEST] Testing reset mid stream...");
		@(negedge clk_i);
		valid_i = 1'b0;
		rstn_i = 1'b0;
		repeat (2) @(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	task drain();
		@(negedge clk_i);
		valid_i = 1'b0;
		ready_i = 1'b1;
		repeat (4) @(negedge clk_i);
		if (scb.exp_q.size() != 0) begin
			scb.error_count++;
			$display("[TEST] MISMATCH: %0d words never left the buffer", scb.exp_q.size());
		end
	endtask

	initial begin
		reset_seq();
		test_idle_after_reset();
		test_full_rate();
		run_random_stream(2000);
		test_reset_mid_stream();
		test_full_rate();
		run_random_stream(1000);
		drain();
		scb.report();

		$display("--------------------------------------");
		$display("[TEST] Handshake coverage: %0.2f%%", handshake_cov.get_coverage());
		$display("[TEST] Pointer coverage: %0.2f%%", pointers_cov.get_coverage());
		$display("[TEST] Overall coverage: %0.2f%%", $get_coverage());
		$display("--------------------------------------");
		$finish;
	end
endmodule
