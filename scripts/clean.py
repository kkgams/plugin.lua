"""Remove explicit recreatable output; preserve supplied scripts and legacy output."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
PATHS = (
    "build.nosync/bindings", "build.nosync/runtime.h",
    "build.nosync/plugin.lua.unstripped.wasm", "build.nosync/plugin.lua.stripped.wasm",
    "build.nosync/plugin.lua.wasm", "build.nosync/LICENSE", "build.nosync/NOTICE",
    "build.nosync/SHA256SUMS", "build.nosync/test", "build.nosync/runtime-target",
    "build.nosync/runtime-fixtures", "build.nosync/tmp", "build.nosync/site",
    "build.nosync/pycache", "build.nosync/cache", "build.nosync/legacy-output",
    "build.nosync/oci-manifest.json",
    "build.nosync/wiki-v1.4.0", "build.nosync/wiki-v1.4.0.mk",
    "tools/gams.app", "tools/gams-release-notices",
)

# Only current configured downloads are recreatable. Preserve supplied Units and
# unrelated/stale entries rather than recursively deleting gams_modules.
config = json.loads((ROOT / "gams.json").read_text())
sources = list(config["plugins"])
ui = config.get("ui", {})
for group in (ui.get("views", {}), ui.get("services", {})):
    sources.extend(entry["url"] for entry in group.values())
if "theme" in ui:
    sources.append(ui["theme"]["url"])
modules = ROOT / "gams_modules"
if modules.is_symlink():
    raise SystemExit("Refusing symlink in clean path: gams_modules")
for source in sources:
    entry = None
    if isinstance(source, dict):
        source = source["$file"]
        if isinstance(source, dict):
            entry = source.get("entry")
            source = source["url"]
    url = urlsplit(source)
    if url.scheme not in ("http", "https"):
        continue
    key = hashlib.sha256(source.encode("utf-8")).hexdigest()
    if url.path.lower().endswith(".zip"):
        if not url.fragment and (not isinstance(entry, str) or not entry):
            raise SystemExit(f"ZIP Unit requires an entry selector: {source}")
        path = key
    else:
        suffix = Path(url.path).suffix.lower()
        path = key + (suffix if suffix in (".wasm", ".js", ".css") else ".bin")
    PATHS += (f"gams_modules/{path}",)

# Check every target before deleting anything. Never traverse directory symlinks.
for name in PATHS:
    path = ROOT / name
    for part in (path, *path.parents):
        if part == ROOT:
            break
        if part.is_symlink():
            raise SystemExit(f"Refusing symlink in clean path: {part.relative_to(ROOT)}")
    if path.is_dir():
        for child in path.rglob("*"):
            if child.is_symlink():
                raise SystemExit(f"Refusing symlink in clean path: {child.relative_to(ROOT)}")
    tracked = subprocess.check_output(
        ["git", "ls-files", "--", name], cwd=ROOT, text=True
    )
    if tracked:
        raise SystemExit(f"Refusing to remove tracked output files:\n{tracked}")

for name in PATHS:
    path = ROOT / name
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()

if modules.is_dir() and not any(modules.iterdir()):
    modules.rmdir()
