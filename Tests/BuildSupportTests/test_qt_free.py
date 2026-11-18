"""Verify native source and product linkage failures propagate through the build gate."""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PRODUCTS = ("Dust3DViewer", "Dust3DEditor", "Dust3DQuickLookExtension", "Dust3DThumbnailExtension", "Dust3DExport")


class QtFreeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures = tempfile.TemporaryDirectory()
        cls.addClassCleanup(fixtures.cleanup)
        fixture = Path(fixtures.name)
        (fixture / "clean.c").write_text("int main(void) { return 0; }\n")
        (fixture / "qt.c").write_text("int fixture_symbol(void) { return 0; }\n")
        (fixture / "linked.c").write_text("int fixture_symbol(void); int main(void) { return fixture_symbol(); }\n")
        cls.clean = fixture / "clean"
        cls.linked = fixture / "linked"
        cls.clean_library = fixture / "libFixture.dylib"
        library = fixture / "libQt6Network.6.dylib"
        subprocess.run(["xcrun", "clang", fixture / "clean.c", "-o", cls.clean], check=True, timeout=30)
        subprocess.run(["xcrun", "clang", "-dynamiclib", fixture / "qt.c", "-o", cls.clean_library],
                       check=True, timeout=30)
        subprocess.run(["xcrun", "clang", "-dynamiclib", fixture / "qt.c",
                        "-Wl,-install_name,@rpath/libQt6Network.6.dylib", "-o", library],
                       check=True, timeout=30)
        subprocess.run(["xcrun", "clang", fixture / "linked.c", library, "-o", cls.linked],
                       check=True, timeout=30)
        other_arch = "x86_64" if platform.machine() == "arm64" else "arm64"
        other_library = fixture / "other-libQt6Network.6.dylib"
        other_linked = fixture / "other-linked"
        cls.universal = fixture / "universal"
        cross_compile = ["xcrun", "clang", "-arch", other_arch, "-mmacosx-version-min=14.0"]
        subprocess.run([*cross_compile, "-dynamiclib", fixture / "qt.c",
                        "-Wl,-install_name,@rpath/libQt6Network.6.dylib", "-o", other_library],
                       check=True, timeout=30)
        subprocess.run([*cross_compile, fixture / "linked.c", other_library, "-o", other_linked],
                       check=True, timeout=30)
        subprocess.run(["xcrun", "lipo", "-create", cls.clean, other_linked, "-output", cls.universal],
                       check=True, timeout=30)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.checkout = Path(temporary.name)
        self.build = self.checkout / "build-root"
        self.source = self.checkout / "Sources"
        self.core = self.build / "build/checkouts/dust3d-core"
        self.binary = self.build / "build" / f"{platform.machine()}-apple-macosx" / "debug"
        for path in (self.source, self.core / "dust3d", self.core / "native/Engine", self.binary):
            path.mkdir(parents=True)
        (self.source / "ordinary.c").write_text("int native_source;\n")
        scripts = self.checkout / "script"
        scripts.mkdir()
        for name in ("build_paths.sh", "check_qt_free.sh"):
            shutil.copy2(ROOT / "script" / name, scripts / name)
        self.script = scripts / "check_qt_free.sh"
        products = ",\n".join(f'.executable(name: "{name}", targets: ["Sample"])' for name in PRODUCTS)
        (self.checkout / "Package.swift").write_text(
            "// swift-tools-version: 6.0\nimport PackageDescription\n"
            f'let package = Package(name: "Fixture", products: [{products}], '
            'targets: [.executableTarget(name: "Sample")])\n')
        for name in PRODUCTS:
            shutil.copy2(self.clean, self.binary / name)

    def run_gate(self):
        return subprocess.run(
            ["bash", self.script], env={**os.environ, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "DUST3D_BUILD_ROOT": str(self.build)},
            capture_output=True, text=True, timeout=30)

    def test_clean_sources_and_products_pass(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_source_scan_path_fails(self):
        shutil.rmtree(self.core / "native/Engine")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native/Engine", result.stderr)

    def test_missing_and_invalid_mach_o_fail(self):
        binary = self.binary / "Dust3DEditor"
        binary.unlink()
        with self.subTest(input="missing"):
            missing = self.run_gate()
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("Dust3DEditor", missing.stderr)
        binary.write_text("not a Mach-O executable")
        with self.subTest(input="invalid"):
            invalid = self.run_gate()
            self.assertNotEqual(invalid.returncode, 0)
            self.assertIn("Dust3DEditor", invalid.stderr)
            self.assertIn("is not an object file", invalid.stderr)

    def test_library_cannot_replace_executable_product(self):
        shutil.copy2(self.clean_library, self.binary / "Dust3DViewer")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Dust3DViewer", result.stderr)
        self.assertIn("executable", result.stderr)

    def test_qt_references_in_native_source_fail(self):
        (self.source / "bad.cc").write_text("#include <QWidget>\n")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Qt references found", result.stderr)

    def test_qt_linkage_in_additional_executable_fails(self):
        shutil.copy2(self.linked, self.binary / "Dust3DExport")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("libQt6Network.6.dylib", result.stdout + result.stderr)
        self.assertIn("Qt linked into Dust3DExport", result.stderr)

    def test_qt_linkage_in_other_architecture_fails(self):
        shutil.copy2(self.universal, self.binary / "Dust3DViewer")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("libQt6Network.6.dylib", result.stdout + result.stderr)
        self.assertIn("Qt linked into Dust3DViewer", result.stderr)


if __name__ == "__main__":
    unittest.main()
