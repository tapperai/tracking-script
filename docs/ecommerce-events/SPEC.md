# Tapper e-commerce events tag (GTM)

> **Status:** ACTIVE (built 2026-11-03, tracking-script)
>
> **Implemented in:** tracking-script (`template.tpl` tag type "Send an e-commerce event", `gtm/`, `scripts/`)
>
> **Companion:** tapperai/tracker `docs/client/ecommerce-capture/SPEC.md` ("`tapper.track`", "Full GA4 detail")

## What it is

The GTM Community Template now has two tag types (the field **What should this tag do?**, default **Start the Tapper monitoring script**, so every tag made before this change behaves exactly as it did):

1. **Start the Tapper monitoring script** (All Pages): loads `bundle.js` and calls `tapper.init(pk)`. New optional field **E-commerce platform capture** (None, WooCommerce, BigCommerce, Salla, Zid) becomes `tapper.init(pk, { ecommerce: "<platform>" })`.
2. **Send an e-commerce event**: fired by a **Custom Event** trigger on a GA4 e-commerce event name. It reads the event name and the `ecommerce` object at fire time with the sandboxed `copyFromDataLayer` (read-only) and calls `tapper.track(name, params)`. On `purchase` it also records the order as a conversion.

**It never wraps, replaces or calls `dataLayer.push`** (incident 2026-06-12). `copyFromDataLayer` reads GTM's own data model for two keys, `event` and `ecommerce`, and nothing else.

## Fields of the e-commerce tag

| Field | Meaning |
|---|---|
| What should this tag do? | `Send an e-commerce event` |
| Public Key | the customer's `pk_live_...` / `pk_test_...` (same as the monitoring tag) |
| Event name (optional) | empty: the tag reads the firing Custom Event's name. Set only to override |
| Record purchases as conversions | default **ON**. A `purchase` event also calls `tapper.push(value, currency, transaction_id, extras, userData)` exactly like the Tapper conversion tag. Turn OFF if the Tapper conversion tag stays on purchases, so an order is never counted twice |
| Customer email (optional, purchase only) | a GTM variable; plain, or an already SHA-256 hashed 64-hex value (GA4 `user_data` / Enhanced Conversions variables). Only the 5th argument of `tapper.push`, never in `tapper.track` |
| Customer phone (optional, purchase only) | the same, international format (`+` or `00`) or a 64-hex hash |
| Additional fields (optional) | name / value rows for the purchase conversion, the conversion tag's own table and rules |

## What it reads and sends

`ecommerce.value`, `currency`, `transaction_id`, `coupon`, `shipping`, `tax`, `payment_type`, `shipping_tier`, `item_list_id`, `item_list_name`, `promotion_id`, `promotion_name`, `creative_name`, `creative_slot`, `location_id`, and up to 200 `items` with `item_id`, `item_name`, `item_brand`, `item_category` to `item_category5`, `item_variant`, `price`, `quantity`, `discount`, `coupon`, `affiliation`, `index`, `item_list_id`, `item_list_name`, `location_id`. Only strings (cut at 200 characters) and numbers pass; any other key of the object is never read. `tapper.track` validates again (closed shapes, no `@`, no phone-shaped text, 200 items, 60,000 characters) and stores the result as the event's `ed` detail.

## Rules the tag keeps (each a scenario in `___TESTS___`)

- **Every event sends its own values.** Google's rule is to push `ecommerce: null` before each e-commerce event. If a page does not, the previous event's object is still in the data layer: an `ecommerce` object identical to the one the previous, DIFFERENTLY named event used is ignored, and the event goes out with its name only. (Cost: an add_to_cart followed on the same page by a begin_checkout that pushes the identical object loses that begin_checkout's items. Push `ecommerce: null` and the new object to keep them.)
- **An amount rides only with its currency** in `tapper.track`. The purchase conversion keeps a value without a currency (the ad account's currency is used), like the conversion tag.
- **One order id is one purchase.** A `transaction_id` this browser already sent (`localStorage` key `tapper_ecom_orders`, the last 20) is skipped for both the event and the conversion, so a reloaded thank-you page or a second trigger does not double. Server-side keying of a browser conversion on its order id was NOT found in back-end (the dedupe there is on the visitor and the exact time), so this client rule is the one that holds.
- **A purchase with no usable value** records a plain conversion (`tapper.push(1)`), the conversion tag's legacy behaviour.
- **Before the script has loaded** (`window.tapper` is the loader stub array) the call goes into the stub's buffer as `["track", name, params]`; the script drains it at init.
- **An event name outside the vocabulary sends nothing** and the tag still reports success.
- **No personal data in the event.** E-mail and phone exist only as the 5th `tapper.push` argument, hashed in the browser.

## Permissions (exactly what the JS uses; `scripts/validate_template.py` fails on any extra)

`access_globals`: read `tapper`; execute `tapper.init`, `tapper.track`, `tapper.push`. `inject_script`: `https://monitor.tapper.ai/bundle.js`. `read_data_layer`: keys `event` and `ecommerce`. `access_local_storage`: `tapper_ecom_orders` (read, write). `logging`: debug.

## Files

- `template.tpl`: the template (one file, both tag types).
- `gtm/tapper-ecommerce-events.container.json`: the ready import: the tag, one Custom Event trigger per GA4 event (`view_item`, `view_item_list`, `add_to_cart`, `remove_from_cart`, `view_cart`, `begin_checkout`, `add_payment_info`, `purchase`), the built-in Event variable, and this template inline (works before Google lists it in the Gallery).
- `gtm/tapper-ecommerce-events-custom-html.container.json`: the same triggers with the Custom HTML tag below and the `DLV - ecommerce` Data Layer Variable it reads.
- `gtm/custom-html-tag.html`: the Custom HTML body (same rules, plain JS). Tests: `scripts/run_custom_html_tests.mjs`.
- Both import files are BUILT from the two files above by `scripts/build_gtm_container.mjs`; `--check` (run by the tests) fails when they are stale.

## Customer steps (GTM)

1. In Google Tag Manager open **Admin > Import Container**, choose the file `tapper-ecommerce-events.container.json` (downloaded from the Tapper app, Setup > Website), pick your workspace, choose **Merge** and **Rename conflicting tags, triggers and variables**, then **Confirm**.
2. Open the new tag **Tapper - E-commerce events**, paste your **Public Key**, leave **Record purchases as conversions** on (turn it off only if you keep the Tapper conversion tag for purchases), and save.
3. Click **Submit** and **Publish**. Open Preview, add a product to the cart: the tag fires on the `add_to_cart` trigger.

The Tapper monitoring tag must already be on All Pages, and the store must push GA4 e-commerce events (with `ecommerce: null` before each). Without the Gallery template or the import: use the Custom HTML import file, or paste `gtm/custom-html-tag.html` into a Custom HTML tag with the same triggers and a Data Layer Variable `DLV - ecommerce` (name `ecommerce`, version 2).

## Not proven

The import files follow GTM's export format (version 2) and were not imported into a live GTM account by this change; the template scenarios run in this repo's emulator of GTM's sandbox (`scripts/run_template_tests.mjs`), the same one that guards the monitoring tag. First live proof: import into a test container, fire each trigger in Preview, read the events in the Tapper app.
