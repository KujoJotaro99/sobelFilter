import os
import random
from pathlib import Path

import cv2 as cv
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

CLOCK_PERIOD_NS = 10
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path(__file__).resolve().parent / "out"


def reference(rgb, width):
    """Bit accurate software model of the core on a flattened pixel stream."""
    r = rgb[..., 0].astype(np.int64).ravel()
    g = rgb[..., 1].astype(np.int64).ravel()
    b = rgb[..., 2].astype(np.int64).ravel()

    # rgb2gray shift and add approximation
    gray = (((r >> 2) + (r >> 5)) + ((g >> 1) + (g >> 4)) + ((b >> 4) + (b >> 5))) & 0xFF

    def window(stream, k):
        # 3x3 window over the flattened stream, newest pixel at k
        rows = [k - 2 * width, k - width, k]
        return np.array([[stream[i - 2], stream[i - 1], stream[i]] for i in rows])

    n = gray.size
    start = 2 * width + 2

    # gaussian blur
    blur = np.zeros(n, dtype=np.int64)
    kernel = np.array([[1, 2, 1], [2, 4, 2], [1, 2, 1]])
    for k in range(start, n):
        blur[k] = int(np.sum(window(gray, k) * kernel)) >> 4

    # sobel and magnitude
    mag = np.zeros(n, dtype=np.int64)
    for k in range(2 * start, n):
        w = window(blur, k)
        gx = (w[:, 2] - w[:, 0]) @ np.array([1, 2, 1])
        gy = (w[2, :] - w[0, :]) @ np.array([1, 2, 1])
        # the core keeps the low WIDTH bits of each absolute value before the saturating add
        mag[k] = min((abs(gx) & 0xFF) + (abs(gy) & 0xFF), 255)
    return mag, 2 * start


@cocotb.test()
async def image_test(dut):
    name = os.environ.get("IMAGE", "car")
    stall = float(os.environ.get("STALL", "0.1"))
    width = int(dut.LINE_W_P.value)

    img = cv.imread(str(ROOT / "jupyter" / f"{name}.jpg"), cv.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(name)
    rgb = cv.cvtColor(img, cv.COLOR_BGR2RGB)
    assert rgb.shape[1] == width, f"image width {rgb.shape[1]} does not match LINE_W_P {width}"
    pixels = rgb.reshape(-1, 3)
    n = len(pixels)

    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    dut.rstn_i.value = 0
    dut.valid_i.value = 0
    dut.ready_i.value = 0
    for _ in range(4):
        await FallingEdge(dut.clk_i)
    dut.rstn_i.value = 1

    random.seed(1)
    idx = 0
    out = []
    while len(out) < n:
        await FallingEdge(dut.clk_i)
        if idx < n:
            red, green, blue = pixels[idx]
            dut.red_i.value = int(red)
            dut.green_i.value = int(green)
            dut.blue_i.value = int(blue)
            dut.valid_i.value = 1
        else:
            dut.valid_i.value = 0
        # random output stalls to exercise backpressure
        dut.ready_i.value = 0 if random.random() < stall else 1

        # handshakes resolve before the next rising edge
        await Timer(1, unit="ns")
        accept = bool(dut.valid_i.value) and bool(dut.ready_o.value)
        transfer = bool(dut.valid_o.value) and bool(dut.ready_i.value)
        if transfer:
            out.append(int(dut.mag_o.value) if dut.mag_o.value.is_resolvable else 0)
        await RisingEdge(dut.clk_i)
        if accept:
            idx += 1

    hw = np.array(out, dtype=np.int64)
    ref, warmup = reference(rgb, width)
    mismatches = int(np.count_nonzero(hw[warmup:] != ref[warmup:]))
    dut._log.info(f"{name}: {n} pixels, {mismatches} mismatches after {warmup} warmup pixels")

    OUT_DIR.mkdir(exist_ok=True)
    shape = rgb.shape[:2]
    hw_img = hw.reshape(shape).astype(np.uint8)
    ref_img = ref.reshape(shape).astype(np.uint8)
    cv.imwrite(str(OUT_DIR / f"{name}_hw.png"), hw_img)
    cv.imwrite(str(OUT_DIR / f"{name}_ref.png"), ref_img)

    # input, hardware output, and reference side by side
    labels = ["input", "sobel (RTL)", "software model"]
    tiles = [img, cv.cvtColor(hw_img, cv.COLOR_GRAY2BGR), cv.cvtColor(ref_img, cv.COLOR_GRAY2BGR)]
    for tile, label in zip(tiles, labels):
        cv.putText(tile, label, (10, 30), cv.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2)
    cv.imwrite(str(OUT_DIR / f"{name}_compare.png"), np.hstack(tiles))

    assert mismatches == 0, f"{mismatches} pixels differ from the software model"
