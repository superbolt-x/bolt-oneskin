-- Fails (returns rows) if blended_spend holds two rows for the same key.
SELECT date, channel_subgrouping_2, campaign_id, adset_id, ad_id, source, COUNT(*) AS n
FROM {{ ref('blended_spend') }}
GROUP BY 1, 2, 3, 4, 5, 6
HAVING COUNT(*) > 1
