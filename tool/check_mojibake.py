from pathlib import Path
import sys

roots = [Path("lib")]
extra = [Path("server.js")]

patterns = (
    "Рђ", "Рµ", "Рѕ", "СЃ", "С‚", "С‡", "СЊ",
    "рџ", "вЂ", "вќ", "вњ", "вљ", "╨", "╤", "тА",
)

files = []
for root in roots:
    if root.exists():
        files.extend(root.rglob("*.dart"))

files.extend(p for p in extra if p.exists())

bad = []

for path in files:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        bad.append((path, f"invalid UTF-8: {error}"))
        continue

    replacement = text.count("\ufffd")
    mojibake = sum(text.count(marker) for marker in patterns)
    box_chars = sum(1 for char in text if 0x2500 <= ord(char) <= 0x257F)

    if replacement or mojibake or box_chars:
        bad.append(
            (
                path,
                f"replacement={replacement}, "
                f"mojibake={mojibake}, "
                f"box={box_chars}",
            )
        )

if bad:
    print("UTF-8 / MOJIBAKE CHECK: FAILED")
    for path, reason in bad:
        print(f"  {path}: {reason}")
    sys.exit(1)

print("UTF-8 / MOJIBAKE CHECK: CLEAN")
