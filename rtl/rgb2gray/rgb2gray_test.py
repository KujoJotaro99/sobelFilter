from pathlib import Path

import cv2 as cv
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLOCK_PERIOD_NS = 10


class ModelManager:
    def __init__(self, dut):
        self.width = int(dut.WIDTH_P.value)

    def run(self, input_data):
        red, green, blue = input_data
        return int((red * 0.299) + (green * 0.587) + (blue * 0.114))


class InputManager:
    def __init__(self, stream):
        self.data = list(np.asarray(stream).reshape(-1, 3))
        self.index = 0
        self.valid = False
        self.current = None

    def drive(self, handshake):
        if not self.valid and self.index < len(self.data):
            self.current = tuple(int(value) for value in self.data[self.index])
            self.valid = True
        handshake.drive(self.valid, self.current if self.valid else (0, 0, 0))

    def accept(self):
        if self.valid:
            self.index += 1
            self.valid = False
            return self.current
        return None


class ScoreManager:
    def __init__(self, model, expected_outputs, rms_threshold=13):
        self.model = model
        self.expected_outputs = expected_outputs
        self.rms_threshold = rms_threshold
        self.pending = []
        self.sse = 0
        self.checked = 0
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
        error = int(output) - int(expected)
        self.sse += error * error
        self.checked += 1

        if self.checked == self.expected_outputs:
            rms = float(np.sqrt(self.sse / self.checked))
            assert rms < self.rms_threshold, f"RMS error too high: {rms} (threshold {self.rms_threshold})"

        return True


class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.expected_outputs = len(self.input.data)
        self.scoreboard = ScoreManager(ModelManager(dut), self.expected_outputs)
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
                    self.handshake.drive(False, (0, 0, 0))
        finally:
            self.handshake.dut.valid_i.value = 0
            self.handshake.dut.ready_i.value = 0
            self.handshake.dut.red_i.value = 0
            self.handshake.dut.green_i.value = 0
            self.handshake.dut.blue_i.value = 0


class HandshakeManager:
    def __init__(self, dut):
        self.dut = dut

    def drive(self, valid, data):
        red, green, blue = data
        self.dut.valid_i.value = 1 if valid else 0
        self.dut.red_i.value = int(red)
        self.dut.green_i.value = int(green)
        self.dut.blue_i.value = int(blue)

    def input_accepted(self):
        return bool(self.dut.valid_i.value and self.dut.ready_o.value)

    def output_accepted(self):
        return bool(self.dut.valid_o.value and self.dut.ready_i.value)

    def output_value(self):
        if not self.dut.gray_o.value.is_resolvable:
            return None
        return int(self.dut.gray_o.value)


async def clock_test(dut):
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await Timer(5 * CLOCK_PERIOD_NS, unit="ns")


async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.valid_i.value = 0
    dut.ready_i.value = 0
    dut.red_i.value = 0
    dut.green_i.value = 0
    dut.blue_i.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)


@cocotb.test()
async def single_zeroes_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(dut, np.zeros((100, 3), dtype=np.uint8)).run()


@cocotb.test()
async def single_ones_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    await TestManager(dut, np.ones((100, 3), dtype=np.uint8)).run()


@cocotb.test()
async def single_impulse_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    stream = np.zeros((100, 3), dtype=np.uint8)
    stream[50, :] = 1
    await TestManager(dut, stream).run()


@cocotb.test()
async def single_alternate_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    stream = np.zeros((100, 3), dtype=np.uint8)
    stream[::2, :] = 1
    await TestManager(dut, stream).run()


@cocotb.test()
async def single_random_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    np.random.seed(42)
    await TestManager(dut, np.random.randint(0, 256, size=(100, 3), dtype=np.uint8)).run()


@cocotb.test()
async def single_image_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img_path = Path(__file__).resolve().parents[2] / "jupyter" / "car.jpg"
    img = cv.imread(str(img_path), cv.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(img_path)
    img = cv.cvtColor(img, cv.COLOR_BGR2RGB)
    await TestManager(dut, img[:, : int(dut.WIDTH_P.value), :]).run()
