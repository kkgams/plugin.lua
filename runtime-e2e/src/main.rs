use std::env;
use std::path::PathBuf;
use wasmtime::component::{Component, Linker, ResourceTable};
use wasmtime::{Config, Engine, Result, Store};
use wasmtime_wasi::{WasiCtx, WasiCtxView, WasiView};

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
    let path = PathBuf::from(args.next().ok_or_else(|| {
        wasmtime::Error::msg("usage: lua-runtime-e2e <dist/plugin.lua.wasm>")
    })?);
    if args.next().is_some() {
        return Err(wasmtime::Error::msg("usage: lua-runtime-e2e <dist/plugin.lua.wasm>"));
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_exceptions(true);
    let engine = Engine::new(&config)?;
    let component = Component::from_file(&engine, &path)?;
    let mut linker = Linker::<State>::new(&engine);
    wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;
    linker.instance("gams:runtime/runtime@1.0.0")?.func_wrap(
        "call",
        |mut cx, (target, args): (String, String)| -> Result<(std::result::Result<String, String>,)> {
            if target != "e2e/echo" || args != "[\"hello\",7]" {
                return Err(wasmtime::Error::msg(format!(
                    "unexpected gams:runtime/runtime.call({target:?}, {args:?})"
                )));
            }
            cx.data_mut().bridge_calls += 1;
            Ok((Ok("{\"ok\":\"bridge-ok\"}".to_owned()),))
        },
    )?;

    let mut store = Store::new(
        &engine,
        State {
            wasi: WasiCtx::builder().build(),
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
        .typed::<(&str,), (std::result::Result<String, String>,)>(&store)?;

    let (value,) = run.call(&mut store, ("function main() return 42 end",))?;
    if value.as_deref() != Ok("42") {
        return Err(wasmtime::Error::msg(format!("main() return mismatch: {value:?}")));
    }

    let (value,) = run.call(
        &mut store,
        ("function main() return host.call('e2e/echo', 'hello', 7) end",),
    )?;
    if value.as_deref() != Ok("bridge-ok") || store.data().bridge_calls != 1 {
        return Err(wasmtime::Error::msg(format!(
            "host.call bridge mismatch: {value:?}, calls={}",
            store.data().bridge_calls
        )));
    }

    let (value,) = run.call(&mut store, ("function main( return 42 end",))?;
    match value {
        Err(message) if message.contains("(input):1:") && message.contains("expected near 'return'") => {}
        other => return Err(wasmtime::Error::msg(format!("invalid Lua error mismatch: {other:?}"))),
    }
    if store.data().bridge_calls != 1 {
        return Err(wasmtime::Error::msg("invalid Lua unexpectedly called host bridge"));
    }
    println!("Lua component E2E passed: main return, host.call bridge, syntax error");
    Ok(())
}
