import random
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLOCK_PERIOD_NS = 10


class ModelManager:
    def __init__(self, dut):
        self.delay = int(dut.DELAY_P.value)
        self.delay_a = int(dut.DELAY_A_P.value)
        self.delay_b = int(dut.DELAY_B_P.value)
        self.buffer = np.full((self.delay + 1,), np.nan)

    def run(self, input_data):
        self.buffer = np.roll(self.buffer, -1)
        self.buffer[-1] = int(input_data)

        exp_a = self.buffer[-1 - self.delay_a]
        exp_b = self.buffer[-1 - self.delay_b]

        return (
            None if np.isnan(exp_a) else int(exp_a),
            None if np.isnan(exp_b) else int(exp_b),
        )


class InputManager:
    def __init__(self, stream):
        self.data = list(stream)
        self.index = 0
        self.valid = False
        self.current = None

    def drive(self, handshake):
        while not self.valid and self.index < len(self.data):
            item = self.data[self.index]
            if item is None:
                self.index += 1
                continue
            self.current = item
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else 0)

    def accept(self):
        if self.valid:
            self.index += 1
            self.valid = False
            return self.current
        return None


class ScoreManager:
    def __init__(self, model):
        self.model = model
        self.pending_a = []
        self.pending_b = []
        self.outputs_received = 0
        self.pipeline_delay = 0
        self.checked_a = 0
        self.checked_b = 0

    def update_expected(self, input_data):
        exp_a, exp_b = self.model.run(input_data)
        if exp_a is not None:
            self.pending_a.append(exp_a)
        if exp_b is not None:
            self.pending_b.append(exp_b)

    def check_output(self, output):
        if output is None:
            return False

        self.outputs_received += 1
        if self.outputs_received <= self.pipeline_delay:
            return False

        got_a, got_b = output
        matched = False

        if got_a is not None and self.pending_a:
            exp_a = self.pending_a.pop(0)
            assert int(got_a) == int(exp_a), f"Port A mismatch got {int(got_a)} exp {int(exp_a)}"
            self.checked_a += 1
            matched = True

        if got_b is not None and self.pending_b:
            exp_b = self.pending_b.pop(0)
            assert int(got_b) == int(exp_b), f"Port B mismatch got {int(got_b)} exp {int(exp_b)}"
            self.checked_b += 1
            matched = True

        return matched


class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        valid_inputs = sum(1 for item in stream if item is not None)
        self.expected_a = max(0, valid_inputs - self.model.delay_a)
        self.expected_b = max(0, valid_inputs - self.model.delay_b)

    async def run(self):
        try:
            self.input.drive(self.handshake)
            while self.scoreboard.checked_a < self.expected_a or self.scoreboard.checked_b < self.expected_b:
                await FallingEdge(self.handshake.dut.clk_i)

                if self.handshake.input_accepted():
                    input_data = self.input.accept()
                    if input_data is not None:
                        self.scoreboard.update_expected(input_data)

                if self.handshake.output_accepted():
                    self.scoreboard.check_output(self.handshake.output_value())

                self.input.drive(self.handshake)
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0
            self.handshake.dut.data_i.value = 0


class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.data_i.value = int(data)
        self.dut.ready_i.value = 1

    def input_accepted(self):
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)

    def output_accepted(self):
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

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
    dut.valid_i.value = 0
    dut.ready_i.value = 1
    dut.data_i.value = 0
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)


def random_stream(width, count):
    mask = (1 << width) - 1
    return [random.randint(0, mask) for _ in range(count)]


@cocotb.test(skip=False)
async def test_ramdelay_buffer_reset(dut):
    await clock_test(dut)
    await reset_test(dut)
    dut.valid_i.value = 0

    for cycle in range(10):
        await FallingEdge(dut.clk_i)
        assert dut.valid_o.value == 0, f"valid_o should stay low after {cycle + 1} cycles"


@cocotb.test(skip=False)
async def test_ramdelay_buffer_stream(dut):
    await clock_test(dut)
    await reset_test(dut)
    delay = int(dut.DELAY_P.value)
    env = TestManager(dut, random_stream(int(dut.WIDTH_P.value), (2 * delay) + 50))
    await env.run()
    assert env.scoreboard.checked_a == env.expected_a
    assert env.scoreboard.checked_b == env.expected_b
