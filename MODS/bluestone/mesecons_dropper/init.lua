--[[ This mod registers 3 nodes:
- One node for the horizontal-facing dropper (mesecons_dropper:dropper)
- One node for the upwards-facing droppers (mesecons_dropper:dropper_up)
- One node for the downwards-facing droppers (mesecons_dropper:dropper_down)

3 node definitions are needed because of the way the textures are defined.
All node definitions share a lot of code, so this is the reason why there
are so many weird tables below.
]]

local S = mesecon.S

local VER = "3"

local deg, random = math.deg, math.random
local tcopy, tinsert = table.copy, table.insert
local vsubtract = vector.subtract

local hopper_exists = minetest.global_exists("hopper")

local function get_dropoper_formspec(pos)
	local spos = pos.x .. "," .. pos.y .. "," .. pos.z
	local buf = string.buffer:new()
	buf:put(default.gui)
	buf:put("item_image[0,-0.1;1,1;mesecons_dropper:dropper]")
	buf:putf("label[0.9,0.1;%s]", S("Dropper"))
	buf:put("style_type[list;bgimg=formspec_cell.png^formspec_split.png;bgimg_hovered=formspec_cell_hovered.png^formspec_split.png]")
	buf:putf("list[nodemeta:%s;split;8,3.2;1,1;]", spos)
	buf:put(default.list_style)
	buf:putf("list[nodemeta:%s;main;3,0.5;3,3;]", spos)
	buf:putf("listring[nodemeta:%s;main]", spos)
	buf:put("listring[current_player;main]")

	return buf:tostring()
end

-- For after_place_node
local function setup_dropper(meta)
	meta:set_string("version", VER)
	local inv = meta:get_inventory()
	inv:set_size("main", 3 * 3)
	inv:set_size("split", 1)
end

local function dropper_orientate(pos, placer)
	-- Not placed by player
	if not placer then return end

	-- Pitch in degrees
	local pitch = deg(placer:get_look_vertical())
	local node = minetest.get_node(pos)
	if pitch > 55 then
		node.name = "mesecons_dropper:dropper_up"
	elseif pitch < -55 then
		node.name = "mesecons_dropper:dropper_down"
	else
		return
	end
	minetest.swap_node(pos, node)
end

-- Shared core definition table
local dropperdef = {
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	groups = {cracky = 3, dropper = 1},
	on_rotate = mesecon.on_rotate_horiz,
	after_dig_node = function(pos, _, oldmetadata)
		if not oldmetadata.inventory.main then return end
		for _, stack in ipairs(oldmetadata.inventory.main) do
			if not stack:is_empty() then
				minetest.item_drop(stack, nil, pos)
			end
		end
	end,

	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker then return itemstack end

		local name = clicker:get_player_name()

		if not minetest.get_meta(pos) or minetest.is_protected(pos, name) then
			return itemstack
		end

		minetest.show_formspec(name, node.name, get_dropoper_formspec(pos))
	end,

	allow_metadata_inventory_move = function(pos, _, _, to_list, _, count, player)
		local name = player and player:get_player_name() or ""
		if minetest.is_protected(pos, name) then
			minetest.record_protection_violation(pos, name)
			return 0
		elseif to_list == "split" then
			return 1
		else
			return count
		end
	end,

	allow_metadata_inventory_take = function(pos, _, _, stack, player)
		local name = player and player:get_player_name() or ""
		if minetest.is_protected(pos, name) then
			minetest.record_protection_violation(pos, name)
			return 0
		else
			return stack:get_count()
		end
	end,

	allow_metadata_inventory_put = function(pos, listname, _, stack, player)
		local name = player and player:get_player_name() or ""
		if minetest.is_protected(pos, name) then
			minetest.record_protection_violation(pos, name)
			return 0
		else
			if listname == "split" then
				return stack:get_count() / 2
			else
				return stack:get_count()
			end
		end
	end,

	mesecons = {effector = {
		-- Drop random item when triggered
		action_on = function(pos, node)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()

			local node_name = node.name
			local droppos = pos
			if node_name == "mesecons_dropper:dropper" then
				droppos = vsubtract(pos, minetest.facedir_to_dir(node.param2))
			elseif node_name == "mesecons_dropper:dropper_up" then
				droppos.y = droppos.y + 1
			elseif node_name == "mesecons_dropper:dropper_down" then
				droppos.y = droppos.y - 1
			end

			local dropnode = minetest.get_node(droppos)
			local dropnode_name = dropnode.name

			-- Upwards-Facing Dropper can move items to Hopper
			local hopper = hopper_exists and
					(node_name == "mesecons_dropper:dropper_up" and
					dropnode_name == "hopper:hopper") or
					(node_name == "mesecons_dropper:dropper_down" and
					dropnode_name == "hopper:hopper" or dropnode_name == "hopper:hopper_side")

			if not hopper then
				-- Do not drop into solid nodes
				local dropnodedef = minetest.registered_nodes[dropnode_name]
				if not dropnodedef or dropnodedef.walkable then
					return
				end
			end

			local stacks = {}
			for i = 1, inv:get_size("main") do
				local stack = inv:get_stack("main", i)
				if not stack:is_empty() then
					tinsert(stacks, {stack = stack, stackpos = i})
				end
			end

			if #stacks >= 1 then
				local r = random(1, #stacks)
				local stack = stacks[r].stack
				local dropitem = ItemStack(stack)
				dropitem:set_count(1)
				local stack_id = stacks[r].stackpos

				if hopper then
					-- Move to Hopper
					local hopper_inv = minetest.get_meta(droppos):get_inventory()
					if not hopper_inv or
							not hopper_inv:room_for_item("main", dropitem) then
						return
					end
					hopper_inv:add_item("main", dropitem)
				else
					-- Drop item
					minetest.add_item(droppos, dropitem)
				end
				stack:take_item()
				inv:set_stack("main", stack_id, stack)
			end
		end,

		rules = mesecon.rules.alldirs
	}}
}

local ttop = "default_furnace_top.png"
local tside = "default_furnace_side.png"

-- Horizontal dropper
local horizontal_def = tcopy(dropperdef)
horizontal_def.description = S("Dropper")
horizontal_def.after_place_node = function(pos, placer)
	setup_dropper(minetest.get_meta(pos))
	dropper_orientate(pos, placer)
end
horizontal_def.tiles = {
	ttop, ttop,
	tside, tside,
	tside, tside ..
		"^mesecons_dropper_front.png^mesecons_dropper_front_horizontal.png"
}
horizontal_def.paramtype2 = "facedir"
minetest.register_node("mesecons_dropper:dropper", horizontal_def)

-- Down dropper
local down_def = tcopy(dropperdef)
down_def.after_place_node = function(pos)
	setup_dropper(minetest.get_meta(pos))
end
down_def.tiles = {
	ttop, ttop .. "^mesecons_dropper_front_vertical.png",
	tside, tside,
	tside, tside
}
down_def.groups.not_in_creative_inventory = 1
down_def.drop = "mesecons_dropper:dropper"
minetest.register_node("mesecons_dropper:dropper_down", down_def)

-- Up dropper
local up_def = tcopy(down_def)
up_def.tiles = {
	ttop .. "^mesecons_dropper_front_vertical.png", ttop,
	tside, tside,
	tside, tside
}
minetest.register_node("mesecons_dropper:dropper_up", up_def)

minetest.register_craft({
	output = "mesecons_dropper:dropper",
	recipe = {
		{"default:cobble", "default:cobble", "default:cobble"},
		{"default:cobble", "bluestone:dust", "default:cobble"},
		{"default:cobble", "default:chest", "default:cobble"},
	}
})

if hopper_exists then
	hopper.add_container({
		{"bottom", "mesecons_dropper:dropper", "main"},
		{"side", "mesecons_dropper:dropper", "main"},
		{"bottom", "mesecons_dropper:dropper_down", "main"},
		{"side", "mesecons_dropper:dropper_down", "main"},
		{"side", "mesecons_dropper:dropper_up", "main"}
	})
end

-- LBM for updating Dropper
minetest.register_lbm({
	label = "Dropper updater",
	name = "mesecons_dropper:updater_v" .. VER,
	nodenames = "group:dropper",
	action = function(pos)
		local meta = minetest.get_meta(pos)
		if meta:get_string("version") == VER then return end
		setup_dropper(meta)
		meta:set_string("formspec", "")
		meta:set_string("owner", "")
	end
})
