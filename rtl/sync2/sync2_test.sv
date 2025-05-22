`timescale 1ns/1ps

module sync2_test #(
	parameter WIDTH_P = 8
);
	logic [0:0] clk = 1'b0;
	logic [0:0] rstn = 1'b0;
	logic [WIDTH_P-1:0] sync_i = '0;
	logic [WIDTH_P-1:0] sync_o;

	sync2 #(
		.WIDTH_P(WIDTH_P)
	) dut_inst (
		.clk_sync_i(clk),
		.rstn_i(rstn),
		.sync_i(sync_i),
		.sync_o(sync_o)
	);

	always #5 clk = ~clk;

	// covergroups
	covergroup cg_sync @(posedge clk);
		cp_reset: coverpoint rstn {
			bins pulse = (1 => 0 => 1);
			bins held = (1 => 0[*2:5] => 1);
		}
		cp_input: coverpoint sync_i {
			bins zero = {0};
			bins ones = {(1 << WIDTH_P) - 1};
			bins other = default;
		}
	endgroup

	cg_sync sync_cov = new();

	// SVA
	// output is the input from two edges earlier
	a_latency: assert property (@(posedge clk)
		($past(rstn) && $past(rstn, 2)) |-> sync_o == $past(sync_i, 2))
	else $fatal(1, "latency: sync_o=%0h expected %0h", sync_o, $past(sync_i, 2));

	// reset in either of the last two edges clears the output
	a_reset: assert property (@(posedge clk)
		(!$past(rstn) || !$past(rstn, 2)) |-> sync_o == '0)
	else $fatal(1, "reset: sync_o=%0h not cleared", sync_o);

	// a change on the input reaches the output after two edges
	c_propagate: cover property (@(posedge clk) disable iff (!rstn)
		$changed(sync_i) ##2 $changed(sync_o));

	initial begin
		repeat (2) @(negedge clk);
		rstn = 1'b1;
		sync_i = '1;
		repeat (3) @(negedge clk);

		// reset is synchronous so asserting it between edges must not change sync_o
		rstn = 1'b0;
		#1;
		if (sync_o != '1) $fatal(1, "reset changed sync_o before clock edge: %0h", sync_o);
		repeat (3) @(negedge clk);

		for (int unsigned i = 0; i < 1000; i++) begin
			@(negedge clk);
			sync_i = WIDTH_P'($urandom);
			rstn = !($urandom_range(0, 49) == 0);
		end

		$display("[TEST] Sync coverage: %0.2f%%", sync_cov.get_coverage());
		$display("sync2_test PASSED");
		$finish;
	end
endmodule
