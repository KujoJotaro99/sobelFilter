`timescale 1ns/1ps

// MODEL: Queue based simulation model for a FIFO
// Has push and pop access functions
// Has full and empty access functions
class Model #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 256
);
	logic [WIDTH_P-1:0] ref_q [$];
	logic [0:0] full_o;
	logic [0:0] empty_o;

	function new ();
		update_flags();
	endfunction

	function void update_flags();
		full_o = (ref_q.size() == DEPTH_P);
		empty_o = (ref_q.size() == 0);
	endfunction

	// clear contents on reset
	function void reset();
		ref_q.delete();
		update_flags();
	endfunction

	function void push(logic [WIDTH_P-1:0] data);
		if (!full_o) begin
			ref_q.push_back(data);
			update_flags();
		end
	endfunction

	function logic [WIDTH_P-1:0] pop();
		logic [WIDTH_P-1:0] data;
		if (!empty_o) begin
			data = ref_q.pop_front();
			update_flags();
			return data;
		end
		return '0;
	endfunction

	function logic [0:0] is_full();
		return full_o;
	endfunction

	function logic [0:0] is_empty();
		return empty_o;
	endfunction
endclass


// TRANSACTION: Encapsulation representing the expected input transaction of this FIFO spec
class Transaction #(
	parameter WIDTH_P = 8
);
	static int trans_id = 0;
	rand logic [WIDTH_P-1:0] data_i;
	rand logic [0:0] valid_i;
	rand logic [0:0] ready_i;

	constraint c_valid { valid_i dist { 1'b0 := 30, 1'b1 := 70}; }
	constraint c_ready { ready_i dist { 1'b0 := 30, 1'b1 := 70}; }

	function new();
		trans_id++;
	endfunction
endclass

// GENERATOR: Generates and randomizes instance of transaction
class Generator #(
	parameter WIDTH_P = 8
);
	function void randomize_trs(output Transaction #(WIDTH_P) tx);
		tx = new();
		assert (tx.randomize()) else $fatal(1, "transaction randomize failed");
	endfunction
endclass

// DRIVER: Stimulates DUT pins and feeds Generator produced transaction
class Driver #(
	parameter WIDTH_P = 8
);
	task drive(input Transaction #(WIDTH_P) tx, output logic [WIDTH_P-1:0] data_i, output logic [0:0] valid_i, output logic [0:0] ready_i);
		begin
			data_i = tx.data_i;
			ready_i = tx.ready_i;
			valid_i = tx.valid_i;
		end
	endtask
endclass

// SCOREBOARD: Contains instance of reference model, monitors DUT output to compare to expected model reads, writes, and FIFO states
class Scoreboard #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 256
);
	Model #(WIDTH_P, DEPTH_P) model;
	int success_count;
	int error_count;

	function new();
		model = new();
		success_count = 0;
		error_count = 0;
	endfunction

	function void check_flags(logic [0:0] valid_o, logic [0:0] ready_o);
		if (ready_o !== !model.is_full() || valid_o !== !model.is_empty()) begin
			error_count++;
			$display("[TEST] MISMATCH: flags got valid_o=%b ready_o=%b, expected valid_o=%b ready_o=%b", valid_o, ready_o, !model.is_empty(), !model.is_full());
		end
	endfunction

	function void check_write(logic [0:0] valid_i, logic [0:0] ready_o, logic [WIDTH_P-1:0] data_i);
		if (valid_i && ready_o) begin
			model.push(data_i);
		end
	endfunction

	function void check_read(logic [0:0] valid_o, logic [0:0] ready_i, logic [WIDTH_P-1:0] data_o);
		if (valid_o && ready_i) begin
			logic [WIDTH_P-1:0] expected = model.pop();
			if (data_o !== expected) begin
				error_count++;
				$display("[TEST] MISMATCH: got %h, expected %h", data_o, expected);
			end else begin
				$display("[TEST] MATCH: got %h, expected %h", data_o, expected);
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
module fifo_sync_test #(
	parameter WIDTH_P = 8,
	parameter DEPTH_P = 256
);
	logic [0:0] clk_i = 1'b0;
	logic [0:0] rstn_i;
	logic [WIDTH_P-1:0] data_i;
	logic [0:0] valid_i;
	logic [0:0] ready_i;
	logic [WIDTH_P-1:0] data_o;
	logic [0:0] valid_o;
	logic [0:0] ready_o;

	Scoreboard #(WIDTH_P, DEPTH_P) scb;
	Generator #(WIDTH_P) gen;
	Driver #(WIDTH_P) drv;
	Transaction #(WIDTH_P) trs;

	fifo_sync #(
		.WIDTH_P(WIDTH_P),
		.DEPTH_P(DEPTH_P)
	) dut_inst (
		.clk_i(clk_i),
		.rstn_i(rstn_i),
		.data_i(data_i),
		.valid_i(valid_i),
		.ready_i(ready_i),
		.data_o(data_o),
		.valid_o(valid_o),
		.ready_o(ready_o)
	);

	// covergroups
	covergroup cg_input_handshake;
		cp_input_valid: coverpoint valid_i {
			bins low = {0};
			bins high = {1};
		}
		cp_output_ready: coverpoint ready_o {
			bins low = {0};
			bins high = {1};
		}

		cp_input_cross: cross cp_input_valid, cp_output_ready;
	endgroup


	covergroup cg_output_handshake;
		cp_output_valid: coverpoint valid_o {
			bins low = {0};
			bins high = {1};
		}
		cp_input_ready: coverpoint ready_i {
			bins low = {0};
			bins high = {1};
		}

		cp_output_cross: cross cp_output_valid, cp_input_ready;
	endgroup

	covergroup cg_occupancy;
		cp_occupancy: coverpoint scb.model.ref_q.size() {
			bins empty = {0};
			bins one_entry = {1};
			bins mixed = {[2:DEPTH_P-2]};
			bins one_left = {DEPTH_P-1};
			bins full = {DEPTH_P};
		}
	endgroup

	covergroup cg_operations;
		cp_write: coverpoint (valid_i && ready_o) {
			bins no_write = {0};
			bins write = {1};
		}
		cp_read: coverpoint (valid_o && ready_i) {
			bins no_read = {0};
			bins read = {1};
		}

		cp_write_read_cross: cross cp_write, cp_read {
			bins idle = binsof(cp_write.no_write) && binsof(cp_read.no_read);
			bins write_only = binsof(cp_write.write) && binsof(cp_read.no_read);
			bins read_only = binsof(cp_write.no_write) && binsof(cp_read.read);
			bins write_read = binsof(cp_write.write) && binsof(cp_read.read);
		}
	endgroup

	// occupancy and operation cross
	covergroup cg_occupancy_operations;
		cp_level: coverpoint scb.model.ref_q.size() {
			bins empty = {0};
			bins partial = {[1:DEPTH_P-1]};
			bins full = {DEPTH_P};
		}
		cp_write_attempt: coverpoint valid_i;
		cp_read_attempt: coverpoint ready_i;

		cp_level_cross: cross cp_level, cp_write_attempt, cp_read_attempt;
	endgroup

	covergroup cg_sequences;
		cp_write_burst: coverpoint (valid_i && ready_o) {
			bins two_writes = (1[*2]);
			bins short_burst = (1[*3:5]);
			bins long_burst = (1[*6:DEPTH_P-1]);
		}

		cp_read_burst: coverpoint (valid_o && ready_i) {
			bins two_reads = (1[*2]);
			bins short_burst = (1[*3:5]);
			bins long_burst = (1[*6:DEPTH_P-1]);
		}
	endgroup

	covergroup cg_reset;
		cp_reset: coverpoint rstn_i {
			bins reset_asserted = {0};
			bins reset_released = {1};
		}
		// reset taken while the fifo holds data
		cp_reset_with_data: coverpoint (!rstn_i && valid_o) {
			bins hit = {1};
		}
	endgroup

	cg_reset reset_cov = new();
	cg_input_handshake input_handshake_cov = new();
	cg_output_handshake output_handshake_cov = new();
	cg_occupancy occupancy_cov = new();
	cg_operations operations_cov = new();
	cg_occupancy_operations occupancy_operations_cov = new();
	cg_sequences sequences_cov = new();

	// SVA
	// reset leaves the fifo empty and ready
	a_reset: assert property (@(posedge clk_i)
		!rstn_i |=> (!valid_o && ready_o))
	else $error("reset did not empty the fifo");

	// output holds while a stalled read persists
	a_hold: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i) |=> $stable(data_o))
	else $error("data_o changed during a stalled read");

	// valid_o cannot drop without a read
	a_no_drop: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i) |=> valid_o)
	else $error("valid_o dropped without a read");

	// the word returned by a read equals the word held during the stall
	property p_stall_read;
		logic [WIDTH_P-1:0] held_l;
		@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i, held_l = data_o) |->
			(valid_o && !ready_i)[*1:$] ##1 (valid_o && ready_i && data_o == held_l);
	endproperty

	a_stall_read: assert property (p_stall_read)
	else $error("read returned a different word than the stalled head");

	// a write into an empty fifo is visible on the next cycle
	property p_fwft;
		logic [WIDTH_P-1:0] data_l;
		@(posedge clk_i) disable iff (!rstn_i)
		(valid_i && ready_o && !valid_o, data_l = data_i) |=> (valid_o && data_o == data_l);
	endproperty

	a_fwft: assert property (p_fwft)
	else $error("first word did not fall through");

	// a rejected write at full leaves the fifo full
	a_reject_write: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_i && !ready_o && !ready_i) |=> !ready_o)
	else $error("rejected write changed the full state");

	// an idle empty fifo stays empty
	a_reject_read: assert property (@(posedge clk_i) disable iff (!rstn_i)
		(!valid_o && !valid_i) |=> !valid_o)
	else $error("empty fifo produced data without a write");

	// read stalls of 3 to 6 cycles
	c_stall_run: cover property (@(posedge clk_i) disable iff (!rstn_i)
		(valid_o && !ready_i)[*3:6]);

	// fill from empty to full
	c_fill: cover property (@(posedge clk_i) disable iff (!rstn_i)
		!valid_o ##1 ready_o[*1:$] ##1 !ready_o);

	// write and read in the same cycle with one entry stored
	c_bypass: cover property (@(posedge clk_i) disable iff (!rstn_i)
		valid_i && ready_o && valid_o && ready_i && (scb.model.ref_q.size() == 1));

	always #5 clk_i = ~clk_i;

	always @(posedge clk_i) begin
		reset_cov.sample();
		if (rstn_i === 1'b1 && scb != null) begin
			scb.check_flags(valid_o, ready_o);
			scb.check_read(valid_o, ready_i, data_o);
			scb.check_write(valid_i, ready_o, data_i);
			input_handshake_cov.sample();
			output_handshake_cov.sample();
			occupancy_cov.sample();
			operations_cov.sample();
			occupancy_operations_cov.sample();
			sequences_cov.sample();
		end else if (scb != null) begin
			scb.model.reset();
		end
	end

	// DIRECTED TESTS
	task reset_seq();
		$display("[TEST] Testing reset behavior...");
		rstn_i = 0;
		data_i = 0;
		valid_i = 0;
		ready_i = 0;
		repeat (10) begin
			#10;
		end
		rstn_i = 1;
	endtask

	task test_empty_at_start();
		@(posedge clk_i);
		#1;
		if (valid_o == 1'b1) begin
			$display("[TEST] MISMATCH: FIFO should be empty after reset");
		end else begin
			$display("[TEST] MATCH: FIFO is empty after reset");
		end
	endtask

	task test_fwft();
		$display("[TEST] Testing First Word Fall Through behavior...");
		@(posedge clk_i);
		#1;
		data_i = 8'hAB;
		valid_i = 1'b1;
		ready_i = 1'b0;

		@(posedge clk_i);
		#1;
		valid_i = 1'b0;

		if (valid_o == 1'b1 && data_o == 8'hAB) begin
			$display("[TEST] MATCH: First word visible on data_o before read");
		end else begin
			$display("[TEST] MISMATCH: First word not visible, got %h expected 8'hAB", data_o);
		end

		ready_i = 1'b1;

		@(posedge clk_i);
		#1;
		ready_i = 1'b0;
	endtask

	task test_fill();
		$display("[TEST] Testing FIFO full behavior...");
		repeat (DEPTH_P + 4) begin
			@(posedge clk_i);
			#1;
			valid_i = 1'b1;
			ready_i = 1'b0;
			data_i = $random;
		end

		@(posedge clk_i);
		#1;
		if (ready_o == 1'b1) begin
			$display("[TEST] MISMATCH: FIFO should be full");
		end else begin
			$display("[TEST] MATCH: FIFO full flag asserted correctly");
		end
		valid_i = 1'b0;
	endtask

	task test_drain();
		$display("[TEST] Testing FIFO empty behavior...");
		valid_i = 1'b0;
		ready_i = 1'b1;
		repeat (DEPTH_P + 4) begin
			@(posedge clk_i);
			#1;
		end

		if (valid_o == 1'b1) begin
			$display("[TEST] MISMATCH: FIFO should be empty after draining");
		end else begin
			$display("[TEST] MATCH: FIFO empty flag asserted after drain");
		end
		ready_i = 1'b0;
	endtask

	task test_reset_with_data();
		$display("[TEST] Testing reset while FIFO contains data...");
		repeat (DEPTH_P / 2) begin
			@(posedge clk_i);
			#1;
			valid_i = 1'b1;
			ready_i = 1'b0;
			data_i = $random;
		end

		@(posedge clk_i);
		#1;
		valid_i = 1'b0;
		rstn_i = 1'b0;

		repeat (2) begin
			@(posedge clk_i);
			#1;
		end
		rstn_i = 1'b1;

		if (valid_o == 1'b1 || ready_o == 1'b0) begin
			$display("[TEST] MISMATCH: FIFO should be empty after reset with data");
		end else begin
			$display("[TEST] MATCH: FIFO empty after reset with data");
		end
	endtask

	task run_random_stream(input int cycles);
		$display("[TEST] Testing FIFO random behavior for %0d cycles...", cycles);
		repeat (cycles) begin
			@(posedge clk_i);
			#1;
			gen.randomize_trs(trs);
			drv.drive(trs, data_i, valid_i, ready_i);
		end
	endtask

	initial begin
		gen = new();
		drv = new();
		scb = new();

		reset_seq();
		test_empty_at_start();
		test_fwft();
		test_fill();
		test_drain();
		test_reset_with_data();
		run_random_stream(1000);
		#100;
		scb.report();

		$display("--------------------------------------");
		$display("[TEST] Reset coverage: %0.2f%%", reset_cov.get_coverage());
		$display("[TEST] Input handshake coverage: %0.2f%%", input_handshake_cov.get_coverage());
		$display("[TEST] Output handshake coverage: %0.2f%%", output_handshake_cov.get_coverage());
		$display("[TEST] Occupancy coverage: %0.2f%%", occupancy_cov.get_coverage());
		$display("[TEST] Operations coverage: %0.2f%%", operations_cov.get_coverage());
		$display("[TEST] Occupancy operations coverage: %0.2f%%", occupancy_operations_cov.get_coverage());
		$display("[TEST] Sequence coverage: %0.2f%%", sequences_cov.get_coverage());
		$display("[TEST] Overall coverage: %0.2f%%", $get_coverage());
		$display("--------------------------------------");
		$display("\n");
		$finish;
	end
endmodule
