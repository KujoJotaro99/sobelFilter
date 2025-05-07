`timescale 1ns/1ps

// TRANSACTION one cycle of counter controls
class Transaction #(
	parameter WIDTH_P = 8,
	parameter MAX_VAL_P = 100
);
	rand logic [0:0] en_i;
	rand logic [0:0] up_i;
	rand logic [0:0] down_i;
	rand logic [WIDTH_P-1:0] rstn_data_i;

	constraint c_en { en_i dist { 1'b0 := 20, 1'b1 := 80}; }
	constraint c_dir { {up_i, down_i} dist { 2'b10 := 40, 2'b01 := 40, 2'b00 := 10, 2'b11 := 10}; }
	constraint c_load { rstn_data_i dist { 0 := 20, MAX_VAL_P := 20, [1:MAX_VAL_P-1] :/ 60}; }
endclass

// GENERATOR randomizes a new transaction
class Generator #(
	parameter WIDTH_P = 8,
	parameter MAX_VAL_P = 100
);
	function void randomize_trs(output Transaction #(WIDTH_P, MAX_VAL_P) tx);
		tx = new();
		assert (tx.randomize()) else $fatal(1, "transaction randomize failed");
	endfunction
endclass

// MODEL wrapping up and down counter
class Model #(
	parameter WIDTH_P = 8,
	parameter MAX_VAL_P = 100
);
	logic [WIDTH_P-1:0] count_q;

	function void load(logic [WIDTH_P-1:0] data);
		count_q = data;
	endfunction

	function void step(logic [0:0] en, logic [0:0] up, logic [0:0] down);
		if (en && up && !down) begin
			count_q = (count_q == MAX_VAL_P) ? '0 : count_q + 1'b1;
		end else if (en && down && !up) begin
			count_q = (count_q == '0) ? WIDTH_P'(MAX_VAL_P) : count_q - 1'b1;
		end
	endfunction
endclass

// SCOREBOARD compares the count each cycle against the model
class Scoreboard #(
	parameter WIDTH_P = 8,
	parameter MAX_VAL_P = 100
);
	Model #(WIDTH_P, MAX_VAL_P) model;
	int success_count;
	int error_count;

	function new();
		model = new();
	endfunction

	function void check_count(logic [WIDTH_P-1:0] count_o);
		if (count_o !== model.count_q) begin
			error_count++;
			$display("[TEST] MISMATCH: got %0d, expected %0d", count_o, model.count_q);
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
module counter_test #(
	parameter WIDTH_P = 8,
	parameter MAX_VAL_P = 100
);
	logic [0:0] clk_i = 1'b0;
	logic [0:0] rstn_i = 1'b0;
	logic [WIDTH_P-1:0] rstn_data_i = '0;
	logic [0:0] up_i = 1'b0;
	logic [0:0] down_i = 1'b0;
	logic [0:0] en_i = 1'b0;
	logic [WIDTH_P-1:0] count_o;

	Generator #(WIDTH_P, MAX_VAL_P) gen = new();
	Scoreboard #(WIDTH_P, MAX_VAL_P) scb = new();
	Transaction #(WIDTH_P, MAX_VAL_P) trs;

	counter #(
		.WIDTH_P(WIDTH_P),
		.MAX_VAL_P(MAX_VAL_P)
	) dut_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.rstn_data_i(rstn_data_i),
		.up_i(up_i),
		.down_i(down_i),
		.en_i(en_i),
		.count_o(count_o)
	);

	// covergroups
	covergroup cg_controls @(posedge clk_i iff rstn_i);
		cp_op: coverpoint {en_i, up_i, down_i} {
			bins up = {3'b110};
			bins down = {3'b101};
			bins both = {3'b111};
			bins none = {3'b100};
			bins disabled = {[3'b000:3'b011]};
		}
		cp_count: coverpoint count_o {
			bins zero = {0};
			bins max = {MAX_VAL_P};
			bins mid = {[1:MAX_VAL_P-1]};
		}
		cp_wrap: coverpoint count_o {
			bins wrap_up = (MAX_VAL_P => 0);
			bins wrap_down = (0 => MAX_VAL_P);
		}

		cp_op_count_cross: cross cp_op, cp_count;
	endgroup

	covergroup cg_load @(posedge clk_i iff !rstn_i);
		cp_load: coverpoint rstn_data_i {
			bins zero = {0};
			bins max = {MAX_VAL_P};
			bins mid = {[1:MAX_VAL_P-1]};
		}
	endgroup

	cg_controls controls_cov = new();
	cg_load load_cov = new();

	// SVA
	// count up
	a_up: assert property (@(posedge clk_i)
		(rstn_i && en_i && up_i && !down_i && count_o != MAX_VAL_P) |=> count_o == $past(count_o) + 1'b1)
	else $error("up count wrong, got %0d", count_o);

	// wrap from max to zero
	a_up_wrap: assert property (@(posedge clk_i)
		(rstn_i && en_i && up_i && !down_i && count_o == MAX_VAL_P) |=> count_o == '0)
	else $error("up wrap wrong, got %0d", count_o);

	// count down
	a_down: assert property (@(posedge clk_i)
		(rstn_i && en_i && down_i && !up_i && count_o != '0) |=> count_o == $past(count_o) - 1'b1)
	else $error("down count wrong, got %0d", count_o);

	// wrap from zero to max
	a_down_wrap: assert property (@(posedge clk_i)
		(rstn_i && en_i && down_i && !up_i && count_o == '0) |=> count_o == MAX_VAL_P)
	else $error("down wrap wrong, got %0d", count_o);

	// disabled or conflicting controls hold the count
	a_hold: assert property (@(posedge clk_i)
		(rstn_i && (!en_i || (up_i == down_i))) |=> $stable(count_o))
	else $error("count changed while holding");

	// reset loads the reset value
	a_load: assert property (@(posedge clk_i)
		!rstn_i |=> count_o == $past(rstn_data_i))
	else $error("reset load wrong, got %0d", count_o);

	// count never leaves the legal range
	a_range: assert property (@(posedge clk_i) disable iff (!rstn_i)
		count_o <= MAX_VAL_P)
	else $error("count %0d above max", count_o);

	// a full lap upward
	c_lap: cover property (@(posedge clk_i) disable iff (!rstn_i)
		(count_o == 0) ##1 (count_o != 0)[*1:$] ##1 (count_o == 0));

	always #5 clk_i = ~clk_i;

	// monitor
	always @(posedge clk_i) begin
		if (rstn_i) begin
			scb.check_count(count_o);
			scb.model.step(en_i, up_i, down_i);
		end else begin
			scb.model.load(rstn_data_i);
		end
	end

	// DIRECTED TESTS
	task reset_seq(input logic [WIDTH_P-1:0] data);
		@(negedge clk_i);
		rstn_i = 1'b0;
		rstn_data_i = data;
		repeat (2) @(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	task drive(input logic [0:0] en, input logic [0:0] up, input logic [0:0] down, input int unsigned cycles);
		repeat (cycles) begin
			@(negedge clk_i);
			en_i = en;
			up_i = up;
			down_i = down;
		end
	endtask

	task test_up_wrap();
		$display("[TEST] Testing up count through the wrap...");
		reset_seq('0);
		drive(1'b1, 1'b1, 1'b0, MAX_VAL_P + 3);
	endtask

	task test_down_wrap();
		$display("[TEST] Testing down count through the wrap...");
		reset_seq(WIDTH_P'(MAX_VAL_P));
		drive(1'b1, 1'b0, 1'b1, MAX_VAL_P + 3);
	endtask

	task test_hold();
		$display("[TEST] Testing hold on disable and conflicting controls...");
		reset_seq(WIDTH_P'(MAX_VAL_P / 2));
		drive(1'b0, 1'b1, 1'b0, 4);
		drive(1'b1, 1'b1, 1'b1, 4);
		drive(1'b1, 1'b0, 1'b0, 4);
	endtask

	task run_random_stream(input int unsigned cycles);
		$display("[TEST] Testing random controls for %0d cycles...", cycles);
		repeat (cycles) begin
			@(negedge clk_i);
			gen.randomize_trs(trs);
			en_i = trs.en_i;
			up_i = trs.up_i;
			down_i = trs.down_i;
			rstn_data_i = trs.rstn_data_i;
			// occasional reset with a random load value
			rstn_i = ($urandom_range(0, 99) != 0);
		end
		@(negedge clk_i);
		rstn_i = 1'b1;
	endtask

	initial begin
		test_up_wrap();
		test_down_wrap();
		test_hold();
		run_random_stream(5000);
		repeat (2) @(negedge clk_i);
		scb.report();

		$display("--------------------------------------");
		$display("[TEST] Control coverage: %0.2f%%", controls_cov.get_coverage());
		$display("[TEST] Load coverage: %0.2f%%", load_cov.get_coverage());
		$display("[TEST] Overall coverage: %0.2f%%", $get_coverage());
		$display("--------------------------------------");
		$finish;
	end
endmodule
