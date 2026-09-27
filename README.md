# Tapper Ad Fraud Protection — GTM Template

Protect your Google Ads, Meta Ads, and TikTok Ads campaigns from invalid clicks and ad fraud using [Tapper](https://tapper.ai).

## Setup

1. Import this template into your GTM workspace via the **Community Template Gallery**.
2. Create a new tag using the **Tapper Ad Fraud Protection** template.
3. Enter your **Public Key** from the [Tapper dashboard](https://tapper.ai) (Settings → Public Key).
4. Set the trigger to **All Pages**.
5. Publish your container.

## Requirements

- A Tapper account — [sign up at tapper.ai](https://tapper.ai)
- Your Public Key (`pk_live_...` or `pk_test_...`)

## What it does

Loads the Tapper monitoring script and initialises it with your Public Key. Tapper detects invalid traffic patterns and automatically protects your ad campaigns.

## Updating

Versions published before 2026-09-28 loaded the script but were not permitted to start it, so monitoring never began. If you imported the template earlier, open **Templates** in your GTM workspace, accept the update offered on the Tapper template (it adds permission to call `tapper.init`), then publish your container.
