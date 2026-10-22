{{ config (
    alias = target.database + '_blended_conversions'
)}}

{#
  Looker last-click new-customer orders, from looker_utm_orders, summed to the same keys as blended_spend.
  The other half of the blended pair. match_level says how deep the UTM could be resolved (ad, adset, campaign
  or none), so orders that could not be resolved are kept and visible, never dropped.
  Orders can sit deeper than spend (Google orders resolve to an ad group and ad, Google spend stops at the
  campaign), so compare spend and orders at campaign level or above.
#}

SELECT
    date,
    channel_grouping,
    channel_subgrouping,
    channel_subgrouping_2,
    campaign_id,
    campaign_name,
    adset_id,
    adset_name,
    ad_id,
    ad_name,
    'looker_orders' AS source,
    match_level,
    SUM(new_customer_orders) AS new_customer_orders
FROM {{ ref('looker_utm_orders') }}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
