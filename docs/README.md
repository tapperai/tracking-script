# tracking-script — Documentation

> **Approach:** [DOCUMENT_FIRST.md](../document-first-template/DOCUMENT_FIRST.md) — Write the spec, then write the code.
>
> **Template:** [SPEC.md](../document-first-template/_templates/SPEC.md) — Copy this to start a new spec.

---

## Domains

| Domain | Status | Description |
|--------|--------|-------------|
| [tracking-script](tracking-script/SPEC.md) | `SHIPPED` | Single-file GTM Community Template that injects `monitor.tapper.ai/bundle.js` and calls `tapper.init(pk)`. Known defect (issue #3): the tag never starts the monitor. The version the Gallery serves (`551ea056`) grants no `access_globals` key, and `main` grants the key `tapper`, but GTM matches the key exactly and `callInWindow('tapper.init', pk)` needs execute on `tapper.init`, so GTM denies the call in both. Remove this note once the Gallery listing serves a sha that grants `tapper.init`. |

See also [`tracking-script/TESTING.md`](tracking-script/TESTING.md) and
[`tracking-script/ENVIRONMENT_SPINUP.md`](tracking-script/ENVIRONMENT_SPINUP.md).
