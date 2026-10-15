"""Извлекает локализуемые строки интерфейса (кириллица) из Swift-кода приложения.

Пропускает: значения Phrase(ru:...), Text(verbatim:), служебные списки (демо-данные, заголовки CSV, подсказки распознавателю).
Интерполяции превращаются в спецификаторы формата так же, как это делает Xcode: целые → %lld, остальное → %@.
"""
import json
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "MonoFinance"
SKIP_FILES = {"DemoData.swift", "Services.swift"}
CYR = re.compile(r"[А-Яа-яЁё]")
INT_PATTERN = re.compile(r"(\.count\b|^count$|Count$|\+ 1|\.day$|rawValue|\binterval$|inserted$|skippedDuplicates$|\bindex\b)")

def literals(line):
    """Строковые литералы строки с учётом экранирования и вложенных интерполяций."""
    i, n = 0, len(line)
    while i < n:
        if line[i] == '"' and not line.startswith('"""', i):
            start = i
            i += 1
            depth = 0
            buf = []
            while i < n:
                c = line[i]
                if c == "\\" and i + 1 < n and line[i + 1] == "(":
                    # интерполяция: ищем парную скобку
                    j = i + 2
                    level = 1
                    while j < n and level > 0:
                        if line[j] == "(":
                            level += 1
                        elif line[j] == ")":
                            level -= 1
                        elif line[j] == '"':
                            # строка внутри интерполяции
                            j += 1
                            while j < n and line[j] != '"':
                                if line[j] == "\\":
                                    j += 1
                                j += 1
                        j += 1
                    buf.append(("interp", line[i + 2:j - 1]))
                    i = j
                    continue
                if c == "\\" and i + 1 < n:
                    buf.append(("text", line[i:i + 2]))
                    i += 2
                    continue
                if c == '"':
                    yield start, i + 1, buf
                    i += 1
                    break
                buf.append(("text", c))
                i += 1
        else:
            i += 1

def to_key(parts):
    out = []
    for kind, value in parts:
        if kind == "text":
            if value == "\\n":
                out.append("\n")
            elif value == '\\"':
                out.append('"')
            elif value == "\\\\":
                out.append("\\")
            elif value.startswith("\\u{"):
                out.append(value)
            else:
                out.append(value.replace("%", "%%"))
        else:
            expr = value.strip()
            out.append("%lld" if INT_PATTERN.search(expr) else "%@")
    return "".join(out)

keys = {}
for dirpath, _, files in os.walk(ROOT):
    for name in files:
        if not name.endswith(".swift") or name in SKIP_FILES:
            continue
        path = os.path.join(dirpath, name)
        in_examples = False
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            if "examples = [" in line or "var strings = [" in line or "contextualStrings" in line:
                in_examples = True
            if in_examples:
                if "]" in line and "[" not in line.split("]")[0][-1:]:
                    if stripped.endswith("]") or stripped.endswith("],"):
                        in_examples = False
                continue
            if "let word =" in line or ".applicationName" in line:
                continue
            for start, end, parts in literals(line):
                raw = line[start:end]
                if not CYR.search(raw):
                    continue
                before = line[:start]
                if re.search(r"(ru|verbatim):\s*$", before):
                    continue
                if re.search(r"Phrase\(ru:\s*$", before):
                    continue
                key = to_key(parts)
                # \u{202F} и подобные — в реальные символы
                key = re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), key)
                if not CYR.search(key):
                    continue
                keys.setdefault(key, []).append(f"{os.path.relpath(path, ROOT)}:{number}")

print(json.dumps({k: v for k, v in sorted(keys.items())}, ensure_ascii=False, indent=1))
