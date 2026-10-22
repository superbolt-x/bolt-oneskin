-- Fails (returns a row) if looker_utm_orders gained or lost orders or rows compared with its source.
SELECT s.orders AS source_orders, m.orders AS model_orders, s.n AS source_rows, m.n AS model_rows
FROM (SELECT SUM(new_customer_orders) AS orders, COUNT(*) AS n FROM {{ source('looker_raw', 'looker_last_click_utm_daily') }}) s
CROSS JOIN (SELECT SUM(new_customer_orders) AS orders, COUNT(*) AS n FROM {{ ref('looker_utm_orders') }}) m
WHERE s.orders <> m.orders OR s.n <> m.n
