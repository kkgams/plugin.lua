import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const wit = spawnSync('wasm-tools', ['component', 'wit', 'dist/plugin.lua.wasm'], { encoding: 'utf8' })
assert.equal(wit.status, 0, wit.stderr)
assert.match(wit.stdout, /export gams:lua\/lua@1\.0\.0/)
assert.match(wit.stdout, /import gams:runtime\/runtime@1\.0\.0/)
assert.match(wit.stdout, /import wasi:filesystem\/preopens@0\.2\.[0-9]+/)
const luaHeader = readFileSync(new URL('../src/vendor/lua/lua.h', import.meta.url), 'utf8')
assert.match(luaHeader, /LUA_VERSION_MAJOR_N\s+5/)
assert.match(luaHeader, /LUA_VERSION_MINOR_N\s+5/)
const component = readFileSync(new URL('../src/component.c', import.meta.url), 'utf8')
for (const feature of ['lua_push_json_null', 'lua_host_call', 'lua_fs_read_text']) assert.ok(component.includes(feature), feature)
console.log('plugin.lua static build, validation, WIT, and vendored-source checks: ok')
console.log('not a runtime E2E test: jco 1.32.1 cannot translate the component exception-handling core')
