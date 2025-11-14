import sqlite3
import pandas as pd
import os

DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')
DB_PATH = os.path.join(os.path.dirname(__file__), 'ecom.db')

# Read CSV files
customers_csv = os.path.join(DATA_DIR, 'customers.csv')
products_csv = os.path.join(DATA_DIR, 'products.csv')
orders_csv = os.path.join(DATA_DIR, 'orders.csv')
order_items_csv = os.path.join(DATA_DIR, 'order_items.csv')
payments_csv = os.path.join(DATA_DIR, 'payments.csv')

# Load into pandas
customers_df = pd.read_csv(customers_csv)
products_df = pd.read_csv(products_csv)
orders_df = pd.read_csv(orders_csv)
order_items_df = pd.read_csv(order_items_csv)
payments_df = pd.read_csv(payments_csv)

# Connect to SQLite and create tables
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Create tables with schemas matching CSV columns
cursor.execute('''
CREATE TABLE IF NOT EXISTS customers (
    customer_id INTEGER PRIMARY KEY,
    name TEXT,
    email TEXT,
    phone TEXT,
    city TEXT
)
''')

cursor.execute('''
CREATE TABLE IF NOT EXISTS products (
    product_id INTEGER PRIMARY KEY,
    product_name TEXT,
    category TEXT,
    price REAL
)
''')

cursor.execute('''
CREATE TABLE IF NOT EXISTS orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    order_date TEXT,
    order_status TEXT,
    FOREIGN KEY(customer_id) REFERENCES customers(customer_id)
)
''')

cursor.execute('''
CREATE TABLE IF NOT EXISTS order_items (
    item_id INTEGER PRIMARY KEY,
    order_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    unit_price REAL,
    FOREIGN KEY(order_id) REFERENCES orders(order_id),
    FOREIGN KEY(product_id) REFERENCES products(product_id)
)
''')

cursor.execute('''
CREATE TABLE IF NOT EXISTS payments (
    payment_id INTEGER PRIMARY KEY,
    order_id INTEGER,
    payment_date TEXT,
    payment_method TEXT,
    amount REAL,
    FOREIGN KEY(order_id) REFERENCES orders(order_id)
)
''')

conn.commit()

# Clear existing data before inserting
cursor.execute('DELETE FROM payments')
cursor.execute('DELETE FROM order_items')
cursor.execute('DELETE FROM orders')
cursor.execute('DELETE FROM products')
cursor.execute('DELETE FROM customers')
conn.commit()

# Insert dataframes into sqlite
customers_df.to_sql('customers', conn, if_exists='append', index=False)
products_df.to_sql('products', conn, if_exists='append', index=False)
orders_df.to_sql('orders', conn, if_exists='append', index=False)
order_items_df.to_sql('order_items', conn, if_exists='append', index=False)
payments_df.to_sql('payments', conn, if_exists='append', index=False)

conn.commit()
conn.close()

print('Data successfully loaded into SQLite')
