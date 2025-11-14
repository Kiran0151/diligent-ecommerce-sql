# Synthetic e-commerce data

This repository contains a small Python script to generate synthetic e-commerce CSV data and the generated CSVs in the `data/` folder.

Files generated:
- data/customers.csv (76 rows incl header)
- data/products.csv (81 rows incl header)
- data/orders.csv (121 rows incl header)
- data/order_items.csv (355 rows incl header)
- data/payments.csv (121 rows incl header)

Usage

Run the generator:

```powershell
python .\generate_data.py
```

CSV schema

1. customers.csv: customer_id, name, email, phone, city
2. products.csv: product_id, product_name, category, price
3. orders.csv: order_id, customer_id, order_date, order_status
4. order_items.csv: item_id, order_id, product_id, quantity, unit_price
5. payments.csv: payment_id, order_id, payment_date, payment_method, amount

Notes

- IDs are consistent across files.
- Prices and quantities are realistic.
- Dates are randomized within the last year.
