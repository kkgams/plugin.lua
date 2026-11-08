# plugin.lua context

## Language

**Lua Runtime Plugin**: The singleton WASM Plugin built by this repository. It embeds
Lua 5.5 and exports `gams:lua/lua@1.0.0` with `run(source, entry?, args-json?, source-path?)`.

**Script Entrypoint**: A selected global Lua function (default `main`) called after source evaluation with the optional JSON argument array unpacked. Missing or non-function entries are errors. Its
return becomes the WIT result: strings pass through, `nil` becomes JSON `null`, and
other values are JSON encoded.

**Host Call**: `host.call(target, ...)`, which JSON-encodes arguments and invokes the
imported `gams:runtime/runtime@1.0.0` call router. Single-field `ok` and `err`
envelopes are unwrapped into Lua values and errors.

**Raw Host Call**: `host.raw_call(target, args_json)`, the string-level runtime call
protocol without Host Call's argument/result conversion.

**Lua Filesystem Access**: `fs.read_text`, `fs.read`, and module loading backed by
Host-granted WASI preopened directories. This is not an import of `gams:fs`.

**Import**: `import(path)` reads a Lua file through the existing WASI preopens,
executes it in a module-local environment, and returns its explicit exports.
Relative paths resolve from the importing chunk's lexical source path, including
calls from functions invoked later. Normalized paths are cached per run; cycles
and modules returning nil are errors. `require` retains its existing loader.

**Run Context**: Optional caller-supplied context such as `pluginId` and `runId`
is an ordinary argument: `args-json = '[{"pluginId":"lua","runId":"r1"}]'`.
Metadata functions can be selected without defining or invoking `main`.

**JSON Null**: `json.null`, the explicit sentinel for a JSON null inside a Lua table;
Lua `nil` removes a table field instead.

## Relationships and boundaries

- The Host supplies the runtime call import and WASI filesystem preopens.
- Runtime call targets are resolved by the Host's Plugin Manager, not by this Plugin.
- The distribution artifact is `dist/plugin.lua.wasm`; Project installation maps it
  to `plugins/lua.comp.wasm`.
- `make test` is a static build, component validation, WIT, and source-invariant
  check. Candidate and tag workflows also exercise the final WASM using a locked
  standalone Wasmtime component-model host for the runtime import, without copying
  the larger GAMS Host. Hosted Linux confirmation remains a release gate.
