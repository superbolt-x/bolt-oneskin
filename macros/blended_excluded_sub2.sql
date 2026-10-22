{#
  SQL list of the channel_subgrouping_2 labels left OUT of the blended models, from the project var
  blended_exclude_subgrouping_2 (pipe-separated, like the other vars; default 'Spotlights').
  Spotlights orders cannot be tied to any campaign in OneSkin's Meta ad account, so they do not belong in a
  table built around platform spend. looker_utm_orders still carries them. To bring them back, set the var to
  'dummy' (a label that never occurs).
#}
{% macro blended_excluded_sub2() -%}
({%- for item in var('blended_exclude_subgrouping_2', 'Spotlights').split('|') -%}'{{ item }}'{{ ', ' if not loop.last }}{%- endfor -%})
{%- endmacro %}
