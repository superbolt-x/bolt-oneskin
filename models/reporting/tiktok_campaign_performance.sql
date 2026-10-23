{{ config (
    alias = target.database + '_tiktok_campaign_performance'
)}}

{#
  Standard TikTok campaigns (Fivetran connector) plus TikTok GMV Max campaigns.

  GMV Max is NOT in the connector's tables (they have read $0 since 2026-07-22 and Fivetran's raw GMV Max table stops
  on 2026-02-03), so its daily cost comes from tiktok_gmv_max_to_redshift.py (TikTok Business API) into
  looker_raw.tiktok_gmv_max_daily, and is rolled up here into the same day / week / month / quarter / year rows,
  with the same get_date_parts rules as the package. No GMV Max campaign id appears in the standard tables, so
  nothing is double counted. GMV Max rows are marked campaign_type_default = 'GMV Max'.

  For GMV Max: purchases = TikTok Shop orders and revenue = TikTok Shop gross revenue (TikTok's own figures, not
  Looker's or Shopify's; Looker attributes no new customers to GMV Max). impressions, clicks and atc are 0: the
  GMV Max report is read for cost, orders and revenue only.
#}

{%- set date_granularity_list = ['day','week','month','quarter','year'] -%}

WITH standard AS (
    SELECT
        campaign_name,
        campaign_id,
        campaign_status,
        campaign_type_default,
        date,
        date_granularity,
        cost as spend,
        impressions,
        clicks,
        complete_payment as purchases,
        total_complete_payment_rate as revenue,
        web_event_add_to_cart as atc
    FROM {{ ref('tiktok_performance_by_campaign') }}
),

gmv_parts AS (
    SELECT
        *,
        {{ get_date_parts('date') }}
    FROM (
        SELECT date::date AS date, campaign_id::BIGINT AS campaign_id, cost, orders, gross_revenue
        FROM {{ source('looker_raw', 'tiktok_gmv_max_daily') }}
    )
),

{%- for date_granularity in date_granularity_list %}
gmv_{{ date_granularity }} AS (
    SELECT
        '{{ date_granularity }}' AS date_granularity,
        {{ date_granularity }} AS date,
        campaign_id,
        SUM(cost) AS cost,
        SUM(orders) AS orders,
        SUM(gross_revenue) AS gross_revenue
    FROM gmv_parts
    GROUP BY 1, 2, 3
),
{%- endfor %}

gmv_campaigns AS (
    SELECT campaign_id::BIGINT AS campaign_id, campaign_name, campaign_status
    FROM {{ source('looker_raw', 'tiktok_gmv_max_campaigns') }}
),

gmv AS (
    SELECT
        COALESCE(c.campaign_name, '(not set)') AS campaign_name,
        g.campaign_id,
        c.campaign_status,
        'GMV Max' AS campaign_type_default,
        g.date,
        g.date_granularity,
        g.cost::FLOAT AS spend,
        CAST(0 AS BIGINT) AS impressions,
        CAST(0 AS BIGINT) AS clicks,
        CAST(g.orders AS BIGINT) AS purchases,
        g.gross_revenue::FLOAT AS revenue,
        CAST(0 AS BIGINT) AS atc
    FROM (
        {%- for date_granularity in date_granularity_list %}
        SELECT * FROM gmv_{{ date_granularity }}
        {%- if not loop.last %} UNION ALL{% endif %}
        {%- endfor %}
    ) g
    LEFT JOIN gmv_campaigns c USING (campaign_id)
)

SELECT * FROM standard
UNION ALL
SELECT * FROM gmv
