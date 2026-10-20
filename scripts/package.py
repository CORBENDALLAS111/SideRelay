"""Package the device .app while preserving executable permissions and symlinks."""
from pathlib import Path
import os
import stat
import zipfile
import plistlib

app = Path("build/DerivedData/Build/Products/Release-iphoneos/SideRelay.app")
if not app.is_dir():
    raise SystemExit("Device app bundle is missing")
with (app / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
executable = app / info["CFBundleExecutable"]
if not executable.is_file() or executable.read_bytes()[:4] != b"\xcf\xfa\xed\xfe":
    raise SystemExit("Missing arm64 Mach-O executable")
with zipfile.ZipFile("build/SideRelay.ipa", "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        name = "Payload/" + str(path.relative_to(app.parent)).replace(os.sep, "/")
        if path.is_symlink():
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(entry, os.readlink(path))
        elif path.is_file():
            archive.write(path, name)
print("Packaged build/SideRelay.ipa (unsigned; install with SideStore)")
