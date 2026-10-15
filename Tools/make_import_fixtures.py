#!/usr/bin/env python3
"""Генерирует тестовые выписки для MonoImportTests (запускать из корня репозитория).
Файлы создаются сторонними инструментами (openpyxl, zlib), чтобы проверять разбор не на собственных данных."""
import datetime, os, random, zlib, zipfile, io
from openpyxl import Workbook

OUT = os.path.join(os.path.dirname(__file__), "..", "Packages", "MonoKit", "Tests", "MonoImportTests", "Fixtures")
os.makedirs(OUT, exist_ok=True)

# 1. XLSX: преамбула, заголовки, даты Excel, суммы со знаком, общие строки, пустая строка, итоговая строка.
wb = Workbook()
ws = wb.active
ws.title = "Выписка"
ws.append(["Выписка по карте", None, None, None])
ws.append(["Период: 01.10.2026 – 14.10.2026", None, None, None])
ws.append([])
ws.append(["Дата операции", "Описание", "Сумма", "Валюта"])
rows = [
    (datetime.datetime(2026, 10, 1, 9, 15), "KORZINKA CHILANZAR 12 TASHKENT UZ", -245000, "UZS"),
    (datetime.datetime(2026, 10, 2, 13, 5), "YANDEX GO", -32000.5, "UZS"),
    (datetime.datetime(2026, 10, 2, 13, 5), "YANDEX GO", -32000.5, "UZS"),   # честный повтор в тот же момент
    (datetime.datetime(2026, 10, 5, 10, 0), "Зачисление заработной платы", 12000000, "UZS"),
    (datetime.datetime(2026, 10, 6, 18, 40), "Комиссия за перевод", -5000, "UZS"),
    (datetime.datetime(2026, 10, 7, 20, 10), "EVOS MAGIC CITY", -85000, "UZS"),
    (datetime.datetime(2026, 10, 9, 11, 0), "Возврат: UZUM MARKET", 150000, "UZS"),
    (datetime.datetime(2026, 10, 10, 12, 0), "AMAZON", -20, "USD"),
]
for r in rows:
    ws.append(list(r))
for row in ws.iter_rows(min_row=5, max_row=4 + len(rows), min_col=1, max_col=1):
    for cell in row:
        cell.number_format = "dd.mm.yyyy hh:mm"
ws.append([None, "Итого", 11722999, None])
ws2 = wb.create_sheet("Пустой")
wb.save(os.path.join(OUT, "statement.xlsx"))

# 2. CSV в Windows-1251, разделитель «;», отдельные колонки дебет/кредит, десятичная запятая и пробелы в разрядах.
csv1251 = (
    "Дата;Время;Назначение платежа;Дебет;Кредит\r\n"
    "14.10.2026;08:30;Оплата: Makro Yunusabad;1 250 000,00;\r\n"
    "14.10.2026;19:02;Пополнение с карты Uzum;;500 000,00\r\n"
    "13.10.2026;12:00;\"Кафе \"\"Сафия\"\"; торт\";180 000,00;\r\n"
)
with open(os.path.join(OUT, "statement_cp1251.csv"), "wb") as f:
    f.write(csv1251.encode("cp1251"))

# 3. CSV UTF-8 с BOM, разделитель «,», ISO-даты, суммы в американском формате.
csvutf = (
    "Date,Merchant,Amount,Currency\n"
    "2026-10-03,\"Netflix, Inc.\",\"-1,250.00\",USD\n"
    "2026-10-04,Upwork Escrow,\"2,400.00\",USD\n"
)
with open(os.path.join(OUT, "statement_utf8_bom.csv"), "wb") as f:
    f.write(b"\xef\xbb\xbf" + csvutf.encode("utf-8"))

# 4. Эталонные raw-DEFLATE потоки (без заголовка zlib): разные уровни, повторы, случайные данные.
random.seed(42)
samples = {
    "text": ("Корзинка 245000 сум; " * 400).encode("utf-8"),
    "random": bytes(random.getrandbits(8) for _ in range(20000)),
    "mixed": b"".join(random.choice([b"AAAA", b"xyz", bytes([random.getrandbits(8)])]) for _ in range(30000)),
}
for name, data in samples.items():
    for level in (0, 1, 9):
        c = zlib.compressobj(level, zlib.DEFLATED, -15)
        raw = c.compress(data) + c.flush()
        with open(os.path.join(OUT, f"deflate_{name}_{level}.bin"), "wb") as f:
            f.write(raw)
    with open(os.path.join(OUT, f"deflate_{name}.orig"), "wb") as f:
        f.write(data)

# 5. ZIP с «stored» и «deflate» записями и комментарием в конце.
buffer = io.BytesIO()
with zipfile.ZipFile(buffer, "w") as z:
    z.writestr(zipfile.ZipInfo("stored.txt"), "hello stored", compress_type=zipfile.ZIP_STORED)
    z.writestr(zipfile.ZipInfo("deflated.txt"), "hello deflated " * 100, compress_type=zipfile.ZIP_DEFLATED)
    z.comment = b"MONO test archive"
with open(os.path.join(OUT, "archive.zip"), "wb") as f:
    f.write(buffer.getvalue())
print("fixtures:", sorted(os.listdir(OUT)))
