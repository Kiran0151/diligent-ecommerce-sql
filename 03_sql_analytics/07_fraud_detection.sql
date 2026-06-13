-- ============================================================================
-- FRAUD DETECTION MODULE
-- ============================================================================
-- Identifies suspicious orders, high-risk customers, unusual patterns
-- Uses: Risk scoring, anomaly detection, velocity checks
-- ============================================================================

-- ============================================================================
-- 1. SUSPICIOUSLY LARGE ORDERS
-- ============================================================================

-- 1.1 Unusually Large Orders (Statistical Outliers)
WITH order_stats AS (
    SELECT 
        PERCENTILE_CONT(0.75) OVER () as q75,
        PERCENTILE_CONT(0.25) OVER () as q25,
        COUNT(*) as total_orders
    FROM (
        SELECT SUM(oi.line_total) as order_total
        FROM orders o
        JOIN order_items oi ON o.order_id = oi.order_id
        WHERE o.status_id IN (3, 4)
        GROUP BY o.order_id
    )
),
large_orders AS (
    SELECT 
        o.order_id,
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        o.order_date,
        ROUND(SUM(oi.line_total), 2) as order_total,
        COUNT(DISTINCT oi.product_id) as unique_products,
        SUM(oi.quantity) as total_items,
        ROUND(AVG(c_history.avg_order_value), 2) as customer_avg_order_value,
        ROUND(SUM(oi.line_total) / NULLIF(AVG(c_history.avg_order_value), 0), 2) as times_avg_multiplier
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN customers c ON o.customer_id = c.customer_id
    LEFT JOIN (
        SELECT 
            customer_id,
            AVG(oi2.line_total) as avg_order_value
        FROM order_items oi2
        JOIN orders o2 ON oi2.order_id = o2.order_id
        WHERE o2.status_id IN (3, 4)
        GROUP BY customer_id
    ) c_history ON c.customer_id = c_history.customer_id
    GROUP BY o.order_id
    HAVING order_total > (SELECT q75 FROM order_stats) + ((SELECT q75 FROM order_stats) - (SELECT q25 FROM order_stats)) * 1.5
)
SELECT 
    order_id,
    customer_name,
    email,
    city,
    order_date,
    order_total,
    unique_products,
    total_items,
    customer_avg_order_value,
    ROUND(times_avg_multiplier, 2) as deviation_from_avg,
    CASE 
        WHEN times_avg_multiplier > 10 THEN '🔴 CRITICAL - Immediate Review'
        WHEN times_avg_multiplier > 5 THEN '🟠 HIGH - Likely Fraud'
        WHEN times_avg_multiplier > 3 THEN '🟡 MEDIUM - Review'
        ELSE '🟢 OK'
    END as fraud_risk
FROM large_orders
ORDER BY order_total DESC;

-- ============================================================================
-- 2. MULTIPLE ORDERS IN SHORT TIMEFRAME
-- ============================================================================

-- 2.1 Rapid Repeat Orders (Velocity Check)
WITH rapid_orders AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        COUNT(DISTINCT o.order_id) as orders_in_period,
        MIN(o.order_date) as first_order_date,
        MAX(o.order_date) as last_order_date,
        ROUND((JULIANDAY(MAX(o.order_date)) - JULIANDAY(MIN(o.order_date))), 1) as days_span,
        SUM(oi.line_total) as total_revenue,
        ROUND(AVG(o.total_amount), 2) as avg_order_value
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
      AND o.order_date >= DATE('now', '-7 days')
    GROUP BY c.customer_id
    HAVING COUNT(DISTINCT o.order_id) >= 3
)
SELECT 
    customer_name,
    email,
    orders_in_period,
    days_span,
    total_revenue,
    avg_order_value,
    ROUND(orders_in_period / NULLIF(days_span, 0), 2) as orders_per_day,
    CASE 
        WHEN days_span <= 1 AND orders_in_period >= 5 THEN '🔴 CRITICAL - Bot Activity'
        WHEN days_span <= 3 AND orders_in_period >= 4 THEN '🟠 HIGH - Suspicious Velocity'
        WHEN days_span <= 7 AND orders_in_period >= 3 THEN '🟡 MEDIUM - Unusual Activity'
        ELSE '🟢 OK'
    END as fraud_risk
FROM rapid_orders
ORDER BY orders_per_day DESC;

-- ============================================================================
-- 3. HIGH-RISK CUSTOMER IDENTIFICATION
-- ============================================================================

-- 3.1 High-Risk Customer Scoring
WITH customer_risk AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        c.created_date,
        COUNT(DISTINCT o.order_id) as total_orders,
        ROUND((JULIANDAY('now') - JULIANDAY(c.created_date)), 0) as days_as_customer,
        ROUND(SUM(oi.line_total), 2) as lifetime_revenue,
        COUNT(DISTINCT CASE WHEN p.is_refunded = 1 THEN 1 END) as refund_count,
        MAX(CASE WHEN ROUND((JULIANDAY('now') - JULIANDAY(o.order_date))) <= 1 THEN o.total_amount ELSE 0 END) as latest_order_amount,
        -- Risk Scoring
        CASE WHEN days_as_customer < 7 THEN 1 ELSE 0 END as new_account_score,
        CASE WHEN refund_count > 3 THEN 2 WHEN refund_count > 1 THEN 1 ELSE 0 END as refund_score,
        CASE WHEN ROUND(SUM(oi.line_total)) > 
            (SELECT AVG(total) FROM (SELECT SUM(line_total) as total FROM order_items GROUP BY order_id)) * 5 
            THEN 2 ELSE 0 END as high_spend_score,
        CASE WHEN COUNT(DISTINCT o.order_id) >= 10 THEN 0 ELSE 1 END as low_order_volume_score
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status_id IN (3, 4)
    LEFT JOIN order_items oi ON o.order_id = oi.order_id
    LEFT JOIN payments p ON o.order_id = p.order_id
    GROUP BY c.customer_id
)
SELECT 
    customer_name,
    email,
    city,
    days_as_customer,
    total_orders,
    lifetime_revenue,
    refund_count,
    latest_order_amount,
    (new_account_score + refund_score + high_spend_score + low_order_volume_score) as risk_score,
    CASE 
        WHEN (new_account_score + refund_score + high_spend_score + low_order_volume_score) >= 5 THEN '🔴 CRITICAL'
        WHEN (new_account_score + refund_score + high_spend_score + low_order_volume_score) >= 3 THEN '🟠 HIGH'
        WHEN (new_account_score + refund_score + high_spend_score + low_order_volume_score) >= 1 THEN '🟡 MEDIUM'
        ELSE '🟢 LOW'
    END as risk_level
FROM customer_risk
WHERE (new_account_score + refund_score + high_spend_score + low_order_volume_score) > 0
ORDER BY risk_score DESC
LIMIT 100;

-- ============================================================================
-- 4. UNUSUAL PURCHASING PATTERNS
-- ============================================================================

-- 4.1 Geographic Anomaly Detection
WITH customer_locations AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city as profile_city,
        COUNT(DISTINCT o.order_id) as total_orders
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_id
),
order_locations AS (
    SELECT 
        o.customer_id,
        c.city as order_city,
        COUNT(*) as orders_from_city
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY o.customer_id, c.city
)
SELECT 
    cl.customer_name,
    cl.email,
    cl.profile_city,
    ol.order_city,
    ol.orders_from_city,
    CASE 
        WHEN ol.order_city != cl.profile_city AND ol.orders_from_city = 1 THEN '🟡 UNUSUAL - Different City'
        ELSE '🟢 OK'
    END as location_anomaly
FROM customer_locations cl
JOIN order_locations ol ON cl.customer_id = ol.customer_id
WHERE ol.order_city != cl.profile_city
ORDER BY cl.customer_name;

-- ============================================================================
-- 5. FRAUD SCORE AGGREGATION
-- ============================================================================

-- 5.1 Comprehensive Fraud Risk Dashboard
WITH fraud_indicators AS (
    SELECT 
        o.order_id,
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        o.order_date,
        ROUND(SUM(oi.line_total), 2) as order_amount,
        COUNT(DISTINCT oi.product_id) as unique_products,
        -- Risk Factors
        CASE WHEN SUM(oi.line_total) > (SELECT AVG(total_amount) FROM orders)*3 THEN 1 ELSE 0 END as large_order,
        CASE WHEN ROUND((JULIANDAY('now') - JULIANDAY(c.created_date))) < 7 THEN 1 ELSE 0 END as new_account,
        CASE WHEN COUNT(DISTINCT o.order_id) OVER (PARTITION BY o.customer_id ORDER BY o.order_date 
            ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) >= 2 THEN 1 ELSE 0 END as repeat_order,
        CASE WHEN COUNT(DISTINCT oi.product_id) > 15 THEN 1 ELSE 0 END as bulk_order
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY o.order_id
)
SELECT 
    order_id,
    customer_name,
    order_date,
    order_amount,
    unique_products,
    (large_order + new_account + repeat_order + bulk_order) as fraud_score,
    CASE 
        WHEN (large_order + new_account + repeat_order + bulk_order) >= 3 THEN '🔴 HIGH RISK'
        WHEN (large_order + new_account + repeat_order + bulk_order) = 2 THEN '🟠 MEDIUM RISK'
        WHEN (large_order + new_account + repeat_order + bulk_order) = 1 THEN '🟡 LOW RISK'
        ELSE '🟢 MINIMAL RISK'
    END as fraud_flag,
    'MANUAL_REVIEW_REQUIRED' as recommended_action
FROM fraud_indicators
WHERE (large_order + new_account + repeat_order + bulk_order) >= 2
ORDER BY fraud_score DESC;

-- ============================================================================
-- FRAUD PREVENTION BEST PRACTICES
-- ============================================================================
/*

Fraud Detection Strategy:

1. VELOCITY CHECKS
   - Multiple orders same IP/email within hours/days
   - Threshold: >3 orders in <24 hours = flag

2. ORDER PATTERN ANOMALIES
   - Amount 5x+ customer average = suspicious
   - Bulk orders unusual for customer history
   - New customer + high-value order = higher risk

3. REFUND PATTERNS
   - >3 refunds in 30 days = high risk
   - High refund rate by category = investigate
   - Return fraud patterns

4. GEOGRAPHIC ANOMALIES
   - Orders from different countries than profile
   - Rapid geographic switching
   - Impossible travel (NYC then London in 2 hours)

5. CHARGEBACK HISTORY
   - Previous chargebacks = higher risk
   - High chargeback rate per payment method
   - Correlate with delivery confirmations

6. PAYMENT RED FLAGS
   - Multiple payment methods on same account
   - Mismatched billing/shipping address
   - Declined cards, then different card accepted
   - High-value orders with prepaid cards

7. SCORING SYSTEM
   - 0-2: Green (low risk)
   - 3-5: Yellow (review)
   - 6+: Red (block or manual review)

Recommended Actions:
- Score 8+: Immediately cancel
- Score 6-7: Manual review before fulfillment
- Score 3-5: Send verification email
- Score <3: Process normally
*/
