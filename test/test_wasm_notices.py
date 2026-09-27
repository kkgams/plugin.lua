import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "scripts/wasm-notices.py"
spec = importlib.util.spec_from_file_location("wasm_notices", SCRIPT)
wasm_notices = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = wasm_notices
spec.loader.exec_module(wasm_notices)

HEADER = wasm_notices.COMPONENT_HEADER
LICENSE = b"license bytes\n\x00"
NOTICE = b"notice bytes\r\n"


def section(section_id, payload):
    return bytes((section_id,)) + wasm_notices.encode_u32(len(payload)) + payload


def named(name, contents):
    return wasm_notices.custom_section(name, contents)


class WasmNoticeTests(unittest.TestCase):
    def test_empty_license_or_notice_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            license_path = Path(temporary) / "LICENSE"
            notice_path = Path(temporary) / "NOTICE"
            for contents in (b"", b" \n\t"):
                license_path.write_bytes(contents)
                with self.assertRaisesRegex(wasm_notices.NoticeError, "empty licensing text"):
                    wasm_notices.expected_notices(license_path, None)
                license_path.write_bytes(LICENSE)
                notice_path.write_bytes(contents)
                with self.assertRaisesRegex(wasm_notices.NoticeError, "empty licensing text"):
                    wasm_notices.expected_notices(license_path, notice_path)

    def test_u32_leb_over_127_and_exact_raw_bytes(self):
        long_payload = bytes(range(130))
        ordinary_custom = named("x" * 130, long_payload)
        unknown = section(42, b"y" * 140)
        source = HEADER + ordinary_custom + unknown
        result = wasm_notices.embed_bytes(
            source,
            {wasm_notices.LICENSE_SECTION: LICENSE, wasm_notices.NOTICE_SECTION: NOTICE},
        )
        wasm_notices.verify_bytes(
            result,
            {wasm_notices.LICENSE_SECTION: LICENSE, wasm_notices.NOTICE_SECTION: NOTICE},
        )
        parsed = wasm_notices.parse_component(result)
        self.assertEqual([item.raw for item in parsed[:2]], [ordinary_custom, unknown])
        self.assertEqual(parsed[-2].contents, LICENSE)
        self.assertEqual(parsed[-1].contents, NOTICE)

    def test_embed_replaces_duplicates_and_corrupt_stale_notices(self):
        source = (
            HEADER
            + named("before", b"unchanged")
            + named(wasm_notices.LICENSE_SECTION, b"old")
            + named(wasm_notices.LICENSE_SECTION, b"corrupt")
            + named(wasm_notices.NOTICE_SECTION, b"old notice")
        )
        result = wasm_notices.embed_bytes(
            source,
            {wasm_notices.LICENSE_SECTION: LICENSE, wasm_notices.NOTICE_SECTION: NOTICE},
        )
        wasm_notices.verify_bytes(
            result,
            {wasm_notices.LICENSE_SECTION: LICENSE, wasm_notices.NOTICE_SECTION: NOTICE},
        )
        self.assertEqual(sum(s.name == wasm_notices.LICENSE_SECTION for s in wasm_notices.parse_component(result)), 1)
        self.assertEqual(sum(s.name == wasm_notices.NOTICE_SECTION for s in wasm_notices.parse_component(result)), 1)

    def test_verify_rejects_missing_duplicate_stale_and_unexpected(self):
        license_only = {wasm_notices.LICENSE_SECTION: LICENSE}
        with self.assertRaisesRegex(wasm_notices.NoticeError, "missing gams.license"):
            wasm_notices.verify_bytes(HEADER, license_only)
        with self.assertRaisesRegex(wasm_notices.NoticeError, "duplicate gams.license"):
            wasm_notices.verify_bytes(
                HEADER + named(wasm_notices.LICENSE_SECTION, LICENSE) * 2,
                license_only,
            )
        with self.assertRaisesRegex(wasm_notices.NoticeError, "stale or altered gams.license"):
            wasm_notices.verify_bytes(
                HEADER + named(wasm_notices.LICENSE_SECTION, LICENSE + b"changed"),
                license_only,
            )
        with self.assertRaisesRegex(wasm_notices.NoticeError, "unexpected gams.notice"):
            wasm_notices.verify_bytes(
                HEADER
                + named(wasm_notices.LICENSE_SECTION, LICENSE)
                + named(wasm_notices.NOTICE_SECTION, NOTICE),
                license_only,
            )

    def test_changed_source_license_and_notice_are_stale(self):
        original = {
            wasm_notices.LICENSE_SECTION: LICENSE,
            wasm_notices.NOTICE_SECTION: NOTICE,
        }
        component = wasm_notices.embed_bytes(HEADER, original)
        for changed in (
            {**original, wasm_notices.LICENSE_SECTION: b"new license"},
            {**original, wasm_notices.NOTICE_SECTION: b"new notice"},
        ):
            with self.assertRaisesRegex(wasm_notices.NoticeError, "stale or altered"):
                wasm_notices.verify_bytes(component, changed)

    def test_optional_notice_removal(self):
        with_notice = wasm_notices.embed_bytes(
            HEADER,
            {wasm_notices.LICENSE_SECTION: LICENSE, wasm_notices.NOTICE_SECTION: NOTICE},
        )
        without_notice = wasm_notices.embed_bytes(
            with_notice,
            {wasm_notices.LICENSE_SECTION: LICENSE},
        )
        wasm_notices.verify_bytes(without_notice, {wasm_notices.LICENSE_SECTION: LICENSE})
        self.assertNotIn(
            wasm_notices.NOTICE_SECTION,
            [item.name for item in wasm_notices.parse_component(without_notice)],
        )

    def test_empty_module_and_malformed_sections_fail(self):
        malformed = (
            b"",
            b"\x00asm",
            b"\x00asm\x01\x00\x00\x00",
            HEADER + b"\x00\x80",
            HEADER + b"\x01\x05x",
            HEADER + b"\x00\x01\x02",
            HEADER + b"\x00\x80\x80\x80\x80\x10",
            HEADER + b"\x00\x80\x00",
        )
        for component in malformed:
            with self.subTest(component=component):
                with self.assertRaises(wasm_notices.NoticeError):
                    wasm_notices.parse_component(component)

    def test_cli_embeds_in_place_and_verify_detects_source_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "component.wasm"
            license_path = root / "LICENSE"
            notice_path = root / "NOTICE"
            artifact.write_bytes(HEADER + named("kept", b"raw"))
            license_path.write_bytes(LICENSE)
            notice_path.write_bytes(NOTICE)
            arguments = [
                str(SCRIPT), "embed", str(artifact), "--license", str(license_path),
                "--notice", str(notice_path),
            ]
            subprocess.run([sys.executable, *arguments], check=True)
            subprocess.run(
                [sys.executable, str(SCRIPT), "verify", str(artifact), "--license",
                 str(license_path), "--notice", str(notice_path)],
                check=True,
            )
            license_path.write_bytes(b"changed")
            failed = subprocess.run(
                [sys.executable, str(SCRIPT), "verify", str(artifact), "--license",
                 str(license_path), "--notice", str(notice_path)],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("stale or altered gams.license", failed.stderr)


if __name__ == "__main__":
    unittest.main()
