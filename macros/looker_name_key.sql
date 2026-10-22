{#
  Comparable key for a campaign / ad / ad set name or a UTM value.
  URL-decodes the three escapes Looker leaves in UTMs (%5b %5d %2b), lower-cases, turns runs of
  _ + | / - and whitespace into one space, and drops a leading "[sb] " tag. So
  '%5bsb%5d+us-pro_asc_evergreen_body_7dc%2b1dev_volume_7.7.26' and
  '[SB] US-PRO_ASC_evergreen_Body_7dc+1dev_volume_7.7.26' give the same key.
  Brackets are written as [[] and []] so no backslash is needed in a Redshift string.
#}
{% macro looker_name_key(col) -%}
TRIM(
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            TRIM(REPLACE(REPLACE(REPLACE(LOWER({{ col }}), '%5b', '['), '%5d', ']'), '%2b', '+')),
            '[_+|/[:space:]-]+', ' '
        ),
        '^[[]sb[]] ?', ''
    )
)
{%- endmacro %}
