use std::env;
use std::path::PathBuf;
use wasmtime::component::{Component, Linker, ResourceTable};
use wasmtime::{Config, Engine, Result, Store};
use wasmtime_wasi::{DirPerms, FilePerms, WasiCtx, WasiCtxView, WasiView};

struct State {
    wasi: WasiCtx,
    table: ResourceTable,
    bridge_calls: usize,
}

impl WasiView for State {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView {
            ctx: &mut self.wasi,
            table: &mut self.table,
        }
    }
}

fn main() -> Result<()> {
    let mut args = env::args_os().skip(1);
    let path = PathBuf::from(
        args.next()
            .ok_or_else(|| wasmtime::Error::msg("usage: lua-runtime-e2e <component.wasm>"))?,
    );
    let extra: Vec<_> = args.collect();
    let manual = if extra.is_empty() {
        None
    } else {
        if extra.len() != 6 || extra[0] != "--run" {
            return Err(wasmtime::Error::msg("usage: lua-runtime-e2e COMPONENT [--run SOURCE_FILE PREOPEN_DIR ENTRY ARGS_JSON SOURCE_PATH] (use '-' for absent options; preopen mounts at /project)"));
        }
        Some((
            std::fs::read_to_string(&extra[1])?,
            PathBuf::from(&extra[2]),
            extra[3].to_string_lossy().into_owned(),
            extra[4].to_string_lossy().into_owned(),
            extra[5].to_string_lossy().into_owned(),
        ))
    };

    run_component(path, manual)
}

type ManualRun = (String, PathBuf, String, String, String);

#[test]
fn lua_runtime_cases() -> Result<()> {
    let path = env::var_os("LUA_COMPONENT_PATH")
        .ok_or_else(|| wasmtime::Error::msg("LUA_COMPONENT_PATH must select the test component"))?;
    run_component(PathBuf::from(path), None)
}

fn run_component(path: PathBuf, manual: Option<ManualRun>) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_exceptions(true);
    let engine = Engine::new(&config)?;
    let component = Component::from_file(&engine, &path)?;
    let mut linker = Linker::<State>::new(&engine);
    wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;
    linker.instance("gams:runtime/runtime@1.0.0")?.func_wrap(
        "call",
        |mut cx,
         (target, args): (String, String)|
         -> Result<(std::result::Result<String, String>,)> {
            let expected_args = match target.as_str() {
                "e2e/echo" => "[\"hello\",7]",
                "random/seeded-random::get-seed" => "[]",
                "e2e/one" => "[\"hello\"]",
                "e2e/null" => "[null]",
                "e2e/null-boundaries" => "[null,\"hello\",null]",
                _ => {
                    return Err(wasmtime::Error::msg(format!(
                        "unexpected target {target:?}"
                    )))
                }
            };
            if args != expected_args {
                return Err(wasmtime::Error::msg(format!(
                    "unexpected gams:runtime/runtime.call({target:?}, {args:?})"
                )));
            }
            cx.data_mut().bridge_calls += 1;
            Ok((Ok("{\"ok\":\"bridge-ok\"}".to_owned()),))
        },
    )?;

    let fixtures =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../build.nosync/runtime-fixtures");
    if manual.is_none() {
        std::fs::create_dir_all(fixtures.join("nested/deep"))?;
        for (name, source) in [
            ("nested/module.lua", "local leaf = import('./deep/leaf.lua'); return { leaf = leaf, later = function() return import('./deep/../deep/leaf.lua') end }"),
            ("nested/deep/leaf.lua", "return { value = 17 }"),
            ("cycle-a.lua", "return import('./cycle-b.lua')"),
            ("cycle-b.lua", "return import('./cycle-a.lua')"),
            ("callable.lua", "return function(inputs, outputs, context) outputs.answer=inputs.value+context.delta end"),
            ("graph.lua", "function main() return 31 end; function ng_graph_json() return 12 end; return {main=main,ng_graph_json=ng_graph_json}"),
            ("false.lua", "return false"), ("empty.lua", "local x=1"),
            ("broken.lua", "return ("), ("legacy.lua", "return {value=9}"),
            ("legacy-globals.lua", "assert(root_value==13); legacy_value=7; return true"),
        ] { std::fs::write(fixtures.join(name), source)?; }
    }
    let mut wasi = WasiCtx::builder();
    let preopen = manual
        .as_ref()
        .map(|(_, root, _, _, _)| root)
        .unwrap_or(&fixtures);
    wasi.preopened_dir(preopen, "/project", DirPerms::READ, FilePerms::READ)?;
    let mut store = Store::new(
        &engine,
        State {
            wasi: wasi.build(),
            table: ResourceTable::new(),
            bridge_calls: 0,
        },
    );
    let instance = linker.instantiate(&mut store, &component)?;
    let interface = instance
        .get_export_index(&mut store, None, "gams:lua/lua@1.0.0")
        .ok_or_else(|| wasmtime::Error::msg("missing gams:lua/lua@1.0.0 export"))?;
    let run_index = instance
        .get_export_index(&mut store, Some(&interface), "run")
        .ok_or_else(|| wasmtime::Error::msg("missing gams:lua/lua@1.0.0.run export"))?;
    let run = instance
        .get_func(&mut store, &run_index)
        .ok_or_else(|| wasmtime::Error::msg("run export is not a function"))?
        .typed::<(&str, Option<&str>, Option<&str>, Option<&str>), (std::result::Result<String, String>,)>(&store)?;
    if let Some((source, _, entry, args, path)) = manual {
        fn optional(s: &str) -> Option<&str> {
            if s == "-" {
                None
            } else {
                Some(s)
            }
        }
        let (value,) = run.call(
            &mut store,
            (&source, optional(&entry), optional(&args), optional(&path)),
        )?;
        match value {
            Ok(value) => println!("{value}"),
            Err(message) => return Err(wasmtime::Error::msg(message)),
        }
        return Ok(());
    }
    let cases = [
        ("root_value=13; require('/project/legacy-globals.lua'); function main() return legacy_value end", None, None, None, Ok("7")),
        ("function main() return import('./nested/module.lua').leaf.value end", None, None, Some("root.lua"), Ok("17")),
        ("function main() return import('./nested/module.lua').leaf.value end", None, None, None, Ok("17")),
        ("function ng_graph_json() return {nodes=json.array()} end", Some("ng_graph_json"), None, None, Ok(r#"{"nodes":[]}"#)),
        ("function main() local out={}; import('./callable.lua')({value=5},out,{delta=2}); return out.answer end", None, None, Some("/project/root.lua"), Ok("7")),
        ("local graph=import('./graph.lua'); function main() return graph.ng_graph_json()+graph.main() end", None, None, Some("/project/root.lua"), Ok("43")),
        ("function main() for i=1,2 do local ok,err=pcall(import,'./cycle-a.lua'); assert(not ok and err:find('import cycle:',1,true)) end; return true end", None, None, Some("/project/root.lua"), Ok("true")),
        ("function main() return import('/project/../outside.lua') end", None, None, Some("/project/root.lua"), Err("file not found or not readable")),
        (r"function main() return import('./bad\0.lua') end", None, None, Some("/project/root.lua"), Err("invalid source/import path")),
        ("function main() return 42 end", None, None, None, Ok("42")),
        ("function main() return host.call('random/seeded-random::get-seed') end", None, None, None, Ok("bridge-ok")),
        ("function main() return host.raw_call('random/seeded-random::get-seed', '[]') end", None, None, None, Ok(r#"{"ok":"bridge-ok"}"#)),
        ("function main() return host.call('e2e/one', 'hello') end", None, None, None, Ok("bridge-ok")),
        ("function main() return host.call('e2e/null', json.null) end", None, None, None, Ok("bridge-ok")),
        ("function main() return host.call('e2e/null-boundaries', json.null, 'hello', json.null) end", None, None, None, Ok("bridge-ok")),
        ("function main() return host.call('e2e/echo', 'hello', 7) end", None, None, None, Ok("bridge-ok")),
        ("function graph() return 12 end", Some("graph"), None, None, Ok("12")),
        ("function main(ctx) return ctx.pluginId .. ':' .. ctx.runId end", None, Some(r#"[{"pluginId":"lua","runId":"r1"}]"#), None, Ok("lua:r1")),
        ("function sum(a,b) return a+b end", Some("sum"), Some("[3,4]"), None, Ok("7")),
        ("function main(...) assert(select('#',...)==3); local a,b,c=...; assert(a==nil and b==2 and c==nil); return true end", None, Some("[null,2,null]"), None, Ok("true")),
        ("local m=import('./nested/module.lua'); function main() assert(m.leaf==m.later()); assert(m==import('./nested/../nested/module.lua')); return m.later().value end", None, None, Some("/project/root.lua"), Ok("17")),
        ("local m=import('./nested/module.lua'); m.leaf.value=99; function main() return m.later().value end", None, None, Some("/project/root.lua"), Ok("99")),
        ("function main() return import('./nested/module.lua').leaf.value end", None, None, Some("/project/root.lua"), Ok("17")),
        ("function main() return import('./false.lua') end", None, None, Some("/project/root.lua"), Ok("false")),
        ("function main() return require('/project/legacy.lua').value end", None, None, None, Ok("9")),
        ("function main( return 42 end", None, None, None, Err("(input):1:")),
        ("function main( return 42 end", None, None, Some("/project/bad.lua"), Err("/project/bad.lua:1:")),
        ("function graph() end", None, None, None, Err("entry 'main' is not a function")),
        ("graph=2", Some("graph"), None, None, Err("entry 'graph' is not a function")),
        ("function main() end", None, Some("{}"), None, Err("args-json must encode an array")),
        ("function main() end", None, Some("["), None, Err("json.decode")),
        ("function main() return import('./cycle-a.lua') end", None, None, Some("/project/root.lua"), Err("import cycle:")),
        ("function main() return import('./empty.lua') end", None, None, Some("/project/root.lua"), Err("must return exports")),
        ("function main() return import('./broken.lua') end", None, None, Some("/project/root.lua"), Err("/project/broken.lua:1:")),
        ("function main() return import('./missing.lua') end", None, None, Some("/project/root.lua"), Err("file not found or not readable")),
        ("function main() return import('/etc/passwd') end", None, None, Some("/project/root.lua"), Err("file not found or not readable")),
        ("function main() return import('../../secret.lua') end", None, None, Some("/project/root.lua"), Err("escapes its root")),
    ];
    for (index, (source, entry, args, path, expected)) in cases.into_iter().enumerate() {
        let (value,) = run.call(&mut store, (source, entry, args, path))?;
        let matches = match (&value, expected) {
            (Ok(actual), Ok(expected)) => actual == expected,
            (Err(actual), Err(expected)) => actual.contains(expected),
            _ => false,
        };
        if !matches {
            return Err(wasmtime::Error::msg(format!(
                "case {index} mismatch: {value:?}, expected {expected:?}"
            )));
        }
    }
    if store.data().bridge_calls != 6 {
        return Err(wasmtime::Error::msg("unexpected bridge count"));
    }
    println!("Lua component E2E passed: {} runtime cases", cases.len());
    Ok(())
}
