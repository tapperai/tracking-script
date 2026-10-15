# tracking-script — Documentation

> **Approach:** [DOCUMENT_FIRST.md](DOCUMENT_FIRST.md) — Write the spec, then write the code.
>
> **Template:** [SPEC.md](_templates/SPEC.md) — Copy this to start a new spec.

---

## Domains

| Domain | Status | Description |
|--------|--------|-------------|
| [tracking-script](tracking-script/SPEC.md) | `SHIPPED` | Single-file GTM Community Template that injects `monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`; it grants `access_globals` execute on the exact key `tapper.init` (GTM matches the full dotted path). |

See also [`tracking-script/TESTING.md`](tracking-script/TESTING.md) and
[`tracking-script/ENVIRONMENT_SPINUP.md`](tracking-script/ENVIRONMENT_SPINUP.md).
