-- Fails (returns a row) if blended lost or gained spend or orders compared with the two tables it stacks.
SELECT b.spend AS blended_spend, s.spend AS spend_model, b.orders AS blended_orders, c.orders AS orders_model
FROM (SELECT SUM(spend) AS spend, SUM(new_customer_orders) AS orders FROM {{ ref('blended') }}) b
CROSS JOIN (SELECT SUM(spend) AS spend FROM {{ ref('blended_spend') }}) s
CROSS JOIN (SELECT SUM(new_customer_orders) AS orders FROM {{ ref('looker_utm_orders') }}) c
WHERE ABS(b.spend - s.spend) > 0.01 OR b.orders <> c.orders
