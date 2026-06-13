-- ============================================================================
-- VIEWS & STORED PROCEDURES
-- ============================================================================
-- Analytics views and business logic procedures
-- ============================================================================

-- ============================================================================
-- VIEWS
-- ============================================================================

-- 1. Monthly Sales Summary View
CREATE VIEW IF NOT EXISTS MonthlySalesSummary AS
SELECT 
    STRFTIME('%Y-%m', o.order_date) as month,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    ROUND(SUM(oi.line_total), 2) as total_revenue,
    ROUND(AVG(oi.line_total), 2) as avg_order_value,
    ROUND(SUM(oi.quantity), 0) as total_units_sold,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.customer_id), 2) as revenue_per_customer
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status_id IN (3, 4)
GROUP BY STRFTIME('%Y-%m', o.order_date);

-- 2. Product Performance View
CREATE VIEW IF NOT EXISTS ProductPerformance AS
WITH product_stats AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        p.price,
        COALESCE(p.cost, p.price * 0.6) as product_cost,
        SUM(oi.quantity) as units_sold,
        COUNT(DISTINCT o.order_id) as orders,
        ROUND(SUM(oi.line_total), 2) as total_revenue,
        ROUND((SUM(oi.line_total) - SUM(oi.quantity) * COALESCE(p.cost, p.price * 0.6)), 2) as gross_profit,
        i.quantity_on_hand
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status_id IN (3, 4)
    LEFT JOIN inventory i ON p.product_id = i.product_id
    GROUP BY p.product_id
)
SELECT 
    product_name,
    category_name,
    price,
    units_sold,
    orders,
    total_revenue,
    ROUND((gross_profit / NULLIF(total_revenue, 0)) * 100, 2) as profit_margin_percent,
    quantity_on_hand,
    RANK() OVER (ORDER BY total_revenue DESC) as revenue_rank
FROM product_stats;

-- 3. Customer Insights View
CREATE VIEW IF NOT EXISTS CustomerInsights AS
SELECT 
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) as customer_name,
    c.email,
    c.city,
    COUNT(DISTINCT o.order_id) as lifetime_orders,
    ROUND(SUM(oi.line_total), 2) as lifetime_value,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as avg_order_value,
    ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as days_since_last_purchase,
    CASE 
        WHEN MAX(o.order_date) >= DATE('now', '-30 days') THEN 'Active'
        WHEN MAX(o.order_date) >= DATE('now', '-90 days') THEN 'At Risk'
        ELSE 'Inactive'
    END as customer_status
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status_id IN (3, 4)
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id;

-- 4. Inventory Status View
CREATE VIEW IF NOT EXISTS InventoryStatus AS
SELECT 
    p.product_id,
    p.product_name,
    c.category_name,
    i.quantity_on_hand,
    i.reorder_level,
    i.reorder_quantity,
    COALESCE(SUM(oi.quantity) / ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date))) / 30.0), 0) as monthly_sales_rate,
    ROUND(i.quantity_on_hand / NULLIF(COALESCE(SUM(oi.quantity) / ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date))) / 30.0), 1), 0), 1) as weeks_of_inventory,
    CASE 
        WHEN i.quantity_on_hand <= i.reorder_level THEN 'URGENT'
        WHEN i.quantity_on_hand <= (i.reorder_level * 1.5) THEN 'WARNING'
        WHEN i.quantity_on_hand <= (i.reorder_level * 2) THEN 'CAUTION'
        ELSE 'OK'
    END as reorder_status
FROM inventory i
JOIN products p ON i.product_id = p.product_id
JOIN categories c ON p.category_id = c.category_id
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id
GROUP BY p.product_id;

-- 5. Revenue by Category View
CREATE VIEW IF NOT EXISTS CategoryRevenue AS
SELECT 
    c.category_name,
    COUNT(DISTINCT o.order_id) as orders,
    COUNT(DISTINCT o.customer_id) as customers,
    SUM(oi.quantity) as units_sold,
    ROUND(SUM(oi.line_total), 2) as revenue,
    ROUND(AVG(oi.line_total), 2) as avg_order_value,
    RANK() OVER (ORDER BY SUM(oi.line_total) DESC) as revenue_rank
FROM categories c
JOIN products p ON c.category_id = p.category_id
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status_id IN (3, 4)
GROUP BY c.category_id;

-- 6. Customer Churn Risk View
CREATE VIEW IF NOT EXISTS ChurnRisk AS
SELECT 
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) as customer_name,
    c.email,
    COUNT(DISTINCT o.order_id) as lifetime_orders,
    ROUND(SUM(oi.line_total), 2) as lifetime_value,
    ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as days_inactive,
    CASE 
        WHEN ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) > 180 THEN 'HIGH'
        WHEN ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) > 90 THEN 'MEDIUM'
        ELSE 'LOW'
    END as churn_risk
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status_id IN (3, 4)
LEFT JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id
HAVING ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) > 30;

-- ============================================================================
-- STORED PROCEDURES / FUNCTIONS (SQLite UDFs)
-- ============================================================================

-- Note: SQLite doesn't support traditional stored procedures,
-- but we can use Python/application code to run these queries.
-- Below are the SQL query patterns for procedures:

-- 1. GetTopSellingProducts: Returns top N products by revenue
-- Query: (See 03_sql_analytics/03_product_analytics.sql - 1.1)

-- 2. GetCustomerLifetimeValue: Returns CLV by customer
-- Query: (See 03_sql_analytics/02_customer_analytics.sql - 6.1)

-- 3. GenerateMonthlyReport: Summary metrics for a given month
CREATE VIEW IF NOT EXISTS MonthlyReport AS
SELECT 
    STRFTIME('%Y-%m', o.order_date) as month,
    'Metrics Summary' as report_type,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    ROUND(SUM(oi.line_total), 2) as total_revenue,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as aov,
    COUNT(DISTINCT p.product_id) as products_sold,
    COUNT(DISTINCT c.category_id) as categories_represented
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN categories c ON p.category_id = c.category_id
WHERE o.status_id IN (3, 4)
GROUP BY STRFTIME('%Y-%m', o.order_date);

-- 4. GenerateInventoryReport: Stock status by category
CREATE VIEW IF NOT EXISTS InventoryReport AS
SELECT 
    c.category_name,
    COUNT(p.product_id) as product_count,
    SUM(i.quantity_on_hand) as total_units,
    COUNT(CASE WHEN i.quantity_on_hand = 0 THEN 1 END) as out_of_stock,
    COUNT(CASE WHEN i.quantity_on_hand <= i.reorder_level THEN 1 END) as needs_reorder,
    ROUND(SUM(i.quantity_on_hand * p.price), 2) as total_inventory_value
FROM categories c
JOIN products p ON c.category_id = p.category_id
JOIN inventory i ON p.product_id = i.product_id
GROUP BY c.category_id;

-- ============================================================================
-- MATERIALIZED VIEW QUERIES (For Performance)
-- ============================================================================
-- These should be refreshed periodically for reporting

-- Daily Sales Summary (refresh daily)
CREATE TABLE IF NOT EXISTS DailySalesSummary AS
SELECT 
    DATE(o.order_date) as sale_date,
    COUNT(DISTINCT o.order_id) as daily_orders,
    ROUND(SUM(oi.line_total), 2) as daily_revenue,
    ROUND(AVG(oi.line_total), 2) as daily_aov
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status_id IN (3, 4)
GROUP BY DATE(o.order_date);

-- Top Customers Cache (refresh weekly)
CREATE TABLE IF NOT EXISTS TopCustomersCache AS
SELECT 
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) as customer_name,
    c.email,
    SUM(oi.line_total) as lifetime_value,
    COUNT(DISTINCT o.order_id) as order_count,
    RANK() OVER (ORDER BY SUM(oi.line_total) DESC) as value_rank
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status_id IN (3, 4)
GROUP BY c.customer_id
LIMIT 1000;

-- ============================================================================
-- REFRESH PROCEDURES (Execute via Python/Scheduler)
-- ============================================================================
/*

Python pseudocode for stored procedure execution:

def refresh_daily_sales_summary(db_path):
    conn = sqlite3.connect(db_path)
    conn.execute('DELETE FROM DailySalesSummary')
    conn.execute('''INSERT INTO DailySalesSummary
        SELECT DATE(o.order_date), 
               COUNT(...), 
               ...
        FROM orders o ...''')
    conn.commit()

def refresh_top_customers_cache(db_path):
    conn = sqlite3.connect(db_path)
    conn.execute('DELETE FROM TopCustomersCache')
    conn.execute('''INSERT INTO TopCustomersCache
        SELECT c.customer_id, 
               ..., 
               RANK() OVER (ORDER BY SUM(...) DESC)
        FROM customers c ...''')
    conn.commit()

# Schedule using APScheduler
from apscheduler.schedulers.background import BackgroundScheduler
scheduler = BackgroundScheduler()
scheduler.add_job(refresh_daily_sales_summary, 'cron', hour=0, minute=5)
scheduler.add_job(refresh_top_customers_cache, 'cron', day_of_week='sun', hour=0)
scheduler.start()

*/

-- ============================================================================
-- PERFORMANCE OPTIMIZATION INDEXES
-- ============================================================================

-- Composite Indexes for Common Queries
CREATE INDEX IF NOT EXISTS idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX IF NOT EXISTS idx_order_items_order_product ON order_items(order_id, product_id);
CREATE INDEX IF NOT EXISTS idx_payments_order_method ON payments(order_id, payment_method_id);

-- Full-text Search Index (SQLite FTS)
-- CREATE VIRTUAL TABLE product_search USING fts5(product_name, category_name);
-- INSERT INTO product_search SELECT product_name, category_name FROM products;
