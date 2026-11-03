# Tapper - Monitoring Script (GTM template)

Monitor your Google Ads, Meta Ads, and TikTok Ads traffic for invalid clicks using [Tapper](https://tapper.ai).

## Setup

1. Import this template into your GTM workspace via the **Community Template Gallery**.
2. Create a new tag using the **Tapper - Monitoring Script** template.
3. Enter your **Public Key** from the [Tapper dashboard](https://tapper.ai) (Settings → Public Key).
4. Set the trigger to **All Pages**.
5. Publish your container.

## Requirements

- A Tapper account — [sign up at tapper.ai](https://tapper.ai)
- Your Public Key (`pk_live_...` or `pk_test_...`)

## What it does

Loads the Tapper monitoring script and initialises it with your Public Key. Tapper detects invalid traffic patterns and automatically protects your ad campaigns.

## Updating

Earlier versions of this template loaded the script but were not permitted to start it, so monitoring never began. To check yours, open **Templates** in your GTM workspace and view the Tapper template's permissions: if they do not list `tapper.init` under **Accesses global variables**, accept the update offered on the template, then publish your container.

## E-commerce events (optional second tag)

The same template can also send your store's GA4 e-commerce events (view_item, view_item_list, add_to_cart, remove_from_cart, view_cart, begin_checkout, add_payment_info, purchase) to Tapper, and record purchases as conversions. In three steps:

1. In Google Tag Manager: **Admin > Import Container** > `gtm/tapper-ecommerce-events.container.json` > your workspace > **Merge** > **Rename conflicting tags, triggers and variables** > **Confirm**.
2. Open the tag **Tapper - E-commerce events**, paste your **Public Key**, keep **Record purchases as conversions** on (off only if you keep the Tapper conversion tag for purchases).
3. **Submit** and **Publish**.

The tag reads the event and the `ecommerce` object with GTM's own read-only data-layer variable and never touches the page's `dataLayer.push`. Push `ecommerce: null` before each e-commerce event (Google's own rule) so every event carries its own values. No Gallery template or import? `gtm/tapper-ecommerce-events-custom-html.container.json` does the same with a Custom HTML tag, body in `gtm/custom-html-tag.html`. Full field list and rules: `docs/ecommerce-events/SPEC.md`.
