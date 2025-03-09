#!/usr/bin/env python3
import argparse
import time
import threading
from pathlib import Path
import serial
from PIL import Image

W, H, BAUD = 640, 480, 220588

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("image", nargs="?", type=Path)
    args = parser.parse_args()

    img_path = args.image or Path(__file__).parents[2] / "jupyter" / "mountain.jpg"
    if not img_path.exists():
        raise SystemExit("Image not found")

    tx = Image.open(img_path).convert("RGB").resize((W, H), Image.BILINEAR).tobytes()
    rx_buf = bytearray()
    stop = threading.Event()

    def reader():
        while not stop.is_set() and len(rx_buf) < len(tx):
            chunk = ser.read(min(4096, len(tx) - len(rx_buf)))
            if chunk:
                rx_buf.extend(chunk)
            else:
                time.sleep(0.002)

    with serial.Serial(args.port, BAUD, timeout=0.1, rtscts=False, dsrdtr=False, xonxoff=False) as ser:
        ser.dtr = ser.rts = False
        time.sleep(0.2)
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        threading.Thread(target=reader, daemon=True).start()
        
        for i in range(0, len(tx), 2048):
            ser.write(tx[i:i+2048])
            ser.flush()

        while len(rx_buf) < len(tx):
            time.sleep(0.01)
        stop.set()

    warmup = (2 * W + 2) * 3
    Image.frombytes("RGB", (W, H), bytes(rx_buf[warmup:]) + b"\x00" * warmup).save("sobel_out.png")
    print("Wrote sobel_out.png")

if __name__ == "__main__":
    main()