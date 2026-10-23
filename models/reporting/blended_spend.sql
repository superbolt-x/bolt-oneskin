{{ config (
    alias = target.database + '_blended_spend'
)}}

{#
  Spend, from the ad platforms, at the deepest level each platform gives us. Half of the blended pair:
  blended_conversions holds the Looker orders, and blended stacks the two.

    Meta        ad level, from facebook_performance_by_ad (an ad-day sits in one attribution_setting row, so
                summing the settings is safe: 0 of 134,942 ad-days with spend have two)
    Google Ads  campaign level. channel_subgrouping / _2 come from seeds/blended_channel_map.csv, because the
                platform has no Branded / Non-Branded or PMax / Search label of its own
    TikTok      campaign level
    TikTok GMV Max
                campaign level, from looker_raw.tiktok_gmv_max_daily (TikTok Business API, loaded by
                tiktok_gmv_max_to_redshift.py): the connector's tables do not carry it. Spend only; Looker
                attributes no new customers to it.
    Pinterest   one channel-level row a day from Looker's own sheet (looker_channel_daily): there is no platform
                connector, so campaign, ad set and ad stay '(not set)'
    Before a platform's own data starts (Meta 2022-11, Google 2023-12, TikTok 2025-01) the same Looker channel
    rows fill the gap, so spend history is complete. They carry source = 'looker_channel_spend'; on and after the
    platform's first date only platform spend is used, so nothing is counted twice.

  channel_subgrouping_2 is 'Meta' for every Meta campaign unless the seed says otherwise. That is where
  Spotlights spend would be split out once we know which Meta campaigns it is: add a Meta row to the seed.
#}

WITH channel_map AS (
    SELECT platform, campaign_id::VARCHAR AS campaign_id, channel_subgrouping, channel_subgrouping_2
    FROM {{ ref('blended_channel_map') }}
),

-- ---------------------------------------------------------------- Meta
meta_campaigns AS (
    SELECT campaign_id, campaign_name
    FROM (
        SELECT campaign_id::VARCHAR AS campaign_id, campaign_name,
               ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) AS rn
        FROM {{ ref('facebook_performance_by_campaign') }}
        WHERE date_granularity = 'day'
    )
    WHERE rn = 1
),

meta_ad_names AS (
    SELECT ad_id, ad_name, adset_name
    FROM (
        SELECT ad_id::VARCHAR AS ad_id, ad_name, adset_name,
               ROW_NUMBER() OVER (PARTITION BY ad_id ORDER BY date DESC) AS rn
        FROM {{ ref('facebook_performance_by_ad') }}
        WHERE date_granularity = 'day'
    )
    WHERE rn = 1
),

meta_spend AS (
    SELECT
        s.date,
        'Meta' AS channel_grouping,
        COALESCE(m.channel_subgrouping, 'Meta') AS channel_subgrouping,
        COALESCE(m.channel_subgrouping_2, 'Meta') AS channel_subgrouping_2,
        s.campaign_id,
        c.campaign_name,
        s.adset_id,
        n.adset_name,
        s.ad_id,
        n.ad_name,
        'platform_spend' AS source,
        'ad' AS match_level,
        s.spend, s.impressions, s.clicks
    FROM (
        SELECT date, campaign_id::VARCHAR AS campaign_id, adset_id::VARCHAR AS adset_id, ad_id::VARCHAR AS ad_id,
               SUM(spend) AS spend, SUM(impressions) AS impressions, SUM(clicks) AS clicks
        FROM {{ ref('facebook_performance_by_ad') }}
        WHERE date_granularity = 'day'
        GROUP BY 1, 2, 3, 4
    ) s
    LEFT JOIN meta_campaigns c ON c.campaign_id = s.campaign_id
    LEFT JOIN meta_ad_names n ON n.ad_id = s.ad_id
    LEFT JOIN channel_map m ON m.platform = 'Meta' AND m.campaign_id = s.campaign_id
),

-- ---------------------------------------------------------------- Google Ads
google_campaigns AS (
    SELECT campaign_id, campaign_name
    FROM (
        SELECT campaign_id::VARCHAR AS campaign_id, campaign_name,
               ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) AS rn
        FROM {{ ref('googleads_performance_by_campaign') }}
        WHERE date_granularity = 'day'
    )
    WHERE rn = 1
),

google_spend AS (
    SELECT
        s.date,
        'Google Ads' AS channel_grouping,
        COALESCE(m.channel_subgrouping, '(not mapped)') AS channel_subgrouping,
        COALESCE(m.channel_subgrouping_2, '(not mapped)') AS channel_subgrouping_2,
        s.campaign_id,
        c.campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        'platform_spend' AS source,
        'campaign' AS match_level,
        s.spend, s.impressions, s.clicks
    FROM (
        SELECT date, campaign_id::VARCHAR AS campaign_id,
               SUM(spend) AS spend, SUM(impressions) AS impressions, SUM(clicks) AS clicks
        FROM {{ ref('googleads_performance_by_campaign') }}
        WHERE date_granularity = 'day'
        GROUP BY 1, 2
    ) s
    LEFT JOIN google_campaigns c ON c.campaign_id = s.campaign_id
    LEFT JOIN channel_map m ON m.platform = 'Google Ads' AND m.campaign_id = s.campaign_id
),

-- ---------------------------------------------------------------- TikTok
tiktok_campaigns AS (
    SELECT campaign_id, campaign_name
    FROM (
        SELECT campaign_id::VARCHAR AS campaign_id, campaign_name,
               ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) AS rn
        FROM {{ ref('tiktok_performance_by_campaign') }}
        WHERE date_granularity = 'day' AND campaign_name IS NOT NULL
    )
    WHERE rn = 1
),

tiktok_spend AS (
    SELECT
        s.date,
        'TikTok' AS channel_grouping,
        COALESCE(m.channel_subgrouping, 'TikTok') AS channel_subgrouping,
        COALESCE(m.channel_subgrouping_2, 'TikTok') AS channel_subgrouping_2,
        s.campaign_id,
        c.campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        'platform_spend' AS source,
        'campaign' AS match_level,
        s.spend, s.impressions, s.clicks
    FROM (
        SELECT date, campaign_id::VARCHAR AS campaign_id,
               SUM(cost) AS spend, SUM(impressions) AS impressions, SUM(clicks) AS clicks
        FROM {{ ref('tiktok_performance_by_campaign') }}
        WHERE date_granularity = 'day'
        GROUP BY 1, 2
    ) s
    LEFT JOIN tiktok_campaigns c ON c.campaign_id = s.campaign_id
    LEFT JOIN channel_map m ON m.platform = 'TikTok' AND m.campaign_id = s.campaign_id
),

-- ---------------------------------------------------------------- TikTok GMV Max (API table)
gmv_max_spend AS (
    SELECT
        g.date::DATE AS date,
        'TikTok' AS channel_grouping,
        'TikTok' AS channel_subgrouping,
        'TikTok GMV Max' AS channel_subgrouping_2,
        g.campaign_id,
        COALESCE(c.campaign_name, g.campaign_name) AS campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        'platform_spend' AS source,
        'campaign' AS match_level,
        g.cost AS spend,
        0 AS impressions,
        0 AS clicks
    FROM {{ source('looker_raw', 'tiktok_gmv_max_daily') }} g
    LEFT JOIN {{ source('looker_raw', 'tiktok_gmv_max_campaigns') }} c ON c.campaign_id = g.campaign_id
    WHERE g.cost > 0
),

-- ---------------------------------------------------------------- channels with no platform data
looker_channel_spend AS (
    SELECT
        date,
        'Pinterest' AS channel_grouping,
        'Pinterest' AS channel_subgrouping,
        channel AS channel_subgrouping_2,
        CAST(NULL AS VARCHAR) AS campaign_id,
        CAST(NULL AS VARCHAR) AS campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        'looker_channel_spend' AS source,
        'channel' AS match_level,
        marketing_spend AS spend,
        0 AS impressions,
        0 AS clicks
    FROM {{ source('looker_raw', 'looker_channel_daily') }}
    WHERE channel = 'Pinterest'
      AND marketing_spend IS NOT NULL
),

platform_start AS (
    SELECT 'Meta' AS channel_grouping, MIN(date) AS first_date FROM meta_spend
    UNION ALL SELECT 'Google Ads', MIN(date) FROM google_spend
    UNION ALL SELECT 'TikTok', MIN(date) FROM tiktok_spend
),

looker_history AS (
    SELECT
        p.date,
        CASE WHEN p.channel = 'Meta' THEN 'Meta' WHEN p.channel = 'TikTok' THEN 'TikTok' ELSE 'Google Ads' END AS channel_grouping,
        CASE WHEN p.channel = 'Meta' THEN 'Meta' WHEN p.channel = 'TikTok' THEN 'TikTok'
             WHEN p.channel LIKE 'Brand%' THEN 'Branded' ELSE 'Non-Branded' END AS channel_subgrouping,
        p.channel AS channel_subgrouping_2,
        CAST(NULL AS VARCHAR) AS campaign_id,
        CAST(NULL AS VARCHAR) AS campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        'looker_channel_spend' AS source,
        'channel' AS match_level,
        p.marketing_spend AS spend,
        0 AS impressions,
        0 AS clicks
    FROM {{ source('looker_raw', 'looker_channel_daily') }} p
    JOIN platform_start s
      ON s.channel_grouping = CASE WHEN p.channel = 'Meta' THEN 'Meta' WHEN p.channel = 'TikTok' THEN 'TikTok' ELSE 'Google Ads' END
     AND p.date < s.first_date
    WHERE p.channel IN ('Meta', 'TikTok', 'Brand PMax', 'Brand Search', 'Brand Shopping', 'NB Demand Gen', 'NB PMax', 'NB Search', 'NB Shopping')
      AND p.marketing_spend > 0
),

stacked AS (
    SELECT * FROM meta_spend
    UNION ALL SELECT * FROM google_spend
    UNION ALL SELECT * FROM tiktok_spend
    UNION ALL SELECT * FROM gmv_max_spend
    UNION ALL SELECT * FROM looker_channel_spend
    UNION ALL SELECT * FROM looker_history
)

SELECT
    date,
    channel_grouping,
    channel_subgrouping,
    channel_subgrouping_2,
    COALESCE(campaign_id, '(not set)') AS campaign_id,
    COALESCE(campaign_name, '(not set)') AS campaign_name,
    COALESCE(adset_id, '(not set)') AS adset_id,
    COALESCE(adset_name, '(not set)') AS adset_name,
    COALESCE(ad_id, '(not set)') AS ad_id,
    COALESCE(ad_name, '(not set)') AS ad_name,
    source,
    match_level,
    CAST(spend AS DECIMAL(18, 4)) AS spend,
    CAST(impressions AS BIGINT) AS impressions,
    CAST(clicks AS BIGINT) AS clicks
FROM stacked
