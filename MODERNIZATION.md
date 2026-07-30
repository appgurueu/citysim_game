# Luanti API modernization guide (5.0 → 5.16.1 / 5.17-dev)

A catalogue of deprecations, removals and behaviour changes in the Luanti (formerly
Minetest) Lua API, from the perspective of a mod/game author, together with the
action required for each.

Target: **latest master (5.17-dev)**, practically **5.16.1**.

Sources: `doc/lua_api.md` diffs between every release tag from 5.0.1 to master,
`builtin/game/deprecated.lua`, `doc/breakages.md`,
<https://docs.luanti.org/about/changelog/>, <https://docs.luanti.org/for-creators/warnings/>.

---

## 0. How to use this document

### 0.1 Find the actual problems first

Do not grep blindly — make the engine tell you:

```
# minetest.conf
debug_log_level = info                # "warning" for messages only, "info" adds backtraces
deprecated_lua_api_handling = log     # the default; leave it here
```

* `deprecated_lua_api_handling` accepts `none`, `log` (default) or `error`.
  **`log` is what you want.** It prints the deprecation message *and* a Lua backtrace,
  so it already tells you exactly which call site is at fault.
* The two halves land at different log levels: the message goes to the **warning**
  stream, the backtrace to the **info** stream. So `debug_log_level = warning` tells you
  *what* is deprecated, and `debug_log_level = info` also tells you *where*.
* `error` is only worth reaching for when you want to hard-stop on one specific
  offender. It is not more informative — the engine throws a `LuaError` *instead of*
  emitting the backtrace — and it aborts the callback, so a single deprecated call in a
  busy mod can cascade into unrelated breakage. Not a good setting for a first sweep
  over 148 mods.
* Identical messages from the same source are logged only once, so the log shows each
  distinct offender rather than one line per call.
* This only covers calls the engine explicitly flags (see §5) — never the **[SILENT]**
  behaviour changes.
* Warnings land in `debug.txt`. `chat_log_level = warning` surfaces client-side ones
  in chat.
* Beware Lua tail calls: `return foo()` erases the frame from the backtrace. Disable
  the profiler for accurate source locations.

### 0.2 Severity classes used below

| Marker | Meaning |
|---|---|
| **[BREAK]** | Already broken / hard error / removed. Must fix. |
| **[WARN]** | Still works, logs a runtime deprecation warning. Fix to silence. |
| **[SILENT]** | Still works, no warning, but semantics or defaults changed. Verify by hand. |
| **[SOFT]** | Documented as deprecated/discouraged, no warning yet. Fix opportunistically. |
| **[NEW]** | New API worth adopting (replacement for something old, or removes a workaround). |

### 0.3 The `minetest` → `core` namespace

Since 5.10.0 the documented namespace is `core`. `minetest` remains a permanent
alias — it is **not** deprecated and old code will not break. `core` has existed
since 0.4.10, so using it does not hurt backwards compatibility.

Recommendation for this game: leave existing `minetest.*` calls alone unless you are
touching the file anyway; use `core.*` in new code. A blanket rename is a large,
risky, zero-functional-benefit diff. (If you do it, remember `minetest.env` is a
*different* thing — see 5.0 legacy below.)

---

## 1. Work plan (stateful — keep this updated)

These are the items most likely to actually affect a 0.4-era / early-5.x codebase.
Each links to its detailed entry in §2.

**This section is the source of truth for progress.** Tick a box only when the item is
done *across the whole game*; use `~` for partial and record which mods remain in the
per-item note. Per-mod state lives in §7.2.

Convention: `- [ ]` not started · `- [~]` in progress · `- [x]` done · `- [n/a]` verified
not applicable.

### 1.1 Hard breakage — must fix

- [ ] **[BREAK]** Writing anything into a mod directory — mod dirs are read-only since
      5.9, and writes are *disallowed* since 5.16. → `core.get_mod_data_path()` / world path. ([5.9](#59), [5.16](#516))
- [ ] **[BREAK]** Vectors with `nil` components passed to engine functions error since 5.13. ([5.13](#513))
- [ ] **[BREAK]** `.bmp` textures stop working on clients ≥ 5.11. ([5.11](#511))
- [ ] **[BREAK]** Re-using one table for two `register_node`/`register_craftitem`/`register_tool`
      calls — the table is modified; stricter checks since 5.12. ([5.12](#512))
- [ ] **[BREAK]** `liquid_alternative_source` / `liquid_alternative_flowing` are mandatory
      for liquids and `flowingliquid` drawtypes. ([5.7](#57), [5.9](#59))
- [ ] **[BREAK]** `core.registered_schematics` was removed. ([5.9](#59))
- [ ] **[BREAK]** Object property `weight` removed. ([5.2](#52))
- [ ] **[BREAK]** `minetest.item_place_node` / `item_place` second return value changed from
      `success` to `position`. ([5.2](#52))
- [ ] **[BREAK]** `dump(obj, dumped)`'s second parameter changed meaning to `indent`. ([5.12](#512))

### 1.2 Runtime deprecation warnings — visible in `debug.txt`

These are the ones the log-driven sweep (§0.1) will hand you directly.

- [ ] **[WARN]** `player:get_attribute` / `set_attribute` → `player:get_meta()`. ([5.0](#legacy))
- [ ] **[WARN]** `obj:set_bone_position` / `get_bone_position` → `set_bone_override` / `get_bone_override`. ([5.9](#59))
- [ ] **[WARN]** `use_texture_alpha = true/false` → `"opaque"` / `"clip"` / `"blend"`. ([5.4](#54))
- [x] **[WARN]** TileDef `image = ...` → `name = ...`. — done in commit `09cecc8d`
- [ ] **[WARN]** Entity properties in the bare definition table → `initial_properties`. ([5.8](#58))
- [~] **[WARN]** `core.get_connected_players()` at load time. — one instance fixed in
      commit `ee1815e1`; not yet swept across all mods. ([warnings](#5-runtime-warning--fix-table))
- [~] **[WARN]** Missing `mod.conf` with a `name`; `depends.txt` / `description.txt`. —
      **essentially done**: census of all 142 mods found only `mods/cooking` and
      `mods/cooking_fr` lacking `mod.conf` (both are submodules, both still have
      `depends.txt`); zero `description.txt` remain. ([5.5](#55), [5.6](#56), §7.1)
- [ ] **[WARN]** `hud_elem_type` → `type` in HUD definitions. ([5.9](#59))
- [ ] **[WARN]** craftitem/tool `image` → `inventory_image`; tool caps directly in def → `tool_capabilities`;
      `cookresult_itemstring` / `furnace_burntime` → `core.register_craft`. ([legacy](#legacy))
- [ ] **[WARN]** `core.env:foo()`, `core.setting_*`, `core.register_on_auth_fail`,
      `core.register_async_metatable`, `core.get_node_group`. ([legacy](#legacy), [5.3](#53), [5.9](#59))
- [ ] **[WARN]** `core.set_player_privs(name, {priv = false})` — pass only `true` values,
      or use `core.change_player_privs`. ([5.9](#59))

### 1.3 Silent behaviour changes — the dangerous ones

No warning will ever fire for these. Each needs a deliberate audit, and each should get
a note recording *how* it was verified, because "no diff" and "not looked at" are
indistinguishable otherwise.

- [ ] **[SILENT]** `paramtype2 = "degrotate"` rotation step changed 2° → 1.5°, range 0–179 → 0–239.
      Existing nodes rotate differently. ([5.5](#55))
- [~] **[SILENT]** `use_texture_alpha` default became `"opaque"` for **nodebox and mesh** nodes.
      Transparent nodeboxes/meshes now render opaque unless you set it explicitly. ([5.9](#59))
      — **globally mitigated already** by the `alpha_workaround_minus` submodule, which
      back-fills the old default at `on_mods_loaded`. Follow-up: the workaround is a
      band-aid — set `use_texture_alpha` per node and then retire it.
- [ ] **[SILENT]** The `hand` inventory list now *entirely replaces* the hand, instead of
      only "enhancing" its tool capabilities. ([5.12](#512))
- [ ] **[SILENT]** `set_physics_override{speed = x}` now scales acceleration too. ([5.8](#58))
- [ ] **[SILENT]** HP clamping removed from `register_on_player_hpchange`. ([5.10](#510))
- [ ] **[SILENT]** Iterating `get_objects_inside_radius` while modifying the world can hand you
      invalid `ObjectRef`s → use `core.objects_inside_radius`. ([5.9](#59))
- [ ] **[SILENT]** Default `sky_color` values changed. ([5.5](#55))
- [ ] **[SILENT]** `set_sky` skybox `textures` order is X+/X− then Z−/Z+ (docs were wrong before 5.9). ([5.9](#59))
- [ ] **[SILENT]** LBM `run_at_every_load = false` never runs on mapblocks generated after the
      LBM's introduction; and no LBM can reliably modify mapgen output. ([5.12](#512), [5.16](#516))
- [ ] **[SILENT]** HUD `text` element `scale` never worked — do not use it. ([master](#517-dev-master))

### 1.4 Session log

Append one line per working session so the next session knows where it stopped.

| Date | Items touched | Notes |
|---|---|---|
| 2026-07-30 | — | `MODERNIZATION.md` written; no code changes yet. luacheck baseline recorded in §7.1. |
| 2026-07-30 | §7.5 steps 1, 2 | `alpha_workaround_minus` submodule bumped `fc8f9df` → `a4f9749` (upstream HEAD). `.luacheckrc` `read_globals` extended: 3579 → 3341 warnings, W113 540 → 302, 0 errors (§7.1.1). The 302 survivors are now classified into a real bug queue (§7.1.1). |
| 2026-07-30 | §7.6 | Upstream import protocol defined and `tools/verify-upstream-imports.sh` checked in (positive + both negative cases tested). No mod upgraded yet. Corrected `enable_shadows` upstream URL in §7.2.2. |

---

## 2. Version-by-version catalogue

### Legacy (deprecated at or before 5.0, still warned about today) <a name="legacy"></a>

These live in `builtin/game/deprecated.lua` and `builtin/game/register.lua` and all
log a `deprecated` message.

| Old | New | Notes |
|---|---|---|
| `core.env:foo(...)` | `core.foo(...)` | **[WARN]** |
| `core.setting_get/set/getbool/setbool/save` | `core.settings:get/set/get_bool/set_bool/write` | **[WARN]** |
| `core.register_on_auth_fail(f)` | `core.register_on_authplayer(name, ip, is_success)` | **[WARN]**, deprecated 5.3 |
| `core.get_node_group(name, group)` | `core.get_item_group(name, group)` | **[WARN]** |
| `core.register_async_metatable(...)` | `core.register_portable_metatable(name, mt)` | **[WARN]**, renamed 5.9 |
| craftitem/tool def `image = "x.png"` | `inventory_image = "x.png"` | **[WARN]** |
| tool def with `full_punch_interval`/`groupcaps`/`damage_groups` at top level | put them in `tool_capabilities = {...}` | **[WARN]** |
| itemdef `cookresult_itemstring` | `core.register_craft{type="cooking", ...}` | **[WARN]** |
| itemdef `furnace_burntime` | `core.register_craft{type="fuel", ...}` | **[WARN]** |
| `player:get_attribute(k)` | `player:get_meta():get(k)` | **[WARN]** |
| `player:set_attribute(k, v)` | `player:get_meta():set_string(k, v)` | **[WARN]** |
| TileDef `{image = "x.png"}` | `{name = "x.png"}` | **[WARN]** |
| `ItemStack:get_metadata()` | `stack:get_meta():get_string("")` | **[SOFT]** (5.9 documented the exact replacement) |
| `ItemStack:set_metadata(s)` | `stack:get_meta():set_string("", s)` | **[SOFT]** |
| `player:get_look_pitch()` / `set_look_pitch(r)` | `get_look_vertical()` / `set_look_vertical(r)` | **[SOFT]** "deprecated as broken" |
| `player:get_look_yaw()` / `set_look_yaw(r)` | `get_look_horizontal()` / `set_look_horizontal(r)` | **[SOFT]** |
| `core.rollback_get_last_node_actor` | `core.rollback_get_node_actions(pos, range, secs, 1)[1]` | shim in builtin |
| formspec `invsize[W,H;]` | `size[W,H]` | **[SOFT]** |
| formspec inventory location `"current_name"` | `"context"` | **[SOFT]** |
| `set_physics_override(num, num, num)` | table form | undocumented; slated for removal |

---

### 5.1.0 <a name="51"></a>

* **[SOFT]** Mapgen aliases `mapgen_lava_source` and `mapgen_cobble` deprecated for
  non-V6 mapgens. → Define `node_cave_liquid`, `node_dungeon`, `node_dungeon_alt`,
  `node_dungeon_stair` in your biome definitions. `mapgen_stair_cobble`,
  `mapgen_mossycobble`, `mapgen_desert_stone`, `mapgen_stair_desert_stone`,
  `mapgen_sandstone`, `mapgen_sandstonebrick`, `mapgen_stair_sandstone_block` are
  no longer needed for non-V6 at all. (Broadened to unconditional in 5.6.)
* **[SOFT]** Entity `visual = "wielditem"` / `"item"`: `textures = {itemname}` deprecated.
  → `wield_item = itemname`.
* **[SOFT]** Node `drop.items[].tools` matching by string prefix (`"~default:shovel_"`)
  deprecated. → List exact item names, or use `tool_groups` (added 5.5).
* **[SILENT]** `register_on_item_eat`: returning `true` to cancel is deprecated.
  → Return the `itemstack`.
* **[BREAK]** `AreaStore:get_area` / `get_areas_for_pos` / `get_areas_in_area` return
  format changed (now `{min=, max=, data=}` tables indexed by area ID).
* **[SILENT]** `register_ore/biome/decoration/schematic` return an *object handle*, not
  the biome/decoration ID. → Use `core.get_biome_id` / `core.get_decoration_id`.
* **[SOFT]** `tool_capabilities.punch_attack_uses`: set it explicitly rather than relying
  on the `uses * 3^(maxlevel-1)` fallback derived from `groupcaps`.
* **[NEW]** `formspec_version[]`, `real_coordinates[]`, `style[]`/`style_type[]`,
  `background9[]`, `vector.angle/dot/cross`, `math.factorial`,
  `core.format_chat_message`, `core.calculate_knockback`, `core.read_schematic`,
  `player:send_mapblock`, `set_fov`/`get_fov`, `ItemStack:get_description()`.
* Guidance: `is_protected` overrides should honour the `protection_bypass` privilege.

### 5.2.0 <a name="52"></a>

* **[BREAK]** Object property **`weight` removed** (it was a no-op). Delete it.
* **[BREAK]** `core.item_place_node(...)` and `core.item_place(...)` now return
  `itemstack, position` instead of `itemstack, success`. `position` is `nil` if nothing
  was placed. Any code doing `local stack, ok = core.item_place(...)` and treating `ok`
  as a boolean is subtly wrong — `nil` is falsy so the common case still works, but a
  position table is truthy in the same way `true` was, so usually harmless. Audit
  anything that *stores* or *compares* the second value.
* **[BREAK]** `core.item_place_object` is deprecated **and will never be called**.
* **[SILENT]** `core.item_eat(hp_change[, replace_with_item])` returns a *function wrapper*
  for `core.do_item_eat` (this is what you assign to `on_use`).
* **[BREAK]** itemdef `sound.place` removed (node sounds have `place`; item sounds only
  have `breaks` and `eat`, plus `punch_use`/`punch_use_air` from 5.7).
* **[SOFT]** `player:set_sky(bgcolor, type, textures, clouds)` → `set_sky(sky_parameters)`
  table form. New `set_sun`/`set_moon`/`set_stars`.
* **[SILENT]** `core.get_node_drops(node, toolname)`: first argument may now be a node
  table *or* a name.
* **[SILENT]** `set_hp` / `set_breath` clamped to `[0, 65535]`. Group ratings limited to
  `[-32767, 32767]`; `damage_groups` values to `[-32768, 32767]`.
* **[SILENT]** `mesh = "model.obj"` — the filename must include its extension.
* **[SILENT]** `ObjectRef:remove()` makes the ref instantly unusable (all methods return `nil`).
  Also: do not hold on to `ObjectRef`s across returns into the engine.
* **[BREAK]** Special sound file `main_menu` removed.
* **[NEW]** `core.deserialize(str, safe)`, `core.sound_play(spec, params, ephemeral)`,
  sound `exclude_player`, node `sounds.dig = "__group"` + `default_dig_<group>` sounds,
  formspec version 3 (`animated_image[]`, `hypertext[]`, `scrollbaroptions[]`,
  extended `bgcolor[]`, comma-separated `style[]` names), `table.key_value_swap`,
  `table.shuffle`, `Settings:get_flags`, HUD `z_index`, `paramtype/paramtype2 = "none"`.

### 5.3.0 <a name="53"></a>

* **[WARN]** `core.register_on_auth_fail` → `core.register_on_authplayer(name, ip, is_success)`.
* **[SOFT]** `PerlinNoise(seed, octaves, persistence, spread)` and
  `core.get_perlin(seeddiff, octaves, persistence, spread)` deprecated → pass a
  noiseparams table. (Also renamed entirely in 5.12 — see there.)
* **[SOFT]** Formspec style properties `bgcolor_hovered`, `bgcolor_pressed`,
  `bgimg_hovered`, `bgimg_pressed`, `fgimg_hovered`, `fgimg_pressed` deprecated.
  → Use state selectors: `style[name:hovered;bgcolor=...]`,
  `style_type[button:pressed;...]`. `*` selects every element.
* **[SILENT]** `register_on_joinplayer(player, last_login)` — new second argument.
* **[SILENT]** `register_on_prejoinplayer` now fires *before* authentication.
* **[SILENT]** `core.add_node_level`: `level` must be in `[-127, 127]`.
* **[SILENT]** `get_fov()` now returns three values; `set_fov(fov, is_mult, transition_time)`.
* **[SILENT]** `core.decode_base64` returns `nil` on invalid input.
* **[SILENT]** `core.request_insecure_environment()` must be called from the mod's
  `init.lua` main scope — not another file, not inside a function.
* **[NEW]** Entity `on_step(self, dtime, moveresult)`; `get_player_control().zoom`;
  `core.is_creative_enabled` (override point for creative mods);
  `core.dynamic_add_media`; `core.get_translated_string`; `vector.rotate`,
  `vector.rotate_around_axis`, `vector.dir_to_rotation`; object properties
  `damage_texture_modifier`, `shaded`; nodedef `leveled_max`; particle `node`/`node_tile`;
  formspec `scroll_container[]`; HUD `image_waypoint`, statbar `text2`/`item`,
  waypoint `precision`.
* `disable_jump` group is not supported when `new_move = false`.

### 5.4.0 <a name="54"></a>

* **[WARN]** nodedef `use_texture_alpha = true/false` → string modes:
  * `"opaque"` — ignore alpha entirely
  * `"clip"` — binary transparency (alpha above/below 50 %)
  * `"blend"` — real semi-transparency (costs performance)

  Defaults: `"opaque"` for `normal`/`liquid`/`flowingliquid` (and, from 5.9, `mesh`
  and `nodebox`); `"clip"` otherwise.
  Feature flag: `use_texture_alpha_string_modes`.
* **[SOFT]** `vector.multiply(v, s)` / `vector.divide(v, s)` with a **vector** `s`
  (Schur product/quotient) deprecated. → Use `vector.combine(v, w, f)` or explicit
  per-component maths.
* **[WARN]** `player:get_player_velocity()` → `obj:get_velocity()`;
  `player:add_player_velocity(v)` → `obj:add_velocity(v)`.
  Feature flag: `direct_velocity_on_players`.
* **[WARN]** `obj:get_entity_name()` → `obj:get_luaentity().name` (5.9 wording;
  5.6 said `self.name`). Documented as "will be removed in a future version".
* **[SOFT]** HTTP request `post_data` → `data` plus explicit
  `method = "GET"/"POST"/"PUT"/"DELETE"`.
* **[SOFT]** nodedef `on_dig` returning `nil` is deprecated → return `true`/`false`.
* **[SOFT]** `core.dynamic_add_media(filepath, callback)` — omitting the callback is
  deprecated (and the whole signature changed again in 5.5/5.9).
* **[SILENT]** `core.sound_fade(handle, step, gain)`: a signed `step` is deprecated; the
  client uses `abs(step)` and the direction comes from the target `gain`. Fading to
  zero deletes the sound.
* **[BREAK]** Tile definition fields `tileable_vertical` / `tileable_horizontal` removed
  from the docs — bumpmapping, generated normal maps and parallax occlusion were
  removed from the engine. Also delete `*_normal.png` normal maps; they do nothing.
* **[SILENT]** `light_source` moved from nodedef to itemdef (it also controls the glow of
  dropped items now). Still works on nodes.
* **[SILENT]** `get_player_control()` gained `dig` and `place`. **`LMB`/`RMB` exist only
  for backwards compatibility** — migrate to `dig`/`place`.
  `get_player_control_bits()`: bit 7 = dig, bit 8 = place.
* **[SILENT]** `obj:set_sprite(start_frame, num_frames, framelength, select_x_by_camera)` —
  4th parameter renamed from `select_horiz_by_yawpitch`, semantics documented.
* **[SILENT]** `set_attach(parent[, bone, position, rotation, forced_visible])`;
  `get_attach()` now returns 5 values.
* **[SILENT]** `set_local_animation(idle, walk, dig, walk_while_dig, frame_speed)` —
  `frame_speed` is an ordinary 5th positional argument.
* **[SILENT]** `core.get_modpath(name)` returns `nil` for mods that are not enabled;
  `core.get_modnames()` lists only enabled mods.
* **[SILENT]** `player:set_sky(base_color, type, textures, clouds)` explicitly marked
  deprecated.
* **[SILENT]** Media subfolders are now scanned recursively; subfolders whose names start
  with `_` or `.` are ignored.
* **[NEW]** `register_on_rightclickplayer`, `register_on_chatcommand`,
  `core.get_natural_light`, `core.get_artificial_light`, `core.get_objects_in_area`,
  `core.after(...)` returns a job with `:cancel()`,
  `core.find_nodes_in_area(p1, p2, names, grouped)`, `short_description` +
  `ItemStack:get_short_description()`, entity `on_deactivate`, `set_minimap_modes`,
  `nametag_bgcolor`, `show_on_minimap`, nodedef `mod_origin`, `vector.offset`,
  formspec `model[]`, `set_focus[]`, box `colors`/`bordercolors`/`borderwidths`,
  `font`/`font_size` styles, `list` `size`/`spacing` styles, formspec v4 dropdown
  `index event`, HUD `compass` and `minimap` element types.

### 5.5.0 <a name="55"></a>

* **[SOFT]** **Manually constructed vectors `{x=…, y=…, z=…}` are deprecated and "highly
  discouraged".** → `vector.new(x, y, z)`. Vectors now carry a metatable enabling
  `v[1]`, `v:length()`, `v1 + v2`, `v * s`, `v1 == v2`, `-v`, `tostring(v)`.
  All `vector.*` functions still accept plain tables, and the engine still hands you
  plain tables in some places, so this is not a hard break — but new code and any
  API you expose should use `vector.new`.
* **[SOFT]** `vector.new()` (no args) → `vector.zero()`; `vector.new(v)` → `vector.copy(v)`.
* **[SILENT]** ⚠ `paramtype2 = "degrotate"`: values now `0..239` multiplied by **1.5°**
  (was `0..179` × 2°). **Existing param2 values in saved worlds rotate differently.**
  If this game has degrotate nodes with stored rotations, they will visually change.
  Feature flag: `degrotate_240_steps`. Also valid for `mesh` drawtype now.
* **[SOFT]** Node `drop.items[].tools` string matching → new `tool_groups` field
  (a list of group names, or lists of group names that must all match).
* **[SOFT]** `core.dynamic_add_media(filepath, cb)` → `core.dynamic_add_media(options, cb)`
  with `options = {filepath=, to_player=, ephemeral=}`.
  Feature flag: `dynamic_add_media_table`.
* **[SILENT]** `set_sky`/`set_sun`/`set_moon`/`set_stars`/`set_clouds` **with no arguments
  now reset to defaults**.
* **[SILENT]** ⚠ Default `sky_color` values changed: `day_sky` `#8cbafa`→`#61b5f5`,
  `day_horizon` `#9bc1f0`→`#90d3f6`, `night_sky` `#006aff`→`#006bff`;
  `fog_sun_tint` default `#f47d1d`, `fog_moon_tint` default `#7f99cc`.
  `sky_color` only applies to `type = "regular"`.
* **[SILENT]** Tool capabilities apply to **all items**, not just tools. `uses` max is
  65535, `0` = infinite. `uses` and `punch_attack_uses` have no effect on non-tools.
* **[SILENT]** `get_player_control()` returns `{}` and `get_player_control_bits()`
  returns `0` for non-players.
* **[SILENT]** itemdef `on_place` / `on_secondary_use` / `on_use` may return `nil` to leave
  the inventory unmodified. `core.do_item_eat` returns leftover **or nil**.
* **[SILENT]** ColorStrings: named colours accept a single-digit alpha (`red#8`) too.
* **[WARN]** Missing `mod.conf` (with a `name`) is deprecated;
  `depends.txt` / `description.txt` are deprecated. → Every mod needs
  `mod.conf` with at least `name = …`, plus `description`, `depends`,
  `optional_depends`, `title`.
* `persist` remains a valid alias for NoiseParams `persistence` — **not** deprecated,
  the docs merely switched which spelling they show.
* **[NEW]** `core.rmdir`, `cpdir`, `mvdir`, `colorspec_to_colorstring`,
  `colorspec_to_bytes`, `encode_png`, `[png:<base64>` texture modifier,
  `register_on_liquid_transformed`, `get_server_max_lag`, `disconnect_player`,
  `compare_block_status`, `math.round`, `vector.zero/copy/from_string/to_string/check`,
  the LuaJIT `bit` library, nodedef `move_resistance` + `liquid_move_physics`,
  ABM `min_y`/`max_y`, HUD `style` bitfield, `paramtype2 = "colordegrotate"`,
  `set_inventory_formspec("")` to disable a player's inventory,
  formspec version 5 (`padding[]`),
  `core.get_dig_params(..., wear)` / `core.get_hit_params(..., wear)`.

### 5.6.0 <a name="56"></a>

* **[WARN]** `game.conf`: `name` deprecated → **`title`**. This game's `game.conf`
  currently has `title = CitySim`, which is already correct.
  Mods/modpacks also gained `title`.
* **[SOFT]** Mapgen alias deprecation broadened: `mapgen_lava_source` and `mapgen_cobble`
  are now deprecated unconditionally (not only for non-V6). The V6 alias list is split
  into essential vs. optional with documented fallbacks.
* **[SOFT]** `player:get_sky()` without `true` (the tuple return) is deprecated →
  `get_sky(true)` returns a table. `get_sky_color()` deprecated → `get_sky(true)`.
  Feature flag: `get_sky_as_table`.
* **[SILENT]** Entity `on_deactivate(self, removal)` — new second argument.
* **[SILENT]** LBMs run when a mapblock is **activated**, not merely loaded.
* **[SILENT]** `hud_change(id, stat, value)` accepts every HUD-definition key except the
  element type.
* **[SILENT]** Particlespawner definitions gained a whole new syntax: `pos`/`vel`/`acc`/
  `exptime`/`size` as scalar, vec3, `{min=, max=, bias=}` range, or `*_tween` table;
  plus `jitter`, `drag`, `bounce`, `attract`, `radius`, table-form `texture` with
  `alpha`/`scale`/`blend` (+ tweens), and `texpool`. The legacy `minpos`/`maxpos`/…
  fields still work and may be supplied alongside for old clients.
  Feature flag: `particlespawner_tweenable`.
* **[SILENT]** AreaStore: `include_borders` → `include_corners`, `edge1`/`edge2` →
  `corner1`/`corner2` (positional, so no code change needed); `type_name` is only
  `"LibSpatial"`; `reserve()` is a no-op without SpatialIndex.
* **[SILENT]** Object property defaults corrected in the docs: `physical` defaults to
  `false`; `collisionbox`/`selectionbox` default to `{-0.5,-0.5,-0.5, 0.5,0.5,0.5}`
  (the docs previously claimed `{-0.5, 0.0, -0.5, 0.5, 1.0, 0.5}`); `hp_max` 10.
  If any entity here relied on the documented old default, set it explicitly.
* **[SILENT]** `pointable` redocumented as "whether the object can be pointed at".
* Attachment relative positions are ×10 vs. world coordinates (documented; on the
  removal list for the next major version).
* nodedef legacy field names `tile_images` / `special_materials` dropped from the docs.
* **[NEW]** Async environment (`core.handle_async`, `core.register_async_dofile`),
  `player:set_lighting`/`get_lighting`, `player:respawn()`, `set_stars{day_opacity=}`,
  formspec version 6 (9-sliced `image[]`/`animated_image[]`, `fgimg_middle`),
  `vector.combine`, `core.string_to_area(str, relative_to)` with `~` notation,
  item meta `count_meta`/`count_alignment`, itemstrings with a 4th metadata component,
  `ItemStack:add_wear_by_uses`, `core.get_tool_wear_after_use`,
  `hud_set_flags{basic_debug=}`, `core.get_version().is_dev`.

### 5.7.0 <a name="57"></a>

* **[SOFT]** ⚠ **MetaDataRef `${k}` value substitution is deprecated and will be removed.**
  A metadata *value* of the literal form `${k}` currently resolves to the value of key
  `k` when read. Store the resolved value instead. (`${k}` inside *formspec strings*
  is fine and not deprecated.)
* **[BREAK]** nodedef `liquid_alternative_flowing` / `liquid_alternative_source` are now
  **required** whenever `liquidtype ~= "none"` or the drawtype is `"liquid"` /
  `"flowingliquid"`. A `liquid` source node must name itself in
  `liquid_alternative_source`; a `flowingliquid` node must name itself in
  `liquid_alternative_flowing`. For a standalone non-flowing source, set
  `liquid_alternative_source` and `liquid_range = 0`.
  5.12 turned violations into hard registration errors — check `dynamic_liquid`,
  `bucket` and any custom fluids in this game.
* **[SILENT]** LBM `action = function(pos, node, dtime_s)` — new third argument.
* **[SILENT]** Texture-modifier escaping now also requires escaping `\` (in addition to
  `^` and `:`).
* **[SILENT]** `core.get_auth_handler()` must be called **after** load time.
* **[SILENT]** `InvRef:get_list(name)` returns `nil` if the list does not exist.
* **[SILENT]** `obj:set_rotation` does not reset rotation accumulated via `automatic_rotate`.
* **[SILENT]** `get_formspec_prepend()` takes no argument (the documented one never existed).
* **[NEW]** `paramtype2 = "4dir"` / `"color4dir"` + `core.dir_to_fourdir` /
  `core.fourdir_to_dir`; `attached_node` group values `1`–`4`; negative `bouncy`;
  object property `selectionbox = {..., rotate = true}`; itemdef `on_pickup`,
  `sound.punch_use`, `sound.punch_use_air`; `core.item_pickup`,
  `core.register_on_item_pickup`; `core.register_on_mapblocks_changed`;
  `core.get_game_info`, `core.get_player_window_information`,
  `core.get_mapgen_edges`, `core.parse_relative_number`,
  `core.forceload_block(pos, transient, limit)`, `"zstd"` compression,
  `VoxelArea(pmin, pmax)`, `VoxelManip:get_light_data(buffer)`,
  `ItemStack:equals()` and `==`, `MetaDataRef:get_keys()`, metadata tables,
  `core.error_handler`, `set_lighting{saturation=, exposure=}`,
  `set_sky{body_orbit_tilt=}`, `hud_set_flags{chat=}`.
* Non-API (changelog): worlds with unresolved dependencies can no longer be loaded;
  default keybindings for pitchmove and (un)limited viewing range removed;
  Development Test is no longer shipped.

### 5.8.0 <a name="58"></a>

* **[WARN]** ⚠ **Reading/defining initial object properties directly on the entity
  definition table is deprecated.** → Move them into `initial_properties`:

  ```lua
  core.register_entity("mymod:thing", {
      initial_properties = {
          visual = "mesh", mesh = "thing.b3d", textures = {"thing.png"},
          physical = true, collisionbox = {-0.4, 0, -0.4, 0.4, 0.8, 0.4},
      },
      on_step = function(self, dtime, moveresult) ... end,
  })
  ```

  Also access them as `self.initial_properties.foo`, not `self.foo`.
* **[SOFT]** nodedef `air_equivalent` documented and marked deprecated
  ("unclear meaning; the engine sets this for `air` and `ignore`").
* **[SILENT]** ⚠ `set_physics_override{speed = x}` now multiplies **movement speed *and*
  acceleration**. If you use `speed` to make players faster, their acceleration
  changes too. Fine-grained fields were added (feature `physics_overrides_v2`):
  `speed_climb`, `speed_crouch`, `liquid_fluidity`, `liquid_fluidity_smooth`,
  `liquid_sink`, `acceleration_default`, `acceleration_air`
  (plus `speed_walk`, `speed_fast`, `acceleration_fast` in 5.9).
* **[SILENT]** `set_eye_offset([first, third_back, third_front])` — new 3rd argument;
  values clamped to `(-10,-10,-5)`…`(10,15,5)`.
* **[SILENT]** `set_lighting()` with no arguments resets to defaults.
* **[SILENT]** `override_day_night_ratio()` — pass **no arguments** to disable the override
  (the docs previously said `nil`).
* **[SILENT]** `set_armor_groups(t)` *removes* every group not present in `t`.
* **[SILENT]** `ObjectRef:set_pos` / `move_to` are no-ops while the object is attached.
* **[SILENT]** `core.get_gametime()` returns `nil` before the first server step.
* **[SILENT]** Reading an unloaded-but-generated region with a VoxelManip loads it from
  disk (like `core.load_area`).
* Media: allowed filename characters are `a-zA-Z0-9_.-`. Accepted formats:
  images `.png .jpg .tga` (`.bmp` deprecated), sounds `.ogg`, models `.x .b3d .obj`.
  Anything else is silently not sent to clients.
* `doc/lua_api.txt` became `doc/lua_api.md`.
* **[NEW]** `SimpleSoundSpec.fade`, sound parameter `start_time`
  (feature `sound_params_start_time`); `disable_descend` group;
  nodedef `post_effect_color_shaded`; decoration `check_offset`;
  `Settings:has(key)`; `core.urlencode`; `core.get_version().proto_min/proto_max`;
  formspec version 7 (`style[]` `focused` state, `field_enter_after_edit[]`);
  texture modifiers `[fill:`, `[colorizehsl:`, `[screen:`, `[hsl:`, `[contrast:`,
  `[overlay:`, `[hardlight:`.
* Non-API: Minetest Game is no longer the default game and is no longer shipped.

### 5.9.0 <a name="59"></a>

* **[WARN]** HUD definitions: `hud_elem_type` → **`type`**. If both are present `type`
  wins. `hud_change` cannot change the element type.
  Feature flag: `hud_def_type_field`. Also new: `hud_get_all()`.
* **[WARN]** `obj:set_bone_position(bone, pos, rot)` → `obj:set_bone_override(bone, override)`;
  `obj:get_bone_position(bone)` → `obj:get_bone_override(bone)` (plus
  `get_bone_overrides()`).

  ```lua
  -- old
  obj:set_bone_position("Arm_Right", {x=0,y=6,z=0}, {x=90,y=0,z=0})
  -- new  (note: RADIANS, and absolute must be requested explicitly)
  obj:set_bone_override("Arm_Right", {
      position = {vec = vector.new(0, 6, 0), absolute = true},
      rotation = {vec = vector.new(math.rad(90), 0, 0), absolute = true},
  })
  ```

  The new API adds `scale`, relative overrides (`absolute = false`, the default!) and
  `interpolation`. **Rotation is radians in the new API and degrees in the old one** —
  this is the single easiest thing to get wrong during migration.
  Clients before 5.9 only support absolute position/rotation without interpolation.
* **[WARN]** `core.register_async_metatable` renamed to `core.register_portable_metatable`.
* **[WARN]** `core.set_player_privs(name, privs)`: `privs` is a **set** — a table whose
  values are all `true`. Passing `false` values warns.
  → Use `core.change_player_privs(name, {interact = true, fly = false})` to grant/revoke
  without clobbering the rest.
* **[BREAK]** `core.registered_schematics` **removed**.
* **[SILENT]** ⚠ **`use_texture_alpha` default changed**: now `"opaque"` for
  `normal`, `liquid`, `flowingliquid`, **`mesh` and `nodebox`**; `"clip"` otherwise.
  Any nodebox or mesh node that relied on implicit transparency now renders opaque.
  → Set `use_texture_alpha = "clip"` (or `"blend"`) explicitly.
  This is likely to hit fences, panes, rails, plants-as-nodeboxes and mesh decorations
  in this game.
* **[SILENT]** `liquid_alternative_*` requirement narrowed: required if
  `liquidtype ~= "none"` or `drawtype == "flowingliquid"` (plain `drawtype == "liquid"`
  alone no longer requires it).
* **[SILENT]** `paramtype2 = "wallmounted"` range extended to `[0, 7]`
  (6 = y+ rotated 90°, 7 = y− rotated −90°). New nodedef `wallmounted_rotate_vertical`
  opts in to the extra values on placement. If you switch on `param2` for wallmounted
  nodes, handle 6 and 7. Feature flag: `wallmounted_rotate`.
* **[SILENT]** ⚠ **`core.get_objects_inside_radius` / `get_objects_in_area` are unsafe to
  iterate** if the loop body touches the world — punching an entity can remove its
  children and invalidate later entries.
  → `for obj in core.objects_inside_radius(center, radius) do … end` (and
  `core.objects_in_area`), which only yields valid objects.
* **[SILENT]** ⚠ `set_sky{textures = …}` order is documented (correctly, since 5.9) as
  **Y+ (top), Y− (bottom), X+ (east), X− (west), Z− (south), Z+ (north)**.
  Pre-5.9 docs said Y+, Y−, X−, X+, Z+, Z−. If a custom skybox here was built against
  the old documentation, its sides are swapped. Top/bottom are aligned with the east
  face; textures authored for a north-aligned top/bottom need ∓90° rotation.
* **[SILENT]** `core.show_formspec`: `formname` must not be empty. Node
  `on_receive_fields` receives `formname == ""` and you must not use it.
  (5.13 re-allowed the empty name for `show_formspec` with a new meaning.)
* **[SILENT]** `core.after` ordering is now guaranteed (expiry, then registration order).
  Feature flag: `after_order_expiry_registration`.
* **[SILENT]** Texture overlay `^` does **not** alpha-blend when both pixels are
  semi-transparent, and is not associative.
* **[NEW]** `core.get_mod_data_path()` — per-mod, world-independent writable directory.
  **This is the replacement for writing into the mod directory.**
* **[NEW]** `pointable` may be `true`/`false`/`"blocking"`; itemdef `pointabilities`;
  `core.raycast(..., pointabilities)`; `ObjectRef:is_valid()`, `add_pos()`;
  `core.place_node(pos, node, placer)`, `dig_node(pos, digger)`, `punch_node(pos, puncher)`;
  `core.override_item(name, redef, del_fields)`; the **mapgen environment**
  (`core.register_mapgen_script`, mapgen-env `register_on_generated(vm, minp, maxp, seed)`,
  `core.save_gen_notify`, `set_gen_notify(flags, deco_ids, custom_ids)`);
  `core.sha256`; `core.get_node_boxes`; itemdef `wear_color` + wear-bar colours;
  itemdef `touch_interaction`; itemstack meta `range`; decoration type `lsystem`;
  `PcgRandom:get_state/set_state`, `PseudoRandom:get_state`;
  `moveresult.collisions[].new_pos`; `dynamic_add_media{filename=, filedata=}` and
  startup-time usage with `callback = nil`; `set_lighting{volumetric_light=}`;
  `set_sky{fog = {fog_color = …}}`; content-meta translation via
  `locale/<textdomain>.<lang>.tr` + `textdomain` in mod.conf/game.conf;
  game.conf `first_mod`/`last_mod`.
* **[BREAK]** Non-API but critical: **trusted mod directories became read-only and
  writing to any mod directory is deprecated.** Any mod here that writes files next to
  its own `init.lua` must move to `core.get_mod_data_path()` or
  `core.get_worldpath()`. Hard error since 5.16.
* Non-API: setting `opaque_water` renamed `translucent_liquids`; disabling fog/camera
  updates needs the `debug` privilege.

### 5.10.0 <a name="510"></a>

* Docs switched `minetest.` → `core.` and "Minetest" → "Luanti" throughout.
  `minetest` stays as a permanent alias.
* **[SILENT]** ⚠ `register_on_player_hpchange`: **HP clamping removed.** Historically the
  new HP value was clamped to `[0, 65535]` before computing `hp_change`; it no longer is.
  Also: when `hp == 0`, damage does not trigger the callback; when `hp == hp_max`,
  healing still does. Any damage-modifier mod (armour, classes, anticombatlog…) that
  relied on pre-clamped values needs review.
* **[SILENT]** `VoxelManip:was_modified()` — "this doesn't do what you think it does and
  is subject to removal. Don't use it!"
* **[SILENT]** `SecureRandom()` now **throws** instead of returning `nil` when no secure
  device exists. Wrap in `pcall` if you were checking for `nil`.
* **[SILENT]** `set_animation` `frame_range` accepts floats now (`{x=1.0, y=1.0}`).
* **[SILENT]** Formspec element **names and values must not contain binary/ASCII control
  characters** (engine escape sequences in values excepted).
* **[SILENT]** `set_lighting{bloom = {intensity = …}}`: the default `0.05` is documented as
  changing to `0` in the future — set it explicitly if you depend on it.
* **[NEW]** glTF models (`.gltf`, `.glb`) with documented limitations.
* **[NEW]** HUD element type `hotbar` (feature `hotbar_hud_element`),
  `core.hud_replace_builtin("hotbar", …)`, `inventory` element `alignment`.
* **[NEW]** `get_player_control()` gains `movement_x` / `movement_y` in `[-1, 1]`,
  which account for joystick input. **Prefer them over `up`/`down`/`left`/`right`.**
* **[NEW]** `player:get_flags()` / `set_flags{breathing=, drowning=, node_damage=}`.
* **[NEW]** `ObjectRef:set_observers` / `get_observers` / `get_effective_observers` —
  per-player visibility of entities.
* **[NEW]** `core.show_death_screen(player, reason)` override point;
  `core.bulk_swap_node`; LBM `bulk_action` (feature `bulk_lbms`);
  ABM `without_neighbors` (feature `abm_without_neighbors`);
  IPC (`core.ipc_get/set/cas/poll`); `core.kick_player(name, reason, reconnect)`;
  `core.parse_json(str, nullvalue, return_error)`; `core.is_valid_player_name`;
  `core.colorspec_to_table`; `core.time_to_day_night_ratio`;
  `core.hypertext_escape`; `vector.random_direction/ceil/sign/abs/random_in_area`,
  `vector.apply(v, f, ...)`; `table.keyof`; formspec version 8
  (`scroll_container[...;<content padding>]`); `set_clouds{shadow=, thickness=0}`;
  `set_lighting{shadows = {tint = …}}`; the `tracy` profiler global.
* **[NEW]** Translations: **gettext `.po`/`.mo` support**, `core.translate_n`,
  `local S, PS = core.get_translator(domain)` for plurals. `.tr` is now called the
  "old translation file format" but is fully supported.

### 5.11.0 <a name="511"></a>

* **[BREAK]** ⚠ **`.bmp` textures are no longer supported by clients ≥ 5.11.0.**
  Convert every `.bmp` to `.png`. (`.tga` is still supported.)
* **[WARN]** `core.setting_get_pos(name)` → `core.settings:get_pos(name)`.
  New `Settings:get_pos` / `set_pos`.
* **[SILENT]** Object property `colors` is documented as **"Currently unused."**
  (was "number of required colors depends on visual"). Remove it.
* **[SILENT]** Decoration flag `liquid_surface` semantics changed: it finds the highest
  liquid surface under open air, and **cannot be combined with `all_floors` or
  `all_ceilings`**.
* **[SILENT]** `core.features` is explicitly *server-side* only; `core.has_feature`
  likewise. To test client capability use
  `core.get_player_information(name).protocol_version >= core.protocol_versions["5.8.0"]`.
* **[SILENT]** `core.get_player_information`: debug-only field `vers_string` renamed;
  new documented `version_string` (spoofable, analysis only), `serialization_version`.
* **[SILENT]** `VoxelManip:read_from_map` *adds* to the loaded area rather than resetting it.
* **[NEW]** Custom fonts: a `fonts/` directory with `.ttf`/`.woff` named
  `regular`, `bold`, `italic`, `bold_italic`, `mono`, `mono_bold`, `mono_italic`,
  `mono_bold_italic`. Intended for game mods only.
* **[NEW]** `core.protocol_versions`, `core.spawn_tree_on_vmanip`, biome `weight`
  (feature `biome_weights`), particle `blend = "clip"` (feature `particle_blend_clip`).
* Non-API: basic shader support is mandatory, minimum OpenGL 2.0. A skeletal-animation
  fix changed the behaviour of bones with 180° rotations — check custom animated models.

### 5.12.0 <a name="512"></a>

* **[SOFT]** ⚠ **"Perlin noise" renamed to "fractal value noise"** — it never was Perlin
  noise. Old names remain as aliases with **no warning yet**:

  | Old | New |
  |---|---|
  | `PerlinNoise` | `ValueNoise` |
  | `PerlinNoiseMap` | `ValueNoiseMap` |
  | `core.get_perlin` | `core.get_value_noise` |
  | `core.get_perlin_map` | `core.get_value_noise_map` |

* **[SILENT]** ⚠ **The `hand` inventory list now entirely replaces the hand.**
  Previously it "only enhanced the empty hand's tool capabilities"; now the first item
  in that list behaves as if the default hand `""` had been overridden for that player.
  Any mod here that puts something in a player's `hand` list (armour/class systems are
  the usual suspects) will behave differently.
* **[BREAK]** ⚠ **Stricter registration checks:** you must pass a *clean* table to
  `core.register_node` / `register_craftitem` / `register_tool` — the table is modified
  by the engine. Sharing one definition table between two registrations (a common
  space-saving trick) is now an error. Use `table.copy()`.
* **[BREAK]** `dump(value, indent)` — the second parameter used to be an internal
  `dumped` table and is now an **indent string** (`""` = compact, single line).
  `dump(x, {})` now produces garbage indentation.
* **[SILENT]** `table.copy` strips metatables (this means vectors lose their metatable).
  New `table.copy_with_metatables`.
* **[SILENT]** `core.item_drop` only clears `itemstack` **on success** now (it used to
  clear it unconditionally), and returns `leftover, ObjectRef`.
* **[SILENT]** `MetaDataRef:set_float` now stores a full 64-bit float exactly (was
  system-dependent, usually 32-bit).
* **[SILENT]** `core.serialize`: dumping function bytecode is **deprecated**.
  `core.deserialize(str, true)` silently strips `loadstring` calls.
* **[SILENT]** `find_nodes_in_area` / `find_nodes_in_area_under_air` volume limit raised
  from 4,096,000 to 150,000,000 nodes.
* **[SILENT]** LBM `run_at_every_load = false` documented precisely: it only runs the
  first time a mapblock is activated after the LBM was introduced, and **never on
  mapblocks generated after the LBM's introduction**. For maps generated in 5.11 or
  older many mapblocks have no timestamp, so LBMs introduced between generation and
  first activation never run. Workaround: `run_at_every_load = true`.
* **[SILENT]** nodedef `mesh` scale depends on the file format:
  glTF 10 units = 1 node; `.obj` 1 unit = 1 node; `.b3d`/`.x` 1 unit = 1 node if static,
  10 units = 1 node if animated. Static glTF or obj recommended; compensate with
  `visual_scale`.
* **[SILENT]** Crafting: recipe selection priority is documented (shaped > shapeless >
  toolrepair; then group-free over group-using; then registration order), and empty
  slots outside a recipe's extents are ignored.
* **[SILENT]** The `creative` privilege was removed from the engine's built-in list —
  it is game-provided (this game registers its own or relies on `creative`).
* **[NEW]** Formspec version 9: `allow_close[<bool>]` and the "area label"
  `label[<X>,<Y>;<W>,<H>;<label>]`; the `try_quit` field.
* **[NEW]** Entity `visual = "node"` + `node = {name=…}`; `ObjectRef:set_camera` /
  `get_camera`; `core.MAP_BLOCKSIZE`; `core.get_node_drops(node, toolname, tool, digger, pos)`;
  `InvRef:remove_item(list, stack, match_meta)`; HTTP `HEAD` and `PATCH` methods;
  documented special items `"unknown"`, `"air"`, `"ignore"`, `""` (the hand);
  a "Mapblock status" chapter explaining loaded/emerged/active.
* Non-API: SDL2; keybindings use scancodes; **worlds saved by 5.12+ cannot be opened by
  older versions**; remote media fetched via GET.

### 5.13.0 <a name="513"></a>

* **[BREAK]** ⚠ **Vectors passed to engine (C++) functions may no longer have `nil`
  components.** Code like `core.get_node({x = x, y = y})` or a partially-built position
  table now errors instead of silently treating the missing axis as 0.
* **[SOFT]** `core.object_refs` is **obsolete** → `core.objects_by_guid`, keyed by the new
  `ObjectRef:get_guid()` (feature `object_guids`). GUIDs persist across reloads;
  for players the GUID is the player name.
* **[SILENT]** ⚠ `ValueNoise` / `ValueNoiseMap` / `core.get_value_noise*` (and their
  `Perlin*` aliases) **require the mapgen environment to be initialised — do not call
  them at load time.** A mod creating noise objects in its `init.lua` main scope must
  defer to `core.after(0, ...)`, `on_mods_loaded`, or first use.
* **[SILENT]** New "Coordinate System" chapter: Luanti is **left-handed** (Y up, X right,
  Z forward) with extrinsic X-Y-Z left-handed rotations for attachments and bone
  overrides — **except** object rotation (`set_rotation`, `get_rotation`,
  `automatic_rotate`, and `vector.rotate`), which is **right-handed extrinsic Z-X-Y**.
  If you have hand-derived rotation maths, re-check it against this.
* **[SILENT]** Media files above roughly 16 MB are not handled by the engine.
* **[SILENT]** Item metadata cannot store the byte `"\1"`.
* **[SILENT]** glTF: nodes using matrix transforms must not be animated, and bone
  overrides must not be applied to them.
* **[SILENT]** `core.show_formspec` with an **empty** `formname` is allowed again and now
  means "show a temporary custom inventory formspec" (5.13+ client and server).
* **[NEW]** `VoxelManip:initialize(p1, p2[, node])` (use a VM as a plain node container
  with no map read) and `VoxelManip:close()` (**free the buffers — frequent VM use
  without this can exhaust server RAM**).
* **[NEW]** `core.get_node_raw(x, y, z)` → `content_id, param1, param2, pos_ok`;
  `core.get_mapgen_chunksize()`; formspec version 10 (`model[]` float frames);
  ore definition `name` field.
* `register_on_craft`'s `old_craft_grid` is a list of `ItemStack`s.

### 5.14.0 <a name="514"></a>

* **[SILENT]** ⚠ `core.register_on_shutdown` semantics changed: it is now called
  **during shutdown before players are kicked**. The 5.9–5.13 documentation promised
  that kicked players were still fully accessible in `core.get_connected_players()`;
  that wording is gone. Code that saved per-player data in `on_shutdown` should be
  re-checked (and should in any case also save periodically and in `on_leaveplayer`).
* **[SILENT]** nodedef `on_secondary_use` default changed from `nil` to
  `core.item_secondary_use` (a no-op).
* **[SILENT]** Defining itemdef `on_use` **disables client-side punch/dig prediction**
  for that item, because the interaction is forwarded to the server.
* **[SILENT]** `dynamic_add_media`: `ephemeral` now means the server copies the file and
  forgets it after delivery; new `client_cache` hint (defaults to `!ephemeral`).
* **[NEW]** Node `on_timer = function(pos, elapsed, node, timeout)` — two new arguments
  (feature `on_timer_four_args`).
* **[NEW]** Particlespawner `exclude_player` (feature `particlespawner_exclude_player`);
  `core.generate_decorations(vm, p1, p2, use_mapgen_biomes)`
  (feature `generate_decorations_biomes`); `core.handle_async` returns an `AsyncJob`
  with `:cancel()`; object properties `nametag_fontsize`, `nametag_scale_z`;
  `core.strip_escapes`.
* Formspec `box` styling only applies when the element's `color` field is left unspecified.
* `modpack.txt` 0.4.x-compatibility note removed.

### 5.15.0 <a name="515"></a>

* **[NEW]** HUD `text` element `number` accepts **ARGB** (`0x80FF0000`) on 5.15+ clients.
  Alpha `00` is treated as `FF` for compatibility — hide text by setting `text = ""`.
* **[NEW]** itemdef `inventory_image`, `inventory_overlay`, `wield_image`,
  `wield_overlay` accept an "Item image definition" table with an animation:
  `{name = "x.png", animation = {…}}` (feature `item_image_animation`).
  The corresponding item-meta override keys now override the `.name` sub-field.
* **[SILENT]** `ObjectRef:set_yaw(yaw)` **also resets pitch and roll to 0** (documented).
* **[SILENT]** `set_attach` with `bone = ""` attaches to the parent object's origin.
* **[NEW]** `PlayerHPChangeReason` is formally documented, including a `custom_type`
  field for mod-defined damage types (`__builtin:item_eat`, `__builtin:kill_command`
  exist by default), `drown` now carrying `node`/`node_pos`, and `from` always being
  `"mod"` for `ObjectRef:set_hp`.
* **[NEW]** `string.pack` / `string.unpack` / `string.packsize` backported from Lua 5.4;
  `core.path_exists`; `set_stars{star_seed=}`; game.conf `default_mapgen`;
  mapgen `chunksize` may be a vector (feature `chunksize_vector`).
* Warning: the client reads OpenType kerning only from the legacy `kern` table, not
  `GPOS` — modern custom fonts may render with wrong spacing.
* Non-API: `/pulverize` and `/clearinv` now require the `give` privilege.

### 5.16.0 <a name="516"></a>

* **[BREAK]** ⚠ **Writing to mod directories is now disallowed** (deprecated since 5.9).
  → `core.get_mod_data_path()` for world-independent per-mod data,
  `core.get_worldpath()` for per-world data, `core.get_mod_storage()` for small
  key/value data.
* **[SILENT]** ⚠ **Integer discipline.** The docs now specify integer ranges everywhere
  (`[s16]`, `[u16]`, `[u32]`, `[slua]`, …) and state: *"You must make sure your code only
  passes integers to any function or data structure that expects them. You must respect
  all integer ranges. Failing to do so may lead to undefined behavior."*
  Common offenders in older code: fractional node positions passed to `set_node`,
  computed `param2`, `count`/`wear` values from divisions, HUD `number`/`item`.
  Wrap with `math.floor` / `math.round`.
* **[SILENT]** LBM caveat sharpened: block activation has no interaction with mapgen.
  **An LBM — even `run_at_every_load = true` — cannot reliably modify mapgen output.**
  Use `core.register_on_generated` for that.
* **[SILENT]** itemdef `on_drop`: **only the count of the returned itemstack is
  significant**; you cannot change the item, wear or metadata in a drop operation, and
  the returned count must not exceed the input.
* **[SILENT]** `register_on_player_receive_fields` is **not** called for node metadata
  formspecs — those go to the nodedef's `on_receive_fields`.
* **[SILENT]** `allow_player_inventory_action`'s return value now behaves exactly like
  the matching `allow_metadata_inventory_*` callback.
* **[SILENT]** `allow_metadata_inventory_put/take` returning `-1` means "allow and don't
  modify the destination/source item" (previously worded as "item count in inventory").
* **[SILENT]** Object property `visual_size` default is `{x=1, y=1, z=1}` for entities but
  `{x=1, y=2, z=1}` **for players**.
* **[SILENT]** `core.get_mapgen_params().seed` is **broken** for seeds outside
  `[0, 2^53-1]`. Use `core.get_mapgen_setting("seed")`, which returns a *string* —
  do not convert it to a number.
  `core.set_mapgen_setting("seed", …)` requires a string.
* **[SILENT]** `core.write_json`: empty tables are written as `null`.
* **[NEW]** `vector2.*` — a full 2D vector class (`vector2.new`, `from_angle`, `to_angle`,
  `rotate`, `sort`, `angle`, `offset`, plus the shared vector functions).
* **[NEW]** Object property `step_up_mode` (`"legacy"` / `"floaty"` / `"rigid"`) —
  `"legacy"` remains the default; the others fix edge-clutching/parkour behaviour.
  Needs 5.16+ clients.
* **[NEW]** `core.get_modnames(load_order)` (feature `get_modnames_load_order`);
  `ObjectRef:set_camera(nil)` and `set_lighting(nil)` reset to defaults
  (feature `set_camera_resettable`); `set_wielded_item(item, skip_anim)`;
  `set_lighting{shadows = {direction = …}}`; `set_sky{auto_dim_skybox=}`;
  `core.get_loaded_blocks`, `get_loadable_blocks`, `get_active_blocks`;
  `math.isfinite`; HTTP request `quiet`; game.conf `aliases`;
  `screenshot.{png,jpg,jpeg}` for games and mods; documented texture loading order.
* Escape sequences: tab headers and dropdowns cannot be colorized (vertical labels can,
  contrary to older docs).

### 5.17-dev (master) <a name="517-dev-master"></a>

Not released. Treat as forward-looking; do not depend on it yet.

* **[SILENT]** ⚠ HUD `text` element `scale`: **"Do not use."** The documentation's claim
  that it defines a bounding rectangle "never worked". If you set it, remove it.
* **[NEW]** New multi-track animation API for glTF models:
  `obj:play_animation(track[, animation])`, `update_animation(track, update)`,
  `stop_animation([track])`, `get_animations()`. `set_animation` /
  `get_animation` / `set_animation_frame_speed` remain as the "old animation interface"
  (single unnamed track `1` for `.x`/`.b3d`). Needs 5.17+ clients — combine with
  `set_observers()` if you must support both.
* **[SILENT]** glTF animations use **timestamps in seconds** as frame numbers, so
  `frame_speed` should normally be `1.0` — unlike `.x`/`.b3d`.
  glTF `.bin` buffers must be embedded (base64) or you must use `.glb`.
* **[SILENT]** nodedef `waving`: `liquid`/`flowingliquid` accept only `3` (or `0`);
  `plantlike` always behaves like `1` and `allfaces_optional` like `2` whenever
  `waving > 0` — "this behavior may be removed in the future", so set the correct value.
* **[SILENT]** `[colorize:<color>:<ratio>`: with semitransparent base pixels, or an
  omitted `ratio`, or a non-255 alpha in `color`, behaviour is **undefined**.
  Always pass an explicit integer `ratio` and a fully opaque `color`.
* **[SILENT]** `ItemStack:get_short_description()` now falls back to the item name and
  never returns `nil`.
* **[NEW]** HUD definition `hideable` (feature `hud_hideable_field`);
  formspec `hypertip[]`; textarea/field/label `halign`/`valign` styles;
  `"raw_deflate"` compression; `core.get_all_craft_recipes` gains `time` and
  `replacements`, `width = 0` for non-shaped recipes, and `nil` for empty ingredients
  (features `get_all_craft_recipes_fuel`, `get_all_craft_recipes_replacements`).
* Tooltips (`tooltip[]`, `hypertip[]`) must be declared **after** the element they bind to.

---

## 3. Cross-cutting migration recipes

### 3.1 Player attributes → metadata

```lua
-- old
player:set_attribute("mymod:score", tostring(n))
local n = tonumber(player:get_attribute("mymod:score") or 0)

-- new
local meta = player:get_meta()
meta:set_int("mymod:score", n)          -- or set_string / set_float
local n = meta:get_int("mymod:score")   -- 0 if absent
```

`PlayerMetaRef` uses the same storage as the old attribute API, so existing data
carries over unchanged.

### 3.2 Node transparency

```lua
-- old (warns)
use_texture_alpha = true,
-- new: pick deliberately
use_texture_alpha = "blend",  -- real semi-transparency (glass, water, tinted panes)
use_texture_alpha = "clip",   -- binary cutout (leaves, plants, fences, rails)
use_texture_alpha = "opaque", -- no transparency at all (fastest)
```

Because 5.9 changed the *default* for `nodebox` and `mesh` to `"opaque"`, audit every
nodebox/mesh node whose texture has transparency and set the field explicitly.

### 3.3 Entity definitions

```lua
core.register_entity("mymod:thing", {
    initial_properties = {
        hp_max = 10,
        physical = true,               -- default is FALSE, set it if you need it
        collide_with_objects = true,
        collisionbox = {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4},  -- default is centred on origin
        visual = "mesh",
        mesh = "mymod_thing.b3d",
        textures = {"mymod_thing.png"},
        -- colors = {},               -- REMOVE: unused since 5.11
        -- weight = 5,                -- REMOVE: removed in 5.2
    },
    on_activate = function(self, staticdata, dtime_s) end,
    on_step = function(self, dtime, moveresult) end,
    on_deactivate = function(self, removal) end,
    on_punch = function(self, puncher, tfp, caps, dir, damage) end,
    get_staticdata = function(self) end,
})
```

### 3.4 Bone animation

See the 5.9 entry. Key traps: **radians not degrees**, and `absolute` defaults to
`false` (relative to the playing animation), whereas `set_bone_position` was always
absolute.

### 3.5 Safe object iteration

```lua
-- old, unsafe if the body modifies the world
for _, obj in ipairs(core.get_objects_inside_radius(pos, 5)) do
    obj:punch(...)   -- may invalidate later entries
end

-- new
for obj in core.objects_inside_radius(pos, 5) do
    obj:punch(...)
end
```

### 3.6 Writable storage

| Need | Use |
|---|---|
| Small key/value, per mod + per world | `core.get_mod_storage()` (JSON, no raw binary) |
| Arbitrary files, per world | `core.get_worldpath() .. "/mymod/"` |
| Arbitrary files, shared across worlds | `core.get_mod_data_path()` (call at load time) |
| Never | anywhere under `core.get_modpath(...)` |

### 3.7 Vectors

```lua
local p = vector.new(x, y, z)        -- not {x = x, y = y, z = z}
local q = p + vector.new(0, 1, 0)   -- operators need metatables on both sides
local s = p * 2                     -- vector.multiply(p, 2)
-- Schur product: vector.combine(a, b, function(x, y) return x * y end)
```

Do not pass tables with `nil` components anywhere (5.13 hard error). Remember
`table.copy` strips the metatable (5.12) — use `vector.copy` for vectors.

---

## 4. Feature detection

Prefer feature flags over version comparisons for server-side APIs:

```lua
if core.features.bulk_lbms then ... end
local ok, missing = core.has_feature({dynamic_add_media_table = true})
```

For anything that depends on what the *client* supports:

```lua
local info = core.get_player_information(name)
if info.protocol_version >= core.protocol_versions["5.9.0"] then ... end
```

`core.features` / `core.has_feature` describe the **server** only (documented explicitly
in 5.11). Never gate client behaviour on them.

---

## 5. Runtime warning → fix table

Everything the engine actually prints, with the fix. (Source: docs.luanti.org warnings
page plus `builtin/`.)

| Warning text (abridged) | Fix |
|---|---|
| `Undeclared global variable "…" accessed at …` | Typo or missing `local`. Use `rawget(_G, name)` / `core.global_exists(name)` for intentional probes. |
| `Assignment to undeclared global variable "…"` | Add `local`. Expose an API through exactly one global named after the mod. |
| `Mods not having a mod.conf file with the name is deprecated…` | Add `mod.conf` with `name`, `description`, `depends`, `optional_depends`, `title`. Delete `depends.txt` / `description.txt`. |
| `Field "use_texture_alpha" on node …: Boolean values are deprecated…` | `"opaque"` / `"clip"` / `"blend"`. |
| `Field "image" on TileDef: Deprecated: new name is "name".` | `{name = "x.png", …}`. |
| `Reading initial object properties directly from an entity definition is deprecated…` | Move into `initial_properties`; read via `self.initial_properties.x`. |
| `Deprecated call to set_bone_position, use set_bone_override instead` | See §3.4. |
| `Deprecated call to get_attribute / set_attribute, use MetaDataRef methods instead` | See §3.1. |
| `Calling get_connected_players() at mod load time is deprecated` | Defer with `core.after(0, fn)` or `register_on_mods_loaded`, or delete the dead code. |
| `The image field in craftitem/tool definitions is deprecated. Use inventory_image` | Rename the field. |
| `Specifying tool capabilities directly in the tool definition is deprecated` | Nest under `tool_capabilities`. |
| `The cookresult_itemstring / furnace_burntime item definition field is deprecated` | `core.register_craft{type="cooking"/"fuel", …}`. |
| `core.env:[...] is deprecated` | `core.[...]`. |
| `core.setting_* functions are deprecated` | `core.settings:*`. |
| `core.register_on_auth_fail is deprecated` | `core.register_on_authplayer`. |
| `core.register_async_metatable is deprecated` | `core.register_portable_metatable`. |
| `Deprecated usage of get_node_group, use get_item_group instead` | Rename. |
| `false value given to core.set_player_privs` / `non-true value given` | Pass a set of `true`s, or use `core.change_player_privs`. |
| `Support for dumping functions in core.serialize is deprecated` | Don't serialize functions. |
| `core.deserialize called with nil (expected string)` | Guard the call site. |
| `Server: ignoring file as it has disallowed characters: "…"` | Rename to `[a-zA-Z0-9_.-]` only, prefixed with the mod name. |
| PNG `iCCP: known incorrect sRGB profile` | Re-export, e.g. `mogrify -strip *.png`. |
| PNG `Interlace handling should be turned on…` | Re-export without Adam7 interlacing. |
| glTF `embedded images are not supported` | Supply textures via `textures`/`tiles`; strip with `gltfutil.py`. |
| glTF `multiple animations are not supported` | Merge into one timeline and use frame ranges (multi-track lands in 5.17). |
| glTF `negative weights` | Zero or remove them; normalise weights. |
| glTF `nodes using matrix transforms must not be animated` | Decompose to TRS, or drop the animation channel. |

---

## 6. Already announced for the next major version

From `doc/breakages.md` — not yet in effect, but do not build new code that depends on
any of it:

* `.x` and `.b3d` model support will be removed → move to glTF (`.glb`).
* The ×10 attachment/model space multiplier and the ×2 player gravity multiplier go away.
* `get_sky()` will always return a table; fog moves out of `get/set_sky` into
  `get/set_fog`.
* `depends.txt` / `description.txt` will be removed outright.
* The moon texture will be rotated 180° to match the sun.
* `set_physics_override(num, num, num)` will be removed.
* `${key}` substitution in metadata values will be removed.
* `old_move` will be removed; `physics_override.sneak` will stop affecting speed.
* `use_texture_alpha` will be harmonised between entities and nodes, default `"opaque"`,
  bool compat code removed.
* itemdef `sound` and `sounds` will be merged.
* `DIR_DELIM` will be removed from Lua.
* Built-in knockback and related functions will be removed entirely.
* `core.serialize`'s `safe` parameter goes away — `safe = true` always.
* Strict type checking for every `v3s16`/`v3f` read from Lua.
* `on_drop` will be reworked to `(itemstack, dropper, count)` returning the new stack.
* `get_all_craft_recipes` and `get_craft_result` will use consistent field names.
* Player names may be replaced by UUIDs.
* Particle default blend mode will change to `clip`.

---

## 7. This game specifically

### 7.1 Baseline facts

* `game.conf` already uses `title`, so no 5.6 change is needed there.
* **148 top-level mod directories, 6 of them modpacks, 142 mods with an `init.lua`, 805 Lua files.**
  Modpacks: `3d_armor-version-0.4.11`, `display_modpack`, `mesecons`, `midi-modpack-master`,
  `technic_plus`, `WorldEdit-1.2`.
* Only three mods are git submodules — `mods/cooking`, `mods/cooking_fr`,
  `mods/alpha_workaround_minus`. Everything else is an in-tree copy that can be patched
  directly; the submodules need an upstream commit plus a pointer bump.
* **`mod.conf` migration is already essentially done.** Census over all 142 mods:
  only `mods/cooking` and `mods/cooking_fr` (both submodules) lack a `mod.conf`, and
  those two are also the only mods still carrying a `depends.txt`. **Zero
  `description.txt` files remain.** This closes most of §1.2's `mod.conf` item.
* `mods/basic_materials/mod.conf` and `mods/pipeworks/mod.conf` declare
  `min_minetest_version = 5.2.0`; `mods/technic_plus/modpack.conf` declares
  `min_minetest_version = 5.0`. This key is not read by the engine (it is not in
  lua_api.md's list of `mod.conf` keys); it is ContentDB metadata and gates nothing at
  runtime.
* **luacheck baseline (2026-07-30, luacheck 1.2.0): 3579 warnings / 0 errors in 805 files.**
  Re-run with `luacheck mods/`. Codes that matter:

  | Code | Count | Meaning | Relevance |
  |---|---|---|---|
  | W631 / W611 / W612 | 915 / 685 / 156 | long lines, blank-line and trailing whitespace | cosmetic, ignore |
  | W113 | 540 | accessing undefined variable | mostly false positives (see below) |
  | W131 | 228 | unused implicitly defined global | some real accidental globals |
  | W211 / W311 / W411 / W431 / W432 | 218 / 61 / 64 / 113 / 73 | unused / shadowed locals | cosmetic |
  | W111 | 111 | setting non-standard global | **real** — matches the engine's "Assignment to undeclared global variable" |
  | W122 | 64 | setting read-only field of a global | **interesting** — mods monkeypatching `minetest.*` / `core.*` / `table.*` |

  `luacheck mods/ --only 1` narrows to the global-related ones. Caveats:
  * Many W113 hits are **cross-mod API globals**, not bugs: `digiline` (46), `intllib` (42),
    `stairsplus` (15), `money` (15), `cmdlib` (13), `unifieddyes` (11), `craftguide` (11),
    `toolranks` (10), `cmi` (9), `mg` (9). Fixed by extending `read_globals` in
    `.luacheckrc`, not by touching code — **done 2026-07-30**, see §7.1.1.
  * The genuine accidental globals hide among the short names: `i`, `pos`, `meta`,
    `timer`, `r`, `formspec`, `newFull`.
  * `minetest` (42), `core` (21), `table` (24) appear as W122 — mods assigning into the
    engine namespace. `.luacheckrc` already whitelists `mods/creative/init.lua`.
* **Correction (2026-07-30):** `mssg` and `sgnd` were listed above as cross-mod API false
  positives. They are not — both are **assigned inside this tree**, so they are this game's
  own inter-mod globals (or accidental ones) and were deliberately *not* whitelisted.
  Measured counts under `--only 113` are 9 and 6, not 21 and 18.

### 7.1.1 `.luacheckrc` `read_globals` pass — done 2026-07-30

`read_globals` predated much of the API surface in this document. Extended with the engine
globals it was missing (`PcgRandom`, `SecureRandom`, `AreaStore`, `Raycast`,
`PerlinNoise`/`PerlinNoiseMap`, `ValueNoise`/`ValueNoiseMap`, `vector2`) plus the external
third-party mod APIs. `DIR_DELIM` was kept — it is on the §6 removal list but is still
referenced here — and is now commented as such.

**Result: 3579 → 3341 total warnings; W113 540 → 302; `--only 1` 989 → 751. Still 0 errors.**
Total fell by exactly the W113 reduction, so no `W122`/read-only-assignment warnings were
introduced by the whitelist.

#### The method — reuse this before whitelisting anything else

A name was classified as external **only if it is read but never assigned anywhere in this
tree**, established by cross-referencing the W113 reads against the W111 + W131 assignments:

```sh
luacheck mods/ --only 113 --no-color | grep -oE "accessing undefined variable '[^']+'" \
    | sed "s/.*'\(.*\)'/\1/" | sort -u > /tmp/read.txt
luacheck mods/ --only 111 --no-color | grep -oE "setting non-standard global variable '[^']+'" \
    | sed "s/.*'\(.*\)'/\1/" | sort -u > /tmp/set.txt
luacheck mods/ --only 131 --no-color | grep -oE "unused global variable '[^']+'" \
    | sed "s/.*'\(.*\)'/\1/" | sort -u >> /tmp/set.txt
sort -u /tmp/set.txt -o /tmp/set.txt
comm -23 /tmp/read.txt /tmp/set.txt   # never assigned here -> external API, or a typo
comm -12 /tmp/read.txt /tmp/set.txt   # assigned here too   -> in-tree global, or missing `local`
```

Note `--no-color`: luacheck wraps the variable name in ANSI escapes, so a `'...'` grep
silently matches nothing against colourised output.

The whitelist was kept **deliberately conservative** — ambiguous names were left out so they
stay visible in the queue. A false positive there costs a minute of review; a wrongly
whitelisted missing-`local` bug is hidden permanently.

#### The 302 survivors — this is the work queue for §7.5 step 2

Three distinct classes, not one:

1. **Read *and* assigned in-tree (~45 names)** — the classic missing-`local` bugs. Contains
   every name §7.1 predicted (`i`, `pos`, `meta`, `timer`, `r`, `formspec`, `newFull`) plus
   `b`, `g`, `s`, `buf`, `params`, `path`, `player`, `result`, `row`, `fuel`, `factor`,
   `message`, `childpos`, `stackname`, `bottom_pos`, `bottom_node`, `shadowpos`,
   `open_meta`, `open_env`, `pl_formspec`, `pl_receive_fields`, `sound_open`, `sound_close`,
   `hue2rgb`, `injurydef`, `mod_list`, `diggername`, `puddlesize`, `bloodsize`, and others.
2. **Read but never assigned anywhere** — these always evaluate to `nil` at runtime. Includes
   outright typos: **`minetet`** (for `minetest` — a guaranteed live bug),
   `puddlepuddlesize` (for `puddlesize`), `desc_element_eigthslab_double`.
3. **Uppercase per-mod config globals, read but never set** — `ARMOR_MATERIALS`,
   `ARMOR_FIRE_NODES`, `WORM_CHANCE`, `WORM_IS_MOB`, `NEW_WORM_SOURCE`, `TREASURE_CHANCE`,
   `TREASURE_RANDOM_ENABLE`, `SHARK_CHANCE`, `FISH_CHANCE`, `ESCAPE_CHANCE`, `SHARED_AMOUNT`,
   `BOBBER_VIEW_RANGE`, `SIMPLE_DECO_FISHING_POLE`, `WEAR_OUT`, `MESSAGES`, `HUD_THIRST_POS`,
   `HUD_THIRST_OFFSET`, `HUD_SB_SIZE`. The old-mod convention where a settings file defines
   these. Since nothing assigns them, **the intended defaults are silently inactive** — worth
   checking per mod (`fishing`, `thirsty`, `3d_armor`) rather than mass-fixing.

### 7.2 Mod inventory and upstream comparison

#### Method

Upstream identity was resolved by matching mod directory names against the full
ContentDB package index (3377 packages, fetched 2026-07-30) and the upstream
Minetest Game mod list (34 mods), then falling back to local evidence — `mod.conf`
`description`/`author`, README URLs, `init.lua` licence headers, `.gitmodules`.

#### The divergence metric, and why it never licenses skipping a diff

"Focused commits" = the number of commits in this repository touching a mod, *excluding*
repo-wide sweeps. Only 15 of the 1410 commits touch more than 8 mod directories at once,
so this is close to the raw count but removes the flattering effect of bulk maintenance
commits (e.g. `vote` 34 → 31, `farming` 38 → 32).

**This metric has a hard blind spot: it can only see edits made _after_ import.** A mod
that was modified before it was ever committed — the normal way mod soups are assembled —
looks identical to a pristine copy. There is no way to recover that from git history.

Therefore **every mod must be diffed against upstream before being upgraded.** The bands
below estimate *how large a diff to expect*; they never mean "safe to replace unread". A
mod in band 1 is *unverified*, not *unmodified*.

| Band | Focused commits | Expected local diff | Strategy |
|---|---|---|---|
| **1 · unverified** | 0–2 | unknown; possibly empty | diff first. If genuinely empty, a clean swap is fine — but you only know that *after* the diff |
| **2 · small** | 3–9 | a few local edits | diff, upgrade, re-apply |
| **3 · substantial** | 10–29 | significant divergence | read the full diff, port changes deliberately |
| **4 · heavy fork** | 30+ | effectively a fork | do not replace; cherry-pick upstream fixes instead |

A second blind spot cuts the other way: the metric says nothing about how far *upstream*
has moved. A mod with 0 focused commits may still be five years behind.

#### 7.2.1 Minetest Game-derived (29 mods)

All are stock MTG mod names, all already have `mod.conf`, none carry `depends.txt` or
`description.txt`. `player_api` and `spawn` are present, which puts the base at
**MTG 5.x-era, not 0.4.x**. The exact base release is not yet established — see §7.3.

Note `mtg_craftguide` is absent (this game uses `unified_inventory` plus its own `guide`),
and `farming` is **not** MTG's — see 7.2.2.

| Mod | Focused commits | Expected diff |
|---|---|---|
| `default` | 15 | 3 · substantial |
| `beds` | 4 | 2 · small |
| `doors` | 4 | 2 · small |
| `bones` | 3 | 2 · small |
| `fire` | 3 | 2 · small |
| `boats` | 2 | 1 · unverified |
| `carts` | 2 | 1 · unverified |
| `sethome` | 2 | 1 · unverified |
| `game_commands` | 1 | 1 · unverified |
| `player_api` | 1 | 1 · unverified |
| `tnt` | 1 | 1 · unverified |
| `xpanes` | 1 | 1 · unverified |
| `bucket` | 0 | 1 · unverified |
| `butterflies` | 0 | 1 · unverified |
| `creative` | 0 | 1 · unverified |
| `dungeon_loot` | 0 | 1 · unverified |
| `dye` | 0 | 1 · unverified |
| `env_sounds` | 0 | 1 · unverified |
| `fireflies` | 0 | 1 · unverified |
| `flowers` | 0 | 1 · unverified |
| `give_initial_stuff` | 0 | 1 · unverified |
| `screwdriver` | 0 | 1 · unverified |
| `sfinv` | 0 | 1 · unverified |
| `spawn` | 0 | 1 · unverified |
| `stairs` | 0 | 1 · unverified |
| `vessels` | 0 | 1 · unverified |
| `walls` | 0 | 1 · unverified |
| `weather` | 0 | 1 · unverified |
| `wool` | 0 | 1 · unverified |

#### 7.2.2 ContentDB / identified upstream (58 mods)

These are the upgrade candidates: upstream has already done much of the §2 migration.

| Mod | Focused commits | Expected diff | Upstream | Evidence |
|---|---|---|---|---|
| `3d_armor-version-0.4.11` | 43 | 4 · heavy fork | stu/3d_armor (CDB) | dir name pins v0.4.11 |
| `farming` | 32 | 4 · heavy fork | TenPlus1/farming — **Farming Redo, not MTG farming** | README + optional_depends lucky_block/toolranks |
| `vote` | 31 | 4 · heavy fork | rubenwardy/vote (CDB) |  |
| `currency` | 28 | 3 · substantial | mt-mods/currency (CDB) |  |
| `character_anim` | 21 | 3 · substantial | LMD/character_anim (CDB) | your own mod |
| `mobs_farm` | 21 | 3 · substantial | TenPlus1 mobs family (likely `mobs_animal`) | desc 'Adds farm animals' + intllib |
| `mesecons` | 18 | 3 · substantial | Jeija/mesecons (CDB) |  |
| `technic_plus` | 17 | 3 · substantial | mt-mods/technic_plus (CDB) |  |
| `thirsty` | 17 | 3 · substantial | csirolli/thirsty (CDB) |  |
| `areas` | 16 | 3 · substantial | ShadowNinja/areas (CDB) |  |
| `xdecor` | 16 | 3 · substantial | Wuzzy/xdecor (CDB) |  |
| `hbhunger` | 14 | 3 · substantial | Wuzzy/hbhunger (CDB) |  |
| `seasons` | 14 | 3 · substantial | tbook/seasons (CDB) |  |
| `interact` | 13 | 3 · substantial | Amaz/interact (CDB) |  |
| `streets` | 13 | 3 · substantial | webdesigner97/streets (CDB) |  |
| `waterworks` | 10 | 3 · substantial | FaceDeer/waterworks (minetest-mods) | desc + airtanks/dynamic_liquid URLs |
| `dynamic_liquid` | 8 | 2 · small | FaceDeer/dynamic_liquid (CDB) |  |
| `hudbars` | 8 | 2 · small | Wuzzy/hudbars (CDB) |  |
| `money3` | 8 | 2 · small | luk3yx/money3 (CDB) |  |
| `fishing` | 8 | 2 · small | Mossmanikin/fishing | README URL |
| `midi-modpack-master` | 8 | 2 · small | unknown midi modpack; dir name pins a 'master' snapshot | dir name |
| `grenades_basic` | 7 | 2 · small | Lone_Wolf/grenades_basic (CDB) |  |
| `pipeworks` | 7 | 2 · small | mt-mods/pipeworks (CDB) |  |
| `mobs_redo` | 7 | 2 · small | TenPlus1/mobs (CDB pkg `mobs`, repo `mobs_redo`) | mod.conf desc |
| `cooking` | 7 | 2 · small | submodule → Elkien3/cooking | submodule |
| `elevator` | 6 | 2 · small | shacknetisp/elevator (CDB) |  |
| `playertag` | 6 | 2 · small | forum viewtopic t=10250 / t=7321 | README URLs |
| `digilines` | 5 | 2 · small | Jeija/digilines (CDB) |  |
| `grenades` | 5 | 2 · small | Lone_Wolf/grenades (CDB) |  |
| `inbox` | 5 | 2 · small | bas080/inbox | README URL + forum link |
| `modlib` | 4 | 2 · small | LMD/modlib (CDB) | your own mod |
| `moreores` | 4 | 2 · small | Calinou/moreores (CDB) |  |
| `digistuff` | 3 | 2 · small | mt-mods/digistuff (CDB) |  |
| `unified_inventory` | 3 | 2 · small | RealBadAngel/unified_inventory (CDB) |  |
| `cooking_fr` | 3 | 2 · small | submodule → Elkien3/cooking_fr | submodule |
| `digiline_routing` | 3 | 2 · small | numberZero (LGPL 2.1) | init.lua header |
| `banondie` | 2 | 1 · unverified | srifqi/banondie (CDB) |  |
| `cmdlib` | 2 | 1 · unverified | LMD/cmdlib (CDB) | your own mod |
| `controls` | 2 | 1 · unverified | mt-mods/controls (CDB) |  |
| `display_modpack` | 2 | 1 · unverified | mt-mods/display_modpack (CDB) |  |
| `irc` | 2 | 1 · unverified | kaeza/irc (CDB) |  |
| `irc_commands` | 2 | 1 · unverified | ShadowNinja/irc_commands (CDB) |  |
| `xban2` | 2 | 1 · unverified | kaeza/xban2 (CDB) |  |
| `digiboard` | 2 | 1 · unverified | bas080 orig., 'cracked by jogag' | init.lua header |
| `digiprinter` | 2 | 1 · unverified | jogag, 'Digiline Stuff pack' | init.lua header |
| `basic_materials` | 1 | 1 · unverified | mt-mods/basic_materials (CDB) |  |
| `bedrock2` | 1 | 1 · unverified | Wuzzy/bedrock2 (CDB) |  |
| `builtin_item` | 1 | 1 · unverified | TenPlus1/builtin_item (CDB) |  |
| `enable_shadows` | 1 | 1 · unverified | rollerozxa/**minetest-enable-shadows** | CDB pkg `enable_shadows`; repo name ≠ mod name |
| `envelopes` | 1 | 1 · unverified | archfan7411/envelopes (CDB) |  |
| `itemframes` | 1 | 1 · unverified | TenPlus1/itemframes (CDB) |  |
| `letters` | 1 | 1 · unverified | Amaz/letters (CDB) |  |
| `markers` | 1 | 1 · unverified | Sokomine/markers (CDB) |  |
| `redef` | 1 | 1 · unverified | Linuxdirk/redef (CDB) |  |
| `moremesecons_adjustable_player_detector` | 1 | 1 · unverified | Palige/moremesecons — **unpacked modpack member** | init.lua header |
| `alpha_workaround_minus` | 1 | 1 · unverified | submodule → codeberg `appgurueu/alpha_workaround_minus`; fork of C-C-Minetest-Server/alpha_workaround | submodule + README |
| `WorldEdit-1.2` | 0 | 1 · unverified | sfan5/worldedit (CDB) | dir name pins v1.2 |
| `entitycontrol` | 0 | 1 · unverified | Noodlemire/entitycontrol (CDB) |  |

#### 7.2.3 Custom or unidentified (61 mods)

No ContentDB name match and no upstream URL in local metadata. Numbers are focused commits.

* **heavily forked** (6): `cars`&nbsp;112, `default_tweaks`&nbsp;88, `foodspoil`&nbsp;49, `medical`&nbsp;41, `policetools`&nbsp;32, `spriteguns`&nbsp;30
* **substantially edited** (16): `nolight`&nbsp;29, `mumblereward`&nbsp;27, `betterfall`&nbsp;24, `gas_lib`&nbsp;22, `jobs`&nbsp;22, `frisk`&nbsp;20, `playercontrol`&nbsp;20, `charactercreation`&nbsp;19, `sprint`&nbsp;18, `bones_entity`&nbsp;16, `oil`&nbsp;12, `doorram`&nbsp;11, `anticombatlog`&nbsp;10, `locksmith`&nbsp;10, `package`&nbsp;10, `playertools`&nbsp;10
* **lightly edited** (20): `technic_powermeter`&nbsp;9, `spood`&nbsp;8, `beamlight`&nbsp;7, `block_painting`&nbsp;7, `diet_simple`&nbsp;6, `gun_lathe`&nbsp;6, `antilag`&nbsp;5, `army`&nbsp;5, `beer_test`&nbsp;5, `knifesword`&nbsp;5, `playercollision`&nbsp;5, `supertracker`&nbsp;5, `assembler`&nbsp;4, `classes_test`&nbsp;4, `email`&nbsp;4, `static_ocean`&nbsp;4, `cake`&nbsp;3, `interacthandler`&nbsp;3, `vote_block`&nbsp;3, `wiki`&nbsp;3
* **no commits since import (**unverified, not pristine**)** (19): `hide_minimap`&nbsp;2, `mapp`&nbsp;2, `memorandum`&nbsp;2, `names_per_ip`&nbsp;2, `bed_metal`&nbsp;1, `coalcook`&nbsp;1, `cozy`&nbsp;1, `marker`&nbsp;1, `recipes`&nbsp;1, `referral`&nbsp;1, `report`&nbsp;1, `soccer`&nbsp;1, `toolsonly`&nbsp;1, `utils`&nbsp;1, `voice`&nbsp;1, `vpnban`&nbsp;1, `guide`&nbsp;0, `real_suffocation`&nbsp;0, `silentsneak`&nbsp;0

**Read the first group with suspicion.** A genuinely game-specific mod accumulates history;
a mod nobody has touched since import is more likely an unidentified third-party mod than
an original creation. `guide`, `real_suffocation` and `silentsneak` have *zero* focused
commits — they appear only in bulk import commits. Several have descriptions that read like
published mods (`real_suffocation`: "The player will lose breath inside solid blocks…";
`cozy`: "Sit and lay using chat commands"; `marker` credits "Elkin" and "LMD").
**Treat this group as "upstream not yet found", not "no upstream exists"** — searching
ContentDB by title or description rather than by mod name is the obvious next step.

The heavily-forked group is unambiguously this game's own and carries its identity:
`cars` (112), `default_tweaks` (88), `foodspoil` (49), `medical` (41), `policetools` (32),
`spriteguns` (30). These must be migrated by hand.

#### 7.2.4 Findings that change the plan

* **`farming` is TenPlus1's Farming Redo, not MTG farming.** Its `mod.conf` optional-depends
  on `lucky_block` and `toolranks` and its README mentions "redo". Diffing it against MTG
  would be meaningless; upstream is `TenPlus1/farming`. 32 focused commits.
* **`moremesecons_adjustable_player_detector` is an unpacked modpack member.** Upstream is
  the `moremesecons` modpack (Palige on ContentDB), not a standalone mod. The repo also has
  a commit removing an overridden mesecons playerdetector (`01319573`), so this area has
  been touched once already.
* **`mobs_redo`'s ContentDB package is named `mobs`** (author TenPlus1, repo `mobs_redo`) —
  a genuine mod-name/package-name mismatch, so name matching alone under-reports.
* **`alpha_workaround_minus` already mitigates the 5.9 `use_texture_alpha` change globally**
  by back-filling the old default at `on_mods_loaded`. It is a deliberate band-aid — its own
  comment says "could be missing some registrations but i don't really care" — so the
  long-term plan is to set `use_texture_alpha` per node and retire it.
* Directory names pin three snapshots explicitly: `3d_armor-version-0.4.11`,
  `WorldEdit-1.2`, `midi-modpack-master`. `3d_armor` at 0.4.11 is very old and carries 43
  focused commits on top — the single most valuable upgrade target, and also the most work.

### 7.3 Upstream-upgrade procedure

Applies to **every** mod in 7.2.1 and 7.2.2, regardless of band:

1. Identify upstream and the version the game most likely started from. For ContentDB
   packages the repo URL is in the package detail API
   (`/api/packages/<author>/<name>/` → `repo`, which also carries `provides`).
2. `diff -r` the local copy against upstream-at-that-version. **That diff is the set of
   local customizations to carry over**, and it is the only reliable way to find edits made
   before import. Do this even when the focused-commit count is 0.
3. If the old version can't be pinned, diff against upstream HEAD instead and read the
   result as "local changes ∪ upstream changes" — noisier, but still far better than
   assuming.
4. `git log --oneline -- mods/<mod>` for the human-readable intent behind post-import edits.
5. Upgrade to upstream HEAD, re-apply the customizations from step 2, re-run
   `luacheck mods/<mod>`.
6. Record the outcome in §7.4 — **including "diffed, no local changes, clean swap"**, which
   is exactly the information the commit metric cannot provide and the next session
   should not have to re-derive.

**Commit it per §7.6**, which turns steps 2–5 into one verifiable fetch commit plus one
commit per reapplied customization. Do not land an upgrade as a single lump commit.

Note that a ContentDB *package* name is not the repo name: `enable_shadows` lives at
`rollerozxa/minetest-enable-shadows`, and `mobs_redo` is CDB package `mobs` (§7.2.4).
Resolve the real URL from the package API's `repo` field:
`curl -sS https://content.luanti.org/api/packages/<author>/<name>/`

To establish the MTG base version (§7.2.1), diff `mods/default` against `minetest_game`
at tags 5.0.0 … 5.8.0 and take the best match; the MTG mods almost certainly all came
from a single import.

### 7.4 Per-mod progress

Add a row when you start on a mod; delete nothing. `Items` refers to §1 entries.
Record diff outcomes here, including negative results.

| Mod | Status | Diffed vs upstream? | Items done | Notes |
|---|---|---|---|---|
| _(all)_ | not started | no | — | Repo-wide commits so far: `09cecc8d` (TileDef `image`→`name`), `ee1815e1` (`get_connected_players` at load time), `b6a49a94` (`getpos`→`get_pos`), `0cf5fa2a` (player meta instead of `[gs]et_attribute`), `01319573` (removed overridden mesecons playerdetector) |
| `alpha_workaround_minus` | **at upstream HEAD** | yes — submodule, no local commits on top | — | Bumped `fc8f9df` → `a4f9749` on 2026-07-30. Clean fast-forward, no local customizations to re-apply. Still a band-aid: retire it once `use_texture_alpha` is set per node (§1.3, §7.5 step 8). |

### 7.5 Recommended order of attack

Cheapest and most mechanical first, so the risky audits happen once the noise is gone.

- [x] 1. **`alpha_workaround_minus` → upstream HEAD.** Submodule pointer bumped
      `fc8f9df` → `a4f9749` (2026-07-30).
- [~] 2. **Static pass, no game needed.** `.luacheckrc` `read_globals` extended (§7.1) —
      done. Remaining: work the 302 surviving W113 hits, which are now a real bug queue
      rather than noise (§7.1.1).
- [ ] 3. **Work the band-1 mods in 7.2.2 through the §7.3 procedure.** Expect many empty or
      near-empty diffs, which convert into clean upgrades and let upstream's own
      modernization do the work for you — but confirm each diff rather than assuming.
- [ ] 4. **Establish the MTG base version** (§7.3), then work 7.2.1 the same way.
- [ ] 5. **`3d_armor` 0.4.11 → current.** Oldest pinned snapshot, 43 focused commits.
      Budget real time; expect to hit item 9 below while doing it.
- [ ] 6. **Identify the unidentified mods** (§7.2.3) by title/description search on
      ContentDB. Every one you identify converts hand-migration into an upgrade.
- [ ] 7. **Log-driven pass.** `debug_log_level = info`, default
      `deprecated_lua_api_handling = log`, start the game, exercise the main systems
      (build, dig, craft, cars, elevators, digilines, armour, jobs), then work through
      `debug.txt`. Unexercised code paths stay silent, so this does not replace grepping
      for the §1.2 items.
- [ ] 8. `use_texture_alpha` per node in the band 3/4 and custom mods; then retire
      `alpha_workaround_minus`.
- [ ] 9. `get_attribute`/`set_attribute` → `get_meta()` (partly done, see `0cf5fa2a`).
- [ ] 10. `set_bone_position` → `set_bone_override` — **watch degrees vs radians**.
      Likely hits `3d_armor`/`wieldview`, `character_anim`, `charactercreation`.
- [ ] 11. Entity definitions → `initial_properties`; drop `weight` and `colors`.
      Likely hits `cars`, `spriteguns`, `mobs_redo`, `mobs_farm`, `army`.
- [ ] 12. Any file writes into mod directories.
- [ ] 13. `liquid_alternative_*` completeness on every custom liquid
      (`dynamic_liquid`, `waterworks`, `static_ocean`, `oil`, `gas_lib`, `bucket`).
- [ ] 14. `.bmp` textures and `*_normal.png` normal maps.
- [ ] 15. `LMB`/`RMB` → `dig`/`place`; `up`/`down`/`left`/`right` → `movement_x`/`movement_y`.
      Likely hits `playercontrol`, `controls`, `sprint`, `cars`.
- [ ] 16. `mod.conf` for `mods/cooking` and `mods/cooking_fr` (the only two left, both
      submodules); delete their `depends.txt`.

### 7.6 Upstream import protocol — how §7.3 gets committed

§7.3 says *what* to do; this says how to land it so it can be reviewed remotely without
reading thousands of lines of upstream churn. **Follow this for every mod upgrade.**

#### Branch

One branch per mod, pushed to the `fork` remote (`appgurueu/citysim_game`), matching convention `upgrade/<modname>`. One mod per
branch means a bad upgrade is reverted without blocking the other eighteen.

#### Commit 1 — the fetch. Verify it, do not read it.

A **verbatim** import of the upstream tree: no local content, nothing outside the mod
directory. Because git tree hashes are content-addressed, an equal hash across two
unrelated repositories proves the content is identical — so this commit is checked by
one hash comparison instead of by reading its diff.

Message carries the trailers the verifier consumes, plus the **plan** for what follows:

```
<mod>: import upstream <short-sha>

Verbatim import. Verify with tools/verify-upstream-imports.sh, do not read.

Customizations to reapply:
  1. <what>                        -> kept       (commit follows)
  2. <what>                        -> dropped    (upstream does this since <sha>)
  3. <what>                        -> adapted    (bone API changed in 5.9)

Upstream-Repo: https://github.com/…
Upstream-Commit: <40-hex>
Upstream-Subpath: .
Local-Path: mods/<mod>
Anchor-Commit: <40-hex|none>
Anchor-Method: exact-tree-match | best-diff-match | none
```

The message is not part of the tree, so a rich ledger here costs the verification nothing.
**Dropped customizations exist only here** — they produce no commit of their own, so if they
are not written down they vanish silently. They are also the highest-risk decision on the
branch: dropping local work because "upstream does it now" is exactly what a reviewer needs
to second-guess.

Produce it with (no `git subtree` on this machine):

```sh
git fetch --no-tags <repo> HEAD && SHA=$(git rev-parse FETCH_HEAD)
git rm -r -q --cached mods/<mod> && rm -rf mods/<mod>
git read-tree --prefix=mods/<mod>/ -u "$SHA^{tree}"
```

Upstream's `.github/`, `.gitignore` and CI config come in too. That is deliberate: exact
verification is worth a few deletion lines, and "we strip upstream's CI" genuinely is a
local policy that should be visible rather than assumed.

#### Commits 2..n — one per reapplied customization

Not one lump. Each local change lands as its own commit, so each can be judged, reverted or
questioned on its own, and the subject line says what the customization *is* rather than
"reapply local changes". Order them so anything load-bearing comes first.

**A mod with no commits after the fetch needed no judgment at all** — verify the hash and
skip it. Review effort then scales with real divergence instead of with mod count, which is
the entire point when a batch is nineteen mods wide.

#### `Anchor-Method` — say how the customization list was derived

To know what the local customizations *are* you need the version the game forked from.
§7.3 step 3 concedes it often cannot be pinned. Search for it mechanically: diff the local
tree against each upstream tag/commit candidate and take the smallest diff.

| Value | Meaning | Reviewer should |
|---|---|---|
| `exact-tree-match` | local is pristine upstream at that commit | trust it; there are no customizations to review |
| `best-diff-match` | anchor inferred; customizations computed as a real patch | review normally |
| `none` | no anchor found — the list was assembled **by reading, not by patch application** | scrutinise hard |

`none` is not a failure, it is a disclosure. It is also the machine-readable form of
CLAUDE.md's rule that band 1 means *unverified*, not *unmodified*.

#### Submodules

`cooking`, `cooking_fr`, `alpha_workaround_minus`: the fetch is just the pointer bump, and
it is already exactly verifiable — the gitlink *is* the upstream commit, which the verifier
checks directly. Customizations cannot live in the parent repo; they need an upstream commit
or a fork.

#### Verifying

```sh
tools/verify-upstream-imports.sh              # all history
tools/verify-upstream-imports.sh master..HEAD # just this branch
```

Checks every commit carrying an `Upstream-Commit:` trailer: that the tree at `Local-Path`
is identical to upstream at that commit, and that the commit touches nothing else. Exits
non-zero on any failure, so it can gate a PR. Upstream mirrors are cached under
`${XDG_CACHE_HOME:-~/.cache}/citysim-upstream`.

#### Agent-parallel notes

Each agent owns one mod, one branch, and its own commits — no shared file, so nineteen can
run at once. **Agents must not write `MODERNIZATION.md`**; §7.4 gets merged afterwards from
the commit trailers, which is mechanical because they are structured. An agent that writes
its own §7.4 row will clobber the other eighteen.
