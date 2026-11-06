"""Check actual About options against extracted resources with no SwiftPM build accessor.

An owned metadata-only executable is compiled from the production About sources.
Its instrumented Bundle.module has no build-resource path; any consultation is a
normal verification failure. It runs inside owned copies of the extracted apps.
The GUI executables, About panel, original archives and existing apps are untouched.
"""
from pathlib import Path
import json, plistlib, shutil, subprocess, sys, tempfile, zipfile
root, archives, report = map(Path, sys.argv[1:4])
main = '''import AppKit
import Foundation
@MainActor enum DevelopmentLookup { static var count = 0 }
extension Bundle {
    @MainActor static var module: Bundle {
        DevelopmentLookup.count += 1
        return .main
    }
}
let options = ApplicationAboutPanel.options(applicationName: "Resource Verification")
let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
let result: [String: Any] = ["applicationBundle": Bundle.main.bundleURL.path,
    "credits": credits, "developmentLookupCount": DevelopmentLookup.count]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''
results = []
with tempfile.TemporaryDirectory(prefix='mote3d-about-resources-') as temp:
    stage = Path(temp)
    inputs = []
    for name in ['ApplicationAboutPanel.swift', 'RenderingResourceBundle.swift']:
        relative = 'Sources/Dust3DRendering/' + name
        source = (root / relative).read_bytes()
        path = stage / name
        path.write_bytes(source)
        inputs.append(str(path))
    (stage / 'main.swift').write_text(main)
    binary = stage / 'ResourceLookupVerification'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-module-cache-path', str(stage / 'clang'), *inputs, str(stage / 'main.swift'), '-o', str(binary)], check=True)
    for product in ['Dust3DEditor', 'Dust3DViewer']:
        extracted = stage / product
        with zipfile.ZipFile(archives / (product + '.zip')) as archive:
            archive.extractall(extracted)
        app = extracted / (product + '.app')
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleExecutable'] = binary.name
        info_path.write_bytes(plistlib.dumps(info))
        executable = app / 'Contents/MacOS' / binary.name
        shutil.copyfile(binary, executable)
        executable.chmod(0o755)
        proc = subprocess.run([str(executable)], text=True, capture_output=True, check=True)
        observed = json.loads(proc.stdout)
        assert Path(observed['applicationBundle']).resolve() == app.resolve(), observed
        passed = (root / 'LICENSE').read_text() in observed['credits'] and observed['developmentLookupCount'] == 0
        results.append(dict(product=product, embeddedLicenseContainedExactly=(root / 'LICENSE').read_text() in observed['credits'], developmentLookupCount=observed['developmentLookupCount'], passed=passed))
report.write_text(json.dumps(dict(sourceRoot=str(root), products=results, originalBuildResourcesAvailableToVerifier=False, packagedGUIExecutablesLaunched=False, aboutPanelDisplayed=False, originalArchivesModified=False), indent=2) + '\n')
print(report.read_text())
sys.exit(0 if all(r['passed'] for r in results) else 1)
