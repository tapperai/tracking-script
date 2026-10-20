# tracking-script — Documentation

> **Approach:** the `docs-rule` skill in loop: decide before you build, frozen decision records in
> `docs/decisions/NNNN-title.md`, one now-page per area.

---

## Domains

| Domain | Status | Description |
|--------|--------|-------------|
| [tracking-script](tracking-script/SPEC.md) | ACTIVE | Single-file GTM Community Template that injects `monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`; it grants `access_globals` execute on the exact key `tapper.init` (GTM matches the full dotted path). |

See also [`tracking-script/TESTING.md`](tracking-script/TESTING.md) and
[`tracking-script/ENVIRONMENT_SPINUP.md`](tracking-script/ENVIRONMENT_SPINUP.md).
