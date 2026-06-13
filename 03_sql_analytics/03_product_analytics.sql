-- ============================================================================
-- PRODUCT ANALYTICS QUERIES
-- ============================================================================
-- Advanced SQL for product performance, ranking, and insights
-- Features: Window Functions, CTEs, CASE Statements, Ranking Functions
-- ============================================================================

-- ============================================================================
-- 1. BEST SELLING PRODUCTS
-- ============================================================================

-- 1.1 Top 50 Products by Revenue (with Comprehensive Metrics)
WITH product_performance AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        p.price as current_price,
        COALESCE(p.cost, p.price * 0.6) as product_cost,
        SUM(oi.quantity) as total_units_sold,
        COUNT(DISTINCT o.order_id) as orders,
        COUNT(DISTINCT o.customer_id) as unique_customers,
        ROUND(SUM(oi.line_total), 2) as total_revenue,
        ROUND(AVG(oi.unit_price), 2) as avg_selling_price,
        ROUND(MIN(oi.unit_price), 2) as min_price,
        ROUND(MAX(oi.unit_price), 2) as max_price,
        ROUND(SUM(oi.line_total) - (SUM(oi.quantity) * COALESCE(p.cost, p.price * 0.6)), 2) as gross_profit,
        ROUND(((SUM(oi.line_total) - (SUM(oi.quantity) * COALESCE(p.cost, p.price * 0.6))) / SUM(oi.line_total)) * 100, 2) as profit_margin_percent
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status_id IN (3, 4) -- 'shipped' or 'delivered'
    GROUP BY p.product_id, p.product_name, c.category_name, p.price, p.cost
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) as rank,
    product_name,
    category_name,
    current_price,
    total_units_sold,
    orders,
    unique_customers,
    total_revenue,
    avg_selling_price,
    gross_profit,
    profit_margin_percent,
    ROUND((total_revenue / SUM(total_revenue) OVER ()) * 100, 2) as revenue_contribution_percent,
    NTILE(4) OVER (ORDER BY total_revenue DESC) as performance_quartile
FROM product_performance
LIMIT 50;

-- ============================================================================
-- 2. WORST SELLING PRODUCTS
-- ============================================================================

-- 2.1 Underperforming Products (Low Sales)
WITH product_sales AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        p.price,
        COALESCE(p.cost, p.price * 0.6) as product_cost,
        COUNT(DISTINCT o.order_id) as times_ordered,
        COALESCE(SUM(oi.quantity), 0) as total_units_sold,
        COALESCE(SUM(oi.line_total), 0) as total_revenue,
        DATE(p.created_date) as product_created_date,
        ROUND((JULIANDAY('now') - JULIANDAY(p.created_date)) / 30.0, 1) as months_on_catalog
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status_id IN (3, 4)
    WHERE p.is_active = 1
    GROUP BY p.product_id
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY total_revenue ASC) as rank,
    product_name,
    category_name,
    price,
    times_ordered,
    total_units_sold,
    total_revenue,
    months_on_catalog,
    CASE 
        WHEN total_revenue = 0 AND months_on_catalog > 3 THEN '🔴 Dead Stock'
        WHEN total_revenue < 100 AND months_on_catalog > 6 THEN '🟠 Low Performer'
        WHEN times_ordered < 5 AND months_on_catalog > 2 THEN '🟡 Underperformer'
        ELSE '🟢 Acceptable'
    END as action_required
FROM product_sales
WHERE total_revenue = 0 OR times_ordered < 3
ORDER BY total_revenue ASC
LIMIT 50;

-- ============================================================================
-- 3. CATEGORY PERFORMANCE ANALYSIS
-- ============================================================================

-- 3.1 Category Performance with Ranking
WITH category_metrics AS (
    SELECT 
        c.category_id,
        c.category_name,
        COUNT(DISTINCT p.product_id) as product_count,
        COUNT(DISTINCT o.order_id) as order_count,
        COUNT(DISTINCT o.customer_id) as unique_customers,
        SUM(oi.quantity) as total_units_sold,
        ROUND(SUM(oi.line_total), 2) as category_revenue,
        ROUND(AVG(oi.line_total), 2) as avg_order_value,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as revenue_per_order,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.customer_id), 2) as revenue_per_customer,
        MIN(p.price) as min_product_price,
        ROUND(AVG(p.price), 2) as avg_product_price,
        MAX(p.price) as max_product_price
    FROM categories c
    JOIN products p ON c.category_id = p.category_id
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.category_id, c.category_name
)
SELECT 
    category_name,
    product_count,
    order_count,
    unique_customers,
    category_revenue,
    ROUND((category_revenue / SUM(category_revenue) OVER ()) * 100, 2) as market_share_percent,
    total_units_sold,
    avg_order_value,
    revenue_per_customer,
    avg_product_price,
    RANK() OVER (ORDER BY category_revenue DESC) as revenue_rank,
    DENSE_RANK() OVER (ORDER BY order_count DESC) as popularity_rank,
    PERCENT_RANK() OVER (ORDER BY category_revenue) as revenue_percentile
FROM category_metrics
ORDER BY category_revenue DESC;

-- ============================================================================
-- 4. PRODUCT REVENUE CONTRIBUTION (PARETO ANALYSIS - 80/20 RULE)
-- ============================================================================

-- 4.1 Cumulative Revenue Contribution
WITH product_contribution AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        ROUND(SUM(oi.line_total), 2) as product_revenue,
        SUM(oi.quantity) as units_sold
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY p.product_id, p.product_name, c.category_name
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY product_revenue DESC) as rank,
    product_name,
    category_name,
    product_revenue,
    units_sold,
    SUM(product_revenue) OVER (
        ORDER BY product_revenue DESC 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) as cumulative_revenue,
    ROUND(
        (SUM(product_revenue) OVER (
            ORDER BY product_revenue DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(product_revenue) OVER ()) * 100, 2
    ) as cumulative_percent,
    CASE 
        WHEN (SUM(product_revenue) OVER (
            ORDER BY product_revenue DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(product_revenue) OVER ()) <= 0.80 THEN 'A - Core'
        WHEN (SUM(product_revenue) OVER (
            ORDER BY product_revenue DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(product_revenue) OVER ()) <= 0.95 THEN 'B - Growth'
        ELSE 'C - Long Tail'
    END as abc_classification
FROM product_contribution
ORDER BY product_revenue DESC
LIMIT 100;

-- ============================================================================
-- 5. PRODUCT RANKING USING WINDOW FUNCTIONS
-- ============================================================================

-- 5.1 Comprehensive Product Ranking (Multiple Dimensions)
WITH product_rankings AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        SUM(oi.quantity) as units_sold,
        COUNT(DISTINCT o.order_id) as times_purchased,
        ROUND(SUM(oi.line_total), 2) as total_revenue,
        ROUND(AVG(oi.quantity) OVER (PARTITION BY p.product_id), 2) as avg_quantity_per_order,
        COUNT(DISTINCT o.customer_id) as unique_buyers,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.customer_id), 2) as revenue_per_buyer
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY p.product_id, p.product_name, c.category_name
)
SELECT 
    product_name,
    category_name,
    units_sold,
    times_purchased,
    total_revenue,
    unique_buyers,
    avg_quantity_per_order,
    revenue_per_buyer,
    RANK() OVER (ORDER BY total_revenue DESC) as revenue_rank,
    RANK() OVER (ORDER BY units_sold DESC) as sales_volume_rank,
    RANK() OVER (ORDER BY times_purchased DESC) as popularity_rank,
    RANK() OVER (PARTITION BY category_name ORDER BY total_revenue DESC) as category_revenue_rank,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) as overall_row_num,
    NTILE(10) OVER (ORDER BY total_revenue DESC) as decile,
    PERCENT_RANK() OVER (ORDER BY total_revenue) as revenue_percentile
FROM product_rankings
ORDER BY total_revenue DESC;

-- ============================================================================
-- 6. PRODUCT PRICE ELASTICITY ANALYSIS
-- ============================================================================

-- 6.1 Price Changes and Sales Impact
WITH monthly_product_sales AS (
    SELECT 
        STRFTIME('%Y-%m', o.order_date) as month,
        p.product_id,
        p.product_name,
        ROUND(AVG(oi.unit_price), 2) as avg_price,
        SUM(oi.quantity) as units_sold,
        ROUND(SUM(oi.line_total), 2) as monthly_revenue
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY STRFTIME('%Y-%m', o.order_date), p.product_id, p.product_name
)
SELECT 
    product_name,
    month,
    avg_price,
    units_sold,
    monthly_revenue,
    LAG(avg_price) OVER (PARTITION BY product_id ORDER BY month) as prev_price,
    LAG(units_sold) OVER (PARTITION BY product_id ORDER BY month) as prev_units,
    ROUND(
        ((avg_price - LAG(avg_price) OVER (PARTITION BY product_id ORDER BY month)) / 
        LAG(avg_price) OVER (PARTITION BY product_id ORDER BY month) * 100), 2
    ) as price_change_percent,
    ROUND(
        ((units_sold - LAG(units_sold) OVER (PARTITION BY product_id ORDER BY month)) / 
        LAG(units_sold) OVER (PARTITION BY product_id ORDER BY month) * 100), 2
    ) as volume_change_percent
FROM monthly_product_sales
WHERE product_id IN (
    SELECT product_id FROM order_items 
    GROUP BY product_id 
    HAVING COUNT(DISTINCT STRFTIME('%Y-%m', order_items.created_date)) >= 3
)
ORDER BY product_name, month DESC;

-- ============================================================================
-- 7. INVENTORY HEALTH ANALYSIS
-- ============================================================================

-- 7.1 Products Needing Reorder
SELECT 
    p.product_id,
    p.product_name,
    c.category_name,
    i.quantity_on_hand,
    i.reorder_level,
    i.reorder_quantity,
    p.price,
    ROUND(SUM(oi.quantity) OVER (
        PARTITION BY p.product_id 
        ORDER BY o.order_date DESC 
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
    ) / 
    ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date) OVER (PARTITION BY p.product_id))) / 30.0), 2) as monthly_avg_sales,
    ROUND(i.quantity_on_hand / NULLIF(
        SUM(oi.quantity) OVER (
            PARTITION BY p.product_id 
            ORDER BY o.order_date DESC 
            ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
        ) / 
        ((JULIANDAY('now') - JULIANDAY(MIN(o.order_date) OVER (PARTITION BY p.product_id))) / 30.0), 0), 2) as months_of_stock,
    CASE 
        WHEN i.quantity_on_hand <= i.reorder_level THEN '🔴 URGENT - Reorder Now'
        WHEN i.quantity_on_hand <= (i.reorder_level * 1.5) THEN '🟠 WARNING - Low Stock'
        WHEN i.quantity_on_hand <= (i.reorder_level * 2) THEN '🟡 CAUTION - Monitor'
        ELSE '🟢 OK - Adequate Stock'
    END as reorder_status
FROM products p
JOIN categories c ON p.category_id = c.category_id
JOIN inventory i ON p.product_id = i.product_id
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE p.is_active = 1
GROUP BY p.product_id
HAVING i.quantity_on_hand <= (i.reorder_level * 2)
ORDER BY i.quantity_on_hand ASC;

-- ============================================================================
-- 8. NEW PRODUCT PERFORMANCE
-- ============================================================================

-- 8.1 Recently Launched Products (First 90 Days Analysis)
WITH new_products AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        DATE(p.created_date) as launch_date,
        ROUND((JULIANDAY('now') - JULIANDAY(p.created_date)), 0) as days_since_launch,
        COUNT(DISTINCT o.order_id) as orders,
        COALESCE(SUM(oi.quantity), 0) as units_sold,
        COALESCE(ROUND(SUM(oi.line_total), 2), 0) as revenue,
        COALESCE(COUNT(DISTINCT o.customer_id), 0) as unique_buyers,
        p.price as current_price
    FROM products p
    JOIN categories c ON p.category_id = c.category_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    LEFT JOIN orders o ON oi.order_id = o.order_id AND o.status_id IN (3, 4)
    WHERE ROUND((JULIANDAY('now') - JULIANDAY(p.created_date)), 0) <= 90
    GROUP BY p.product_id, p.product_name, c.category_name, p.created_date, p.price
)
SELECT 
    product_name,
    category_name,
    launch_date,
    days_since_launch,
    orders,
    units_sold,
    revenue,
    unique_buyers,
    ROUND(revenue / NULLIF(orders, 0), 2) as revenue_per_order,
    current_price,
    CASE 
        WHEN days_since_launch <= 30 AND orders >= 10 THEN '🚀 Hot Product'
        WHEN days_since_launch <= 30 AND orders >= 5 THEN '📈 Promising'
        WHEN days_since_launch > 30 AND orders >= 50 THEN '⭐ Successful Launch'
        WHEN days_since_launch > 60 AND orders < 10 THEN '⚠️ May Need Promotion'
        ELSE '📊 Monitoring'
    END as performance_status
FROM new_products
ORDER BY revenue DESC, launch_date DESC;

-- ============================================================================
-- BUSINESS INSIGHTS
-- ============================================================================
/*
Key Analysis Points:

1. Pareto Principle (80/20):
   - 20% of products typically generate 80% of revenue
   - Focus marketing and inventory on A-tier products
   - Consider discontinuing C-tier (long tail) items

2. Dead Stock:
   - Products with zero revenue after 3+ months
   - Tie up capital and warehouse space
   - Candidates for clearance sales or discontinuation

3. Price Elasticity:
   - Negative elasticity: price down, volume up
   - Positive elasticity (unusual): price up, volume up (premium products)
   - Use to optimize pricing strategy

4. Category Mix:
   - Some categories more profitable (higher margins)
   - Others drive volume but lower margins
   - Balance portfolio by revenue and profit contribution

5. New Product Success:
   - Early velocity (orders in first 30 days) predicts success
   - Consider A/B testing for new launches
   - Monitor conversion rate (units/orders)
*/
