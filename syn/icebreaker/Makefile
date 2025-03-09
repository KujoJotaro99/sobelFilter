SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

TOP := sobel
RTL_DIR := ../../rtl/sobel
FILELIST := $(RTL_DIR)/filelist.json
PCF := icebreaker.pcf
BUILD := build
LOGS := $(BUILD)/logs

YOSYS := yosys
NEXTPNR := nextpnr-ice40
ICEPACK := icepack
SEED ?= 14
DEVICE := up5k
PACKAGE := sg48

VERILOG_SOURCES := $(shell python3 -c "import json; \
    j=json.load(open('$(FILELIST)')); \
    print(' '.join('$(RTL_DIR)/' + f for f in j['files']))")

JSON := $(BUILD)/$(TOP).json
ASC := $(BUILD)/$(TOP).asc
BIN := $(BUILD)/$(TOP).bin

.PHONY: synth place prog report abstract clean

synth:
	mkdir -p $(BUILD) $(LOGS)
	$(YOSYS) -p "read_verilog -sv $(VERILOG_SOURCES); synth_ice40 -top $(TOP) -json $(JSON)" > $(LOGS)/synth.log 2>&1

place:
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --json $(JSON) --pcf $(PCF) --asc $(ASC) --seed $(SEED) > $(LOGS)/place.log 2>&1

bit:
	$(ICEPACK) $(ASC) $(BIN) > $(LOGS)/bitstream.log 2>&1

abstract:
	netlistsvg $(JSON) -o $(BUILD)/$(TOP).svg
	@if command -v rsvg-convert >/dev/null 2>&1; then rsvg-convert -f pdf -o $(BUILD)/$(TOP).pdf $(BUILD)/$(TOP).svg; elif command -v inkscape >/dev/null 2>&1; then inkscape $(BUILD)/$(TOP).svg --export-type=pdf --export-filename=$(BUILD)/$(TOP).pdf; else echo 'warning: rsvg-convert or inkscape not found, skipping pdf export'; fi

clean:
	rm -rf $(BUILD)
