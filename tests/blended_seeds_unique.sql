-- Fails if the blended channel seed lists the same campaign twice (it would duplicate spend).
SELECT 'blended_channel_map' AS seed, platform || ':' || campaign_id AS dup_key, COUNT(*) AS n
FROM {{ ref('blended_channel_map') }} GROUP BY 1, 2 HAVING COUNT(*) > 1
