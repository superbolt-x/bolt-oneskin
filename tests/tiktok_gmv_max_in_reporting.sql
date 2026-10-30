-- Fails if GMV Max spend or orders in the two TikTok reporting models differ from the source table. Checked at day
-- grain, and week / month / quarter / year must each equal day. Campaign and ad tables must agree with each other.
WITH src AS (
    SELECT ROUND(SUM(cost)::NUMERIC(18, 2), 2) AS spend, SUM(orders) AS orders FROM {{ source('looker_raw', 'tiktok_gmv_max_daily') }}
),
camp AS (
    SELECT date_granularity, ROUND(SUM(spend)::NUMERIC(18, 2), 2) AS spend, SUM(purchases) AS orders
    FROM {{ ref('tiktok_campaign_performance') }} WHERE campaign_type_default = 'GMV Max' GROUP BY 1
),
ad AS (
    SELECT date_granularity, ROUND(SUM(spend)::NUMERIC(18, 2), 2) AS spend, SUM(purchases) AS orders
    FROM {{ ref('tiktok_ad_performance') }} WHERE campaign_type_default = 'GMV Max' GROUP BY 1
)
SELECT 'campaign' AS model, camp.date_granularity, camp.spend, src.spend AS source_spend, camp.orders, src.orders AS source_orders
FROM camp CROSS JOIN src WHERE ABS(camp.spend - src.spend) > 0.05 OR camp.orders <> src.orders
UNION ALL
SELECT 'ad', ad.date_granularity, ad.spend, src.spend, ad.orders, src.orders
FROM ad CROSS JOIN src WHERE ABS(ad.spend - src.spend) > 0.05 OR ad.orders <> src.orders
