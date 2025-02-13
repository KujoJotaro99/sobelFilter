import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLOCK_PERIOD_NS = 10


class ModelManager:
    def __init__(self, dut):
        self.queue = deque()

    def run(self, input_data):
        self.queue.append(int(input_data))


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
        self.pending = deque()
        self.outputs_received = 0
        self.pipeline_delay = 0

    def update_expected(self, input_data):
        self.model.run(input_data)

    def check_output(self, output):
        if output is None:
            return False

        self.outputs_received += 1
        if self.outputs_received <= self.pipeline_delay or not self.model.queue:
            return False

        expected = self.model.queue.popleft()
        assert int(output) == int(expected), f"Mismatch got {int(output)} exp {int(expected)}"
        self.pending.append(output)
        return True


class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        self.expected_outputs = sum(1 for item in stream if item is not None)
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

                self.handshake.dut.ready_i.value = 1 if (cycle % self.out_stride) == 0 else 0

                if self.handshake.output_accepted():
                    if self.scoreboard.check_output(self.handshake.output_value()):
                        self.checked += 1

                if (cycle % self.in_stride) == 0:
                    if self.handshake.input_accepted():
                        input_data = self.input.accept()
                        if input_data is not None:
                            self.scoreboard.update_expected(input_data)
                    self.input.drive(self.handshake)
                else:
                    self.handshake.drive(False, 0)
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0


class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.data_i.value = int(data)

    def input_accepted(self):
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)

    def output_accepted(self):
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        if not self.dut.data_o.value.is_resolvable:
            return None
        return int(self.dut.data_o.value)


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
async def test_fifo_sync_reset(dut):
    await clock_test(dut)
    await reset_test(dut)
    dut.valid_i.value = 0

    for cycle in range(10):
        await FallingEdge(dut.clk_i)
        assert dut.valid_o.value == 0, f"valid_o should stay low after {cycle + 1} cycles"


@cocotb.test(skip=False)
async def test_fifo_sync_stream(dut):
    await clock_test(dut)
    await reset_test(dut)
    random.seed(42)
    env = TestManager(dut, random_stream(int(dut.WIDTH_P.value), 1000))
    env.out_stride = 2
    await env.run()
    assert env.checked == env.expected_outputs
