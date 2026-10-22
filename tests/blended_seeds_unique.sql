-- Fails if either blended seed lists the same key twice (it would duplicate spend or orders).
SELECT 'blended_channel_map' AS seed, platform || ':' || campaign_id AS dup_key, COUNT(*) AS n
FROM {{ ref('blended_channel_map') }} GROUP BY 1, 2 HAVING COUNT(*) > 1
UNION ALL
SELECT 'looker_google_ad_map', ad_id, COUNT(*)
FROM {{ ref('looker_google_ad_map') }} GROUP BY 1, 2 HAVING COUNT(*) > 1
