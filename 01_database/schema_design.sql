-- ============================================================================
-- E-Commerce Analytics Platform - Database Schema (3NF Normalized)
-- ============================================================================
-- Author: Data Analytics Team
-- Purpose: Production-grade e-commerce database design
-- Last Updated: 2026-06-13
-- ============================================================================

-- ============================================================================
-- DIMENSION TABLES (Reference Data)
-- ============================================================================

-- Product Categories (Dimension)
CREATE TABLE categories (
    category_id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_category_name CHECK (LENGTH(TRIM(category_name)) > 0)
);

-- Payment Methods (Dimension)
CREATE TABLE payment_methods (
    payment_method_id INTEGER PRIMARY KEY AUTOINCREMENT,
    method_name TEXT NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT 1,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_method_name CHECK (LENGTH(TRIM(method_name)) > 0)
);

-- Order Status (Dimension)
CREATE TABLE order_statuses (
    status_id INTEGER PRIMARY KEY AUTOINCREMENT,
    status_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_status_name CHECK (LENGTH(TRIM(status_name)) > 0)
);

-- ============================================================================
-- FACT TABLES (Core Business Entities)
-- ============================================================================

-- Customers (Fact)
CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone TEXT,
    city TEXT NOT NULL,
    country TEXT DEFAULT 'USA',
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 1,
    
    CONSTRAINT check_email CHECK (email LIKE '%@%.%'),
    CONSTRAINT check_names CHECK (LENGTH(TRIM(first_name)) > 0 AND LENGTH(TRIM(last_name)) > 0)
);

-- Products (Fact with FK to Categories)
CREATE TABLE products (
    product_id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_name TEXT NOT NULL,
    category_id INTEGER NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    cost DECIMAL(10, 2),
    description TEXT,
    sku TEXT NOT NULL UNIQUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 1,
    
    CONSTRAINT fk_category FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT check_price CHECK (price > 0),
    CONSTRAINT check_cost CHECK (cost IS NULL OR cost >= 0),
    CONSTRAINT check_product_name CHECK (LENGTH(TRIM(product_name)) > 0)
);

-- Inventory (Tracking Stock Levels)
CREATE TABLE inventory (
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

-- Orders (Fact with FK to Customers and Order Status)
CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
    order_date TIMESTAMP NOT NULL,
    status_id INTEGER NOT NULL,
    total_amount DECIMAL(12, 2),
    discount_amount DECIMAL(10, 2) DEFAULT 0,
    tax_amount DECIMAL(10, 2) DEFAULT 0,
    shipping_cost DECIMAL(10, 2) DEFAULT 0,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_customer_order FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_order_status FOREIGN KEY (status_id) REFERENCES order_statuses(status_id),
    CONSTRAINT check_total CHECK (total_amount >= 0),
    CONSTRAINT check_discount CHECK (discount_amount >= 0),
    CONSTRAINT check_tax CHECK (tax_amount >= 0),
    CONSTRAINT check_shipping CHECK (shipping_cost >= 0)
);

-- Order Items (Transactional Detail)
CREATE TABLE order_items (
    item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    line_total DECIMAL(12, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    discount_percent DECIMAL(5, 2) DEFAULT 0,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_order_items FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_product_items FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT check_qty CHECK (quantity > 0),
    CONSTRAINT check_unit_price CHECK (unit_price > 0),
    CONSTRAINT check_discount_pct CHECK (discount_percent >= 0 AND discount_percent <= 100)
);

-- Payments (Audit Trail)
CREATE TABLE payments (
    payment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL,
    payment_method_id INTEGER NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    payment_date TIMESTAMP NOT NULL,
    transaction_id TEXT UNIQUE,
    is_refunded BOOLEAN DEFAULT 0,
    refund_date TIMESTAMP,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_payment_method FOREIGN KEY (payment_method_id) REFERENCES payment_methods(payment_method_id),
    CONSTRAINT check_payment_amount CHECK (amount > 0)
);

-- ============================================================================
-- INDEXES (Performance Optimization)
-- ============================================================================

-- Customers Indexes
CREATE INDEX idx_customer_email ON customers(email);
CREATE INDEX idx_customer_city ON customers(city);
CREATE INDEX idx_customer_created ON customers(created_date);

-- Products Indexes
CREATE INDEX idx_product_category ON products(category_id);
CREATE INDEX idx_product_sku ON products(sku);
CREATE INDEX idx_product_price ON products(price);
CREATE INDEX idx_product_active ON products(is_active);

-- Orders Indexes
CREATE INDEX idx_order_customer ON orders(customer_id);
CREATE INDEX idx_order_date ON orders(order_date);
CREATE INDEX idx_order_status ON orders(status_id);
CREATE INDEX idx_order_total ON orders(total_amount);
CREATE INDEX idx_order_created ON orders(created_date);

-- Order Items Indexes
CREATE INDEX idx_item_order ON order_items(order_id);
CREATE INDEX idx_item_product ON order_items(product_id);
CREATE INDEX idx_item_line_total ON order_items(line_total);

-- Payments Indexes
CREATE INDEX idx_payment_order ON payments(order_id);
CREATE INDEX idx_payment_method ON payments(payment_method_id);
CREATE INDEX idx_payment_date ON payments(payment_date);
CREATE INDEX idx_payment_refunded ON payments(is_refunded);

-- Inventory Indexes
CREATE INDEX idx_inventory_reorder ON inventory(quantity_on_hand, reorder_level);

-- Composite Indexes for Common Queries
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_order_items_order_product ON order_items(order_id, product_id);

-- ============================================================================
-- DESIGN DECISIONS & NORMALIZATION NOTES
-- ============================================================================
/*

1. NORMALIZATION (Up to 3NF):
   - 1NF: Atomic values, no repeating groups
   - 2NF: All non-key attributes depend on entire primary key
   - 3NF: No transitive dependencies among non-key attributes

   IMPROVEMENTS MADE:
   a) Created separate dimension tables:
      - categories (extracted from products)
      - payment_methods (extracted from payments)
      - order_statuses (extracted from orders)
      
   b) Added inventory table:
      - Separates inventory management from products
      - Tracks stock levels independently
      
   c) Decomposed order table:
      - Separated order header from order items
      - Each order item tracks quantity and price independently

2. PRIMARY & FOREIGN KEYS:
   - Each table has a surrogate key (INTEGER PRIMARY KEY)
   - Foreign keys enforce referential integrity
   - CASCADE delete handled via application logic

3. CONSTRAINTS:
   - CHECK constraints validate data ranges
   - UNIQUE constraints prevent duplicates (email, SKU, category names)
   - NOT NULL constraints enforce data completeness

4. TIMESTAMPS:
   - created_date: Immutable record creation time
   - last_updated: Tracks record modifications (useful for CDC)
   - order_date: Business date (separate from system timestamp)

5. GENERATED COLUMNS:
   - line_total in order_items: Auto-calculated from quantity * unit_price
   - Ensures consistency, eliminates storage redundancy

6. INDEXING STRATEGY:
   - Single-column indexes on frequently queried columns
   - Composite indexes for common join/filter patterns
   - B-Tree indexes (SQLite default) for range queries
   
7. SOFT DELETES:
   - is_active flag for historical data retention
   - Enables audit trails without physical deletion

*/

-- ============================================================================
-- SAMPLE DATA INSERTION
-- ============================================================================

-- Insert Default Order Statuses
INSERT OR IGNORE INTO order_statuses (status_name, description) VALUES
('pending', 'Order received, awaiting processing'),
('processing', 'Order being prepared for shipment'),
('shipped', 'Order dispatched to customer'),
('delivered', 'Order successfully delivered'),
('cancelled', 'Order cancelled by customer or system');

-- Insert Default Payment Methods
INSERT OR IGNORE INTO payment_methods (method_name) VALUES
('credit_card'),
('debit_card'),
('paypal'),
('bank_transfer'),
('apple_pay'),
('google_pay'),
('gift_card');

-- Insert Sample Categories
INSERT OR IGNORE INTO categories (category_name, description) VALUES
('Electronics', 'Electronic devices and gadgets'),
('Home', 'Home and garden products'),
('Clothing', 'Apparel and fashion items'),
('Sports', 'Sports and outdoor equipment'),
('Toys', 'Toys and games'),
('Books', 'Books and publications'),
('Beauty', 'Beauty and personal care'),
('Grocery', 'Food and grocery items');
