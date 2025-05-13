FILELIST_JSON := filelist.json

json = $(shell python3 -c "import json; v = json.load(open('$(FILELIST_JSON)'))['$(1)']; print(' '.join(v) if isinstance(v, list) else v)")

TOPLEVEL := $(call json,top)
RTL_SOURCES := $(call json,files)
TEST_TOP := $(call json,test_top)
TEST_SOURCES := $(call json,test_files)
SOURCES := $(addprefix ../,$(RTL_SOURCES) $(TEST_SOURCES))

# vcs, xrun, or questa
SIM ?= vcs
SEED ?= 1

BUILD := build
SYNTH_JSON := $(BUILD)/$(TOPLEVEL).json
ICE40_JSON := $(BUILD)/$(TOPLEVEL).ice40.json

.PHONY: test lint synth synth_ice40 clean

test: | $(BUILD)
ifeq ($(SIM),vcs)
	cd $(BUILD) && vcs -full64 -sverilog -assert svaext -timescale=1ns/1ps -top $(TEST_TOP) $(SOURCES) -o simv
	cd $(BUILD) && ./simv +ntb_random_seed=$(SEED)
else ifeq ($(SIM),xrun)
	cd $(BUILD) && xrun -sv -access +rwc -timescale 1ns/1ps -svseed $(SEED) -top $(TEST_TOP) $(SOURCES)
else ifeq ($(SIM),questa)
	cd $(BUILD) && vlog -sv $(SOURCES) && vsim -c -sv_seed $(SEED) $(TEST_TOP) -do "run -all; quit -f"
else
	$(error unsupported SIM=$(SIM), use vcs, xrun, or questa)
endif

lint:
	verilator --lint-only -Wall --sv $(RTL_SOURCES) --top-module $(TOPLEVEL)

$(BUILD):
	mkdir -p $(BUILD)

synth: $(SYNTH_JSON)

$(SYNTH_JSON): $(RTL_SOURCES) | $(BUILD)
	yosys -p "read_verilog -sv $(RTL_SOURCES); synth -top $(TOPLEVEL); write_json $(SYNTH_JSON)"

synth_ice40: $(ICE40_JSON)

$(ICE40_JSON): $(RTL_SOURCES) | $(BUILD)
	yosys -p "read_verilog -sv $(RTL_SOURCES); synth_ice40 -top $(TOPLEVEL) -json $(ICE40_JSON)"

clean:
	rm -rf $(BUILD) csrc simv* ucli.key *.vcd *.fst *.vpd xcelium.d xrun.* work transcript
