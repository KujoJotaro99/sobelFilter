import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLOCK_PERIOD_NS = 10


class ModelManager:
    def __init__(self, dut):
        self.depth = int(dut.DEPTH_P.value)
        self.mem = np.full((self.depth,), np.nan)

    def run(self, input_data):
        wr_en, wr_addr, data, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b = input_data

        exp_a = None
        exp_b = None

        if rd_en_a:
            value_a = self.mem[int(rd_addr_a)]
            exp_a = None if np.isnan(value_a) else int(value_a)

        if rd_en_b:
            value_b = self.mem[int(rd_addr_b)]
            exp_b = None if np.isnan(value_b) else int(value_b)

        if wr_en:
            self.mem[int(wr_addr)] = int(data)

        return exp_a, exp_b


class InputManager:
    def __init__(self, stream):
        self.data = list(stream)
        self.index = 0
        self.valid = False
        self.current = None

    def drive(self, handshake):
        if not self.valid and self.index < len(self.data):
            self.current = self.data[self.index]
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else (0, 0, 0, 0, 0, 0, 0))

    def accept(self):
        if self.valid:
            self.index += 1
            self.valid = False
            return self.current
        return None


class ScoreManager:
    def __init__(self, model):
        self.model = model
        self.pending = []
        self.outputs_received = 0
        self.pipeline_delay = 0

    def update_expected(self, input_data):
        expected = self.model.run(input_data)
        if expected != (None, None):
            self.pending.append(expected)

    def check_output(self, output):
        if output is None:
            return False

        self.outputs_received += 1
        if self.outputs_received <= self.pipeline_delay or not self.pending:
            return False

        got_a, got_b = output
        exp_a, exp_b = self.pending.pop(0)

        if exp_a is not None:
            assert got_a is not None, "Port A output missing"
            assert int(got_a) == int(exp_a), f"Port A mismatch got {int(got_a)} exp {int(exp_a)}"

        if exp_b is not None:
            assert got_b is not None, "Port B output missing"
            assert int(got_b) == int(exp_b), f"Port B mismatch got {int(got_b)} exp {int(exp_b)}"

        return True


class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        self.expected_outputs = sum(1 for op in stream if op[3] or op[5])
        self.checked = 0
        self.in_stride = 1
        self.out_stride = 1

    async def run(self):
        try:
            self.input.drive(self.handshake)
            cycle = 0
            while self.checked < self.expected_outputs:
                await FallingEdge(self.handshake.dut.clk_i)
                cycle += 1

                if (cycle % self.in_stride) == 0:
                    if self.handshake.input_accepted():
                        input_data = self.input.accept()
                        if input_data is not None:
                            self.scoreboard.update_expected(input_data)
                    self.input.drive(self.handshake)
                else:
                    self.handshake.drive(False, (0, 0, 0, 0, 0, 0, 0))

                if (cycle % self.out_stride) == 0:
                    if self.scoreboard.pending:
                        if self.scoreboard.check_output(self.handshake.output_value()):
                            self.checked += 1
        finally:
            self.handshake.dut.wr_en_i.value = 0
            self.handshake.dut.rd_en_a_i.value = 0
            self.handshake.dut.rd_en_b_i.value = 0
            self.handshake.dut.data_i.value = 0
            self.handshake.dut.wr_addr_i.value = 0
            self.handshake.dut.rd_addr_a_i.value = 0
            self.handshake.dut.rd_addr_b_i.value = 0


class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut
        self.last_valid = False

    def drive(self, valid, data):
        wr_en, wr_addr, data_i, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b = data
        self.last_valid = bool(valid)

        self.dut.wr_en_i.value = 1 if valid and wr_en else 0
        self.dut.data_i.value = int(data_i)
        self.dut.wr_addr_i.value = int(wr_addr)
        self.dut.rd_en_a_i.value = 1 if valid and rd_en_a else 0
        self.dut.rd_addr_a_i.value = int(rd_addr_a)
        self.dut.rd_en_b_i.value = 1 if valid and rd_en_b else 0
        self.dut.rd_addr_b_i.value = int(rd_addr_b)

    def input_accepted(self):
        return self.last_valid

    def output_value(self):
        data_a = None if not self.dut.data_a_o.value.is_resolvable else int(self.dut.data_a_o.value)
        data_b = None if not self.dut.data_b_o.value.is_resolvable else int(self.dut.data_b_o.value)
        if data_a is None and data_b is None:
            return None
        return data_a, data_b


async def clock_test(dut):
    await Timer(100, unit="ns")
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await Timer(10, unit="ns")


async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.wr_en_i.value = 0
    dut.rd_en_a_i.value = 0
    dut.rd_en_b_i.value = 0
    dut.data_i.value = 0
    dut.wr_addr_i.value = 0
    dut.rd_addr_a_i.value = 0
    dut.rd_addr_b_i.value = 0
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)


def random_stream(width, depth, count, mode):
    mask = (1 << width) - 1
    stream = []
    for _ in range(count):
        wr_en = random.randint(0, 1)
        wr_addr = random.randint(0, depth - 1)
        data = random.randint(0, mask)

        if mode == "a_only":
            rd_en_a = random.randint(0, 1)
            rd_addr_a = random.randint(0, depth - 1)
            rd_en_b = 0
            rd_addr_b = 0
        elif mode == "b_only":
            rd_en_a = 0
            rd_addr_a = 0
            rd_en_b = random.randint(0, 1)
            rd_addr_b = random.randint(0, depth - 1)
        elif mode == "same_addr":
            rd_en_a = random.randint(0, 1)
            rd_addr_a = random.randint(0, depth - 1)
            rd_en_b = rd_en_a
            rd_addr_b = rd_addr_a
        else:
            rd_en_a = random.randint(0, 1)
            rd_addr_a = random.randint(0, depth - 1)
            rd_en_b = random.randint(0, 1)
            rd_addr_b = random.randint(0, depth - 1)

        stream.append((wr_en, wr_addr, data, rd_en_a, rd_addr_a, rd_en_b, rd_addr_b))
    return stream


@cocotb.test(skip=False)
async def test_sync_ram_block_a_only(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(
        dut,
        random_stream(int(dut.WIDTH_P.value), int(dut.DEPTH_P.value), 500, "a_only"),
    ).run()


@cocotb.test(skip=False)
async def test_sync_ram_block_b_only(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(
        dut,
        random_stream(int(dut.WIDTH_P.value), int(dut.DEPTH_P.value), 500, "b_only"),
    ).run()


@cocotb.test(skip=False)
async def test_sync_ram_block_both_random(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(
        dut,
        random_stream(int(dut.WIDTH_P.value), int(dut.DEPTH_P.value), 500, "both_random"),
    ).run()


@cocotb.test(skip=False)
async def test_sync_ram_block_both_same_addr(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(
        dut,
        random_stream(int(dut.WIDTH_P.value), int(dut.DEPTH_P.value), 500, "same_addr"),
    ).run()
