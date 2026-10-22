-- Fails (returns rows) if any looker_raw table holds two rows for the same key.
SELECT 'looker_channel_daily' AS source_table, COUNT(*) AS duplicate_keys FROM (
    SELECT date, channel FROM {{ source('looker_raw', 'looker_channel_daily') }} GROUP BY 1, 2 HAVING COUNT(*) > 1
) HAVING COUNT(*) > 0
UNION ALL
SELECT 'looker_campaign_daily', COUNT(*) FROM (
    SELECT date, utm_campaign, channel_subgrouping_2 FROM {{ source('looker_raw', 'looker_campaign_daily') }} GROUP BY 1, 2, 3 HAVING COUNT(*) > 1
) HAVING COUNT(*) > 0
UNION ALL
SELECT 'looker_last_click_utm_daily', COUNT(*) FROM (
    SELECT date, utm_campaign, channel_subgrouping_2, utm_source, utm_medium, utm_content, utm_term
    FROM {{ source('looker_raw', 'looker_last_click_utm_daily') }} GROUP BY 1, 2, 3, 4, 5, 6, 7 HAVING COUNT(*) > 1
) HAVING COUNT(*) > 0
