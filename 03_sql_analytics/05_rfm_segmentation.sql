-- ============================================================================
-- RFM CUSTOMER SEGMENTATION
-- ============================================================================
-- Recency, Frequency, Monetary Analysis for Customer Segmentation
-- Classification: Champions, Loyal, Potential, New, At-Risk, Lost
-- ============================================================================

-- ============================================================================
-- 1. RFM CALCULATION & SCORING
-- ============================================================================

-- 1.1 RFM Scoring (5-Point Scale)
WITH rfm_calc AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        -- Recency: Days since last purchase
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as recency_days,
        -- Frequency: Number of purchases
        COUNT(DISTINCT o.order_id) as frequency,
        -- Monetary: Total spending
        ROUND(SUM(oi.line_total), 2) as monetary,
        -- Calculate RFM Scores (5=Best, 1=Worst)
        NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) as recency_score,
        NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) as frequency_score,
        NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) as monetary_score
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.city
)
SELECT 
    customer_name,
    email,
    city,
    recency_days,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,
    (recency_score + frequency_score + monetary_score) as rfm_total_score,
    CAST(recency_score AS TEXT) || CAST(frequency_score AS TEXT) || CAST(monetary_score AS TEXT) as rfm_code
FROM rfm_calc
ORDER BY rfm_total_score DESC, monetary DESC;

-- ============================================================================
-- 2. RFM CUSTOMER SEGMENTATION
-- ============================================================================

-- 2.1 Complete RFM Segmentation with Business Rules
WITH rfm_scores AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        c.city,
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as recency_days,
        COUNT(DISTINCT o.order_id) as frequency,
        ROUND(SUM(oi.line_total), 2) as monetary,
        NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) as recency_score,
        NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) as frequency_score,
        NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) as monetary_score
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.city
)
SELECT 
    customer_name,
    email,
    city,
    recency_days,
    frequency,
    monetary,
    -- Segmentation Logic
    CASE 
        WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4 THEN '👑 Champion'
        WHEN recency_score >= 4 AND frequency_score >= 3 AND monetary_score >= 3 THEN '⭐ Loyal Customer'
        WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 2 THEN '🌟 Potential Loyalist'
        WHEN recency_score >= 4 AND frequency_score <= 2 THEN '🆕 New Customer'
        WHEN recency_score <= 2 AND frequency_score >= 3 AND monetary_score >= 3 THEN '⚠️ At Risk'
        WHEN recency_score <= 2 AND frequency_score <= 2 THEN '❌ Lost'
        ELSE '📊 Need Analysis'
    END as rfm_segment,
    -- Engagement Level
    CASE 
        WHEN recency_score >= 4 THEN 'Highly Engaged'
        WHEN recency_score >= 3 THEN 'Engaged'
        WHEN recency_score >= 2 THEN 'Disengaging'
        ELSE 'Inactive'
    END as engagement_level,
    -- Value Level
    CASE 
        WHEN monetary_score >= 4 THEN 'High Value'
        WHEN monetary_score >= 3 THEN 'Medium Value'
        ELSE 'Low Value'
    END as value_level
FROM rfm_scores
ORDER BY monetary DESC, frequency DESC;

-- ============================================================================
-- 3. RFM SEGMENT DISTRIBUTION
-- ============================================================================

-- 3.1 Customer Count by RFM Segment
WITH rfm_segments AS (
    SELECT 
        c.customer_id,
        CASE 
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 4 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 4 THEN '👑 Champion'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 3 THEN '⭐ Loyal Customer'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 3 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 2 THEN '🌟 Potential Loyalist'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) <= 2 THEN '🆕 New Customer'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) <= 2 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 3 THEN '⚠️ At Risk'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) <= 2 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) <= 2 THEN '❌ Lost'
            ELSE '📊 Other'
        END as segment
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    segment,
    COUNT(*) as customer_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM rfm_segments) * 100, 2) as percent_of_base,
    -- Business Recommendations
    CASE 
        WHEN segment = '👑 Champion' THEN 'VIP treatment, exclusive offers'
        WHEN segment = '⭐ Loyal Customer' THEN 'Retention programs, upsell'
        WHEN segment = '🌟 Potential Loyalist' THEN 'Engagement campaigns'
        WHEN segment = '🆕 New Customer' THEN 'Welcome offers, onboarding'
        WHEN segment = '⚠️ At Risk' THEN 'Reactivation campaigns'
        WHEN segment = '❌ Lost' THEN 'Win-back campaigns'
        ELSE 'Further analysis needed'
    END as recommended_action
FROM rfm_segments
GROUP BY segment
ORDER BY customer_count DESC;

-- ============================================================================
-- 4. RFM SEGMENT METRICS
-- ============================================================================

-- 4.1 Segment Performance Metrics
WITH rfm_segments AS (
    SELECT 
        c.customer_id,
        SUM(oi.line_total) as monetary,
        COUNT(DISTINCT o.order_id) as frequency,
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as recency_days,
        CASE 
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 4 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 4 THEN '👑 Champion'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 3 THEN '⭐ Loyal Customer'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 3 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 2 THEN '🌟 Potential Loyalist'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) <= 2 THEN '🆕 New Customer'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) <= 2 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 3 THEN '⚠️ At Risk'
            ELSE '❌ Lost'
        END as segment
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
SELECT 
    segment,
    COUNT(*) as customer_count,
    ROUND(SUM(monetary), 2) as segment_revenue,
    ROUND(AVG(monetary), 2) as avg_clv,
    ROUND(AVG(frequency), 2) as avg_purchase_frequency,
    ROUND(AVG(recency_days), 0) as avg_days_since_purchase,
    ROUND(SUM(monetary) / COUNT(*), 2) as revenue_per_customer,
    ROUND(100.0 * SUM(monetary) / (SELECT SUM(monetary) FROM rfm_segments), 2) as percent_of_revenue
FROM rfm_segments
GROUP BY segment
ORDER BY segment_revenue DESC;

-- ============================================================================
-- 5. RFM SEGMENT TARGETING STRATEGY
-- ============================================================================

-- 5.1 Targeted Customer Lists by Segment
WITH rfm_customers AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) as customer_name,
        c.email,
        SUM(oi.line_total) as monetary,
        COUNT(DISTINCT o.order_id) as frequency,
        ROUND((JULIANDAY('now') - JULIANDAY(MAX(o.order_date))), 0) as recency_days,
        CASE 
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) >= 4 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 4 
             AND NTILE(5) OVER (ORDER BY SUM(oi.line_total) DESC) >= 4 THEN '👑 Champion'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) <= 2 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) <= 2 THEN '❌ Lost'
            WHEN NTILE(5) OVER (ORDER BY (JULIANDAY('now') - JULIANDAY(MAX(o.order_date))) ASC) <= 2 
             AND NTILE(5) OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC) >= 3 THEN '⚠️ At Risk'
            ELSE 'Other'
        END as segment
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
)
-- Lost Customers (Priority: High)
SELECT 
    segment,
    'LOST_CUSTOMER_WINBACK' as campaign_type,
    customer_name,
    email,
    monetary,
    frequency,
    recency_days,
    'Email: "We miss you!" + 15% discount' as campaign_offer,
    'High' as priority
FROM rfm_customers
WHERE segment = '❌ Lost'

UNION ALL

-- At Risk Customers (Priority: High)
SELECT 
    segment,
    'AT_RISK_RETENTION' as campaign_type,
    customer_name,
    email,
    monetary,
    frequency,
    recency_days,
    'Email: Personal offer + loyalty reward' as campaign_offer,
    'High' as priority
FROM rfm_customers
WHERE segment = '⚠️ At Risk'

UNION ALL

-- Champions (Priority: VIP)
SELECT 
    segment,
    'CHAMPION_VIP' as campaign_type,
    customer_name,
    email,
    monetary,
    frequency,
    recency_days,
    'Exclusive early access, VIP support' as campaign_offer,
    'VIP' as priority
FROM rfm_customers
WHERE segment = '👑 Champion'

ORDER BY priority DESC, monetary DESC;

-- ============================================================================
-- BUSINESS INTERPRETATION
-- ============================================================================
/*

RFM Segmentation Strategy:

1. CHAMPIONS (High R, High F, High M)
   - Best customers, most loyal
   - Action: VIP treatment, exclusive benefits, referral programs
   - Expected Lifetime Value: Highest

2. LOYAL CUSTOMERS (High R, High F, Medium-High M)
   - Frequent buyers with consistent spending
   - Action: Personalization, upsell, loyalty rewards
   - Retention Focus: Medium (already engaged)

3. POTENTIAL LOYALISTS (High R, Medium F, Medium M)
   - Growing customers, potential for loyalty
   - Action: Engagement campaigns, cross-sell offers
   - Development Focus: High

4. NEW CUSTOMERS (High R, Low F, Low-Medium M)
   - Recent acquirers with growth potential
   - Action: Welcome series, education, incentives
   - Growth Focus: High

5. AT RISK (Low R, High F, High M)
   - Valuable but disengaging
   - Action: Reactivation campaigns, special offers, surveys
   - Urgency: High (preventing churn)

6. LOST CUSTOMERS (Low R, Low F)
   - No recent activity, low engagement
   - Action: Win-back campaigns, exit surveys, special incentives
   - Reactivation Focus: Medium-Low (expensive)

Campaign Recommendations by Segment:

Champions:
- Frequency: Weekly to bi-weekly
- Content: Exclusive content, VIP events
- Offers: Limited edition, early access
- Channel: Direct mail, personal calls

At Risk:
- Frequency: Weekly
- Content: Personalized, win-back
- Offers: Significant discounts, limited-time
- Channel: Email, SMS, retargeting ads

Lost:
- Frequency: Monthly
- Content: Nostalgia, new features
- Offers: Heavy discount (20-30%)
- Channel: Email, direct mail, ads
*/
