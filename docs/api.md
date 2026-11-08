---
title: Runtime API
status: reference
---

# Runtime API

The component exports `gams:lua/lua@1.0.0` and imports the Host's `gams:runtime/runtime@1.0.0` call router and WASI filesystem interfaces. Filesystem access is native WASI, not a dependency on `gams:fs`.

## Entries and arguments

```wit
run: func(source: string, entry: option<string>, args-json: option<string>, source-path: option<string>) -> result<string, string>;
```

Pass null for absent options. Source is evaluated first, then the selected global function is called. An omitted entry selects `main`; an explicitly requested missing or non-function entry raises an error, never falls back to another function. `args-json` must encode an array; its values become positional arguments. JSON null arguments become Lua nil without losing their positions.

```lua
function main(context)
    return context and context.runId or "outside-editor"
end

function ng_graph_json()
    return "[]"
end
```

Select `ng_graph_json` to retrieve metadata without calling `main`. Top-level source statements still execute, so only load trusted Lua files. Context such as plugin IDs and run IDs is ordinary caller-supplied data, not an implicit runtime argument.

Strings pass through as results; nil becomes JSON `null`; other values are JSON encoded. Each invocation creates a fresh Lua state.

## Module imports

`import("./nodes/add.lua")` reads a text-only Lua module and returns its explicit exports. It does not automatically call the module's `main` function.

```lua
-- nodes/add.lua
return function(inputs, outputs, context)
    outputs[1] = inputs[1] + inputs[2]
end
```

```lua
local add = import("./nodes/add.lua")
function main(context)
    local outputs = {}
    add({3, 4}, outputs, context)
    return outputs[1]
end
```

`source-path` anchors the root script's relative imports and diagnostic filename; it does not read that file or grant new filesystem access. Without it imports start at the existing granted root. Imported modules have their own global environments inheriting runtime libraries; nested imports resolve relative to their owning file, even when made later by an exported function.

Use `/` separators. Normalized `.`/`..` paths are cached for one invocation. Missing files, cycles and nil exports raise errors; failed imports are not cached. False is a valid export. No extension or dotted-name transformation is applied. Cache identity is path-based, not filesystem-inode or symlink-based. Existing filesystem-backed `require` behavior remains separate and unchanged.

A graph file that is also importable can end with:

```lua
return { main = main, ng_graph_json = ng_graph_json }
```

Imports and filesystem reads remain restricted to the Host-granted WASI preopens. A source path does not enlarge those capabilities.

## JSON, filesystem and Host calls

`json.decode` and `json.encode` convert JSON values. Use `json.null` for an explicit null inside a Lua table; assigning nil removes a field. `json.array()` and `json.object()` preserve empty container shape; `json.is_array` and `json.is_object` inspect it.

`fs.read_text(path)` reads text from the granted filesystem; `fs.read` is its alias. Missing/unreadable paths raise errors.

`host.call(target, ...)` JSON-encodes its arguments as an array and synchronously calls the Host router. A single-field `ok` result is unwrapped; a single-field `err` result or a transport error raises a Lua error. `pcall` can handle expected runtime errors. `host.raw_call(target, args_json)` exposes the underlying string protocol directly.
