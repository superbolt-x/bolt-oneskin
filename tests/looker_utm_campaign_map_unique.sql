-- Fails if the seed lists one UTM key twice for a platform (it would duplicate orders in looker_utm_orders).
SELECT platform, utm_campaign_key, COUNT(*) AS n
FROM {{ ref('looker_utm_campaign_map') }}
GROUP BY 1, 2
HAVING COUNT(*) > 1
