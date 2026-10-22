{{ config (
    alias = target.database + '_blended_channel_daily'
)}}

{#
  The client's Channels Daily panel, rebuilt: one row per date and channel_subgrouping_2.
    spend                      ours, from the ad platforms (blended_spend). Meta, Google Ads and TikTok match
                               Looker's panel to the dollar from 2025 on. Pinterest and TikTok GMV Max come from
                               Looker's own sheet because there is no platform data for them.
    utm_new_customer_orders    Looker last-click orders from the UTM export (2 to 3% below the panel)
    looker_new_customers /     the panel itself (looker_channel_daily), kept next to ours so the two can be compared
    looker_spend / looker_blended_cac
    cac                        spend divided by looker_new_customers, the panel's own definition of Blended CAC
  Full outer join: panel history before the platform tables start (2023-12 for Google, 2022-11 for Meta) still shows
  up, with spend null.
#}

WITH ours AS (
    SELECT
        date, channel_grouping, channel_subgrouping, channel_subgrouping_2,
        SUM(spend) AS spend,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks,
        SUM(new_customer_orders) AS utm_new_customer_orders
    FROM {{ ref('blended') }}
    GROUP BY 1, 2, 3, 4
),

labels AS (
    SELECT channel_subgrouping_2, MIN(channel_grouping) AS channel_grouping, MIN(channel_subgrouping) AS channel_subgrouping
    FROM ours
    GROUP BY 1
),

panel AS (
    SELECT
        p.date,
        COALESCE(l.channel_grouping, '(not set)') AS channel_grouping,
        COALESCE(l.channel_subgrouping, '(not set)') AS channel_subgrouping,
        p.channel AS channel_subgrouping_2,
        p.new_customers AS looker_new_customers,
        p.marketing_spend AS looker_spend,
        p.blended_cac AS looker_blended_cac
    FROM {{ source('looker_raw', 'looker_channel_daily') }} p
    LEFT JOIN labels l ON l.channel_subgrouping_2 = p.channel
)

SELECT
    COALESCE(o.date, p.date) AS date,
    COALESCE(o.channel_grouping, p.channel_grouping) AS channel_grouping,
    COALESCE(o.channel_subgrouping, p.channel_subgrouping) AS channel_subgrouping,
    COALESCE(o.channel_subgrouping_2, p.channel_subgrouping_2) AS channel_subgrouping_2,
    o.spend,
    o.impressions,
    o.clicks,
    o.utm_new_customer_orders,
    p.looker_new_customers,
    p.looker_spend,
    p.looker_blended_cac,
    CASE WHEN p.looker_new_customers > 0 THEN o.spend / p.looker_new_customers END AS cac
FROM ours o
FULL OUTER JOIN panel p ON o.date = p.date AND o.channel_subgrouping_2 = p.channel_subgrouping_2
