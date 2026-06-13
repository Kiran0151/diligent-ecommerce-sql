-- ============================================================================
-- Database Migration: Upgrade to 3NF Normalized Schema
-- ============================================================================
-- This script migrates from the simple schema to the normalized 3NF schema
-- ============================================================================

-- Step 1: Create new dimension tables
CREATE TABLE IF NOT EXISTS categories (
    category_id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_category_name CHECK (LENGTH(TRIM(category_name)) > 0)
);

CREATE TABLE IF NOT EXISTS payment_methods (
    payment_method_id INTEGER PRIMARY KEY AUTOINCREMENT,
    method_name TEXT NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT 1,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_method_name CHECK (LENGTH(TRIM(method_name)) > 0)
);

CREATE TABLE IF NOT EXISTS order_statuses (
    status_id INTEGER PRIMARY KEY AUTOINCREMENT,
    status_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_status_name CHECK (LENGTH(TRIM(status_name)) > 0)
);

-- Step 2: Insert dimension data
INSERT OR IGNORE INTO order_statuses (status_name, description) VALUES
('pending', 'Order received, awaiting processing'),
('processing', 'Order being prepared for shipment'),
('shipped', 'Order dispatched to customer'),
('delivered', 'Order successfully delivered'),
('cancelled', 'Order cancelled by customer or system');

INSERT OR IGNORE INTO payment_methods (method_name) VALUES
('credit_card'),
('debit_card'),
('paypal'),
('bank_transfer'),
('apple_pay'),
('google_pay'),
('gift_card');

INSERT OR IGNORE INTO categories (category_name, description) VALUES
('Electronics', 'Electronic devices and gadgets'),
('Home', 'Home and garden products'),
('Clothing', 'Apparel and fashion items'),
('Sports', 'Sports and outdoor equipment'),
('Toys', 'Toys and games'),
('Books', 'Books and publications'),
('Beauty', 'Beauty and personal care'),
('Grocery', 'Food and grocery items');

-- Step 3: Backup existing data (if not already backed up)
CREATE TABLE IF NOT EXISTS customers_backup AS SELECT * FROM customers;
CREATE TABLE IF NOT EXISTS products_backup AS SELECT * FROM products;
CREATE TABLE IF NOT EXISTS orders_backup AS SELECT * FROM orders;
CREATE TABLE IF NOT EXISTS order_items_backup AS SELECT * FROM order_items;
CREATE TABLE IF NOT EXISTS payments_backup AS SELECT * FROM payments;

-- Step 4: Alter existing tables to add new columns and constraints

-- Enhance customers table
ALTER TABLE customers ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS last_name TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'USA';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT 1;

-- Migrate name data (split 'name' into first_name and last_name)
UPDATE customers 
SET first_name = TRIM(SUBSTR(name, 1, INSTR(name, ' ') - 1)),
    last_name = TRIM(SUBSTR(name, INSTR(name, ' ') + 1))
WHERE first_name IS NULL AND name IS NOT NULL;

-- Enhance products table
ALTER TABLE products ADD COLUMN IF NOT EXISTS category_id INTEGER;
ALTER TABLE products ADD COLUMN IF NOT EXISTS cost DECIMAL(10, 2);
ALTER TABLE products ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku TEXT UNIQUE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT 1;

-- Assign categories to products (random distribution for existing data)
UPDATE products 
SET category_id = (ABS(RANDOM()) % 8) + 1, 
    cost = ROUND(price * 0.6, 2),
    sku = 'SKU-' || product_id || '-' || UPPER(SUBSTR(product_name, 1, 3))
WHERE category_id IS NULL;

-- Enhance orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS status_id INTEGER DEFAULT 4; -- 'delivered'
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tax_amount DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_cost DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Update status_id based on order_status text (if it exists)
UPDATE orders 
SET status_id = (
    CASE 
        WHEN order_status = 'pending' THEN 1
        WHEN order_status = 'processing' THEN 2
        WHEN order_status = 'shipped' THEN 3
        WHEN order_status = 'delivered' THEN 4
        WHEN order_status = 'cancelled' THEN 5
        ELSE 4
    END
)
WHERE order_status IS NOT NULL;

-- Calculate total_amount from order_items if not already populated
UPDATE orders 
SET total_amount = (
    SELECT SUM(quantity * unit_price) 
    FROM order_items 
    WHERE order_items.order_id = orders.order_id
)
WHERE total_amount IS NULL;

-- Enhance order_items table
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS discount_percent DECIMAL(5, 2) DEFAULT 0;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Step 5: Create inventory table
CREATE TABLE IF NOT EXISTS inventory (
    inventory_id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL UNIQUE,
    quantity_on_hand INTEGER NOT NULL DEFAULT 0,
    reorder_level INTEGER NOT NULL DEFAULT 10,
    reorder_quantity INTEGER NOT NULL DEFAULT 50,
    warehouse_location TEXT,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_product_inventory FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT check_quantity CHECK (quantity_on_hand >= 0),
    CONSTRAINT check_reorder_level CHECK (reorder_level > 0)
);

-- Initialize inventory with reasonable stock levels
INSERT OR IGNORE INTO inventory (product_id, quantity_on_hand, reorder_level, reorder_quantity)
SELECT product_id, 
       50 + ABS(RANDOM()) % 200 as quantity_on_hand,
       10,
       100
FROM products 
WHERE product_id NOT IN (SELECT product_id FROM inventory);

-- Step 6: Enhance payments table
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_method_id INTEGER;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS transaction_id TEXT UNIQUE;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS is_refunded BOOLEAN DEFAULT 0;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refund_date TIMESTAMP;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Map payment methods from text to IDs
UPDATE payments 
SET payment_method_id = (
    CASE 
        WHEN payment_method = 'credit_card' THEN 1
        WHEN payment_method = 'debit_card' THEN 2
        WHEN payment_method = 'paypal' THEN 3
        WHEN payment_method = 'bank_transfer' THEN 4
        WHEN payment_method = 'apple_pay' THEN 5
        WHEN payment_method = 'google_pay' THEN 6
        WHEN payment_method = 'gift_card' THEN 7
        ELSE 1
    END
)
WHERE payment_method_id IS NULL AND payment_method IS NOT NULL;

-- Set default payment method if none specified
UPDATE payments 
SET payment_method_id = 1 
WHERE payment_method_id IS NULL;

-- Generate transaction IDs
UPDATE payments 
SET transaction_id = 'TXN-' || payment_id || '-' || DATE(payment_date)
WHERE transaction_id IS NULL;

-- Step 7: Create indexes
CREATE INDEX IF NOT EXISTS idx_customer_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customer_city ON customers(city);
CREATE INDEX IF NOT EXISTS idx_customer_created ON customers(created_date);
CREATE INDEX IF NOT EXISTS idx_product_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_product_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_product_price ON products(price);
CREATE INDEX IF NOT EXISTS idx_product_active ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_order_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_date ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_order_status ON orders(status_id);
CREATE INDEX IF NOT EXISTS idx_order_total ON orders(total_amount);
CREATE INDEX IF NOT EXISTS idx_item_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_item_product ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_payment_order ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_method ON payments(payment_method_id);
CREATE INDEX IF NOT EXISTS idx_payment_date ON payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_inventory_reorder ON inventory(quantity_on_hand, reorder_level);
CREATE INDEX IF NOT EXISTS idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX IF NOT EXISTS idx_order_items_order_product ON order_items(order_id, product_id);

-- Step 8: Verify migration
SELECT 'Migration Complete!' as status;
SELECT COUNT(*) as customer_count FROM customers;
SELECT COUNT(*) as product_count FROM products;
SELECT COUNT(*) as order_count FROM orders;
SELECT COUNT(*) as inventory_count FROM inventory;
SELECT COUNT(*) as category_count FROM categories;
SELECT COUNT(*) as status_count FROM order_statuses;
SELECT COUNT(*) as method_count FROM payment_methods;
