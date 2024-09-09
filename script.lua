vehicle_count = property.slider("AI Count", 0, 50, 1, 25)

g_savedata =
{
show_markers = property.checkbox("Show hostile vessels on the map", true),
vehicles = {}
}

built_locations = {}
unique_locations = {}

local render_debug = false

local g_debug_vehicle_id = "0"

function onCreate(is_world_create)
    if is_world_create then

        for i in iterPlaylists() do
			for j in iterLocations(i) do
				build_locations(i, j)
			end
		end

	g_savedata.lt = 5000
	g_savedata.mt = 10000
	g_savedata.ht = 20000
	g_savedata.et = 30000

        server.announce("hostile_ai", "spawning " .. vehicle_count .. " ships")

        for i = 1, vehicle_count do

            local random_location_index = math.random(1, #built_locations)
            local location = built_locations[random_location_index]

            local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

            local spawn_transform, is_success =  server.getOceanTransform(random_transform, 1000, 10000)
            spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

            if is_success then
                local all_mission_objects = {}
                local spawned_objects = {
                    vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
                    survivors = spawnObjects(spawn_transform, location.playlist_index,location.location_index, location.objects.survivors, all_mission_objects),
                    objects = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.objects, all_mission_objects),
                    zones = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.zones, all_mission_objects)
                }

                g_savedata.vehicles[spawned_objects.vehicle.id] = {survivors = spawned_objects.survivors, destination = { x = 0, z = 0 }, path = {}, map_id = server.getMapID(), state = { s = "pseudo", timer = math.fmod(spawned_objects.vehicle.id, 300) }, bounds = location.objects.vehicle.bounds, size = spawned_objects.vehicle.size, current_damage = 0, despawn_timer = 0, ai_type = spawned_objects.vehicle.ai_type }
            end
        end

        for i = 1, #unique_locations do

            local location = unique_locations[i]

            local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

            local spawn_transform, is_success = server.getOceanTransform(random_transform, 1000, 10000)
            spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

            if is_success then
                local all_mission_objects = {}
                local spawned_objects = {
                    vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
                    survivors = spawnObjects(spawn_transform, location.playlist_index,location.location_index, location.objects.survivors, all_mission_objects),
                    objects = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.objects, all_mission_objects),
                    zones = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.zones, all_mission_objects)
                }

                g_savedata.vehicles[spawned_objects.vehicle.id] = {survivors = spawned_objects.survivors, destination = { x = 0, z = 0 },  path = {}, map_id = server.getMapID(), state = { s = "pseudo", timer = math.fmod(spawned_objects.vehicle.id, 300) }, bounds = location.objects.vehicle.bounds, size = spawned_objects.vehicle.size, current_damage = 0, despawn_timer = 0, ai_type = spawned_objects.vehicle.ai_type }
            end
        end
    else
        for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do

            if vehicle_object.path == nil then
                if createDestination(vehicle_id) then
                    vehicle_object.path = createPath(vehicle_id)
                end
            end

            if server.getVehicleSimulating(vehicle_id) then
                vehicle_object.state.s = "pathing"
            else
                vehicle_object.state.s = "pseudo"
            end
            if vehicle_object.bounds == nil then
                vehicle_object.bounds = { x_min = -40000, z_min = -40000, x_max = 40000, z_max = 140000}
            end
            if vehicle_object.current_damage == nil then vehicle_object.current_damage = 0 end
            if vehicle_object.despawn_timer == nil then vehicle_object.despawn_timer = 0 end
        end

    end
end

function build_locations(playlist_index, location_index)
    local location_data = server.getLocationData(playlist_index, location_index)

    local mission_objects =
    {
        vehicle = nil,
        survivors = {},
        objects = {},
        zones = {},
    }

    local is_valid = false
    local is_unique = false
    local bounds = { x_min = -40000, z_min = -40000, x_max = 40000, z_max = 140000}

    for object_index, object_data in iterObjects(playlist_index, location_index) do

        object_data.index = object_index

        -- investigate tags
        for tag_index, tag_object in pairs(object_data.tags) do
            if tag_object == "type=enemy_ai_boat" then
                is_valid = true
            elseif tag_object == "unique" then
                is_unique = true
            elseif string.find(tag_object, "x_min=") ~= nil then
                bounds.x_min = tonumber(string.sub(tag_object, 7))
            elseif string.find(tag_object, "z_min=") ~= nil then
                bounds.z_min = tonumber(string.sub(tag_object, 7))
            elseif string.find(tag_object, "x_max=") ~= nil then
                bounds.x_max = tonumber(string.sub(tag_object, 7))
            elseif string.find(tag_object, "z_max=") ~= nil then
                bounds.z_max = tonumber(string.sub(tag_object, 7))
            end
        end

        if object_data.type == "vehicle" then
            if mission_objects.vehicle == nil and hasTag(object_data.tags, "type=enemy_ai_boat") then
                mission_objects.vehicle = object_data
            end
        elseif object_data.type == "character" then
            table.insert(mission_objects.survivors, object_data)
        elseif object_data.type == "object" then
            table.insert(mission_objects.objects, object_data)
        elseif object_data.type == "zone" then
            table.insert(mission_objects.zones, object_data)
        end
    end

    if is_valid then
        if mission_objects.vehicle ~= nil and #mission_objects.survivors > 0 then

            mission_objects.vehicle.bounds = bounds

            if is_unique then
                table.insert(unique_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = mission_objects } )
            else
                table.insert(built_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = mission_objects } )
            end
        end
    end
end

function onVehicleUnload(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        vehicle_object.state.s = "pseudo"
    end

end

function onVehicleLoad(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        vehicle_object.state.s = "pathing"

        for npc_index, npc in pairs(vehicle_object.survivors) do
            local c = server.getCharacterData(npc.id)
            if c then
                server.setCharacterData(npc.id, c.hp, false, true)
                server.setCharacterSeated(npc.id, vehicle_id, c.name)
            end
        end
        refuel(vehicle_id)
		reload(vehicle_id)
    end

end

function createDestination(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]

    local random_transform = matrix.translation(math.random(vehicle_object.bounds.x_min, vehicle_object.bounds.x_max), 0, math.random(vehicle_object.bounds.z_min, vehicle_object.bounds.z_max))
    local target_pos, is_success = server.getOceanTransform(random_transform, 1000, 10000)

    if is_success == false then return false end

    local destination_pos = matrix.multiply(target_pos, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))
    local dest_x, dest_y, dest_z = matrix.position(destination_pos)

    vehicle_object.destination.x = dest_x
    vehicle_object.destination.z = dest_z

    return true
end

function createPath(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    local vehicle_pos = server.getVehiclePos(vehicle_id)

    local avoid_tags = "size=null"
    if vehicle_object.size == "large" then
        avoid_tags = "size=null,size=small,size=medium"
    end
    if vehicle_object.size == "medium" then
        avoid_tags = "size=null,size=small"
    end

    local path_list = server.pathfind(vehicle_pos, (matrix.translation(vehicle_object.destination.x, 50, vehicle_object.destination.z)), "ocean_path", avoid_tags)
    for path_index, path in pairs(path_list) do
        path.ui_id = server.getMapID()
    end

    if render_debug then
        if tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0) then
            if(#vehicle_object.path >= 1) then
                server.removeMapLine(0, vehicle_object.map_id)
                server.addMapLine(0, vehicle_object.map_id, vehicle_pos, matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z), 0.5, 0, 0, 255, 255)

                for i = 1, #vehicle_object.path - 1 do
                    local waypoint = vehicle_object.path[i]
                    local waypoint_next = vehicle_object.path[i + 1]

                    local waypoint_pos = matrix.translation(waypoint.x, waypoint.y, waypoint.z)
                    local waypoint_pos_next = matrix.translation(waypoint_next.x, waypoint_next.y, waypoint_next.z)

                    server.removeMapLine(0, waypoint.ui_id)
                    server.addMapLine(0, waypoint.ui_id, waypoint_pos, waypoint_pos_next, 0.5, 0, 0, 255, 255)
                end
            end
        end
    end

   return path_list
end

function onTick(tick_time)

    for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do

        if vehicle_object ~= nil then
            vehicle_object.state.timer = vehicle_object.state.timer + 1

            if vehicle_object.state.s == "pathing" then

                if #vehicle_object.path > 0 then

                    if vehicle_object.state.timer >= 300 then

                        vehicle_object.state.timer = 0

                        k1 = true

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_pos)
                        server.setAITarget(vehicle_object.survivors[1].id, (matrix.translation(vehicle_object.path[1].x, 0, vehicle_object.path[1].z)))
                        server.setAIState(vehicle_object.survivors[1].id, 1)

                        refuel(vehicle_id)
						reload(vehicle_id)

                        if distance < 100 then
                            table.remove(vehicle_object.path, 1)
                        end
                    end

                else
                    vehicle_object.state.s = "waiting"
                    server.setAIState(vehicle_object.survivors[1].id, 0)
                end

            elseif vehicle_object.state.s == "waiting" then

                local wait_time = 3600
                if vehicle_object.ai_type == "hospital" then wait_time = 3600 * 30 end

                if vehicle_object.state.timer >= wait_time then
                    vehicle_object.state.timer = 0

                    if render_debug then
                        for i = 1, #vehicle_object.path - 1 do
                            server.removeMapLine(0, vehicle_object.path[i].ui_id)
                        end
                    end

                    if createDestination(vehicle_id) then
                        vehicle_object.path = createPath(vehicle_id)

                        if server.getVehicleSimulating(vehicle_id) then
                            vehicle_object.state.s = "pathing"
                        else
                            vehicle_object.state.s = "pseudo"
                        end

                        refuel(vehicle_id)
						reload(vehicle_id)
                    end
                end

            elseif vehicle_object.state.s == "pseudo" then

                if vehicle_object.state.timer >= 900 then

                    vehicle_object.state.timer = 0

                    if #vehicle_object.path > 0 then
                        local vehicle_transform = server.getVehiclePos(vehicle_id)
                        local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_transform)

                        local speed = 60
                        local movement_x = vehicle_object.path[1].x - vehicle_x
                        local movement_z = vehicle_object.path[1].z - vehicle_z

                        local length_xz = math.sqrt((movement_x * movement_x) + (movement_z * movement_z))

                        movement_x = movement_x * speed / length_xz
                        movement_z = movement_z * speed / length_xz

                        local rotation_matrix = matrix.rotationToFaceXZ(movement_x, movement_z)
                        local new_pos = matrix.multiply(matrix.translation(vehicle_x + movement_x, 0, vehicle_z + movement_z), rotation_matrix)

                        if server.getVehicleLocal(vehicle_id) == false then
                            local vehicle_data = server.getVehicleData(vehicle_id)
                            local success, new_transform = server.moveGroupSafe(vehicle_data.group_id, new_pos)
                            for npc_index, npc_object in pairs(vehicle_object.survivors) do
                                server.setObjectPos(npc_object.id, new_transform)
                            end
                        end

                        local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_transform)
                        if distance < 100 then
                            table.remove(vehicle_object.path, 1)
                        end
                    else
                        vehicle_object.state.s = "waiting"
                        server.setAIState(vehicle_object.survivors[1].id, 0)
                    end
                end
            end
			
			local enemy_vehicle_hp = 4000
			marker_radius = 2000
			explosion_size = 0.6
			icon_r = 255
			icon_g = 255
			icon_b = 0
            if vehicle_object.size == "large" then
                enemy_vehicle_hp = 100000
				marker_radius = 2000
				explosion_size = 1.5
				icon_r = 255
				icon_g = 0
				icon_b = 0
			end
            if vehicle_object.size == "medium" then
                enemy_vehicle_hp = 10000
				marker_radius = 2000
				explosion_size = 1.0
				icon_r = 255
				icon_g = 125
				icon_b = 0
            end

            if g_savedata.show_markers then
				local vehicle_pos = server.getVehiclePos(vehicle_id)
                local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

                    server.removeMapObject(-1, vehicle_object.map_id)
                    server.addMapObject(-1, vehicle_object.map_id, 1, 18, v_x, v_z, 0, 0, vehicle_id, 0, "Hostile vessel sighted", marker_radius, "A " .. vehicle_object.size .. " sized vessel flying the flag of the Bungeling Empire has been spotted at this location, moving at high speed.", icon_r, icon_g, icon_b, 255)
             end
            			
            if render_debug then
                if tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0) then

                    local vehicle_pos = server.getVehiclePos(vehicle_id)
                    local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

                    local debug_data = vehicle_object.state.s .. " : " .. vehicle_object.state.timer .. "\n"

                    if vehicle_object.size then debug_data = debug_data .. "Size: " .. vehicle_object.size .. "\n" end
                    debug_data = debug_data .. "Pos: " .. math.floor(vehicle_x) .. "\n".. math.floor(vehicle_y) .. "\n".. math.floor(vehicle_z) .. "\n"

                    server.removeMapObject(0, vehicle_object.map_id)
                    server.addMapObject(0, vehicle_object.map_id, 1, 17, v_x, v_z, 0, 0, vehicle_id, 0, "Hostile AI Boat" .. vehicle_id, 2000, debug_data, icon_r, icon_g, icon_b, 255)
                end
            end

             if  vehicle_object.current_damage > enemy_vehicle_hp then
                vehicle_object.despawn_timer = vehicle_object.despawn_timer + 1
            end

            if vehicle_object.state.timer == 0 or (vehicle_object.despawn_timer > 60 * 60 * 2) then
                local vehicle_pos = server.getVehiclePos(vehicle_id)
                if vehicle_pos[14] < -22 or vehicle_object.despawn_timer > 2 * 1 * 1 then
				server.spawnExplosion(vehicle_pos, explosion_size)
				server.removeMapObject(0, vehicle_object.map_id)
				server.despawnVehicle(vehicle_id, true)
                    for _, survivor in pairs(vehicle_object.survivors) do
                        server.despawnObject(survivor.id, true)
                    end
                    g_savedata.vehicles[vehicle_id] = nil
                end
            end
        end
    end
end

function onVehicleDamaged(vehicle_id, amount, x, y, z, body_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
       vehicle_object.current_damage = vehicle_object.current_damage + amount
    end
end

function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, arg1, arg2, arg3, arg4)

	if peer_id == -1 then
		if command == "?hostile_ai_debug" and server.isDev() then
            render_debug = not render_debug

            if arg1 ~= nil then
                g_debug_vehicle_id = arg1
            else
                g_debug_vehicle_id = tostring(0)
            end

            for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do
                server.removeMapObject(0, vehicle_object.map_id)
                server.removeMapLine(0, vehicle_object.map_id)
                for i = 1, #vehicle_object.path - 1 do
                    server.removeMapLine(0, vehicle_object.path[i].ui_id)
                end

                if render_debug then
                    if tostring(vehicle_id) == g_debug_vehicle_id or g_debug_vehicle_id == tostring(0) then
                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        if(#vehicle_object.path >= 1) then
                            server.removeMapLine(0, vehicle_object.map_id)
                            server.addMapLine(0, vehicle_object.map_id, vehicle_pos, matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z), 0.5, 0, 0, 255, 255)
    
                            for i = 1, #vehicle_object.path - 1 do
                                local waypoint = vehicle_object.path[i]
                                local waypoint_next = vehicle_object.path[i + 1]
    
                                local waypoint_pos = matrix.translation(waypoint.x, waypoint.y, waypoint.z)
                                local waypoint_pos_next = matrix.translation(waypoint_next.x, waypoint_next.y, waypoint_next.z)
    
                                server.removeMapLine(0, waypoint.ui_id)
                                server.addMapLine(0, waypoint.ui_id, waypoint_pos, waypoint_pos_next, 0.5, 0, 0, 255, 255)
                            end
                        end
                    end
                end
            end
        end
    end
end

function refuel(vehicle_id)
    server.setVehicleTank(vehicle_id, "diesel1", 999, 1)
    server.setVehicleTank(vehicle_id, "diesel2", 999, 1)
    server.setVehicleBattery(vehicle_id, "battery1", 1)
end

function reload(vehicle_id)
	if render_debug then server.announce("decw", "reloaded: " .. vehicle_id) end
	for i=1, 15 do
		server.setVehicleWeapon(vehicle_id, "Ammo "..i, 999)
	end
end

function calculate_distance_to_next_waypoint(path_pos, vehicle_pos)
    local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

    local vector_x = path_pos.x - vehicle_x
    local vector_z = path_pos.z - vehicle_z

    return math.sqrt( (vector_x * vector_x) + (vector_z * vector_z))
end

function normalize_2d(x, z)
    local xz_length = math.sqrt((x * x) + (z * z))
    return x / xz_length, z / xz_length
end

function get_angle(ax, az, bx, bz)
    local dot = (ax * bx) + (az * bz)
    dot = math.min(1, math.max(dot, -1))
    local radians = math.acos(dot)
    local perpendicular_dot = (az * bx) + (-ax * bz)
    if perpendicular_dot > 0 then
        return radians
    else
        return -radians
    end
end

function spawnObjects(spawn_transform, playlist_index, location_index, object_descriptors, out_spawned_objects)
	local spawned_objects = {}

	for _, object in pairs(object_descriptors) do
		-- find parent vehicle id if set

		local parent_vehicle_id = 0
		if object.vehicle_parent_component_id > 0 then
			for spawned_object_id, spawned_object in pairs(out_spawned_objects) do
				if spawned_object.type == "vehicle" and spawned_object.component_id == object.vehicle_parent_component_id then
					parent_vehicle_id = spawned_object.id
				end
			end
		end

		spawnObject(spawn_transform, playlist_index, location_index, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
	end

	return spawned_objects
end

function spawnObject(spawn_transform, playlist_index, location_index, object, parent_vehicle_id, spawned_objects, out_spawned_objects)
	-- spawn object

	local spawned_object_id = spawnObjectType(matrix.multiply(spawn_transform, object.transform), playlist_index, location_index, object, parent_vehicle_id)

	-- add object to spawned object tables

	if spawned_object_id ~= nil and spawned_object_id ~= 0 then

        local l_size = "small"
		for tag_index, tag_object in pairs(object.tags) do
			if string.find(tag_object, "size=") ~= nil then
				l_size = string.sub(tag_object, 6)
			end
		end

        local l_ai_type = "default"
		if hasTag(object.tags, "capability=hospital") then
			l_ai_type = "hospital"
		end

		local object_data = { type = object.type, id = spawned_object_id, component_id = object.id, size = l_size, ai_type = l_ai_type }

		if spawned_objects ~= nil then
			table.insert(spawned_objects, object_data)
		end
        
		if out_spawned_objects ~= nil then
			table.insert(out_spawned_objects, object_data)
		end

		return object_data
	end

	return nil
end

-- spawn an individual object descriptor from a playlist location
function spawnObjectType(spawn_transform, playlist_index, location_index, object_descriptor, parent_vehicle_id)
	local component = server.spawnAddonComponent(spawn_transform, playlist_index, location_index, object_descriptor.index, parent_vehicle_id)
    if component.type == "vehicle" then
        return component.vehicle_ids[1]
    end
	return component.object_id
end

-- iterator function for iterating over all playlists, skipping any that return nil data
function iterPlaylists()
	local playlist_count = server.getAddonCount()
	local playlist_index = 0

	return function()
		local playlist_data = nil
		local index = playlist_count

		while playlist_data == nil and playlist_index < playlist_count do
			playlist_data = server.getAddonData(playlist_index)
			index = playlist_index
			playlist_index = playlist_index + 1
		end

		if playlist_data ~= nil then
			return index, playlist_data
		else
			return nil
		end
	end
end

-- iterator function for iterating over all locations in a playlist, skipping any that return nil data
function iterLocations(playlist_index)
	local playlist_data = server.getAddonData(playlist_index)
	local location_count = 0
	if playlist_data ~= nil then location_count = playlist_data.location_count end
	local location_index = 0

	return function()
		local location_data = nil
		local index = location_count

		while location_data == nil and location_index < location_count do
			location_data = server.getLocationData(playlist_index, location_index)
			index = location_index
			location_index = location_index + 1
		end

		if location_data ~= nil then
			return index, location_data
		else
			return nil
		end
	end
end

-- iterator function for iterating over all objects in a location, skipping any that return nil data
function iterObjects(playlist_index, location_index)
	local location_data = server.getLocationData(playlist_index, location_index)
	local object_count = 0
	if location_data ~= nil then object_count = location_data.component_count end
	local object_index = 0

	return function()
		local object_data = nil
		local index = object_count

		while object_data == nil and object_index < object_count do
			object_data = server.getLocationComponentData(playlist_index, location_index, object_index)
            object_data.index = object_index
			index = object_index
			object_index = object_index + 1
		end

		if object_data ~= nil then
			return index, object_data
		else
			return nil
		end
	end
end

function hasTag(tags, tag)
	for k, v in pairs(tags) do
		if v == tag then
			return true
		end
	end

	return false
end

function onVehicleDespawn(vehicle_id, peer_id)

    local vehicle_data = server.getVehicleData(vehicle_id)

    local threat_level = "none"
    for tag_index, tag_object in pairs(vehicle_data.tags) do
        if tag_object:find("threat=") ~= nil then
            threat_level = tag_object:gsub("threat=","")
        end
    end
    local reward_amount = 0
    if threat_level == "low" then
        reward_amount = g_savedata.lt
    elseif threat_level == "medium" then
        reward_amount = g_savedata.mt
		elseif threat_level == "high" then
        reward_amount = g_savedata.ht
    elseif threat_level == "extreme" then
        reward_amount = g_savedata.et
    end
	if reward_amount > 1 then
    server.notify(-1, "Enemy vessel destroyed", "Rewarded $ "..math.floor(reward_amount), 9)
    server.setCurrency(server.getCurrency() + reward_amount)
	end
end
