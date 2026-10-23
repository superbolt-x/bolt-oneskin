-- Fails (returns rows) if the GMV Max tables hold one campaign-day or one campaign twice (it would double its spend).
SELECT 'tiktok_gmv_max_daily' AS source_table, date::VARCHAR AS k1, campaign_id AS k2, COUNT(*) AS n
FROM {{ source('looker_raw', 'tiktok_gmv_max_daily') }} GROUP BY 1, 2, 3 HAVING COUNT(*) > 1
UNION ALL
SELECT 'tiktok_gmv_max_campaigns', campaign_id, '', COUNT(*)
FROM {{ source('looker_raw', 'tiktok_gmv_max_campaigns') }} GROUP BY 1, 2, 3 HAVING COUNT(*) > 1
