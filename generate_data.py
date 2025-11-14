import csv
import random
import uuid
from datetime import datetime, timedelta
import os

# Config
NUM_CUSTOMERS = 75
NUM_PRODUCTS = 80
NUM_ORDERS = 120
MIN_ITEMS_PER_ORDER = 1
MAX_ITEMS_PER_ORDER = 5
DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')

random.seed(42)

first_names = [
    'James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','William','Elizabeth',
    'David','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen',
    'Christopher','Nancy','Daniel','Lisa','Matthew','Betty','Anthony','Margaret','Mark','Sandra'
]
last_names = [
    'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
    'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin'
]

cities = ['New York','Los Angeles','Chicago','Houston','Phoenix','Philadelphia','San Antonio','San Diego','Dallas','San Jose']

product_categories = ['Electronics','Home','Clothing','Sports','Toys','Books','Beauty','Grocery']
product_adjectives = ['Portable','Advanced','Wireless','Eco','Smart','Deluxe','Mini','Ultra','Classic','Premium']
product_nouns = ['Speaker','Headphones','Blender','Jacket','Sneakers','Ball','Doll','Mug','Lamp','Backpack','Novel','Cream','Coffee']

payment_methods = ['credit_card','paypal','bank_transfer','gift_card']
order_statuses = ['pending','processing','shipped','delivered','cancelled']

os.makedirs(DATA_DIR, exist_ok=True)

# Helpers

def random_date(start_days_ago=365, end_days_ago=1):
    days_ago = random.randint(end_days_ago, start_days_ago)
    dt = datetime.now() - timedelta(days=days_ago)
    # randomize time of day
    dt = dt.replace(hour=random.randint(8,22), minute=random.randint(0,59), second=random.randint(0,59))
    return dt


def write_csv(path, headers, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(rows)

# 1. customers.csv
customers = []
for i in range(1, NUM_CUSTOMERS+1):
    fname = random.choice(first_names)
    lname = random.choice(last_names)
    name = f"{fname} {lname}"
    email = f"{fname.lower()}.{lname.lower()}{i}@example.com"
    phone = f"+1-{random.randint(200,999)}-{random.randint(200,999)}-{random.randint(1000,9999)}"
    city = random.choice(cities)
    customers.append((i, name, email, phone, city))

write_csv(os.path.join(DATA_DIR, 'customers.csv'), ['customer_id','name','email','phone','city'], customers)

# 2. products.csv
products = []
for i in range(1, NUM_PRODUCTS+1):
    adj = random.choice(product_adjectives)
    noun = random.choice(product_nouns)
    pname = f"{adj} {noun}"
    category = random.choice(product_categories)
    # price based on category
    base = {
        'Electronics': random.uniform(30,500),
        'Home': random.uniform(10,300),
        'Clothing': random.uniform(10,200),
        'Sports': random.uniform(5,250),
        'Toys': random.uniform(5,80),
        'Books': random.uniform(5,40),
        'Beauty': random.uniform(5,120),
        'Grocery': random.uniform(1,50),
    }[category]
    price = round(base, 2)
    products.append((i, pname, category, f"{price:.2f}"))

write_csv(os.path.join(DATA_DIR, 'products.csv'), ['product_id','product_name','category','price'], products)

# 3. orders.csv and 4. order_items.csv and 5. payments.csv
orders = []
order_items = []
payments = []
item_id = 1
payment_id = 1

for order_id in range(1, NUM_ORDERS+1):
    customer_id = random.randint(1, NUM_CUSTOMERS)
    order_date = random_date(365, 1)
    status = random.choices(order_statuses, weights=[5,10,30,40,5])[0]
    orders.append((order_id, customer_id, order_date.strftime('%Y-%m-%d %H:%M:%S'), status))

    num_items = random.randint(MIN_ITEMS_PER_ORDER, MAX_ITEMS_PER_ORDER)
    order_total = 0.0
    for _ in range(num_items):
        product = random.choice(products)
        product_id = product[0]
        unit_price = float(product[3])
        # small variation
        unit_price = round(unit_price * random.uniform(0.85, 1.15), 2)
        quantity = random.randint(1, 5)
        line_total = unit_price * quantity
        order_total += line_total
        order_items.append((item_id, order_id, product_id, quantity, f"{unit_price:.2f}"))
        item_id += 1

    # payments: assume full payment with random method and payment date near order date
    payment_date = order_date + timedelta(days=random.randint(0,7))
    method = random.choice(payment_methods)
    amount = round(order_total, 2)
    payments.append((payment_id, order_id, payment_date.strftime('%Y-%m-%d %H:%M:%S'), method, f"{amount:.2f}"))
    payment_id += 1

write_csv(os.path.join(DATA_DIR, 'orders.csv'), ['order_id','customer_id','order_date','order_status'], orders)
write_csv(os.path.join(DATA_DIR, 'order_items.csv'), ['item_id','order_id','product_id','quantity','unit_price'], order_items)
write_csv(os.path.join(DATA_DIR, 'payments.csv'), ['payment_id','order_id','payment_date','payment_method','amount'], payments)

print('Generated CSV files in', DATA_DIR)
