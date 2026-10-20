"""Include dependency notices in the IPA; called after Cargo downloaded the dependencies."""
import json
import subprocess
from pathlib import Path

metadata = json.loads(subprocess.check_output([
    "cargo", "metadata", "--manifest-path", "core/Cargo.toml", "--locked", "--format-version", "1"
]))
output = ["SideRelay dependency notices\n\nSee https://github.com/CORBENDALLAS111/SideRelay for source.\n"]
for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
    root = Path(package["manifest_path"]).parent
    output.append(f"\n{'=' * 72}\n{package['name']} {package['version']}\nLicense: {package.get('license')}\nSource: {package.get('repository')}\nAuthors: {', '.join(package.get('authors', []))}\n")
    files = {p for p in root.iterdir() if p.is_file() and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE"))}
    if package.get("license_file"):
        files.add(root / package["license_file"])
    for folder in [root / "LICENSES", root / "licenses"]:
        if folder.is_dir():
            files.update(p for p in folder.rglob("*") if p.is_file())
    if not files and package["name"] != "siderelay-core":
        explicit = Path('notices') / (package['name'] + '.txt')
        expression = package.get('license') or ''
        if explicit.is_file():
            files.add(explicit)
        elif 'MIT' in expression:
            files.add(Path('notices/MIT.txt'))
        elif expression == 'LGPL-2.1-or-later':
            files.add(Path('notices/LGPL-2.1-or-later.txt'))
        elif expression == 'Apache-2.0':
            files.add(Path('notices/Apache-2.0.txt'))
        else:
            raise SystemExit(f"Missing license text for {package['name']}; inspect before publishing")
    for path in sorted(files):
        output.append(f"\n--- {path.name} ---\n{path.read_text(encoding='utf-8', errors='replace')}\n")
Path("app/Resources").mkdir(exist_ok=True)
Path("app/Resources/ThirdPartyNotices.txt").write_text("".join(output), encoding="utf-8")
print("Dependency license notices bundled")
