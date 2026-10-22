{{ config (
    alias = target.database + '_looker_utm_orders'
)}}

{#
  Looker last-click NEW-customer orders (looker_raw.looker_last_click_utm_daily, loaded daily from the
  Looker email) tied back to the ad platform object each UTM row points at.

  Grain is unchanged: one output row per source row, so SUM(new_customer_orders) always equals the source
  (tests/looker_utm_orders_keeps_orders.sql). Channel Grouping / Subgrouping / Subgrouping 2 come straight
  from Looker, so a user can still filter Spotlights out of Meta with channel_subgrouping_2.

  How each platform is resolved (first hit wins; match_method says which one hit):
    Meta        ad_id_in_term  utm_term 'aid-<ad_id>' is the Meta ad id
                ad_name        utm_content equals ONE ad's name
                adset_name     utm_term equals ONE ad set's name
                seed / campaign_name / campaign_id   campaign only (utm_campaign is a hand-set label that
                               goes stale when a campaign is renamed, so it is the last resort)
    Google Ads  seed / campaign_id / campaign_name   campaign only. The warehouse has no ad group or ad level.
    TikTok      seed / campaign_name                 campaign only (utm_content matches ad names under 7%)
    Pinterest   no_platform_data  there is no Pinterest connector, so ids and names stay '(not set)'
  Rows that cannot be resolved get '(not set)' and a reason: not_set, unrendered_placeholder (the Google
  tracking template left {campaignname} unfilled) or unmatched. Names are compared with looker_name_key.
  Exceptions that need a human live in seeds/looker_utm_campaign_map.csv.
#}

WITH utm AS (
    SELECT
        date,
        channel_grouping,
        channel_subgrouping,
        channel_subgrouping_2,
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        utm_term,
        utm_term_ad_id,
        new_customer_orders,
        {{ looker_name_key('utm_campaign') }} AS campaign_key,
        {{ looker_name_key('utm_content') }} AS content_key,
        {{ looker_name_key('utm_term') }} AS term_key
    FROM {{ source('looker_raw', 'looker_last_click_utm_daily') }}
),

utm_flagged AS (
    SELECT
        *,
        CASE
            WHEN campaign_key IN ('', 'not set', '(not set)') THEN 'not_set'
            WHEN LEFT(campaign_key, 1) = '{' THEN 'unrendered_placeholder'
            ELSE 'unmatched'
        END AS unresolved_reason
    FROM utm
),

seed AS (
    SELECT platform, utm_campaign_key, campaign_id::VARCHAR AS campaign_id
    FROM {{ ref('looker_utm_campaign_map') }}
),

-- ---------------------------------------------------------------- Meta
meta_ads AS (
    SELECT
        ad_id, ad_name, adset_id, adset_name, campaign_id,
        {{ looker_name_key('ad_name') }} AS ad_name_key,
        {{ looker_name_key('adset_name') }} AS adset_name_key
    FROM (
        SELECT
            ad_id::VARCHAR AS ad_id, ad_name,
            adset_id::VARCHAR AS adset_id, adset_name,
            campaign_id::VARCHAR AS campaign_id,
            ROW_NUMBER() OVER (PARTITION BY ad_id ORDER BY date DESC) AS rn
        FROM {{ ref('facebook_performance_by_ad') }}
        WHERE date_granularity = 'day'
    )
    WHERE rn = 1
),

meta_ad_by_name AS (
    SELECT ad_name_key, MIN(ad_id) AS ad_id
    FROM meta_ads
    WHERE ad_name_key <> ''
    GROUP BY 1
    HAVING COUNT(DISTINCT ad_id) = 1
),

meta_adsets AS (
    SELECT adset_id, MAX(adset_name) AS adset_name, MAX(campaign_id) AS campaign_id
    FROM meta_ads
    GROUP BY 1
),

meta_adset_by_name AS (
    SELECT adset_name_key, MIN(adset_id) AS adset_id
    FROM meta_ads
    WHERE adset_name_key <> ''
    GROUP BY 1
    HAVING COUNT(DISTINCT adset_id) = 1
),

meta_campaigns AS (
    SELECT campaign_id, campaign_name
    FROM (
        SELECT
            campaign_id::VARCHAR AS campaign_id, campaign_name,
            ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) AS rn
        FROM {{ ref('facebook_performance_by_campaign') }}
        WHERE date_granularity = 'day'
    )
    WHERE rn = 1
),

-- every name a campaign has ever had, so a UTM carrying an old name still resolves
meta_campaign_by_name AS (
    SELECT {{ looker_name_key('campaign_name') }} AS campaign_name_key, MIN(campaign_id::VARCHAR) AS campaign_id
    FROM (SELECT DISTINCT campaign_id, campaign_name FROM {{ ref('facebook_performance_by_campaign') }} WHERE campaign_name IS NOT NULL)
    GROUP BY 1
    HAVING COUNT(DISTINCT campaign_id) = 1
),

meta_resolved AS (
    SELECT
        u.*,
        COALESCE(a1.ad_id, a2.ad_id) AS r_ad_id,
        COALESCE(a1.ad_name, a2.ad_name) AS r_ad_name,
        COALESCE(a1.adset_id, a2.adset_id, s.adset_id) AS r_adset_id,
        COALESCE(a1.adset_name, a2.adset_name, s.adset_name) AS r_adset_name,
        COALESCE(a1.campaign_id, a2.campaign_id, s.campaign_id, sd.campaign_id, cn.campaign_id, ci.campaign_id) AS r_campaign_id,
        CASE
            WHEN a1.ad_id IS NOT NULL THEN 'ad_id_in_term'
            WHEN a2.ad_id IS NOT NULL THEN 'ad_name'
            WHEN s.adset_id IS NOT NULL THEN 'adset_name'
            WHEN sd.campaign_id IS NOT NULL THEN 'seed'
            WHEN cn.campaign_id IS NOT NULL THEN 'campaign_name'
            WHEN ci.campaign_id IS NOT NULL THEN 'campaign_id'
            ELSE u.unresolved_reason
        END AS match_method
    FROM utm_flagged u
    LEFT JOIN meta_ads a1 ON u.utm_term_ad_id <> '' AND u.utm_term_ad_id = a1.ad_id
    LEFT JOIN meta_ad_by_name an ON u.content_key = an.ad_name_key
    LEFT JOIN meta_ads a2 ON an.ad_id = a2.ad_id
    LEFT JOIN meta_adset_by_name sn ON u.term_key = sn.adset_name_key
    LEFT JOIN meta_adsets s ON sn.adset_id = s.adset_id
    LEFT JOIN seed sd ON sd.platform = 'Meta' AND sd.utm_campaign_key = u.campaign_key
    LEFT JOIN meta_campaign_by_name cn ON u.campaign_key = cn.campaign_name_key
    LEFT JOIN meta_campaigns ci ON u.utm_campaign = ci.campaign_id
    WHERE u.channel_grouping = 'Meta'
),

meta AS (
    SELECT
        m.date, m.channel_grouping, m.channel_subgrouping, m.channel_subgrouping_2,
        m.utm_source, m.utm_medium, m.utm_campaign, m.utm_content, m.utm_term, m.new_customer_orders,
        m.r_campaign_id AS campaign_id, mc.campaign_name AS campaign_name,
        m.r_adset_id AS adset_id, m.r_adset_name AS adset_name,
        m.r_ad_id AS ad_id, m.r_ad_name AS ad_name,
        m.match_method
    FROM meta_resolved m
    LEFT JOIN meta_campaigns mc ON mc.campaign_id = m.r_campaign_id
),

-- ---------------------------------------------------------------- Google Ads
google_campaigns AS (
    SELECT campaign_id, campaign_name
    FROM (
        SELECT
            campaign_id::VARCHAR AS campaign_id, campaign_name,
            ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) AS rn
        FROM {{ ref('googleads_performance_by_campaign') }}
        WHERE date_granularity = 'day'
    )
    WHERE rn = 1
),

google_campaign_by_name AS (
    SELECT {{ looker_name_key('campaign_name') }} AS campaign_name_key, MIN(campaign_id::VARCHAR) AS campaign_id
    FROM (SELECT DISTINCT campaign_id, campaign_name FROM {{ ref('googleads_performance_by_campaign') }} WHERE campaign_name IS NOT NULL)
    GROUP BY 1
    HAVING COUNT(DISTINCT campaign_id) = 1
),

google AS (
    SELECT
        u.date, u.channel_grouping, u.channel_subgrouping, u.channel_subgrouping_2,
        u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term, u.new_customer_orders,
        COALESCE(sd.campaign_id, ci.campaign_id, cn.campaign_id) AS campaign_id,
        gc.campaign_name AS campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        CASE
            WHEN sd.campaign_id IS NOT NULL THEN 'seed'
            WHEN ci.campaign_id IS NOT NULL THEN 'campaign_id'
            WHEN cn.campaign_id IS NOT NULL THEN 'campaign_name'
            ELSE u.unresolved_reason
        END AS match_method
    FROM utm_flagged u
    LEFT JOIN seed sd ON sd.platform = 'Google Ads' AND sd.utm_campaign_key = u.campaign_key
    LEFT JOIN google_campaigns ci ON u.utm_campaign = ci.campaign_id
    LEFT JOIN google_campaign_by_name cn ON u.campaign_key = cn.campaign_name_key
    LEFT JOIN google_campaigns gc ON gc.campaign_id = COALESCE(sd.campaign_id, ci.campaign_id, cn.campaign_id)
    WHERE u.channel_grouping = 'Google Ads'
),

-- ---------------------------------------------------------------- TikTok
tiktok_campaigns AS (
    SELECT campaign_id, campaign_name
    FROM (
        SELECT
            campaign_id::VARCHAR AS campaign_id, campaign_name,
            ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) AS rn
        FROM {{ ref('tiktok_performance_by_campaign') }}
        WHERE date_granularity = 'day' AND campaign_name IS NOT NULL
    )
    WHERE rn = 1
),

tiktok_campaign_by_name AS (
    SELECT {{ looker_name_key('campaign_name') }} AS campaign_name_key, MIN(campaign_id::VARCHAR) AS campaign_id
    FROM (SELECT DISTINCT campaign_id, campaign_name FROM {{ ref('tiktok_performance_by_campaign') }} WHERE campaign_name IS NOT NULL)
    GROUP BY 1
    HAVING COUNT(DISTINCT campaign_id) = 1
),

tiktok AS (
    SELECT
        u.date, u.channel_grouping, u.channel_subgrouping, u.channel_subgrouping_2,
        u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term, u.new_customer_orders,
        COALESCE(sd.campaign_id, cn.campaign_id) AS campaign_id,
        tc.campaign_name AS campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        CASE
            WHEN sd.campaign_id IS NOT NULL THEN 'seed'
            WHEN cn.campaign_id IS NOT NULL THEN 'campaign_name'
            ELSE u.unresolved_reason
        END AS match_method
    FROM utm_flagged u
    LEFT JOIN seed sd ON sd.platform = 'TikTok' AND sd.utm_campaign_key = u.campaign_key
    LEFT JOIN tiktok_campaign_by_name cn ON u.campaign_key = cn.campaign_name_key
    LEFT JOIN tiktok_campaigns tc ON tc.campaign_id = COALESCE(sd.campaign_id, cn.campaign_id)
    WHERE u.channel_grouping = 'TikTok'
),

-- ---------------------------------------------------------------- Pinterest and anything new
other AS (
    SELECT
        date, channel_grouping, channel_subgrouping, channel_subgrouping_2,
        utm_source, utm_medium, utm_campaign, utm_content, utm_term, new_customer_orders,
        CAST(NULL AS VARCHAR) AS campaign_id,
        CAST(NULL AS VARCHAR) AS campaign_name,
        CAST(NULL AS VARCHAR) AS adset_id,
        CAST(NULL AS VARCHAR) AS adset_name,
        CAST(NULL AS VARCHAR) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_name,
        'no_platform_data' AS match_method
    FROM utm_flagged
    WHERE channel_grouping NOT IN ('Meta', 'Google Ads', 'TikTok')
),

stacked AS (
    SELECT * FROM meta
    UNION ALL SELECT * FROM google
    UNION ALL SELECT * FROM tiktok
    UNION ALL SELECT * FROM other
)

SELECT
    date,
    channel_grouping,
    channel_subgrouping,
    channel_subgrouping_2,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    COALESCE(campaign_id, '(not set)') AS campaign_id,
    COALESCE(campaign_name, '(not set)') AS campaign_name,
    COALESCE(adset_id, '(not set)') AS adset_id,
    COALESCE(adset_name, '(not set)') AS adset_name,
    COALESCE(ad_id, '(not set)') AS ad_id,
    COALESCE(ad_name, '(not set)') AS ad_name,
    CASE
        WHEN ad_id IS NOT NULL THEN 'ad'
        WHEN adset_id IS NOT NULL THEN 'adset'
        WHEN campaign_id IS NOT NULL THEN 'campaign'
        ELSE 'none'
    END AS match_level,
    match_method,
    new_customer_orders
FROM stacked
