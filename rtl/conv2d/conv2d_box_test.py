from pathlib import Path

import cv2 as cv
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer

CLOCK_PERIOD_NS = 10


class ModelManager:
    kernel = np.array([[1, 2, 1], [2, 4, 2], [1, 2, 1]], dtype=np.int32)

    def __init__(self, dut):
        self.width = int(dut.DEPTH_P.value)
        self.buffer = np.full((3, self.width), np.nan)

    def run(self, input_data):
        flat = np.roll(self.buffer.flatten(), -1)
        flat[-1] = int(input_data)
        self.buffer = flat.reshape(self.buffer.shape)

        window = self.buffer[:, -3:]
        if np.isnan(window).any():
            return None

        return int(np.sum(window * self.kernel) // 16)


class InputManager:
    def __init__(self, stream):
        self.data = list(np.asarray(stream).flatten())
        self.index = 0
        self.valid = False
        self.current = None

    def drive(self, handshake):
        if not self.valid and self.index < len(self.data):
            self.current = int(self.data[self.index])
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
        self.pending = []
        self.outputs_received = 0
        self.pipeline_delay = 0

    def update_expected(self, input_data):
        expected = self.model.run(input_data)
        if expected is not None:
            self.pending.append(expected)

    def check_output(self, output):
        if output is None:
            return False

        self.outputs_received += 1
        if self.outputs_received <= self.pipeline_delay or not self.pending:
            return False

        gx_out, gy_out = output
        expected = self.pending.pop(0)
        assert int(gx_out) == int(expected), f"Mismatch gx: got {int(gx_out)} expected {int(expected)}"
        assert int(gy_out) == int(expected), f"Mismatch gy: got {int(gy_out)} expected {int(expected)}"
        return True


class TestManager:
    def __init__(self, dut, stream):
        self.handshake = HandshakeManager(dut)
        self.input = InputManager(stream)
        self.scoreboard = ScoreManager(ModelManager(dut))
        height, width = np.asarray(stream).shape
        self.expected_outputs = max(0, (height - 2) * (width - 2))
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
            self.handshake.dut.data_i.value = 0


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
        if not self.dut.gx_o.value.is_resolvable or not self.dut.gy_o.value.is_resolvable:
            return None
        return self.dut.gx_o.value.to_signed(), self.dut.gy_o.value.to_signed()


async def clock_test(dut):
    await Timer(100, unit="ns")
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await Timer(10, unit="ns")


async def reset_test(dut):
    dut.rstn_i.value = 0
    dut.valid_i.value = 0
    dut.ready_i.value = 0
    dut.data_i.value = 0
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1
    await Timer(10 * CLOCK_PERIOD_NS, unit="ns")
    await FallingEdge(dut.clk_i)


@cocotb.test()
async def single_zeroes_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    await TestManager(dut, np.zeros((4 * width, width), dtype=np.uint8)).run()


@cocotb.test()
async def single_ones_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    await TestManager(dut, np.ones((4 * width, width), dtype=np.uint8)).run()


@cocotb.test()
async def single_impulse_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.zeros((height, width), dtype=np.uint8)
    stream[height // 2, width // 2] = 1
    await TestManager(dut, stream).run()


@cocotb.test()
async def single_alternate_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    height = 4 * width
    stream = np.zeros((height, width), dtype=np.uint8)
    stream[::2, ::2] = 1
    stream[1::2, 1::2] = 1
    await TestManager(dut, stream).run()


@cocotb.test()
async def single_random_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    width = int(dut.DEPTH_P.value)
    np.random.seed(42)
    await TestManager(dut, np.random.randint(0, 256, size=(4 * width, width), dtype=np.uint8)).run()


@cocotb.test()
async def single_image_test(dut):
    await clock_test(dut)
    await reset_test(dut)
    img_path = Path(__file__).resolve().parents[2] / "jupyter" / "car.jpg"
    img = cv.imread(str(img_path), cv.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(img_path)
    await TestManager(dut, img[:, : int(dut.DEPTH_P.value)]).run()
