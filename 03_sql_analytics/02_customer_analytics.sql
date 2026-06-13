-- ============================================================================
-- CUSTOMER ANALYTICS QUERIES
-- ============================================================================
-- Advanced SQL for customer lifetime value, retention, and segmentation
-- Features: CTEs, Window Functions, Date Functions, Subqueries
-- ============================================================================

-- ============================================================================
-- 1. TOP CUSTOMERS BY REVENUE
-- ============================================================================

-- 1.1 Top 50 Customers by Total Revenue
WITH customer_metrics AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        SUM(oi.line_total) as lifetime_revenue,
        COUNT(DISTINCT o.order_id) as total_orders,
        COUNT(DISTINCT DATE(o.order_date)) as days_active,
        MIN(o.order_date) as first_purchase_date,
        MAX(o.order_date) as last_purchase_date,
        ROUND((JULIANDAY(MAX(o.order_date)) - JULIANDAY(MIN(o.order_date))) / COUNT(DISTINCT o.order_id), 2) as avg_days_between_orders,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as avg_order_value
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4) -- 'shipped' or 'delivered'
    GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.city
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY lifetime_revenue DESC) as rank,
    customer_name,
    email,
    city,
    lifetime_revenue,
    total_orders,
    avg_order_value,
    avg_days_between_orders,
    first_purchase_date,
    last_purchase_date,
    ROUND(lifetime_revenue / SUM(lifetime_revenue) OVER () * 100, 2) as revenue_contribution_percent
FROM customer_metrics
LIMIT 50;

-- ============================================================================
-- 2. TOP CUSTOMERS BY ORDER FREQUENCY
-- ============================================================================

-- 2.1 Most Frequent Purchasers
WITH customer_frequency AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        COUNT(DISTINCT o.order_id) as total_orders,
        SUM(oi.line_total) as total_revenue,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as avg_order_value,
        MIN(o.order_date) as first_purchase,
        MAX(o.order_date) as last_purchase,
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as days_since_last_purchase
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    RANK() OVER (ORDER BY total_orders DESC) as frequency_rank,
    customer_name,
    email,
    total_orders,
    total_revenue,
    avg_order_value,
    days_since_last_purchase,
    CASE 
        WHEN days_since_last_purchase <= 30 THEN 'Very Active'
        WHEN days_since_last_purchase <= 90 THEN 'Active'
        WHEN days_since_last_purchase <= 180 THEN 'At Risk'
        ELSE 'Inactive'
    END as engagement_status
FROM customer_frequency
WHERE total_orders >= 5
ORDER BY total_orders DESC
LIMIT 50;

-- ============================================================================
-- 3. CUSTOMER PURCHASE FREQUENCY DISTRIBUTION
-- ============================================================================

-- 3.1 Purchase Frequency Buckets
WITH frequency_distribution AS (
    SELECT 
        COUNT(DISTINCT o.order_id) as purchase_count,
        COUNT(DISTINCT c.customer_id) as customer_count,
        ROUND(COUNT(DISTINCT c.customer_id) / (SELECT COUNT(DISTINCT customer_id) FROM orders) * 100, 2) as percent_of_customers,
        SUM(oi.line_total) as segment_revenue,
        ROUND(AVG(oi.line_total), 2) as avg_order_value
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4) OR o.order_id IS NULL
    GROUP BY c.customer_id
)
SELECT 
    CASE 
        WHEN purchase_count = 0 THEN '0 Orders (Prospects)'
        WHEN purchase_count = 1 THEN '1 Order'
        WHEN purchase_count BETWEEN 2 AND 5 THEN '2-5 Orders'
        WHEN purchase_count BETWEEN 6 AND 10 THEN '6-10 Orders'
        WHEN purchase_count > 10 THEN '10+ Orders'
    END as frequency_segment,
    COUNT(*) as customer_count,
    ROUND(COUNT(*) / (SELECT COUNT(DISTINCT customer_id) FROM customers) * 100, 2) as percent_of_base,
    ROUND(SUM(segment_revenue), 2) as total_revenue,
    ROUND(AVG(avg_order_value), 2) as avg_aov
FROM frequency_distribution
GROUP BY CASE 
    WHEN purchase_count = 0 THEN 0
    WHEN purchase_count = 1 THEN 1
    WHEN purchase_count BETWEEN 2 AND 5 THEN 2
    WHEN purchase_count BETWEEN 6 AND 10 THEN 3
    WHEN purchase_count > 10 THEN 4
END
ORDER BY frequency_segment;

-- ============================================================================
-- 4. CUSTOMER RETENTION ANALYSIS
-- ============================================================================

-- 4.1 Monthly Retention Cohort (First Purchase Month)
WITH first_purchase_cohort AS (
    SELECT 
        c.customer_id,
        STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
        STRFTIME('%Y-%m', o.order_date) as transaction_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, STRFTIME('%Y-%m', o.order_date)
),
cohort_data AS (
    SELECT 
        cohort_month,
        ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0) as months_since_first,
        COUNT(DISTINCT customer_id) as returning_customers
    FROM first_purchase_cohort
    GROUP BY cohort_month, ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0)
),
cohort_sizes AS (
    SELECT 
        cohort_month,
        COUNT(DISTINCT customer_id) as cohort_size
    FROM first_purchase_cohort
    WHERE ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0) = 0
    GROUP BY cohort_month
)
SELECT 
    cd.cohort_month,
    cd.months_since_first,
    cd.returning_customers,
    cs.cohort_size,
    ROUND((cd.returning_customers / CAST(cs.cohort_size as FLOAT)) * 100, 2) as retention_percent
FROM cohort_data cd
JOIN cohort_sizes cs ON cd.cohort_month = cs.cohort_month
ORDER BY cd.cohort_month DESC, cd.months_since_first;

-- ============================================================================
-- 5. CUSTOMER CHURN ANALYSIS
-- ============================================================================

-- 5.1 Churned vs Active Customers (By Definition: No Purchase in Last X Days)
WITH customer_activity AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        MAX(o.order_date) as last_purchase_date,
        COUNT(DISTINCT o.order_id) as total_purchases,
        SUM(oi.line_total) as lifetime_value,
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as days_inactive
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    CASE 
        WHEN days_inactive IS NULL THEN 'Never Purchased'
        WHEN days_inactive <= 30 THEN 'Active'
        WHEN days_inactive <= 90 THEN 'At Risk (30-90 days)'
        WHEN days_inactive <= 180 THEN 'At Risk (90-180 days)'
        WHEN days_inactive > 180 THEN 'Churned (180+ days)'
    END as customer_status,
    COUNT(*) as customer_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM customers) * 100, 2) as percent_of_base,
    ROUND(SUM(lifetime_value), 2) as segment_revenue,
    ROUND(AVG(total_purchases), 2) as avg_purchases_per_customer,
    ROUND(AVG(lifetime_value), 2) as avg_ltv
FROM customer_activity
GROUP BY CASE 
    WHEN days_inactive IS NULL THEN 0
    WHEN days_inactive <= 30 THEN 1
    WHEN days_inactive <= 90 THEN 2
    WHEN days_inactive <= 180 THEN 3
    WHEN days_inactive > 180 THEN 4
END
ORDER BY customer_status;

-- 5.2 High-Value Churned Customers (Reactivation Targets)
SELECT 
    CONCAT(c.first_name, ' ', c.last_name) as customer_name,
    c.email,
    c.city,
    MAX(o.order_date) as last_purchase_date,
    ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as days_since_last_purchase,
    COUNT(DISTINCT o.order_id) as lifetime_orders,
    ROUND(SUM(oi.line_total), 2) as lifetime_value,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as avg_order_value
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status_id IN (3, 4)
GROUP BY c.customer_id
HAVING 
    ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) > 90  -- Inactive 90+ days
    AND SUM(oi.line_total) > 500  -- High-value customers
ORDER BY lifetime_value DESC
LIMIT 50;

-- ============================================================================
-- 6. CUSTOMER LIFETIME VALUE (CLV) ANALYSIS
-- ============================================================================

-- 6.1 CLV Calculation with Segmentation
WITH clv_calculation AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        MIN(o.order_date) as first_purchase_date,
        MAX(o.order_date) as last_purchase_date,
        ROUND((JULIANDAY(MAX(o.order_date)) - JULIANDAY(MIN(o.order_date))) / 365.0, 2) as customer_lifetime_years,
        COUNT(DISTINCT o.order_id) as total_orders,
        ROUND(SUM(oi.line_total), 2) as total_revenue,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as avg_order_value,
        ROUND(COUNT(DISTINCT o.order_id) / ((JULIANDAY(MAX(o.order_date)) - JULIANDAY(MIN(o.order_date))) / 365.0), 2) as annual_purchase_frequency
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    customer_name,
    email,
    city,
    total_revenue as clv,
    total_orders,
    avg_order_value,
    annual_purchase_frequency,
    customer_lifetime_years,
    ROUND(total_revenue / NULLIF(customer_lifetime_years, 0), 2) as annual_revenue_value,
    CASE 
        WHEN total_revenue >= PERCENTILE_CONT(0.75) OVER () THEN 'VIP'
        WHEN total_revenue >= PERCENTILE_CONT(0.50) OVER () THEN 'High Value'
        WHEN total_revenue >= PERCENTILE_CONT(0.25) OVER () THEN 'Medium Value'
        ELSE 'Low Value'
    END as clv_segment,
    PERCENT_RANK() OVER (ORDER BY total_revenue) as clv_percentile
FROM clv_calculation
ORDER BY total_revenue DESC;

-- 6.2 Projected CLV (Future Value Prediction)
WITH customer_trends AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        SUM(oi.line_total) as historical_clv,
        COUNT(DISTINCT o.order_id) as total_orders,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) as avg_order_value,
        -- Last 12 months metrics
        SUM(CASE WHEN o.order_date >= DATE('now', '-1 year') THEN oi.line_total ELSE 0 END) as revenue_last_12m,
        COUNT(DISTINCT CASE WHEN o.order_date >= DATE('now', '-1 year') THEN o.order_id END) as orders_last_12m
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    customer_name,
    historical_clv,
    revenue_last_12m,
    ROUND(revenue_last_12m * 3, 2) as projected_clv_3_years,
    ROUND(revenue_last_12m * 5, 2) as projected_clv_5_years,
    total_orders,
    orders_last_12m,
    ROUND(CAST(orders_last_12m as FLOAT) / 12, 2) as monthly_order_rate,
    avg_order_value
FROM customer_trends
WHERE revenue_last_12m > 0
ORDER BY projected_clv_5_years DESC
LIMIT 50;

-- ============================================================================
-- 7. CUSTOMER GEOGRAPHIC ANALYSIS
-- ============================================================================

-- 7.1 Revenue by City
WITH city_performance AS (
    SELECT 
        c.city,
        COUNT(DISTINCT c.customer_id) as customer_count,
        COUNT(DISTINCT o.order_id) as order_count,
        ROUND(SUM(oi.line_total), 2) as total_revenue,
        ROUND(AVG(oi.line_total), 2) as avg_order_value,
        ROUND(SUM(oi.line_total) / COUNT(DISTINCT c.customer_id), 2) as revenue_per_customer
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.city
)
SELECT 
    city,
    customer_count,
    order_count,
    total_revenue,
    ROUND((total_revenue / SUM(total_revenue) OVER ()) * 100, 2) as revenue_share_percent,
    avg_order_value,
    revenue_per_customer,
    RANK() OVER (ORDER BY total_revenue DESC) as city_rank
FROM city_performance
ORDER BY total_revenue DESC;

-- ============================================================================
-- 8. NEW CUSTOMER ACQUISITION
-- ============================================================================

-- 8.1 New Customers (First Purchase) by Month
WITH new_customers AS (
    SELECT 
        STRFTIME('%Y-%m', o.order_date) as signup_month,
        COUNT(DISTINCT c.customer_id) as new_customers,
        COUNT(DISTINCT o.order_id) as first_orders,
        ROUND(SUM(oi.line_total), 2) as first_order_revenue,
        ROUND(AVG(oi.line_total), 2) as avg_first_order_value
    FROM customers c
    JOIN (
        SELECT customer_id, MIN(order_date) as order_date
        FROM orders
        WHERE status_id IN (3, 4)
        GROUP BY customer_id
    ) first_order ON c.customer_id = first_order.customer_id
    JOIN orders o ON c.customer_id = o.customer_id AND o.order_date = first_order.order_date
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY STRFTIME('%Y-%m', o.order_date)
)
SELECT 
    signup_month,
    new_customers,
    first_orders,
    first_order_revenue,
    avg_first_order_value,
    LAG(new_customers) OVER (ORDER BY signup_month) as prev_month_new_customers,
    ROUND(((new_customers - LAG(new_customers) OVER (ORDER BY signup_month)) / 
           LAG(new_customers) OVER (ORDER BY signup_month) * 100), 2) as mom_growth_percent
FROM new_customers
ORDER BY signup_month DESC;

-- ============================================================================
-- BUSINESS INSIGHTS & EXECUTION NOTES
-- ============================================================================
/*
Key Metrics Explained:

1. CLV (Customer Lifetime Value):
   - Total revenue generated by a customer over their entire relationship
   - Foundation for customer segmentation and targeting strategies
   - Higher CLV = higher budget for acquisition and retention

2. Retention Rate:
   - Percentage of customers from a cohort who remain active
   - First month represents base cohort size (100%)
   - Decline indicates need for retention programs

3. Churn Definition:
   - Typically 90-180 days without purchase (depends on industry)
   - At-Risk: 30-90 days (intervention phase)
   - Churned: 180+ days (reactivation campaigns)

4. RFM Indicators:
   - Recency: days_since_last_purchase
   - Frequency: total_orders
   - Monetary: total_revenue (CLV)

5. Geographic Insights:
   - Identify high-growth vs mature markets
   - Prioritize marketing spend by city performance
   - Consider regional logistics optimization
*/
