# CitySim — a Luanti game

City-building / roleplay game for [Luanti](https://www.luanti.org/) (formerly Minetest).
148 mods under `mods/`, 805 Lua files. `game.conf` declares `title = CitySim`.

Only three mods are git submodules — `mods/cooking`, `mods/cooking_fr`,
`mods/alpha_workaround_minus`. Everything else is an in-tree copy and can be edited
directly.

## Active project: API modernization

**`MODERNIZATION.md` is the plan of record.** It catalogues every Luanti API
deprecation and behaviour change from 5.0 to 5.17-dev with the required fix, and it
carries the progress state.

When working on this:

* Read `MODERNIZATION.md` §1 first — it is a stateful checklist, not just a reference.
  §7.2 is the mod inventory with upstream identification and divergence bands,
  §7.3 the upstream-upgrade procedure, §7.4 per-mod progress, §7.5 the order of attack.
* **Never replace a vendored mod with upstream without diffing first.** The divergence
  metric in §7.2 only sees edits made *after* import; a mod modified before it was
  committed is indistinguishable from a pristine copy. Band 1 means *unverified*, not
  *unmodified*. Record negative diff results in §7.4 too.
* **Update the checkboxes and the §1.4 session log as you go.** A future session cannot
  tell "verified, no change needed" from "never looked at" unless you write it down.
* Target is latest master (5.17-dev), practically 5.16.1.
* Distinguish the severity classes (§0.2). The **[SILENT]** items — changed defaults and
  semantics that produce no warning — need deliberate audits and are the ones most
  likely to be missed.

## Conventions

* `minetest` and `core` are both fine; `minetest` is a permanent alias and is *not*
  deprecated. Prefer `core` in new or already-touched code. Do not do a blanket rename.
* Match the surrounding style of each mod — this tree vendors many third-party mods with
  their own conventions. Do not reformat files you are only patching.
* For vendored third-party mods, check whether pulling a current upstream release is
  cheaper than hand-patching before editing.

## Checks

```sh
luacheck mods/                 # .luacheckrc exists; baseline 3579 warnings / 0 errors
luacheck mods/ --only 1        # just the global-related warnings (989 of them)
```

Most luacheck warnings are cosmetic (long lines, whitespace). See `MODERNIZATION.md`
§7.1 for which codes matter and which W113 hits are false positives from cross-mod
globals.

To surface engine deprecation warnings, in `minetest.conf`:

```
debug_log_level = info                # message at "warning", backtrace at "info"
deprecated_lua_api_handling = log     # the default — do NOT set this to "error"
```

`error` mode throws a `LuaError` *instead of* printing the backtrace and aborts the
callback, so it is worse for a broad sweep. See `MODERNIZATION.md` §0.1.

## Git

Current work happens on the `maintenance` branch; `master` is the default branch.
