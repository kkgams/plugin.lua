"""Attach the required license texts to a freshly stripped WASM component."""
from pathlib import Path
import sys


def leb(value):
    result = bytearray()
    while True:
        byte = value & 0x7f
        value >>= 7
        result.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(result)


def section(name, text):
    name = name.encode("utf-8")
    payload = leb(len(name)) + name + text
    return b"\x00" + leb(len(payload)) + payload


if len(sys.argv) != 3:
    raise SystemExit("usage: embed-notices.py INPUT.wasm OUTPUT.wasm")
source, output = map(Path, sys.argv[1:])
if source.resolve() == output.resolve():
    raise SystemExit("input and output must differ; use freshly stripped input")
component = source.read_bytes()
if component[:8] != b"\x00asm\x0d\x00\x01\x00":
    raise SystemExit("input must be a WebAssembly component")
root = Path(__file__).resolve().parent.parent
for name, filenames in (("gams.license", ("LICENSE",)), ("gams.notice", ("NOTICE", "licenses/THIRD-PARTY.txt"))):
    texts = []
    for filename in filenames:
        text = (root / filename).read_bytes()
        if not text.strip():
            raise SystemExit(f"required license text is empty: {filename}")
        texts.append(text)
    component += section(name, b"".join(texts))
output.write_bytes(component)
