`timescale 1ns/1ps

// TRANSACTION one cycle of pixel stimulus
class Transaction #(
	parameter WIDTH_P = 8
);
	rand logic [WIDTH_P-1:0] red_i;
	rand logic [WIDTH_P-1:0] green_i;
	rand logic [WIDTH_P-1:0] blue_i;
	rand logic [0:0] valid_i;
	rand logic [0:0] ready_i;

	constraint c_red { red_i dist { '0 := 10, {WIDTH_P{1'b1}} := 10, [1:(1 << WIDTH_P) - 2] :/ 80}; }
	constraint c_green { green_i dist { '0 := 10, {WIDTH_P{1'b1}} := 10, [1:(1 << WIDTH_P) - 2] :/ 80}; }
	constraint c_blue { blue_i dist { '0 := 10, {WIDTH_P{1'b1}} := 10, [1:(1 << WIDTH_P) - 2] :/ 80}; }
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

// MODEL bit exact shift and add luma approximation
class Model #(
	parameter WIDTH_P = 8
);
	static function logic [WIDTH_P-1:0] gray(logic [WIDTH_P-1:0] red, logic [WIDTH_P-1:0] green, logic [WIDTH_P-1:0] blue);
		logic [WIDTH_P-1:0] red_l;
		logic [WIDTH_P-1:0] green_l;
		logic [WIDTH_P-1:0] blue_l;
		red_l = (red >> 2) + (red >> 5);
		green_l = (green >> 1) + (green >> 4);
		blue_l = (blue >> 4) + (blue >> 5);
		return WIDTH_P'(red_l + green_l + blue_l);
	endfunction
endclass

// SCOREBOARD expected gray values in order of acceptance
class Scoreboard #(
	parameter WIDTH_P = 8
);
	logic [WIDTH_P-1:0] exp_q [$];
	int success_count;
	int error_count;

	function void reset();
		exp_q.delete();
	endfunction

	function void check_write(logic [0:0] valid_i, logic [0:0] ready_o, logic [WIDTH_P-1:0] red_i, logic [WIDTH_P-1:0] green_i, logic [WIDTH_P-1:0] blue_i);
		if (valid_i && ready_o) begin
			exp_q.push_back(Model#(WIDTH_P)::gray(red_i, green_i, blue_i));
		end
	endfunction

	function void check_read(logic [0:0] valid_o, logic [0:0] ready_i, logic [WIDTH_P-1:0] gray_o);
		logic [WIDTH_P-1:0] expected;
		if (valid_o && ready_i) begin
			if (exp_q.size() == 0) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h with nothing expected", gray_o);
				return;
			end
			expected = exp_q.pop_front();
			if (gray_o !== expected) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h, expected %h", gray_o, expected);
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
module rgb2gray_test #(
	parameter WIDTH_P = 8
);
	logic [0:0] clk_i = 1'b0;
	logic [0:0] rstn_i = 1'b0;
	logic [0:0] valid_i = 1'b0;
	logic [0:0] ready_i = 1'b0;
	logic [WIDTH_P-1:0] red_i = '0;
	logic [WIDTH_P-1:0] green_i = '0;
	logic [WIDTH_P-1:0] blue_i = '0;
	logic [0:0] valid_o;
	logic [0:0] ready_o;
	logic [WIDTH_P-1:0] gray_o;

	Generator #(WIDTH_P) gen = new();
	Scoreboard #(WIDTH_P) scb = new();
	Transaction #(WIDTH_P) trs;

	rgb2gray #(
		.WIDTH_P(WIDTH_P)
	) dut_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.valid_i(valid_i),
		.ready_i(ready_i),
		.valid_o(valid_o),
		.ready_o(ready_o),
		.red_i(red_i),
		.blue_i(blue_i),
		.green_i(green_i),
		.gray_o(gray_o)
	);

	// covergroups
	covergroup cg_inputs @(posedge clk_i iff (rstn_i && valid_i && ready_o));
		cp_red: coverpoint red_i {
			bins zero = {0};
			bins max = {(1 << WIDTH_P) - 1};
			bins mid = {[1:(1 << WIDTH_P) - 2]};
		}
		cp_green: coverpoint green_i {
			bins zero = {0};
			bins max = {(1 << WIDTH_P) - 1};
			bins mid = {[1:(1 << WIDTH_P) - 2]};
		}
		cp_blue: coverpoint blue_i {
			bins zero = {0};
			bins max = {(1 << WIDTH_P) - 1};
			bins mid = {[1:(1 << WIDTH_P) - 2]};
		}

		cp_rgb_cross: cross cp_red, cp_green, cp_blue;
	endgroup

	covergroup cg_handshake @(posedge clk_i iff rstn_i);
		cp_write: coverpoint (valid_i && ready_o);
		cp_read: coverpoint (valid_o && ready_i);
		// internal stage between the two elastic registers
		cp_mid_stall: coverpoint (dut_inst.valid_mid && !dut_inst.ready_mid);

		cp_write_read_cross: cross cp_write, cp_read;
	endgroup

	cg_inputs inputs_cov = new();
	cg_handshake handshake_cov = new();

	// SVA
	// with the output ready for two cycles an accepted pixel appears two cycles later
	property p_latency;
		logic [WIDTH_P-1:0] exp_l;
		@(posedge clk_i) disable iff (!rstn_i)
		(valid_i && ready_o, exp_l = Model#(WIDTH_P)::gray(red_i, green_i, blue_i)) ##1 ready_i |=> (valid_o && gray_o == exp_l);
	endproperty

	a_latency: assert property (p_latency)
	else $error("gray wrong or late, got %h", gray_o);

	// a stalled output holds valid and data
	a_hold: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i) |=> (valid_o && $stable(gray_o)))
	else $error("output changed while stalled");

	// both stages full stops input
	a_full_stop: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i && dut_inst.valid_mid) |-> !ready_o)
	else $error("ready_o high with both stages full and stalled");

	// reset clears valid
	a_reset: assert property (@(posedge clk_i)
		!rstn_i |=> !valid_o)
	else $error("valid_o set after reset");

	// pipeline fills completely then drains
	c_fill_drain: cover property (@(posedge clk_i) disable iff (!rstn_i)
		(!ready_o)[*2] ##1 (valid_o && ready_i)[*2]);

	always #5 clk_i = ~clk_i;

	// monitor
	always @(posedge clk_i) begin
		if (rstn_i) begin
			scb.check_read(valid_o, ready_i, gray_o);
			scb.check_write(valid_i, ready_o, red_i, green_i, blue_i);
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

	task send(input logic [WIDTH_P-1:0] red, input logic [WIDTH_P-1:0] green, input logic [WIDTH_P-1:0] blue);
		@(negedge clk_i);
		valid_i = 1'b1;
		ready_i = 1'b1;
		red_i = red;
		green_i = green;
		blue_i = blue;
	endtask

	task test_corners();
		$display("[TEST] Testing black, white, and single channel pixels...");
		send('0, '0, '0);
		send({WIDTH_P{1'b1}}, {WIDTH_P{1'b1}}, {WIDTH_P{1'b1}});
		send({WIDTH_P{1'b1}}, '0, '0);
		send('0, {WIDTH_P{1'b1}}, '0);
		send('0, '0, {WIDTH_P{1'b1}});
		@(negedge clk_i);
		valid_i = 1'b0;
		repeat (2) @(negedge clk_i);
	endtask

	task test_stall_full();
		$display("[TEST] Testing a full pipeline under backpressure...");
		@(negedge clk_i);
		ready_i = 1'b0;
		valid_i = 1'b1;
		repeat (4) begin
			red_i = WIDTH_P'($urandom);
			green_i = WIDTH_P'($urandom);
			blue_i = WIDTH_P'($urandom);
			@(negedge clk_i);
		end
		valid_i = 1'b0;
		ready_i = 1'b1;
		repeat (4) @(negedge clk_i);
	endtask

	task run_random_stream(input int unsigned cycles);
		$display("[TEST] Testing random stream for %0d cycles...", cycles);
		repeat (cycles) begin
			@(negedge clk_i);
			gen.randomize_trs(trs);
			red_i = trs.red_i;
			green_i = trs.green_i;
			blue_i = trs.blue_i;
			valid_i = trs.valid_i;
			ready_i = trs.ready_i;
		end
	endtask

	task drain();
		@(negedge clk_i);
		valid_i = 1'b0;
		ready_i = 1'b1;
		repeat (6) @(negedge clk_i);
		if (scb.exp_q.size() != 0) begin
			scb.error_count++;
			$display("[TEST] MISMATCH: %0d pixels never left the pipeline", scb.exp_q.size());
		end
	endtask

	initial begin
		reset_seq();
		test_corners();
		test_stall_full();
		run_random_stream(3000);
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
