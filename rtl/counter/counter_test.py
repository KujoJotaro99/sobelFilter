import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLOCK_PERIOD_NS = 10


class ModelManager:
    def __init__(self, dut):
        self.width = int(dut.WIDTH_P.value)
        self.max_val = int(dut.MAX_VAL_P.value)
        self.count = 0

    def run(self, input_data):
        en, up, down = input_data

        if en:
            if up and not down:
                self.count = 0 if self.count == self.max_val else self.count + 1
            elif down and not up:
                self.count = self.max_val if self.count == 0 else self.count - 1

        return self.count


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
        handshake.drive(self.valid, self.current if self.valid else (0, 0, 0))

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
        self.pending.append(self.model.run(input_data))

    def check_output(self, output):
        if output is None:
            return False

        self.outputs_received += 1
        if self.outputs_received <= self.pipeline_delay or not self.pending:
            return False

        expected = self.pending.pop(0)
        assert int(output) == int(expected), f"Mismatch: got {int(output)} expected {int(expected)}"
        return True


class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.model = ModelManager(dut)
        self.scoreboard = ScoreManager(self.model)
        self.expected_outputs = len(stream)
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
                    self.handshake.drive(False, (0, 0, 0))

                if (cycle % self.out_stride) == 0:
                    if self.scoreboard.pending:
                        if self.scoreboard.check_output(self.handshake.output_value()):
                            self.checked += 1
        finally:
            self.handshake.dut.en_i.value = 0
            self.handshake.dut.up_i.value = 0
            self.handshake.dut.down_i.value = 0


class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut
        self.last_valid = False

    def drive(self, valid, data):
        en, up, down = data
        self.last_valid = bool(valid)

        self.dut.en_i.value = 1 if en else 0
        self.dut.up_i.value = 1 if up else 0
        self.dut.down_i.value = 1 if down else 0

    def input_accepted(self):
        return self.last_valid

    def output_value(self):
        if not self.dut.count_o.value.is_resolvable:
            return None
        return int(self.dut.count_o.value)


async def clock_test(dut):
    await Timer(100, unit="ns")
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await Timer(10, unit="ns")


async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.rstn_data_i.value = 0
    dut.en_i.value = 0
    dut.up_i.value = 0
    dut.down_i.value = 0
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await FallingEdge(dut.clk_i)


def random_stream(count):
    stream = []
    for _ in range(count):
        choice = random.randint(0, 2)
        stream.append((1, 1 if choice == 1 else 0, 1 if choice == 2 else 0))
    return stream


@cocotb.test(skip=False)
async def test_counter_stream(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(dut, random_stream(300)).run()
