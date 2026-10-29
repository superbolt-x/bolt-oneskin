# Add Meta "OS New Purchase" (PurchaseNewCustomer) to the Facebook reporting models

## What
- `reporting.oneskin_facebook_ad_performance` and `reporting.oneskin_facebook_campaign_performance` get a new column **`os_new_purchases`**: the Meta pixel custom event `PurchaseNewCustomer` ("OS New Purchase" in the weekly doc), taken from the package column `offsite_conversion.fb_pixel_custom.purchasenewcustomer`.
- Present on every `date_granularity` (day / week / month / quarter / year), same rows as `purchases`, so it sums the same way. OS New Purchase CPA = `sum(spend) / sum(os_new_purchases)`.
- The package only creates the column once Meta has reported the action; the model falls back to `0` if it is ever missing (checked with `adapter.get_columns_in_relation`), so the run cannot break on it.

## Why
OS New Purchase CPA has been the primary Meta lens in the weekly doc since 2026-10-26 and was only available from the Meta MCP / Ads Manager.

## Verification (read-only, rendered SQL against the current package tables)
- MTD 10/1-10/25: spend $703,589 / 2,288 OS new purchases = **$308**, the 10/29 weekly doc says $308.
- Weekly (Mon-Sun) 9/28, 10/5, 10/12, 10/19: $298 / $310 / $320 / $329, identical to the doc's "OS New Purchase CPA" row.
- Ad and campaign models give the same totals on every granularity.

## TikTok GMV Max in blended CAC (checked, no change needed)
`oneskin_blended_spend`, `oneskin_blended` and `oneskin_blended_channel_daily` already carry GMV Max as `channel_grouping = 'TikTok'`, `channel_subgrouping_2 = 'TikTok GMV Max'` (October 1-27: $3,071), so "TikTok overall" and the blended CAC include it. Metabase 56988 includes it too.

## Deploy
Runs in the Fivetran transformation `facebook_performance` (integrated with the Facebook connector). No new sources or vars.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
