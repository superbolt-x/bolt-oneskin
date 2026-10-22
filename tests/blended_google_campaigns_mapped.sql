-- Fails if a Google campaign that spent money in the last 90 days is missing from seeds/blended_channel_map.csv
-- (its spend would land under '(not mapped)' and drop out of every Brand / NB channel).
SELECT campaign_id, campaign_name, SUM(spend) AS spend
FROM {{ ref('blended_spend') }}
WHERE channel_grouping = 'Google Ads' AND channel_subgrouping_2 = '(not mapped)' AND date >= CURRENT_DATE - 90
GROUP BY 1, 2
HAVING SUM(spend) > 0
