PLUGIN_WASM_COMPONENT := 1
PLUGIN_WIT_WORLD := gams:lua/lua-plugin@1.0.0
PLUGIN_COMPONENT_NAME := lua_plugin

LUA_COMP_DIR := $(PLUGIN_PATH)/vendor/lua

PLUGIN_COMPONENT_SOURCES := \
  $(PLUGIN_PATH)/component.c \
  $(PLUGIN_PATH)/shim/wasm_setjmp_shim.c \
  $(PLUGIN_PATH)/shim/wasm_eh_tags.s \
  $(LUA_COMP_DIR)/lapi.c \
  $(LUA_COMP_DIR)/lauxlib.c \
  $(LUA_COMP_DIR)/lbaselib.c \
  $(LUA_COMP_DIR)/lcode.c \
  $(LUA_COMP_DIR)/lcorolib.c \
  $(LUA_COMP_DIR)/lctype.c \
  $(LUA_COMP_DIR)/ldebug.c \
  $(LUA_COMP_DIR)/ldo.c \
  $(LUA_COMP_DIR)/ldump.c \
  $(LUA_COMP_DIR)/lfunc.c \
  $(LUA_COMP_DIR)/lgc.c \
  $(LUA_COMP_DIR)/llex.c \
  $(LUA_COMP_DIR)/lmathlib.c \
  $(LUA_COMP_DIR)/lmem.c \
  $(LUA_COMP_DIR)/loadlib.c \
  $(LUA_COMP_DIR)/lobject.c \
  $(LUA_COMP_DIR)/lopcodes.c \
  $(LUA_COMP_DIR)/lparser.c \
  $(LUA_COMP_DIR)/lstate.c \
  $(LUA_COMP_DIR)/lstring.c \
  $(LUA_COMP_DIR)/lstrlib.c \
  $(LUA_COMP_DIR)/ltable.c \
  $(LUA_COMP_DIR)/ltablib.c \
  $(LUA_COMP_DIR)/ltm.c \
  $(LUA_COMP_DIR)/lundump.c \
  $(LUA_COMP_DIR)/lutf8lib.c \
  $(LUA_COMP_DIR)/lvm.c \
  $(LUA_COMP_DIR)/lzio.c

PLUGIN_COMPONENT_CFLAGS := \
  -O2 \
  -Dl_signalT=int \
  -I$(LUA_COMP_DIR) \
  -I$(PLUGIN_PATH) \
  -mexception-handling \
  -mmultivalue \
  -mreference-types \
  -mllvm -wasm-enable-sjlj \
  -mllvm -wasm-use-legacy-eh=false

PLUGIN_COMPONENT_EXTRA_DEPS := \
  $(PLUGIN_PATH)/plugin.mk \
  $(PLUGIN_COMPONENT_SOURCES) \
  $(PLUGIN_PATH)/jsmn.h \
  $(wildcard $(PLUGIN_PATH)/shim/*.h) \
  $(wildcard $(LUA_COMP_DIR)/*.h)
