-- ============================================================================
-- SALES ANALYTICS QUERIES
-- ============================================================================
-- Advanced SQL analytics for revenue, trends, and sales performance
-- Features: CTEs, Window Functions, Date Functions, Aggregations
-- ============================================================================

-- ============================================================================
-- 1. TOTAL REVENUE AND KEY METRICS
-- ============================================================================

-- 1.1 Total Revenue with Breakdown
SELECT 
    SUM(oi.line_total) as total_revenue,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    AVG(oi.line_total) as average_order_value,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as revenue_per_order,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.customer_id), 2) as revenue_per_customer
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status_id IN (3, 4); -- 'shipped' or 'delivered'

-- ============================================================================
-- 2. MONTHLY REVENUE TRENDS (WITH CTE)
-- ============================================================================

-- 2.1 Monthly Revenue with Year/Month Breakdown
WITH monthly_sales AS (
    SELECT 
        DATE_TRUNC('month', o.order_date) as month,
        STRFTIME('%Y-%m', o.order_date) as year_month,
        YEAR(o.order_date) as year,
        MONTH(o.order_date) as month_num,
        SUM(oi.line_total) as monthly_revenue,
        COUNT(DISTINCT o.order_id) as order_count,
        COUNT(DISTINCT o.customer_id) as customer_count,
        AVG(oi.line_total) as avg_order_value
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY STRFTIME('%Y-%m', o.order_date)
)
SELECT 
    year_month,
    monthly_revenue,
    order_count,
    customer_count,
    avg_order_value,
    ROUND(monthly_revenue / order_count, 2) as revenue_per_order,
    LAG(monthly_revenue) OVER (ORDER BY year_month) as previous_month_revenue,
    ROUND(
        ((monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY year_month)) 
        / LAG(monthly_revenue) OVER (ORDER BY year_month) * 100), 2
    ) as mom_growth_percent
FROM monthly_sales
ORDER BY year_month DESC;

-- ============================================================================
-- 3. QUARTERLY REVENUE TRENDS
-- ============================================================================

-- 3.1 Quarterly Revenue Analysis with Ranking
WITH quarterly_sales AS (
    SELECT 
        YEAR(o.order_date) as year,
        CEILING(MONTH(o.order_date) / 3.0) as quarter,
        CONCAT(YEAR(o.order_date), '-Q', CEILING(MONTH(o.order_date) / 3.0)) as quarter_label,
        SUM(oi.line_total) as quarterly_revenue,
        COUNT(DISTINCT o.order_id) as order_count,
        COUNT(DISTINCT o.customer_id) as customer_count
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY YEAR(o.order_date), CEILING(MONTH(o.order_date) / 3.0)
)
SELECT 
    quarter_label,
    quarterly_revenue,
    order_count,
    customer_count,
    ROUND(quarterly_revenue / order_count, 2) as avg_order_value,
    LAG(quarterly_revenue) OVER (ORDER BY year, quarter) as previous_quarter_revenue,
    ROUND(
        ((quarterly_revenue - LAG(quarterly_revenue) OVER (ORDER BY year, quarter)) 
        / LAG(quarterly_revenue) OVER (ORDER BY year, quarter) * 100), 2
    ) as qoq_growth_percent,
    RANK() OVER (ORDER BY quarterly_revenue DESC) as revenue_rank
FROM quarterly_sales
ORDER BY year DESC, quarter DESC;

-- ============================================================================
-- 4. YEAR-OVER-YEAR (YoY) GROWTH ANALYSIS
-- ============================================================================

-- 4.1 YoY Growth by Month
WITH monthly_yoy AS (
    SELECT 
        MONTH(o.order_date) as month,
        YEAR(o.order_date) as year,
        SUM(oi.line_total) as monthly_revenue,
        COUNT(DISTINCT o.order_id) as order_count
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY YEAR(o.order_date), MONTH(o.order_date)
)
SELECT 
    curr.month,
    curr.year as current_year,
    curr.monthly_revenue as current_year_revenue,
    prev.monthly_revenue as prior_year_revenue,
    ROUND(
        ((curr.monthly_revenue - prev.monthly_revenue) / prev.monthly_revenue * 100), 2
    ) as yoy_growth_percent,
    curr.order_count as current_orders,
    prev.order_count as prior_orders
FROM monthly_yoy curr
LEFT JOIN monthly_yoy prev 
    ON curr.month = prev.month 
    AND curr.year = prev.year + 1
WHERE curr.year = YEAR(CURRENT_DATE)
ORDER BY curr.month;

-- ============================================================================
-- 5. MONTH-OVER-MONTH (MoM) GROWTH ANALYSIS
-- ============================================================================

-- 5.1 MoM Growth Rate with Trend
WITH daily_revenue AS (
    SELECT 
        DATE(o.order_date) as order_date,
        SUM(oi.line_total) as daily_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY DATE(o.order_date)
)
SELECT 
    STRFTIME('%Y-%m', order_date) as month,
    SUM(daily_revenue) as total_revenue,
    COUNT(*) as days_active,
    ROUND(AVG(daily_revenue), 2) as avg_daily_revenue,
    LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date)) as prev_month_revenue,
    ROUND(
        ((SUM(daily_revenue) - LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date))) 
        / LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date)) * 100), 2
    ) as mom_growth_percent,
    CASE 
        WHEN ((SUM(daily_revenue) - LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date))) 
        / LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date)) * 100) > 10 THEN '📈 High Growth'
        WHEN ((SUM(daily_revenue) - LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date))) 
        / LAG(SUM(daily_revenue)) OVER (ORDER BY STRFTIME('%Y-%m', order_date)) * 100) > 0 THEN '📊 Moderate Growth'
        ELSE '📉 Decline'
    END as trend
FROM daily_revenue
GROUP BY STRFTIME('%Y-%m', order_date)
ORDER BY month DESC;

-- ============================================================================
-- 6. AVERAGE ORDER VALUE (AOV) ANALYSIS
-- ============================================================================

-- 6.1 AOV Trend Over Time
WITH aov_analysis AS (
    SELECT 
        STRFTIME('%Y-%m', o.order_date) as month,
        SUM(oi.line_total) as total_revenue,
        COUNT(DISTINCT o.order_id) as order_count,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as aov,
        MIN(oi.line_total) as min_order_value,
        MAX(oi.line_total) as max_order_value,
        COUNT(DISTINCT o.customer_id) as customer_count
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY STRFTIME('%Y-%m', o.order_date)
)
SELECT 
    month,
    aov,
    total_revenue,
    order_count,
    customer_count,
    min_order_value,
    max_order_value,
    LAG(aov) OVER (ORDER BY month) as prev_aov,
    ROUND(((aov - LAG(aov) OVER (ORDER BY month)) / LAG(aov) OVER (ORDER BY month) * 100), 2) as aov_change_percent
FROM aov_analysis
ORDER BY month DESC;

-- ============================================================================
-- 7. REVENUE BY CATEGORY
-- ============================================================================

-- 7.1 Category Revenue with Market Share
WITH category_revenue AS (
    SELECT 
        c.category_id,
        c.category_name,
        SUM(oi.line_total) as category_revenue,
        COUNT(DISTINCT o.order_id) as order_count,
        COUNT(DISTINCT p.product_id) as product_count,
        ROUND(AVG(oi.line_total), 2) as avg_order_value,
        SUM(oi.quantity) as total_units_sold
    FROM categories c
    JOIN products p ON c.category_id = p.category_id
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.category_id, c.category_name
)
SELECT 
    category_name,
    category_revenue,
    ROUND((category_revenue / SUM(category_revenue) OVER () * 100), 2) as market_share_percent,
    order_count,
    product_count,
    total_units_sold,
    avg_order_value,
    RANK() OVER (ORDER BY category_revenue DESC) as revenue_rank,
    PERCENT_RANK() OVER (ORDER BY category_revenue) as percentile_rank
FROM category_revenue
ORDER BY category_revenue DESC;

-- ============================================================================
-- 8. REVENUE BY PRODUCT
-- ============================================================================

-- 8.1 Top 20 Products by Revenue with Metrics
WITH product_revenue AS (
    SELECT 
        p.product_id,
        p.product_name,
        c.category_name,
        SUM(oi.line_total) as product_revenue,
        COUNT(DISTINCT o.order_id) as orders,
        SUM(oi.quantity) as units_sold,
        ROUND(AVG(oi.unit_price), 2) as avg_price,
        ROUND(SUM(oi.line_total) / SUM(oi.quantity), 2) as avg_revenue_per_unit,
        p.price as current_price,
        ROUND((p.price - COALESCE(p.cost, p.price * 0.6)) / p.price * 100, 2) as margin_percent
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
    orders,
    units_sold,
    avg_revenue_per_unit,
    current_price,
    margin_percent,
    ROUND(product_revenue / SUM(product_revenue) OVER () * 100, 2) as revenue_contribution_percent
FROM product_revenue
LIMIT 20;

-- ============================================================================
-- 9. CUMULATIVE REVENUE (Running Total)
-- ============================================================================

-- 9.1 Daily Cumulative Revenue
SELECT 
    DATE(o.order_date) as order_date,
    SUM(oi.line_total) as daily_revenue,
    SUM(SUM(oi.line_total)) OVER (
        ORDER BY DATE(o.order_date) 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) as cumulative_revenue,
    ROUND(
        SUM(SUM(oi.line_total)) OVER (
            ORDER BY DATE(o.order_date) 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(SUM(oi.line_total)) OVER () * 100, 2
    ) as cumulative_percent_of_total
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status_id IN (3, 4)
GROUP BY DATE(o.order_date)
ORDER BY order_date DESC
LIMIT 90;

-- ============================================================================
-- 10. SALES BY DAY OF WEEK
-- ============================================================================

-- 10.1 Day of Week Analysis
WITH dow_sales AS (
    SELECT 
        CASE 
            WHEN STRFTIME('%w', o.order_date) = '0' THEN 'Sunday'
            WHEN STRFTIME('%w', o.order_date) = '1' THEN 'Monday'
            WHEN STRFTIME('%w', o.order_date) = '2' THEN 'Tuesday'
            WHEN STRFTIME('%w', o.order_date) = '3' THEN 'Wednesday'
            WHEN STRFTIME('%w', o.order_date) = '4' THEN 'Thursday'
            WHEN STRFTIME('%w', o.order_date) = '5' THEN 'Friday'
            WHEN STRFTIME('%w', o.order_date) = '6' THEN 'Saturday'
        END as day_of_week,
        CAST(STRFTIME('%w', o.order_date) as INTEGER) as dow_number,
        SUM(oi.line_total) as revenue,
        COUNT(DISTINCT o.order_id) as order_count,
        COUNT(DISTINCT o.customer_id) as customer_count
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY STRFTIME('%w', o.order_date)
)
SELECT 
    day_of_week,
    revenue,
    order_count,
    customer_count,
    ROUND(revenue / order_count, 2) as avg_order_value,
    ROUND(revenue / SUM(revenue) OVER () * 100, 2) as percent_of_weekly_revenue
FROM dow_sales
ORDER BY dow_number;

-- ============================================================================
-- EXECUTION PLAN NOTES (for performance analysis)
-- ============================================================================
/*
Performance Considerations:

1. Large Table Scans:
   - order_items and orders are the largest tables
   - Index on (order_id, status_id) would help filtering

2. Aggregation Bottlenecks:
   - SUM/COUNT operations on millions of rows
   - Consider materialized views for frequently accessed metrics

3. Date Function Usage:
   - STRFTIME and DATE functions are CPU-intensive
   - Pre-compute year/month/quarter in ETL if possible

4. Window Functions:
   - LAG/LEAD operations require ordering entire result set
   - Significant memory usage for large datasets

5. CTEs (Common Table Expressions):
   - Logical optimization; performance similar to subqueries
   - Improves readability but may not improve execution speed
*/
