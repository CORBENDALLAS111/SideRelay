"""Supply the application and complete Cargo sources for rebuilding/relinking LGPL code."""
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path("build/Source/SideRelay")
root.mkdir(parents=True, exist_ok=True)
for folder in ["app", "core", "scripts", "notices"]:
    shutil.copytree(folder, root / folder, dirs_exist_ok=True, ignore=shutil.ignore_patterns("target", "__pycache__"))
for name in ["project.yml", "README.md", "LICENSE", "RELEASE_NOTES.md"]:
    shutil.copyfile(name, root / name)
vendor = root / "vendor"
result = subprocess.run(["cargo", "vendor", "--manifest-path", "core/Cargo.toml", "--locked", str(vendor)], check=True, capture_output=True, text=True)
config = root / "core/.cargo"
config.mkdir(exist_ok=True)
# Cargo config is discovered from the working directory. Build the bundled sources
# with `cd core` and `cargo build ...`; vendor paths are relative to this core root.
(config / "config.toml").write_text(result.stdout.replace(str(vendor), "../vendor").replace(str(vendor).replace('\\', '/'), "../vendor"), encoding="utf-8")
(root / "REBUILD.txt").write_text(
    "Complete application and dependency sources for modification and relinking.\n"
    "The application is MIT. apple-codesign-quick is LGPL-2.1-or-later.\n"
    "You may modify the library and rebuild the application for your use.\n"
    "On macOS: install Xcode, Rust and XcodeGen.\n"
    "cd core\n"
    "rustup target add aarch64-apple-ios\n"
    'IPHONEOS_DEPLOYMENT_TARGET=18.0 SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" cargo build --release --locked --target aarch64-apple-ios\n'
    "cd ..\n"
    "xcodegen generate\n"
    "xcodebuild -project SideRelay.xcodeproj -scheme SideRelay -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build\n"
    "python3 scripts/package.py\n"
    "Sign the resulting IPA using your own sideloader/certificate.\n",
    encoding="utf-8"
)
with zipfile.ZipFile("build/SideRelay-source.zip", "w", compression=zipfile.ZIP_DEFLATED, strict_timestamps=False) as archive:
    for path in sorted(root.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(root.parent))
print("Packaged complete application and dependency sources")
