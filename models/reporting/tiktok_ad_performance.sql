{{ config (
    alias = target.database + '_tiktok_ad_performance'
)}}

{#
  Standard TikTok ads (Fivetran connector) plus TikTok GMV Max.

  GMV Max has no ad or ad group: TikTok builds the creative mix itself. Its campaign-level daily cost, orders and
  revenue (looker_raw.tiktok_gmv_max_daily, loaded from the TikTok Business API by tiktok_gmv_max_to_redshift.py)
  are added as ONE row per campaign and period with ad_id and adgroup_id NULL and ad / ad group names '(not set)',
  rolled up to day / week / month / quarter / year with the package's get_date_parts rules. Filter
  campaign_type_default = 'GMV Max' to see or exclude them. Same column meanings as tiktok_campaign_performance.
#}

{%- set date_granularity_list = ['day','week','month','quarter','year'] -%}

WITH standard AS (
    SELECT
        campaign_name,
        campaign_id,
        campaign_status,
        campaign_type_default,
        adgroup_name,
        adgroup_id,
        adgroup_status,
        audience,
        ad_name,
        ad_id,
        ad_status,
        visual,
        date,
        date_granularity,
        cost as spend,
        impressions,
        clicks,
        complete_payment as purchases,
        total_complete_payment_rate as revenue,
        web_event_add_to_cart as atc
    FROM {{ ref('tiktok_performance_by_ad') }}
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
        '(not set)' AS adgroup_name,
        CAST(NULL AS BIGINT) AS adgroup_id,
        CAST(NULL AS VARCHAR) AS adgroup_status,
        CAST(NULL AS VARCHAR) AS audience,
        '(not set)' AS ad_name,
        CAST(NULL AS BIGINT) AS ad_id,
        CAST(NULL AS VARCHAR) AS ad_status,
        CAST(NULL AS VARCHAR) AS visual,
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
