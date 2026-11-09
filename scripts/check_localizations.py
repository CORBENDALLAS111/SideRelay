"""Check UI catalog coverage and format argument parity."""
import json
from pathlib import Path
import re

entry = re.compile(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");')
catalog = {}
for lang in ("ru", "en"):
    lines = (Path("app/Resources") / f"{lang}.lproj/Localizable.strings").read_text(encoding="utf-8").splitlines()
    pairs = [tuple(map(json.loads, entry.fullmatch(line).groups())) for line in lines]
    catalog[lang] = dict(pairs)
    assert len(pairs) == len(catalog[lang]), f"Duplicate key in {lang}"
assert catalog["ru"].keys() == catalog["en"].keys()
for key, value in catalog["en"].items():
    assert value and key.count("%@") == value.count("%@"), key
    assert not re.search(r"[А-Яа-яЁё]",value), key
for path in Path("app").glob("*.swift"):
    for key in re.findall(r'\bL\("([^"\n]+)"',path.read_text(encoding="utf-8-sig")):
        assert key in catalog["en"], f"{path}: missing {key}"
for path in Path("core/src").glob("*.rs"):
    source = path.read_text(encoding="utf-8").split("#[cfg(test)]",1)[0]
    for key in re.findall(r'"([^"\n]*[А-Яа-яЁё][^"\n]*)"',source):
        key = key.replace("{phase}", "%@").replace("{advice}", "%@").replace("{}", "%@")
        assert key in catalog["en"], f"{path}: missing {key}"
print(f"RU/EN catalogs match ({len(catalog['en'])} entries); Swift and core messages covered")
