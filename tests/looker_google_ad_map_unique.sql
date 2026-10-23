-- Fails (returns rows) if looker_raw.google_ad_map holds one ad twice (it would duplicate Google orders in looker_utm_orders).
SELECT ad_id, COUNT(*) AS n
FROM {{ source('looker_raw', 'google_ad_map') }}
GROUP BY 1
HAVING COUNT(*) > 1
