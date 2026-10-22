{{ config (
    alias = target.database + '_blended'
)}}

{#
  Spend and Looker orders in one table, STACKED (UNION ALL), never joined. A join needs both sides to carry the
  same campaign, and they do not (Pinterest spend has no campaign; Google orders resolve deeper than Google
  spend). Stacking keeps every row from both, so any rollup stays correct:

    channel / day / subgrouping 2     SUM(spend) and SUM(new_customer_orders) always add up
    campaign level                    CAC is meaningful only where both a spend row and an order row exist for
                                      that campaign; '(not set)' rows are the part nothing could be tied to

  source: platform_spend | looker_channel_spend | looker_orders. Each row fills its own measures and leaves
  the others at 0. match_level: ad | adset | campaign for platform rows; channel for Looker channel totals;
  ad | adset | campaign | none for orders. Filter channel_subgrouping_2 (e.g. <> 'Spotlights') as needed.
#}

SELECT
    date, channel_grouping, channel_subgrouping, channel_subgrouping_2,
    campaign_id, campaign_name, adset_id, adset_name, ad_id, ad_name,
    source, match_level,
    spend, impressions, clicks,
    CAST(0 AS BIGINT) AS new_customer_orders
FROM {{ ref('blended_spend') }}

UNION ALL

SELECT
    date, channel_grouping, channel_subgrouping, channel_subgrouping_2,
    campaign_id, campaign_name, adset_id, adset_name, ad_id, ad_name,
    source, match_level,
    CAST(0 AS DECIMAL(18, 4)) AS spend, CAST(0 AS BIGINT) AS impressions, CAST(0 AS BIGINT) AS clicks,
    CAST(new_customer_orders AS BIGINT) AS new_customer_orders
FROM {{ ref('blended_conversions') }}
