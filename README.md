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
