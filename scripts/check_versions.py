"""Keep app metadata and the native core version in sync."""
from pathlib import Path
import re

cargo = Path("core/Cargo.toml").read_text(encoding="utf-8")
project = Path("project.yml").read_text(encoding="utf-8")
core_version = re.search(r'^version = "([^"\n]+)"', cargo, re.MULTILINE).group(1)
app_version = re.search(r'CFBundleShortVersionString: "([^"\n]+)"', project).group(1)
if core_version != app_version:
    raise SystemExit(f"Version mismatch: core={core_version}, app={app_version}")
print(f"App and core versions match: {app_version}")
