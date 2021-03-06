local players = {}
local player_positions = {}
local last_wielded = {}

function round(num) 
	return math.floor(num + 0.5) 
end

minetest.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	table.insert(players, player_name)
	last_wielded[player_name] = player:get_wielded_item():get_name()
	local pos = player:getpos()
	local rounded_pos = {x=round(pos.x),y=round(pos.y)+1,z=round(pos.z)}
	local wielded_item = player:get_wielded_item():get_name()
	if wielded_item ~= "default:torch" and wielded_item ~= "xdecor:candle" and wielded_item ~= "xdecor:lantern" then
		-- Force recalculation of light
            if minetest.get_node(rounded_pos) == "walking_light:light" then
		minetest.env:add_node(rounded_pos,{type="node",name="air"})
            end
	end
	player_positions[player_name] = {}
	player_positions[player_name]["x"] = rounded_pos.x;
	player_positions[player_name]["y"] = rounded_pos.y;
	player_positions[player_name]["z"] = rounded_pos.z;
end)

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	for i,v in ipairs(players) do
		if v == player_name then 
			table.remove(players, i)
			last_wielded[player_name] = nil
			-- Force recalculation of light
			local pos = player:getpos()
			local rounded_pos = {x=round(pos.x),y=round(pos.y)+1,z=round(pos.z)}
			local headblock = minetest.env:get_node(rounded_pos)
			if headblock.name == "walking_light:light" then
				minetest.env:add_node(rounded_pos,{type="node",name="air"})
			end
			player_positions[player_name]["x"] = nil
			player_positions[player_name]["y"] = nil
			player_positions[player_name]["z"] = nil
			player_positions[player_name]["m"] = nil
			player_positions[player_name] = nil
		end
	end
end)

minetest.register_globalstep(function(dtime)
	for i,player_name in ipairs(players) do
		local player = minetest.env:get_player_by_name(player_name)
		local wielded_item = player:get_wielded_item():get_name()
		if wielded_item == "default:torch" or wielded_item == "xdecor:candle" or wielded_item == "xdecor:lantern" then
			-- Torch is in your hand
			local pos = player:getpos()
			local rounded_pos = {x=round(pos.x),y=round(pos.y)+1,z=round(pos.z)}
			if (last_wielded[player_name] ~= "default:torch" and last_wielded[player_name] ~= "xdecor:candle" and last_wielded[player_name] ~= "xdecor:lantern") or (player_positions[player_name]["x"] ~= rounded_pos.x or player_positions[player_name]["y"] ~= rounded_pos.y or player_positions[player_name]["z"] ~= rounded_pos.z) then
				-- Torch just picked up or moved to a new node
				local is_air  = minetest.env:get_node_or_nil(rounded_pos)
				if is_air == nil or (is_air ~= nil and (is_air.name == "air" or is_air.name == "walking_light:light")) then
					-- if the current position is "air", set the torch light
					minetest.env:add_node(rounded_pos,{type="node",name="walking_light:light"})
				end
				if (player_positions[player_name]["x"] ~= rounded_pos.x or player_positions[player_name]["y"] ~= rounded_pos.y or player_positions[player_name]["z"] ~= rounded_pos.z) then
					-- if position changed, then extinguish old light
					local old_pos = {x=player_positions[player_name]["x"], y=player_positions[player_name]["y"], z=player_positions[player_name]["z"]}
					-- Force recalculation of light
					local is_light = minetest.env:get_node_or_nil(old_pos)
					if is_light ~= nil and is_light.name == "walking_light:light" then
						minetest.env:add_node(old_pos,{type="node",name="air"})
					end
				end
				-- marked position is now the rounded new position
				player_positions[player_name]["x"] = rounded_pos.x
				player_positions[player_name]["y"] = rounded_pos.y
				player_positions[player_name]["z"] = rounded_pos.z
			end

			last_wielded[player_name] = wielded_item;
		elseif last_wielded[player_name] == "default:torch" or last_wielded[player_name] == "xdecor:candle" or last_wielded[player_name] == "xdecor:lantern" then
			-- Torch not in hand, but the torch was still in the hand on the last run
			local pos = player:getpos()
			local rounded_pos = {x=round(pos.x),y=round(pos.y)+1,z=round(pos.z)}
			repeat
				local is_light  = minetest.env:get_node_or_nil(rounded_pos)
				if is_light ~= nil and is_light.name == "walking_light:light" then
					-- minetest.env:remove_node(rounded_pos)
					-- Force recalculation of light
					minetest.env:add_node(rounded_pos,{type="node",name="air"})
				end
			until minetest.env:get_node_or_nil(rounded_pos) ~= "walking_light:light"
			local old_pos = {x=player_positions[player_name]["x"], y=player_positions[player_name]["y"], z=player_positions[player_name]["z"]}
			repeat
				is_light  = minetest.env:get_node_or_nil(old_pos)
				if is_light ~= nil and is_light.name == "walking_light:light" then
					-- minetest.env:remove_node(old_pos)
					-- Force recalculation of light
					minetest.env:add_node(old_pos,{type="node",name="air"})
				end
			until minetest.env:get_node_or_nil(old_pos) ~= "walking_light:light"
			last_wielded[player_name] = wielded_item
		end
	end
end)

minetest.register_node("walking_light:light", {
	drawtype = "airlike",
	tile_images = {"walking_light.png"},
	-- tile_images = {"walking_light_debug.png"},
	inventory_image = minetest.inventorycube("walking_light.png"),
	paramtype = "light",
	walkable = false,
	is_ground_content = true,
	light_propagates = true,
	sunlight_propagates = true,
	light_source = 10,
	selection_box = {
        type = "fixed",
        fixed = {0, 0, 0, 0, 0, 0},
    },
})

minetest.register_abm({
	nodenames = {"walking_light:light", "technic:light"},
	interval = 10,
	chance = 1,
	catch_up = false,
	action = function(p0, node, _, _)
		local killlight = true
		local objs = minetest.get_objects_inside_radius(p0, 2)
		for _, obj in pairs(objs) do
			if obj:is_player() then
				killlight = false
			end
		end
		if killlight then
			minetest.remove_node(p0)
		end
	end,
})
