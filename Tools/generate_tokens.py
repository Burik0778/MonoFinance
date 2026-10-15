#!/usr/bin/env python3
"""Генерирует Swift- и CSS-токены из Design/tokens.json и проверяет контрастность текста (WCAG).

Запуск из корня репозитория:  python3 Tools/generate_tokens.py
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TOKENS = os.path.join(ROOT, "Design", "tokens.json")
SWIFT_OUT = os.path.join(ROOT, "MonoFinance", "DesignSystem", "Tokens.generated.swift")
CSS_OUT = os.path.join(ROOT, "Design", "preview", "tokens.css")
REPORT_OUT = os.path.join(ROOT, "Design", "contrast-report.md")


def parse_hex(value):
    value = value.lstrip("#")
    r, g, b = int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)
    a = int(value[6:8], 16) / 255 if len(value) == 8 else 1.0
    return r, g, b, a


def luminance(rgb):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb[:3]
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def blend(fg, bg):
    r, g, b, a = fg
    return tuple(round(fg[i] * a + bg[i] * (1 - a)) for i in range(3)) + (1.0,)


def contrast(fg, bg):
    l1, l2 = luminance(fg), luminance(bg)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def swift_rgba(hex_value):
    r, g, b, a = parse_hex(hex_value)
    return f"RGBA({r}, {g}, {b}, {a:.3f})"


def main():
    with open(TOKENS, encoding="utf-8") as f:
        tokens = json.load(f)

    lines = [
        "// Сгенерировано Tools/generate_tokens.py из Design/tokens.json — не редактируйте вручную.",
        "import SwiftUI",
        "",
        "enum MonoTokens {",
        "    enum Palette {",
    ]
    for name, spec in tokens["color"].items():
        lines.append(f"        /// {spec['role']}")
        lines.append(f"        static let {name} = DynamicColor(dark: {swift_rgba(spec['dark'])}, light: {swift_rgba(spec['light'])})")
    lines.append("    }")
    lines.append("")
    lines.append("    enum Skin {")
    for name, stops in tokens["skin"].items():
        values = ", ".join(swift_rgba(s) for s in stops)
        lines.append(f"        static let {name}: [RGBA] = [{values}]")
    lines.append("    }")
    lines.append("")
    lines.append("    enum Spacing {")
    for name, value in tokens["spacing"].items():
        lines.append(f"        static let {name}: CGFloat = {value}")
    lines.append("    }")
    lines.append("")
    lines.append("    enum Radius {")
    for name, value in tokens["radius"].items():
        lines.append(f"        static let {name}: CGFloat = {value}")
    lines.append("    }")
    lines.append("")
    lines.append("    enum Typography {")
    for name, spec in tokens["font"].items():
        tracking = spec.get("tracking", 0)
        lines.append(
            f"        static let {name} = FontToken(size: {spec['size']}, weight: .{spec['weight']}, "
            f"style: .{spec['design']}, relativeTo: .{spec['relativeTo']}, tracking: {tracking})"
        )
    lines.append("    }")
    lines.append("")
    lines.append("    enum Motion {")
    for name, spec in tokens["motion"].items():
        if isinstance(spec, dict):
            lines.append(f"        static let {name} = SpringToken(response: {spec['response']}, damping: {spec['damping']})")
        else:
            lines.append(f"        static let {name}Duration: Double = {spec}")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    os.makedirs(os.path.dirname(SWIFT_OUT), exist_ok=True)
    with open(SWIFT_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    # CSS для HTML-превью
    css = ["/* Сгенерировано Tools/generate_tokens.py из Design/tokens.json */"]
    for mode in ("dark", "light"):
        selector = ":root, .theme-dark" if mode == "dark" else ".theme-light"
        css.append(selector + " {")
        for name, spec in tokens["color"].items():
            r, g, b, a = parse_hex(spec[mode])
            css.append(f"  --{name}: rgba({r}, {g}, {b}, {a:.3f});")
        css.append("}")
    css.append(":root {")
    for name, stops in tokens["skin"].items():
        css.append(f"  --skin-{name}: linear-gradient(135deg, {', '.join(stops)});")
    for name, value in tokens["spacing"].items():
        css.append(f"  --space-{name}: {value}px;")
    for name, value in tokens["radius"].items():
        css.append(f"  --radius-{name}: {value}px;")
    css.append("}")
    os.makedirs(os.path.dirname(CSS_OUT), exist_ok=True)
    with open(CSS_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(css) + "\n")

    # Контрастность: текст и акценты на фонах (WCAG 2.1: 4.5 — обычный текст, 3.0 — крупный текст и графика)
    report = ["# Контрастность токенов (WCAG 2.1)", "", "| Режим | Текст | Фон | Контраст | Норма | Итог |", "|---|---|---|---|---|---|"]
    failures = []
    checks = [("textPrimary", 4.5), ("textSecondary", 4.5), ("textTertiary", 3.0),
              ("electric", 3.0), ("emerald", 3.0), ("coral", 3.0), ("violet", 3.0), ("cyan", 3.0), ("tangerine", 3.0)]
    for mode in ("dark", "light"):
        for surface in ("background", "surface1", "surface2"):
            bg = parse_hex(tokens["color"][surface][mode])
            for name, minimum in checks:
                fg = blend(parse_hex(tokens["color"][name][mode]), bg)
                ratio = contrast(fg, bg)
                ok = ratio >= minimum
                if not ok:
                    failures.append(f"{mode}: {name} на {surface} = {ratio:.2f} < {minimum}")
                report.append(f"| {mode} | {name} | {surface} | {ratio:.2f} | {minimum} | {'✅' if ok else '❌'} |")
    with open(REPORT_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")

    print(f"Swift: {os.path.relpath(SWIFT_OUT, ROOT)}")
    print(f"CSS:   {os.path.relpath(CSS_OUT, ROOT)}")
    print(f"Отчёт: {os.path.relpath(REPORT_OUT, ROOT)}")
    if failures:
        print("Недостаточный контраст:\n  " + "\n  ".join(failures))
        sys.exit(1)
    print("Контрастность: все проверки пройдены")


if __name__ == "__main__":
    main()
