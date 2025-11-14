import sqlite3
from pathlib import Path

DB = Path(__file__).with_name('ecom.db')
if not DB.exists():
    print('ecom.db not found at', DB)
    raise SystemExit(1)

conn = sqlite3.connect(DB)
c = conn.cursor()
for t in ['customers','products','orders','order_items','payments']:
    try:
        c.execute(f"SELECT COUNT(*) FROM {t}")
        print(f"{t}: {c.fetchone()[0]} rows")
    except Exception as e:
        print(f"Error reading table {t}: {e}")

conn.close()
