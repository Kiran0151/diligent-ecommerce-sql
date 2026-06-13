-- ============================================================================
-- PRODUCT RECOMMENDATION ENGINE
-- ============================================================================
-- Frequently bought together, cross-sell, and upsell recommendations
-- Uses: Market basket analysis, association rules, collaborative filtering
-- ============================================================================

-- ============================================================================
-- 1. FREQUENTLY BOUGHT TOGETHER ANALYSIS
-- ============================================================================

-- 1.1 Products Most Often Purchased in Same Order
WITH product_pairs AS (
    SELECT 
        oi1.product_id as product_a,
        oi2.product_id as product_b,
        p1.product_name as product_a_name,
        p2.product_name as product_b_name,
        c1.category_name as category_a,
        c2.category_name as category_b,
        COUNT(DISTINCT o.order_id) as co_purchase_count,
        ROUND(p1.price, 2) as price_a,
        ROUND(p2.price, 2) as price_b
    FROM order_items oi1
    JOIN order_items oi2 ON oi1.order_id = oi2.order_id AND oi1.product_id < oi2.product_id
    JOIN orders o ON oi1.order_id = o.order_id
    JOIN products p1 ON oi1.product_id = p1.product_id
    JOIN products p2 ON oi2.product_id = p2.product_id
    JOIN categories c1 ON p1.category_id = c1.category_id
    JOIN categories c2 ON p2.category_id = c2.category_id
    WHERE o.status_id IN (3, 4)
    GROUP BY oi1.product_id, oi2.product_id
    HAVING COUNT(DISTINCT o.order_id) >= 3
)
SELECT 
    product_a_name,
    product_b_name,
    category_a,
    category_b,
    co_purchase_count,
    price_a,
    price_b,
    ROUND(price_a + price_b, 2) as bundle_price,
    RANK() OVER (ORDER BY co_purchase_count DESC) as co_purchase_rank,
    CASE 
        WHEN category_a = category_b THEN 'Same Category'
        ELSE 'Cross Category'
    END as recommendation_type
FROM product_pairs
ORDER BY co_purchase_count DESC
LIMIT 100;

-- ============================================================================
-- 2. CROSS-SELL RECOMMENDATIONS
-- ============================================================================

-- 2.1 Cross-Sell Opportunities (Different Categories)
WITH customer_purchases AS (
    SELECT 
        o.customer_id,
        c.category_id,
        COUNT(DISTINCT o.order_id) as purchase_count,
        RANK() OVER (PARTITION BY o.customer_id ORDER BY COUNT(DISTINCT o.order_id) DESC) as category_rank
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    JOIN categories c ON p.category_id = c.category_id
    WHERE o.status_id IN (3, 4)
    GROUP BY o.customer_id, c.category_id
),
category_affinity AS (
    SELECT 
        cp1.category_id as purchased_category_id,
        cp2.category_id as crosssell_category_id,
        COUNT(DISTINCT cp1.customer_id) as customers_with_both,
        COUNT(DISTINCT CASE WHEN cp2.category_rank IS NULL THEN cp1.customer_id END) as customers_only_first,
        ROUND(100.0 * COUNT(DISTINCT cp1.customer_id) / 
            (SELECT COUNT(DISTINCT customer_id) FROM customer_purchases 
             WHERE category_rank = 1), 2) as crosssell_potential_percent
    FROM customer_purchases cp1
    LEFT JOIN customer_purchases cp2 ON cp1.customer_id = cp2.customer_id 
        AND cp1.category_id != cp2.category_id
    WHERE cp1.category_rank = 1
    GROUP BY cp1.category_id, cp2.category_id
)
SELECT 
    c1.category_name as primary_category,
    c2.category_name as recommended_category,
    customers_with_both,
    customers_only_first,
    crosssell_potential_percent,
    CASE 
        WHEN crosssell_potential_percent >= 50 THEN '🟢 Excellent Opportunity'
        WHEN crosssell_potential_percent >= 30 THEN '🟡 Good Opportunity'
        ELSE '🔵 Monitor'
    END as opportunity_rating
FROM category_affinity ca
JOIN categories c1 ON ca.purchased_category_id = c1.category_id
JOIN categories c2 ON ca.crosssell_category_id = c2.category_id
WHERE ca.crosssell_category_id IS NOT NULL
ORDER BY crosssell_potential_percent DESC;

-- ============================================================================
-- 3. UPSELL RECOMMENDATIONS
-- ============================================================================

-- 3.1 Upsell Opportunities (Higher Price Points)
WITH customer_price_range AS (
    SELECT 
        o.customer_id,
        p.category_id,
        MAX(p.price) as max_price_purchased,
        AVG(p.price) as avg_price_purchased,
        COUNT(DISTINCT oi.product_id) as products_bought
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status_id IN (3, 4)
    GROUP BY o.customer_id, p.category_id
),
upsell_candidates AS (
    SELECT 
        cpr.customer_id,
        cpr.category_id,
        cpr.max_price_purchased,
        cpr.avg_price_purchased,
        p.product_id,
        p.product_name,
        p.price as upsell_price,
        ROUND((p.price - cpr.max_price_purchased) / cpr.max_price_purchased * 100, 2) as price_increase_percent,
        ROUND(SUM(oi.quantity), 0) as product_popularity
    FROM customer_price_range cpr
    JOIN products p ON cpr.category_id = p.category_id
    LEFT JOIN order_items oi ON p.product_id = oi.product_id
    WHERE p.price > cpr.max_price_purchased * 1.3  -- At least 30% more expensive
      AND p.price <= cpr.max_price_purchased * 2.5  -- But not excessively so
    GROUP BY p.product_id
)
SELECT 
    customer_id,
    product_name,
    max_price_purchased as currently_buys_up_to,
    upsell_price as recommended_upsell_price,
    price_increase_percent,
    product_popularity,
    CASE 
        WHEN price_increase_percent BETWEEN 30 AND 50 THEN '🟢 Good Upsell Target'
        WHEN price_increase_percent BETWEEN 50 AND 100 THEN '🟡 Premium Upsell'
        ELSE '🔵 Luxury Upsell'
    END as upsell_tier
FROM upsell_candidates
WHERE product_popularity IS NOT NULL
ORDER BY customer_id, price_increase_percent;

-- ============================================================================
-- 4. PERSONALIZED PRODUCT RECOMMENDATIONS
-- ============================================================================

-- 4.1 Similar Product Recommendations (For Active Product Page)
WITH product_attributes AS (
    SELECT 
        p1.product_id,
        p2.product_id as similar_product_id,
        p1.product_name,
        p2.product_name as similar_product_name,
        c1.category_name,
        c2.category_name as similar_category,
        ROUND(ABS(p1.price - p2.price) / p1.price * 100, 2) as price_difference_percent,
        COUNT(DISTINCT o.order_id) as co_purchases,
        ROUND(p2.price, 2) as similar_product_price,
        -- Similarity Score
        CASE 
            WHEN c1.category_id = c2.category_id AND ABS(p1.price - p2.price) / p1.price <= 0.2 THEN 'High'
            WHEN c1.category_id = c2.category_id THEN 'Medium'
            ELSE 'Low'
        END as similarity_level
    FROM products p1
    JOIN products p2 ON p1.category_id = p2.category_id AND p1.product_id < p2.product_id
    JOIN categories c1 ON p1.category_id = c1.category_id
    JOIN categories c2 ON p2.category_id = c2.category_id
    LEFT JOIN order_items oi1 ON p1.product_id = oi1.product_id
    LEFT JOIN order_items oi2 ON p2.product_id = oi2.product_id AND oi1.order_id = oi2.order_id
    LEFT JOIN orders o ON oi1.order_id = o.order_id
    WHERE p1.is_active = 1 AND p2.is_active = 1
    GROUP BY p1.product_id, p2.product_id
)
SELECT 
    product_name,
    similar_product_name,
    category_name,
    price_difference_percent,
    co_purchases,
    similar_product_price,
    similarity_level,
    'Check out similar products' as recommendation_message
FROM product_attributes
WHERE co_purchases >= 2
ORDER BY product_id, co_purchases DESC;

-- ============================================================================
-- 5. CUSTOMER SEGMENT RECOMMENDATIONS
-- ============================================================================

-- 5.1 Top Products for Each Customer Segment
WITH customer_segments AS (
    SELECT 
        c.customer_id,
        SUM(oi.line_total) as clv,
        COUNT(DISTINCT o.order_id) as order_count,
        CASE 
            WHEN SUM(oi.line_total) > (SELECT PERCENTILE_CONT(0.75) OVER () as clv FROM (
                SELECT SUM(oi2.line_total) as clv FROM customers c2 
                JOIN orders o2 ON c2.customer_id = o2.customer_id 
                JOIN order_items oi2 ON o2.order_id = oi2.order_id 
                WHERE o2.status_id IN (3,4) GROUP BY c2.customer_id)) 
            THEN 'High Value'
            WHEN COUNT(DISTINCT o.order_id) > 10 THEN 'Frequent'
            ELSE 'Occasional'
        END as segment
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status_id IN (3, 4)
    GROUP BY c.customer_id
),
segment_products AS (
    SELECT 
        cs.segment,
        p.product_id,
        p.product_name,
        COUNT(DISTINCT o.order_id) as popularity,
        ROUND(AVG(oi.quantity), 2) as avg_qty_purchased,
        ROUND(SUM(oi.line_total), 2) as segment_revenue
    FROM customer_segments cs
    JOIN orders o ON cs.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status_id IN (3, 4)
    GROUP BY cs.segment, p.product_id
)
SELECT 
    segment,
    product_name,
    popularity,
    avg_qty_purchased,
    segment_revenue,
    RANK() OVER (PARTITION BY segment ORDER BY segment_revenue DESC) as product_rank
FROM segment_products
WHERE product_rank <= 10;

-- ============================================================================
-- 6. RECOMMENDATION RULES ENGINE
-- ============================================================================

-- 6.1 Recommendation Rules Summary
SELECT 
    '1. Frequently Bought Together' as rule_name,
    'Show similar products purchased in same order' as rule_description,
    'Product detail page, cart' as placement,
    3 as min_co_purchases,
    'Increase basket size' as business_objective

UNION ALL

SELECT 
    '2. Cross-Sell by Category',
    'Recommend products from categories not yet purchased',
    'Post-purchase email, homepage',
    'Minimum 30% affinity',
    'Diversify purchases'

UNION ALL

SELECT 
    '3. Upsell by Price',
    'Recommend higher-priced alternatives in same category',
    'Product page, email',
    '30-250% price increase',
    'Increase order value'

UNION ALL

SELECT 
    '4. Customer Segment',
    'Tailor recommendations by customer value/frequency',
    'Personalized email, dashboard',
    'Segment-specific top products',
    'Improve conversion by relevance'

UNION ALL

SELECT 
    '5. Similar Products',
    'Recommend products with similar attributes',
    'Related items widget',
    'Same category + similar price',
    'Reduce decision time';

-- ============================================================================
-- BUSINESS IMPACT METRICS
-- ============================================================================
/*

Recommendation Engine ROI:

1. FREQUENTLY BOUGHT TOGETHER
   - Typical Lift: 15-25% increase in AOV
   - Implementation: Show on cart and checkout
   - Example: Electronics + Accessories Bundle

2. CROSS-SELL STRATEGY
   - Category affinity >50%: Strong signal
   - Expected Lift: 10-20% of customers add crosssell item
   - Best for: Email, post-purchase, homepage

3. UPSELL STRATEGY
   - Price increase 30-50%: Sweet spot for acceptance
   - Expected Lift: 5-15% conversion rate
   - Best timing: First email post-purchase

4. PERSONALIZATION
   - Segment-specific recs: 25-40% higher engagement
   - Frequency: Weekly for engaged, Monthly for at-risk

5. IMPLEMENTATION PRIORITIES
   - Phase 1: Frequently Bought Together (easy, quick ROI)
   - Phase 2: Cross-Sell by Category (good lift, scalable)
   - Phase 3: Upsell (complex, needs pricing strategy)
   - Phase 4: ML-based (collaborative filtering, NLP)

6. SUCCESS METRICS
   - CTR: Click-through rate on recommendations
   - Conversion: % who purchased recommended item
   - AOV: Average order value lift
   - CAC: Customer acquisition cost savings
   - ROI: Revenue from recs / Cost of implementation

Typical Benchmarks:
- CTR: 2-5%
- Conversion: 0.5-2%
- AOV Lift: 15-30%
- ROI: 300-500% annually
*/
