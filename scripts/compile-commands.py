"""Emit clangd commands using the compiler, flags and sources supplied by Make."""
import json
import os
from pathlib import Path
import shlex
import shutil
import sys

compiler, *args = sys.argv[1:]
compiler = shlex.split(compiler)
compiler[0] = shutil.which(compiler[0]) or compiler[0]
separator = args.index("--")
flags, sources = args[:separator], args[separator + 1:]
# clangd does not query the WASI driver automatically. Supply its target/sysroot
# explicitly; reactor/linker settings are not needed for parsing source files.
sysroot = os.environ["WASI_SYSROOT"]
assert Path(sysroot).is_dir(), f"Missing WASI sysroot: {sysroot}"
json.dump([
    {
        "directory": str(Path.cwd()),
        "file": source,
        "arguments": [*compiler, "--target=wasm32-wasip2", f"--sysroot={sysroot}",
                      *flags, "-c", source],
    }
    for source in sources
], sys.stdout, indent=2)
print()
