SELECT 
    c.customer_id,
    c.name AS customer_name,
    o.order_id,
    SUM(oi.quantity * oi.unit_price) AS total_order_value,
    COUNT(oi.item_id) AS number_of_items
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
GROUP BY c.customer_id, c.name, o.order_id
ORDER BY total_order_value DESC;
