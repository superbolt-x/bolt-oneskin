{{ config (
    alias = target.database + '_facebook_ad_performance'
)}}

{#- OS New Purchase = the Meta pixel custom event PurchaseNewCustomer (OneSkin's new-customer purchase), on the
    same attribution basis as purchases. The package only creates the column once the action has data, so 0 otherwise. -#}
{%- set osnp_col = 'offsite_conversion.fb_pixel_custom.purchasenewcustomer' -%}
{%- set src_cols = adapter.get_columns_in_relation(ref('facebook_performance_by_ad')) | map(attribute='name') | map('lower') | list if execute else [] -%}


SELECT 
campaign_name,
campaign_id,
campaign_effective_status,
campaign_type_default,
adset_name,
adset_id,
adset_effective_status,
audience,
ad_name,
ad_id,
ad_effective_status,
visual,
copy,
format_visual,
visual_copy,
date,
date_granularity,
spend,
impressions,
link_clicks,
add_to_cart,
purchases,
{% if osnp_col in src_cols %}"{{ osnp_col }}"{% else %}0{% endif %} AS os_new_purchases,
revenue
FROM {{ ref('facebook_performance_by_ad') }}
