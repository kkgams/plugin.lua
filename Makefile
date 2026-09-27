SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --no-builtin-rules --warn-undefined-variables

include config.mk

BUILD_DIR ?= build
DIST_DIR ?= dist
ODIN ?= odin
WIT_BINDGEN ?= wit-bindgen
WASM_TOOLS ?= wasm-tools
WASI_P2_CC ?= wasm32-wasip2-clang
NPM ?= npm
NODE ?= node

SOURCE_FILES := $(shell find src -type f | sort)
WIT_SOURCES := $(filter %.wit,$(SOURCE_FILES))
GEN_DIR := $(BUILD_DIR)/bindings
ODIN_OBJ := $(BUILD_DIR)/core.o.wasm
UNSTRIPPED := $(BUILD_DIR)/$(REPOSITORY).unstripped.wasm
COMPONENT := $(DIST_DIR)/$(REPOSITORY).wasm
TRANSPILED := $(BUILD_DIR)/jco/$(REPOSITORY).js

ifeq ($(HAS_ODIN),1)
CORE_OBJECT := $(ODIN_OBJ)
else
CORE_OBJECT :=
endif

ifeq ($(HAS_LUA),1)
TEST_ARTIFACT := $(COMPONENT)
LUA_DIR := src/vendor/lua
LUA_SOURCES := lapi.c lauxlib.c lbaselib.c lcode.c lcorolib.c lctype.c ldebug.c ldo.c ldump.c lfunc.c lgc.c llex.c lmathlib.c lmem.c loadlib.c lobject.c lopcodes.c lparser.c lstate.c lstring.c lstrlib.c ltable.c ltablib.c ltm.c lundump.c lutf8lib.c lvm.c lzio.c
COMPONENT_SOURCES := src/component.c src/shim/wasm_setjmp_shim.c src/shim/wasm_eh_tags.s $(addprefix $(LUA_DIR)/,$(LUA_SOURCES))
COMPONENT_CFLAGS := -Dl_signalT=int -I$(LUA_DIR) -Isrc -mexception-handling -mmultivalue -mreference-types -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false
else
TEST_ARTIFACT := $(TRANSPILED)
COMPONENT_SOURCES := src/component.c $(CORE_OBJECT)
COMPONENT_CFLAGS :=
endif

.PHONY: all build test clean check-tools
all: build
build: $(COMPONENT)

check-tools:
	@for tool in $(WIT_BINDGEN) $(WASM_TOOLS) $(WASI_P2_CC) $(NPM) $(NODE); do command -v "$$tool" >/dev/null || { echo "missing tool: $$tool" >&2; exit 1; }; done
	@if [ "$(HAS_ODIN)" = 1 ]; then command -v "$(ODIN)" >/dev/null || { echo "missing tool: $(ODIN)" >&2; exit 1; }; fi

$(DIST_DIR):
	@mkdir -p "$@"

$(ODIN_OBJ): $(wildcard src/*.odin) $(wildcard src/jsmn/*.odin)
	@mkdir -p "$(dir $@)"
	@rm -f "$@" "$(patsubst %.wasm,%.obj,$@)"
	@$(ODIN) build ./src -target:wasi_wasm32 -build-mode:obj --no-entry-point -o:speed -out:$@
	@if [ -f "$(patsubst %.wasm,%.obj,$@)" ]; then mv "$(patsubst %.wasm,%.obj,$@)" "$@"; fi
	@test -f "$@"

$(UNSTRIPPED): $(SOURCE_FILES) $(CORE_OBJECT) config.mk Makefile
	@rm -rf "$(GEN_DIR)"
	@mkdir -p "$(GEN_DIR)"
	@(cd "$(GEN_DIR)" && $(WIT_BINDGEN) c "$(abspath src/wit)" -w "$(WORLD)")
	@$(WASI_P2_CC) -o "$@" -mexec-model=reactor -I"$(GEN_DIR)" -O2 -DNDEBUG $(COMPONENT_CFLAGS) \
		"$(GEN_DIR)/$(COMPONENT_NAME).c" $(COMPONENT_SOURCES) \
		"$(GEN_DIR)/$(COMPONENT_NAME)_component_type.o" -Wl,--strip-all

$(COMPONENT): $(UNSTRIPPED) | $(DIST_DIR)
	@$(WASM_TOOLS) strip -a "$<" -o "$@"

node_modules/.package-lock.json: package.json package-lock.json
	@$(NPM) ci

$(TRANSPILED): $(COMPONENT) node_modules/.package-lock.json
	@rm -rf "$(BUILD_DIR)/jco"
	@./node_modules/.bin/jco transpile "$<" -o "$(BUILD_DIR)/jco" --name "$(REPOSITORY)"

test: check-tools $(TEST_ARTIFACT)
	@$(WASM_TOOLS) validate "$(COMPONENT)"
	@$(NODE) "$(TEST_SCRIPT)"

clean:
	@rm -rf "$(BUILD_DIR)" "$(DIST_DIR)" node_modules

# Distribution requires separately reviewed, nonempty licensing texts and repo vars.
.PHONY: release-candidate
release-candidate: test
	@COMPONENT_SLUG=lua bash scripts/stage-candidate.sh
	@$(MAKE) test
	@python3 scripts/wasm-notices.py verify "$(COMPONENT)" --license LICENSE --notice NOTICE
	@(cd "$(DIST_DIR)" && sha256sum --check SHA256SUMS)
