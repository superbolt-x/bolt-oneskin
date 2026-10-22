{{ config(severity='warn') }}
-- Warns when our platform spend differs from Looker's own panel by more than $2 on a settled day (3 to 120 days
-- ago) for the nine channels the panel and the platforms share. The panel rounds to whole dollars, so $2 is noise.
SELECT date, channel_subgrouping_2, spend, looker_spend, spend - looker_spend AS diff
FROM {{ ref('blended_channel_daily') }}
WHERE spend IS NOT NULL AND looker_spend IS NOT NULL
  AND channel_subgrouping_2 IN ('Meta', 'TikTok', 'Brand Search', 'Brand Shopping', 'Brand PMax', 'NB Search', 'NB Shopping', 'NB PMax', 'NB Demand Gen')
  AND date BETWEEN CURRENT_DATE - 120 AND CURRENT_DATE - 3
  AND ABS(spend - looker_spend) > 2
