SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --no-builtin-rules --warn-undefined-variables
.DEFAULT_GOAL := build

PYTHON ?= python3
CURL ?= curl
WIT_BINDGEN ?= wit-bindgen
WASM_TOOLS ?= wasm-tools
WASI_P2_CC ?= wasm32-wasip2-clang
export TMPDIR := $(abspath build.nosync/tmp)
export PYTHONPYCACHEPREFIX := $(abspath build.nosync/pycache)
export XDG_CACHE_HOME := $(abspath build.nosync/cache)

LUA_DIR := src/vendor/lua
LUA_SOURCES := lapi.c lauxlib.c lbaselib.c lcode.c lcorolib.c lctype.c ldebug.c ldo.c ldump.c lfunc.c lgc.c llex.c lmathlib.c lmem.c loadlib.c lobject.c lopcodes.c lparser.c lstate.c lstring.c lstrlib.c ltable.c ltablib.c ltm.c lundump.c lutf8lib.c lvm.c lzio.c
COMPONENT_SOURCES := src/component.c src/shim/wasm_setjmp_shim.c src/shim/wasm_eh_tags.s $(addprefix $(LUA_DIR)/,$(LUA_SOURCES))
COMPONENT_HEADERS := $(wildcard src/*.h src/shim/*.h $(LUA_DIR)/*.h)
WIT_SOURCES := $(shell find src/wit -type f -name '*.wit' | sort)
component_compile_flags = -I$(1)/bindings -I$(1) -O2 -DNDEBUG $(COMPONENT_CFLAGS)
COMPONENT_CFLAGS := -Dl_signalT=int -I$(LUA_DIR) -Isrc -mexception-handling -mmultivalue -mreference-types -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false

.PHONY: build package test clean open serve-docs validate-docs docs compile_commands.json
build: build.nosync/plugin.lua.wasm
package: build.nosync/plugin.lua.wasm build.nosync/LICENSE build.nosync/NOTICE build.nosync/SHA256SUMS

# Each build has its own generated bindings and bootstrap header. Tests never
# create the release component or package files.
define component_rules
$(1)/runtime.h: src/runtime.lua Makefile | build.nosync/tmp
	@mkdir -p "$$(@D)"
	@$(PYTHON) -c 'import json, pathlib, sys; source = pathlib.Path(sys.argv[1]).read_text(); pathlib.Path(sys.argv[2]).write_text("static const char runtime_bootstrap[] =\n" + json.dumps(source) + ";\n")' "$$<" "$$@"

$(1)/bindings/lua_plugin.h $(1)/bindings/lua_plugin.c $(1)/bindings/lua_plugin_component_type.o &: $(WIT_SOURCES) Makefile | build.nosync/tmp
	@mkdir -p "$(1)/bindings"
	@(cd "$(1)/bindings" && $(WIT_BINDGEN) c "$(abspath src/wit)" -w gams:lua/lua-plugin@1.0.0)

$(1)/plugin.lua.unstripped.wasm: $(COMPONENT_SOURCES) $(COMPONENT_HEADERS) $(1)/bindings/lua_plugin.h $(1)/bindings/lua_plugin.c $(1)/bindings/lua_plugin_component_type.o $(1)/runtime.h Makefile
	@$(WASI_P2_CC) -o "$$@" -mexec-model=reactor $(call component_compile_flags,$(1)) \
		"$(1)/bindings/lua_plugin.c" $(COMPONENT_SOURCES) \
		"$(1)/bindings/lua_plugin_component_type.o" -Wl,--strip-all

$(1)/plugin.lua.stripped.wasm: $(1)/plugin.lua.unstripped.wasm Makefile
	@$(WASM_TOOLS) strip -a "$$<" -o "$$@"

$(1)/plugin.lua.wasm: $(1)/plugin.lua.stripped.wasm LICENSE NOTICE licenses/THIRD-PARTY.txt scripts/embed-notices.py Makefile
	@$(PYTHON) -B scripts/embed-notices.py "$$<" "$$@"
endef
$(eval $(call component_rules,build.nosync))
$(eval $(call component_rules,build.nosync/test))

compile_commands.json: build.nosync/compile_commands.json

build.nosync/compile_commands.json: Makefile flake.nix flake.lock scripts/compile-commands.py $(COMPONENT_SOURCES) $(COMPONENT_HEADERS) build.nosync/runtime.h build.nosync/bindings/lua_plugin.h build.nosync/bindings/lua_plugin.c | build.nosync/tmp
	@$(PYTHON) scripts/compile-commands.py "$(WASI_P2_CC)" $(call component_compile_flags,build.nosync) -- build.nosync/bindings/lua_plugin.c $(COMPONENT_SOURCES) > "$@.tmp"
	@mv "$@.tmp" "$@"

build.nosync/tmp:
	@mkdir -p "$@"

build.nosync/LICENSE: LICENSE Makefile
	@mkdir -p "$(@D)"
	@cp "$<" "$@"

build.nosync/NOTICE: NOTICE licenses/THIRD-PARTY.txt Makefile
	@mkdir -p "$(@D)"
	@cat NOTICE licenses/THIRD-PARTY.txt > "$@"

build.nosync/SHA256SUMS: build.nosync/plugin.lua.wasm build.nosync/LICENSE build.nosync/NOTICE Makefile
	@cd build.nosync && shasum -a 256 plugin.lua.wasm LICENSE NOTICE > SHA256SUMS

test: build.nosync/test/plugin.lua.wasm
	@bash scripts/test-runtime-component.sh

clean:
	@$(PYTHON) scripts/clean.py

GAMS_RELEASE_API ?= https://api.github.com/repos/kkgams/gams/releases/latest
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
DOCS_PORT ?= 8080
WIKI_VERSION := v1.4.0
WIKI_REPOSITORY := https://github.com/justgook/wiki
WIKI_MAKEFILE := build.nosync/wiki-$(WIKI_VERSION).mk
WIKI_ENGINE := $(abspath build.nosync/wiki-$(WIKI_VERSION))

# Retain an existing app; never update it implicitly.
tools/gams.app:
	@test "$(UNAME_S)" = Darwin && test "$(UNAME_M)" = arm64 || \
		{ echo 'GAMS release download requires macOS Apple Silicon' >&2; exit 1; }
	@test ! -e tools/gams-release-notices || \
		{ echo 'tools/gams-release-notices already exists; move it aside before reinstalling GAMS' >&2; exit 1; }
	@mkdir -p tools build.nosync/tmp
	@set -eu; stage=$$(mktemp -d "build.nosync/tmp/gams-download.XXXXXX"); \
		trap 'rm -rf "$$stage"' EXIT; \
		$(CURL) --fail --location --silent --show-error "$(GAMS_RELEASE_API)" --output "$$stage/release.json"; \
		url=$$($(PYTHON) -c 'import json, sys; release = json.load(open(sys.argv[1])); assets = [a for a in release["assets"] if a["name"].startswith("GAMS-") and a["name"].endswith("-macos-aarch64.zip")]; assert len(assets) == 1, "Expected exactly one GAMS macOS Apple Silicon ZIP asset"; print(assets[0]["browser_download_url"])' "$$stage/release.json"); \
		$(CURL) --fail --location --silent --show-error "$$url" --output "$$stage/gams.zip"; \
		unzip -q "$$stage/gams.zip" -d "$$stage/unpacked"; \
		test -f "$$stage/unpacked/GAMS.app/Contents/Info.plist"; \
		test -x "$$stage/unpacked/GAMS.app/Contents/MacOS/gams"; \
		mv "$$stage/unpacked/GAMS.app" "$$stage/GAMS.app"; \
		mv "$$stage/unpacked" tools/gams-release-notices; \
		mv "$$stage/GAMS.app" "$@"

open: build tools/gams.app
	GAMS_APP_CWD="$(CURDIR)" GAMS_CONFIG="gams.json" ./tools/gams.app/Contents/MacOS/gams

$(WIKI_MAKEFILE): | build.nosync/tmp
	@mkdir -p "$(@D)"
	@trap 'rm -f "$@.tmp"' EXIT
	@$(CURL) --fail --location --retry 3 "$(WIKI_REPOSITORY)/raw/$(WIKI_VERSION)/Makefile" -o "$@.tmp"
	@mv "$@.tmp" "$@"

serve-docs validate-docs docs: $(WIKI_MAKEFILE)
	$(MAKE) -f "$(WIKI_MAKEFILE)" "$(if $(filter docs,$@),build,$(patsubst %-docs,%,$@))" WIKI_REPOSITORY="$(WIKI_REPOSITORY)" WIKI_VERSION="$(WIKI_VERSION)" WIKI_ENGINE="$(WIKI_ENGINE)" WIKI_SOURCE="$(abspath docs)" WIKI_OUTPUT="$(abspath build.nosync/site)" PORT="$(DOCS_PORT)"
