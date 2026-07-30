unused_args = false
allow_defined_top = true

read_globals = {
	-- Engine globals. See MODERNIZATION.md §7.1; this list is evidence-driven,
	-- extend it when luacheck actually flags a real engine global.
	"minetest", "core",
	"dump",
	"vector", "vector2",              -- vector2 added in 5.16
	"ItemStack", "Settings",
	"VoxelManip", "VoxelArea",
	"PseudoRandom", "PcgRandom", "SecureRandom",
	"AreaStore", "Raycast",
	"PerlinNoise", "PerlinNoiseMap",  -- renamed to ValueNoise* in 5.12; aliases are permanent
	"ValueNoise", "ValueNoiseMap",

	-- Slated for removal from Lua (MODERNIZATION.md §6), but still referenced here.
	"DIR_DELIM",

	-- Lua 5.1 compatibility
	"unpack",

	-- Third-party mod APIs probed as optional dependencies. These are read but never
	-- assigned anywhere in this tree, so they are external by construction and cannot
	-- be accidental globals. Verified by cross-referencing W113 reads against W111/W131
	-- assignments -- see MODERNIZATION.md §7.1.
	--
	-- Deliberately conservative: an ambiguous name is left OUT so it stays visible in
	-- `luacheck mods/ --only 1`. A false positive in that queue costs a minute of review;
	-- a wrongly whitelisted missing-`local` bug is hidden permanently.
	"digiline",
	"intllib",
	"stairsplus",
	"money",
	"cmdlib",
	"unifieddyes",
	"craftguide",
	"toolranks",
	"mg",
	"cmi",
	"inventory_plus",
	"factions",
	"binoculars",
	"protector",
	"datastorage",
	"moretrees",
	"lucky_block",
	"awards",
	"drawers",
	"invisibility",
	"monitoring",
	"chatplus",
	-- 3d_armor integration points
	"armor_monoid",
	"player_monoids",
	"wield3d",
	"skins",
	"u_skins",
	"wardrobe",
	-- homedecor's documented opt-in global
	"homedecor_expect_infinite_stacks",

	-- Silence "accessing undefined field copy of global table".
	table = { fields = { "copy" } }
}

-- Overwrites minetest.handle_node_drops
files["mods/creative/init.lua"].globals = { "minetest" }

-- Don't report on legacy definitions of globals.
files["mods/default/legacy.lua"].global = false
