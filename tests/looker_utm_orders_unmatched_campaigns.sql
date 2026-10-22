{{ config(severity='warn') }}
-- Warns with the UTM campaigns we could not resolve in the last 30 days (10+ orders). Add the real ones to
-- seeds/looker_utm_campaign_map.csv. Spotlights is skipped: its UTM campaign is a post id, never a platform campaign.
-- (unrendered_placeholder and not_set are different match_methods, so they never show up here.)
SELECT channel_grouping, utm_campaign, SUM(new_customer_orders) AS orders
FROM {{ ref('looker_utm_orders') }}
WHERE match_method = 'unmatched' AND channel_subgrouping_2 <> 'Spotlights' AND date >= CURRENT_DATE - 30
GROUP BY 1, 2
HAVING SUM(new_customer_orders) >= 10
