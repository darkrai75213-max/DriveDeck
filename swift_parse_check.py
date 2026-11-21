"""Parseo sintáctico real de los archivos Swift con tree-sitter-swift."""
import sys
from pathlib import Path

from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parent
parser = Parser(Language(tree_sitter_swift.language()))
errors = []

for file in sorted(ROOT.rglob("*.swift")):
    source = file.read_bytes()
    tree = parser.parse(source)
    if tree.root_node.has_error:
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == "ERROR" or node.is_missing:
                line = node.start_point[0] + 1
                text = source.splitlines()[line - 1].decode("utf-8", "replace")
                errors.append(f"{file.relative_to(ROOT)}:{line} nodo {node.type}: {text.strip()[:100]}")
            stack.extend(node.children)

if errors:
    for error in errors:
        print("ERROR SINTÁCTICO:", error)
    sys.exit(1)

print(f"OK: {len(list(ROOT.rglob('*.swift')))} archivos Swift parseados sin errores de sintaxis.")
