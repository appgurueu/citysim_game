
local MODPATH = minetest.get_modpath("wiki")

wikilib = { }

local ie = minetest.request_insecure_environment()
assert(ie, "you must allow `wiki` in `secure.trusted_mods`")

local private = { }

private.open = ie.io.open
-- The insecure environment carries no `core`; the sandboxed core.mkdir is fine
-- here because the wiki only creates directories under get_worldpath().
private.mkdir = core.mkdir
loadfile(MODPATH.."/owner.lua")(private)
--dofile(MODPATH.."/owner.lua")
loadfile(MODPATH.."/strfile.lua")(private)
loadfile(MODPATH.."/wikilib.lua")(private)
--dofile(MODPATH.."/wikilib.lua")
loadfile(MODPATH.."/internal.lua")(private)
loadfile(MODPATH.."/plugins.lua")(private)

loadfile(MODPATH.."/plugin_forum.lua")(private)
