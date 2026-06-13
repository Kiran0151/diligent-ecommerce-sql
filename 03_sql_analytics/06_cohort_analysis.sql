-- ============================================================================
-- COHORT ANALYSIS
-- ============================================================================
-- Monthly customer cohorts, retention matrix, revenue analysis
-- ============================================================================

-- ============================================================================
-- 1. MONTHLY CUSTOMER COHORTS
-- ============================================================================

-- 1.1 Customer Cohort Assignment and Activity
WITH customer_cohorts AS (
    SELECT 
        c.customer_id,
        STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
        STRFTIME('%Y-%m', o.order_date) as transaction_month,
        COUNT(DISTINCT o.order_id) as orders_in_month,
        SUM(oi.line_total) as revenue_in_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, STRFTIME('%Y-%m', o.order_date)
)
SELECT 
    cohort_month,
    transaction_month,
    ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0) as months_since_first,
    COUNT(DISTINCT customer_id) as customers_active,
    SUM(orders_in_month) as total_orders,
    ROUND(SUM(revenue_in_month), 2) as cohort_revenue
FROM customer_cohorts
GROUP BY cohort_month, transaction_month
ORDER BY cohort_month DESC, months_since_first ASC;

-- ============================================================================
-- 2. RETENTION MATRIX (Cohort Retention %)
-- ============================================================================

-- 2.1 Cohort Retention Percentage Table
WITH cohort_data AS (
    SELECT 
        STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
        c.customer_id,
        STRFTIME('%Y-%m', o.order_date) as transaction_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, STRFTIME('%Y-%m', o.order_date)
),
cohort_size AS (
    SELECT 
        cohort_month,
        COUNT(DISTINCT customer_id) as cohort_size
    FROM cohort_data
    WHERE ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0) = 0
    GROUP BY cohort_month
),
retention_table AS (
    SELECT 
        cd.cohort_month,
        ROUND((JULIANDAY(cd.transaction_month) - JULIANDAY(cd.cohort_month)) / 30.0, 0) as months_since_first,
        COUNT(DISTINCT cd.customer_id) as customers_retained
    FROM cohort_data cd
    GROUP BY cd.cohort_month, ROUND((JULIANDAY(cd.transaction_month) - JULIANDAY(cd.cohort_month)) / 30.0, 0)
)
SELECT 
    rt.cohort_month,
    rt.months_since_first,
    rt.customers_retained,
    cs.cohort_size,
    ROUND((rt.customers_retained / CAST(cs.cohort_size as FLOAT)) * 100, 1) as retention_percent,
    CASE 
        WHEN (rt.customers_retained / CAST(cs.cohort_size as FLOAT)) >= 0.7 THEN '🟢 Excellent'
        WHEN (rt.customers_retained / CAST(cs.cohort_size as FLOAT)) >= 0.5 THEN '🟡 Good'
        WHEN (rt.customers_retained / CAST(cs.cohort_size as FLOAT)) >= 0.3 THEN '🟠 Moderate'
        ELSE '🔴 Poor'
    END as retention_health
FROM retention_table rt
JOIN cohort_size cs ON rt.cohort_month = cs.cohort_month
WHERE rt.cohort_month >= DATE('now', '-12 months')
ORDER BY rt.cohort_month DESC, rt.months_since_first ASC;

-- ============================================================================
-- 3. COHORT REVENUE ANALYSIS
-- ============================================================================

-- 3.1 Revenue per Cohort Over Time (Cumulative)
WITH cohort_revenue AS (
    SELECT 
        STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
        c.customer_id,
        STRFTIME('%Y-%m', o.order_date) as transaction_month,
        SUM(oi.line_total) as monthly_revenue
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, STRFTIME('%Y-%m', o.order_date)
)
SELECT 
    cohort_month,
    ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0) as months_since_first,
    COUNT(DISTINCT customer_id) as active_customers,
    ROUND(SUM(monthly_revenue), 2) as cohort_revenue,
    ROUND(SUM(monthly_revenue) / COUNT(DISTINCT customer_id), 2) as revenue_per_customer,
    SUM(SUM(monthly_revenue)) OVER (
        PARTITION BY cohort_month 
        ORDER BY ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) as cumulative_revenue
FROM cohort_revenue
GROUP BY cohort_month, ROUND((JULIANDAY(transaction_month) - JULIANDAY(cohort_month)) / 30.0, 0)
ORDER BY cohort_month DESC, months_since_first ASC;

-- ============================================================================
-- 4. COHORT LIFETIME VALUE PROGRESSION
-- ============================================================================

-- 4.1 Average CLV by Cohort at Different Time Points
WITH cohort_clv AS (
    SELECT 
        STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
        c.customer_id,
        SUM(oi.line_total) as total_clv,
        ROUND((JULIANDAY('now') - JULIANDAY(MIN(o.order_date))) / 30.0, 0) as months_active
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    cohort_month,
    ROUND(AVG(CASE WHEN months_active >= 0 THEN total_clv END), 2) as avg_clv_month_0,
    ROUND(AVG(CASE WHEN months_active >= 3 THEN total_clv END), 2) as avg_clv_month_3,
    ROUND(AVG(CASE WHEN months_active >= 6 THEN total_clv END), 2) as avg_clv_month_6,
    ROUND(AVG(CASE WHEN months_active >= 12 THEN total_clv END), 2) as avg_clv_month_12,
    COUNT(DISTINCT customer_id) as total_customers_in_cohort
FROM cohort_clv
GROUP BY cohort_month
ORDER BY cohort_month DESC;

-- ============================================================================
-- 5. COHORT COMPARISON & TREND ANALYSIS
-- ============================================================================

-- 5.1 Cohort Performance Benchmarking
WITH cohort_metrics AS (
    SELECT 
        STRFTIME('%Y-%m', MIN(o.order_date)) as cohort_month,
        COUNT(DISTINCT c.customer_id) as cohort_size,
        ROUND(AVG(SUM(oi.line_total)), 2) as avg_first_order_value,
        COUNT(DISTINCT o.order_id) as total_lifetime_orders,
        ROUND(SUM(oi.line_total), 2) as cohort_ltv
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, STRFTIME('%Y-%m', MIN(o.order_date))
)
SELECT 
    cohort_month,
    cohort_size,
    avg_first_order_value,
    ROUND(SUM(total_lifetime_orders) / COUNT(*), 2) as avg_orders_per_customer,
    ROUND(SUM(cohort_ltv) / COUNT(*), 2) as avg_clv,
    ROUND(SUM(cohort_ltv), 2) as total_cohort_revenue,
    RANK() OVER (ORDER BY SUM(cohort_ltv) / COUNT(*) DESC) as revenue_rank
FROM cohort_metrics
GROUP BY cohort_month
ORDER BY cohort_month DESC;

-- ============================================================================
-- BUSINESS INSIGHTS FROM COHORT ANALYSIS
-- ============================================================================
/*

Cohort Analysis Insights:

1. RETENTION PATTERNS
   - Month 0: 100% (base cohort)
   - Month 1-3: Typical drop-off (50-70% retention)
   - Month 6+: Stable retention (plateau)
   - Sharp drop = Satisfaction issue (investigate)

2. REVENUE TRENDS
   - First 3 months: Highest revenue per cohort
   - Month 6+: Repeat purchases stabilize
   - Declining revenue: Risk of churn

3. COHORT QUALITY
   - Earlier cohorts > more mature, lower total CLV
   - Recent cohorts > less data, but trend indicators
   - Compare same time-point across cohorts

4. ACTION ITEMS
   - Low Month 1 retention: Improve onboarding
   - Declining Month 3-6: Implement engagement
   - Dropping CLV: Evaluate pricing/product quality

5. ACQUISITION IMPACT
   - If recent cohorts > early cohorts: Better marketing
   - If early cohorts > recent: Quality degradation
   - Seasonal patterns: Holiday vs regular months
*/
