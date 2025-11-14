import sqlite3
import json
from pathlib import Path

DB = Path(__file__).with_name('ecom.db')
OUTPUT = Path(__file__).with_name('data.json')

if not DB.exists():
    print(f'Database not found: {DB}')
    raise SystemExit(1)

conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row  # Enable column access by name

data = {}

# Export each table
tables = ['customers', 'products', 'orders', 'order_items', 'payments']
for table in tables:
    cursor = conn.cursor()
    cursor.execute(f"SELECT * FROM {table}")
    rows = cursor.fetchall()
    data[table] = [dict(row) for row in rows]
    print(f"Exported {len(rows)} rows from {table}")

# Export query results (top orders)
cursor = conn.cursor()
query = """
SELECT 
    c.customer_id,
    c.name AS customer_name,
    o.order_id,
    SUM(oi.quantity * oi.unit_price) AS total_order_value,
    COUNT(oi.item_id) AS number_of_items
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
GROUP BY c.customer_id, c.name, o.order_id
ORDER BY total_order_value DESC
LIMIT 20
"""
cursor.execute(query)
rows = cursor.fetchall()
data['top_orders'] = [dict(row) for row in rows]
print(f"Exported {len(rows)} top orders")

conn.close()

# Write to JSON file
with open(OUTPUT, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)

print(f'\nData exported to {OUTPUT}')
