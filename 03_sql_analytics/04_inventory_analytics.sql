-- ============================================================================
-- INVENTORY ANALYTICS QUERIES
-- ============================================================================
-- Fast and slow moving products, reorder alerts, stock optimization
-- ============================================================================

-- ============================================================================
-- 1. FAST MOVING PRODUCTS (HIGH VELOCITY)
-- ============================================================================

-- 1.1 High Turnover Products (Last 30 Days)
SELECT 
    p.product_id,
    p.product_name,
    c.category_name,
    i.quantity_on_hand,
    SUM(oi.quantity) as units_sold_30d,
    COUNT(DISTINCT o.order_id) as orders_30d,
    i.quantity_on_hand + SUM(oi.quantity) as stock_turnover,
    ROUND(i.quantity_on_hand / NULLIF(SUM(oi.quantity), 0), 2) as days_of_inventory,
    ROUND(SUM(oi.line_total), 2) as revenue_30d,
    p.price,
    ROUND((i.quantity_on_hand * p.price), 2) as inventory_value,
    CASE 
        WHEN days_of_inventory <= 5 THEN '🔥 Very Fast Moving'
        WHEN days_of_inventory <= 10 THEN '⚡ Fast Moving'
        WHEN days_of_inventory <= 20 THEN '📊 Normal'
        ELSE '🐌 Slow Moving'
    END as velocity
FROM products p
JOIN categories c ON p.category_id = c.category_id
JOIN inventory i ON p.product_id = i.product_id
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id AND o.order_date >= DATE('now', '-30 days')
WHERE p.is_active = 1
GROUP BY p.product_id
ORDER BY units_sold_30d DESC;

-- ============================================================================
-- 2. SLOW MOVING PRODUCTS (LOW VELOCITY)
-- ============================================================================

-- 2.1 Slow Moving Products with Analysis
WITH product_velocity AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        i.quantity_on_hand,
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(oi.created_date))) / 30.0, 1) as months_since_last_sale,
        COALESCE(SUM(oi.quantity), 0) as lifetime_units_sold,
        COALESCE(ROUND(SUM(oi.line_total), 2), 0) as lifetime_revenue,
        p.price,
        COALESCE(p.cost, p.price * 0.6) as product_cost,
        ROUND((i.quantity_on_hand * p.price), 2) as inventory_value,
        ROUND((i.quantity_on_hand * COALESCE(p.cost, p.price * 0.6)), 2) as inventory_cost
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN inventory i ON p.product_id = i.product_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    WHERE p.is_active = 1
    GROUP BY p.product_id
)
SELECT 
    product_name,
    category_name,
    quantity_on_hand,
    months_since_last_sale,
    lifetime_units_sold,
    lifetime_revenue,
    inventory_value,
    inventory_cost,
    CASE 
        WHEN lifetime_units_sold = 0 THEN '🔴 Dead Stock'
        WHEN months_since_last_sale > 6 AND lifetime_units_sold < 10 THEN '🟠 Very Slow'
        WHEN months_since_last_sale > 3 AND lifetime_units_sold < 20 THEN '🟡 Slow'
        ELSE '🟢 Acceptable'
    END as slowness_level,
    CASE 
        WHEN lifetime_units_sold = 0 THEN 'Discontinue'
        WHEN months_since_last_sale > 6 THEN 'Consider Clearance'
        WHEN months_since_last_sale > 3 THEN 'Price Reduction'
        ELSE 'Monitor'
    END as action_recommendation
FROM product_velocity
WHERE lifetime_units_sold < 30 OR (lifetime_units_sold = 0)
ORDER BY inventory_value DESC;

-- ============================================================================
-- 3. REORDER ALERT SYSTEM
-- ============================================================================

-- 3.1 Urgent Reorder Alerts
WITH sales_velocity AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        i.quantity_on_hand,
        i.reorder_level,
        i.reorder_quantity,
        COALESCE(SUM(oi.quantity) / ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date))) / 30.0), 0) as monthly_sales_rate
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN inventory i ON p.product_id = i.product_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id
    WHERE p.is_active = 1
    GROUP BY p.product_id
)
SELECT 
    product_id,
    product_name,
    category_name,
    quantity_on_hand,
    reorder_level,
    reorder_quantity,
    ROUND(monthly_sales_rate, 2) as estimated_monthly_sales,
    ROUND(quantity_on_hand / NULLIF(monthly_sales_rate, 0), 1) as weeks_of_inventory,
    CASE 
        WHEN quantity_on_hand <= reorder_level THEN 'URGENT - Order Immediately'
        WHEN quantity_on_hand <= (reorder_level * 1.25) THEN 'HIGH - Order This Week'
        WHEN quantity_on_hand <= (reorder_level * 1.5) THEN 'MEDIUM - Plan Order'
        ELSE 'LOW - No Action'
    END as reorder_priority,
    ROUND(reorder_quantity * (SELECT AVG(price) FROM products WHERE product_id = sales_velocity.product_id), 2) as estimated_reorder_cost
FROM sales_velocity
WHERE quantity_on_hand <= (reorder_level * 1.5)
ORDER BY reorder_priority, quantity_on_hand ASC;

-- 3.2 Lead Time Analysis for Reorder Planning
WITH avg_lead_time AS (
    SELECT 
        p.product_id,
        p.product_name,
        i.quantity_on_hand,
        i.reorder_quantity,
        ROUND(SUM(oi.quantity) / 
            ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date))) / 30.0), 2) as monthly_demand,
        ROUND(i.quantity_on_hand / (SUM(oi.quantity) / 
            ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date))) / 30.0)), 1) as days_until_stockout,
        7 as assumed_lead_time_days -- Adjust based on actual supplier lead times
    FROM products p
    JOIN inventory i ON p.product_id = i.product_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id
    GROUP BY p.product_id
)
SELECT 
    product_id,
    product_name,
    quantity_on_hand,
    reorder_quantity,
    ROUND(monthly_demand, 2) as monthly_demand,
    days_until_stockout,
    assumed_lead_time_days,
    CASE 
        WHEN days_until_stockout <= assumed_lead_time_days THEN '🔴 ORDER IMMEDIATELY'
        WHEN days_until_stockout <= (assumed_lead_time_days * 1.5) THEN '🟠 ORDER WITHIN 48H'
        WHEN days_until_stockout <= (assumed_lead_time_days * 2) THEN '🟡 SCHEDULE ORDER'
        ELSE '🟢 OK'
    END as action
FROM avg_lead_time
WHERE days_until_stockout IS NOT NULL AND days_until_stockout > 0
ORDER BY days_until_stockout ASC;

-- ============================================================================
-- 4. STOCK AVAILABILITY REPORT
-- ============================================================================

-- 4.1 Current Stock Status by Category
SELECT 
    c.category_name,
    COUNT(p.product_id) as total_products,
    SUM(i.quantity_on_hand) as total_stock_units,
    ROUND(AVG(i.quantity_on_hand), 2) as avg_stock_per_product,
    SUM(i.quantity_on_hand < i.reorder_level) as products_below_reorder,
    COUNT(CASE WHEN i.quantity_on_hand = 0 THEN 1 END) as out_of_stock_count,
    ROUND(SUM(i.quantity_on_hand * p.price), 2) as total_inventory_value,
    ROUND(SUM(i.quantity_on_hand * COALESCE(p.cost, p.price * 0.6)), 2) as total_inventory_cost,
    ROUND(100.0 * SUM(CASE WHEN i.quantity_on_hand > i.reorder_level THEN 1 ELSE 0 END) / COUNT(p.product_id), 2) as percent_in_stock
FROM categories c
JOIN products p ON c.category_id = p.category_id
JOIN inventory i ON p.product_id = i.product_id
WHERE p.is_active = 1
GROUP BY c.category_id, c.category_name
ORDER BY total_inventory_value DESC;

-- 4.2 Out of Stock Products
SELECT 
    p.product_id,
    p.product_name,
    c.category_name,
    i.quantity_on_hand,
    i.reorder_level,
    i.reorder_quantity,
    ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) / 1.0, 0) as days_since_last_order,
    COUNT(DISTINCT o.order_id) as orders_waiting
FROM products p
JOIN categories c ON p.category_id = c.category_id
JOIN inventory i ON p.product_id = i.product_id
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE i.quantity_on_hand = 0 AND p.is_active = 1
GROUP BY p.product_id
ORDER BY days_since_last_order ASC;

-- ============================================================================
-- 5. INVENTORY TURNOVER ANALYSIS
-- ============================================================================

-- 5.1 Inventory Turnover Ratio
WITH inventory_metrics AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        i.quantity_on_hand,
        COALESCE(ROUND(AVG(p.cost), 2), ROUND(AVG(p.price * 0.6), 2)) as avg_cost,
        COALESCE(SUM(oi.quantity), 0) as annual_units_sold,
        ROUND((JULIANDAY('now') - JULIANDAY(MIN(p.created_date))) / 365.0, 2) as years_active,
        ROUND(SUM(oi.quantity) / ((JULIANDAY('now') - JULIANDAY(MIN(p.created_date))) / 365.0), 2) as annual_turnover_rate
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN inventory i ON p.product_id = i.product_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    WHERE p.is_active = 1
    GROUP BY p.product_id
)
SELECT 
    product_name,
    category_name,
    quantity_on_hand,
    annual_units_sold,
    ROUND(annual_turnover_rate, 2) as turnover_ratio,
    ROUND(365.0 / NULLIF(annual_turnover_rate, 0), 1) as days_inventory_outstanding,
    CASE 
        WHEN annual_turnover_rate >= 12 THEN 'Very High (Weekly Turnover)'
        WHEN annual_turnover_rate >= 6 THEN 'High (Bi-weekly)'
        WHEN annual_turnover_rate >= 4 THEN 'Good (Monthly)'
        WHEN annual_turnover_rate >= 2 THEN 'Moderate (Quarterly)'
        ELSE 'Low (Rare/Dead Stock)'
    END as turnover_category
FROM inventory_metrics
ORDER BY annual_turnover_rate DESC;

-- ============================================================================
-- 6. WAREHOUSE LOCATION OPTIMIZATION
-- ============================================================================

-- 6.1 Products by Warehouse Location with Performance
SELECT 
    i.warehouse_location,
    COUNT(DISTINCT p.product_id) as product_count,
    SUM(i.quantity_on_hand) as total_units,
    COUNT(DISTINCT CASE WHEN i.quantity_on_hand = 0 THEN p.product_id END) as out_of_stock_count,
    COUNT(DISTINCT CASE WHEN i.quantity_on_hand <= i.reorder_level THEN p.product_id END) as low_stock_count,
    ROUND(SUM(i.quantity_on_hand * p.price), 2) as location_inventory_value,
    ROUND(SUM(oi.line_total), 2) as sales_from_location
FROM inventory i
JOIN products p ON i.product_id = p.product_id
LEFT JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY i.warehouse_location
ORDER BY location_inventory_value DESC;

-- ============================================================================
-- 7. STOCK FORECASTING (Simple Moving Average)
-- ============================================================================

-- 7.1 Forecast Next Month Inventory Needs
WITH sales_trend AS (
    SELECT 
        p.product_id,
        p.product_name,
        STRFTIME('%Y-%m', o.order_date) as month,
        SUM(oi.quantity) as monthly_quantity
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date >= DATE('now', '-6 months')
    GROUP BY p.product_id, STRFTIME('%Y-%m', o.order_date)
)
SELECT 
    p.product_id,
    p.product_name,
    i.quantity_on_hand,
    ROUND(AVG(monthly_quantity), 0) as avg_monthly_sales_6m,
    ROUND(AVG(monthly_quantity) * 1.2, 0) as forecasted_next_month_demand,
    ROUND(AVG(monthly_quantity) * 1.2 - i.quantity_on_hand, 0) as reorder_quantity_suggested,
    i.reorder_level,
    i.reorder_quantity,
    CASE 
        WHEN ROUND(AVG(monthly_quantity) * 1.2, 0) > i.quantity_on_hand THEN 'ORDER NEEDED'
        ELSE 'SUFFICIENT'
    END as forecast_status
FROM products p
JOIN inventory i ON p.product_id = i.product_id
LEFT JOIN sales_trend ON p.product_id = sales_trend.product_id
WHERE p.is_active = 1
GROUP BY p.product_id
HAVING AVG(monthly_quantity) > 0
ORDER BY forecasted_next_month_demand DESC;

-- ============================================================================
-- EXECUTION NOTES
-- ============================================================================
/*
Key Inventory Metrics:

1. Velocity = Units Sold / Inventory Level
   - High velocity = fast turnover, low holding costs
   - Low velocity = excess inventory, holding costs

2. Days of Inventory Outstanding (DIO)
   - 365 / Turnover Ratio
   - Lower is better (less capital tied up)
   - Industry average: 30-60 days

3. Reorder Point = (Daily Demand × Lead Time) + Safety Stock
   - Prevents stockouts
   - Accounts for demand variability and supply delays

4. Economic Order Quantity (EOQ)
   - Balances ordering costs vs. holding costs
   - Formula: √(2DS/H) where D=demand, S=order cost, H=holding cost

5. ABC Classification
   - A: High value, high frequency (tight control)
   - B: Medium value/frequency (moderate control)
   - C: Low value or slow-moving (minimal control)
*/
