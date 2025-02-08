SIM ?= icarus
TOPLEVEL_LANG ?= verilog

FILELIST_JSON := filelist.json

RTL_SOURCES := $(shell python3 -c "import json; \
    j=json.load(open('$(FILELIST_JSON)')); \
    print(' '.join(j['files']))")

VERILOG_SOURCES := $(RTL_SOURCES)

TOPLEVEL := $(shell python3 -c "import json; \
    print(json.load(open('$(FILELIST_JSON)'))['top'])")

BUILD := build
SYNTH_JSON := $(BUILD)/$(TOPLEVEL).json
ICE40_JSON := $(BUILD)/$(TOPLEVEL).ice40.json
ABSTRACT_JSON ?= $(ICE40_JSON)
	
MODULE := ramdelaybuffer_test

COCOTB_LOG_LEVEL ?= INFO

COMPILE_ARGS += -g2012

WAVES ?= 1

# TB_SV := ramdelaybuffer_tb.sv

ifneq ($(filter sv,$(MAKECMDGOALS)),)
    # skip cocotb include for pure SystemVerilog run
else
include $(shell cocotb-config --makefile)/Makefile.sim
endif

.PHONY: clean
clean::
	rm -rf sim_build __pycache__ .pytest_cache *.pyc *.vcd *.fst results.xml sim_sv build


.PHONY: sweep

sweep:
	$(MAKE) WIDTH_P=8
	$(MAKE) WIDTH_P=16
	$(MAKE) WIDTH_P=32

lint:
	verilator --lint-only $(RTL_SOURCES) --top-module $(TOPLEVEL)

$(BUILD):
	mkdir -p $(BUILD)

.PHONY: synth
synth: $(SYNTH_JSON)

$(SYNTH_JSON): $(RTL_SOURCES) | $(BUILD)
	yosys -p "read_verilog -sv $(RTL_SOURCES); synth -top $(TOPLEVEL); write_json $(SYNTH_JSON)"

.PHONY: synth_ice40
synth_ice40: $(ICE40_JSON)

$(ICE40_JSON): $(RTL_SOURCES) | $(BUILD)
	yosys -p "read_verilog -sv $(RTL_SOURCES); synth_ice40 -top $(TOPLEVEL) -json $(ICE40_JSON)"


.PHONY: python
python: sim

.PHONY: sv
# sv: clean
# 	iverilog $(COMPILE_ARGS) -s ramdelaybuffer_tb -o sim_sv $(VERILOG_SOURCES) $(TB_SV)
# 	vvp sim_sv



.PHONY: abstract
abstract:
	netlistsvg $(ABSTRACT_JSON) -o $(BUILD)/$(TOPLEVEL).svg
	@if command -v rsvg-convert >/dev/null 2>&1; then \
		rsvg-convert -f pdf -o $(BUILD)/$(TOPLEVEL).pdf $(BUILD)/$(TOPLEVEL).svg; \
	elif command -v inkscape >/dev/null 2>&1; then \
		inkscape $(BUILD)/$(TOPLEVEL).svg --export-type=pdf --export-filename=$(BUILD)/$(TOPLEVEL).pdf; \
	else \
		echo 'warning: rsvg-convert or inkscape not found, skipping pdf export'; \
	fi
