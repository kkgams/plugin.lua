# plugin.lua context

## Language

**Lua Runtime Plugin**: The singleton WASM Plugin built by this repository. It embeds
Lua 5.5 and exports `gams:lua/lua@1.0.0` with `run(source)`.

**Script Entrypoint**: The Lua `main()` function called after source evaluation. Its
return becomes the WIT result: strings pass through, `nil` becomes JSON `null`, and
other values are JSON encoded.

**Host Call**: `host.call(target, ...)`, which JSON-encodes arguments and invokes the
imported `gams:runtime/runtime@1.0.0` call router. Single-field `ok` and `err`
envelopes are unwrapped into Lua values and errors.

**Raw Host Call**: `host.raw_call(target, args_json)`, the string-level runtime call
protocol without Host Call's argument/result conversion.

**Lua Filesystem Access**: `fs.read_text`, `fs.read`, and module loading backed by
Host-granted WASI preopened directories. This is not an import of `gams:fs`.

**JSON Null**: `json.null`, the explicit sentinel for a JSON null inside a Lua table;
Lua `nil` removes a table field instead.

## Relationships and boundaries

- The Host supplies the runtime call import and WASI filesystem preopens.
- Runtime call targets are resolved by the Host's Plugin Manager, not by this Plugin.
- The distribution artifact is `dist/plugin.lua.wasm`; Project installation maps it
  to `plugins/lua.comp.wasm`.
- The repository's current `make test` is a static build, component validation, WIT,
  and source-invariant check. It does not execute Lua. A real runtime E2E needs a
  small standalone component-model host for the runtime import; the existing native
  path is coupled to the larger GAMS Host and is not copied into this repository.
