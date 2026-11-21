import re
from pathlib import Path

p = Path(__file__).parent / "DriveDeck" / "MediaFeature.swift"
lines = p.read_text(encoding="utf-8").splitlines()
depth = 0
for number, line in enumerate(lines, 1):
    cleaned = re.sub(r"//.*$", "", line)
    cleaned = re.sub(r'"(?:\\.|[^"\\])*"', '""', cleaned)
    depth += cleaned.count("{") - cleaned.count("}")
    if 520 <= number <= 665 and line.strip() == "}" and len(line) - len(line.lstrip()) <= 12:
        print(number, "depth", depth, repr(line))
