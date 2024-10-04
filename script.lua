

g_savedata =
{
    show_markers = property.checkbox("Show hostile vessels on the map", true),
    allow_missiles = property.checkbox("Allow hostile vessels with missiles", true),
    allow_submarines = property.checkbox("Allow hostile submarine vessels", true),
    vehicles = {},
    respawn_timer = 0,
    start_vehicle_count = property.slider("Initial AI count", 0, 50, 1, 25),
    max_vehicle_count = property.slider("Max AI count", 0, 50, 1, 25),
    victim_vehicles = {},
    max_vehicle_size = property.slider("Max AI vessel size (1-Small 2-Medium 3-Large)", 1, 3, 1, 3),
    respawn_frequency = property.slider("Respawn frequency (minutes)", 0, 60,1,30),
    hp_modifier = property.slider("AI hp modifier", 0.3,3,0.1,1.0)
}

local built_locations = {}
local unique_locations = {}

local tick_counter = 0

local friendly_frequency = 999

function onCreate(is_world_create)
    for i in iterPlaylists() do
        for j in iterLocations(i) do
            build_locations(i, j)
        end
    end
    if is_world_create then
        server.announce("hostile_ai", "spawning " .. math.min(g_savedata.start_vehicle_count,g_savedata.max_vehicle_count) .. " ships")
        for _ = 1, math.min(g_savedata.start_vehicle_count,g_savedata.max_vehicle_count) do

            local location = getRandomLocation()

            local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

            local spawn_transform, is_success =  server.getOceanTransform(random_transform, 1000, 10000)
            spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

            if is_success then
                spawnVehicle(location, spawn_transform)
            end
        end
    else
        for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do
            local vehicle_data,success = server.getVehicleData(vehicle_id)
            if g_savedata.allow_missiles == nil then g_savedata.allow_missiles = true end
            if g_savedata.allow_submarines == nil then g_savedata.allow_submarines = true end
            if g_savedata.show_markers == nil then g_savedata.show_markers = true end
            if g_savedata.max_vehicle_count == nil then g_savedata.max_vehicle_count = 25 end
            if g_savedata.respawn_frequency == nil then g_savedata.respawn_frequency = 5 end
            if g_savedata.max_vehicle_size == nil then g_savedata.max_vehicle_size = 3 end
            if g_savedata.hp_modifier == nil then g_savedata.hp_modifier = 1 end
            if not success then
                server.announce("hostile_ai","failed to get vehicle data when initiating")
                vehicle_data = nil
            end
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
            if vehicle_data ~= nil then
                if vehicle_object.reward == nil then
                    setReward(vehicle_id, vehicle_data)
                end
                setAIType(vehicle_id, vehicle_data)
                setSizeData(vehicle_id,vehicle_data)
            end

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
        for _, tag_object in pairs(object_data.tags) do
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

    removeVictim(vehicle_id)
end

function onPlayerSit(peer_id, vehicle_id, seat_name)
    local transform,success = server.getVehiclePos(vehicle_id)
    if success then
        --successful got position of the vehicle
        local x,y,z = matrix.position(transform)
        addVictim(vehicle_id,peer_id,x,y,z)
    end
end

function onVehicleLoad(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        vehicle_object.state.s = "pathing"

        for _, npc in pairs(vehicle_object.survivors) do
            local c = server.getCharacterData(npc.id)
            if c then
                server.setCharacterData(npc.id, c.hp, false, true)
                server.setCharacterSeated(npc.id, vehicle_id, c.name)
            end
        end
        refuel(vehicle_id)
        reload(vehicle_id)
    end
    --check if vehicle loaded is registered as a victim
    if g_savedata.victim_vehicles[vehicle_id] ~= nil then
        g_savedata.victim_vehicles[vehicle_id].transform = server.getVehiclePos(vehicle_id)
    else
        --if not a victim check it can be
        local transform,success = server.getVehiclePos(vehicle_id)
        if success then
            --successful got position of the vehicle
            local x,y,z = matrix.position(transform)
            addVictim(vehicle_id,-1,x,y,z)
        end
    end

end

function createCombatDestination(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object.target == nil then
        return false
    end
    local target_transform, target_success = server.getVehiclePos(vehicle_object.target)
    if not target_success then
        server.announce("hostile_ai", "failed to find target transform")
        return false
    end

    local vehicle_transform, vehicle_success = server.getVehiclePos(vehicle_id)
    if not vehicle_success then
        server.announce("hostile_ai", "failed to find target transform")
        return false
    end
    local target_x,_,target_z = matrix.position(target_transform)
    local vehicle_x, _, vehicle_z = matrix.position(vehicle_transform)
    local orbit_direction = (vehicle_id % 2) * 2 - 1
    local orbit_rotation = matrix.rotationY(math.rad(45)*orbit_direction)
    local delta_x = vehicle_x - target_x
    local delta_z = vehicle_z - target_z
    local distance = math.sqrt(delta_x^2 + delta_z^2)
    delta_x = delta_x / distance * vehicle_object.orbit_radius
    delta_z = delta_z / distance * vehicle_object.orbit_radius
    local orbit_offset = matrix.multiply(orbit_rotation, matrix.translation(delta_x,0,delta_z))
    local offset_x,_,offset_z = matrix.position(orbit_offset)

    vehicle_object.destination.x = target_x + offset_x + math.random(-20, 20)
    vehicle_object.destination.z = target_z + offset_z + math.random(-20, 20)

    return true
end

function createDestination(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]

    local random_transform = matrix.translation(math.random(vehicle_object.bounds.x_min, vehicle_object.bounds.x_max), 0, math.random(vehicle_object.bounds.z_min, vehicle_object.bounds.z_max))
    local target_pos, is_success = server.getOceanTransform(random_transform, 1000, 10000)

    if is_success == false then return false end

    local destination_pos = matrix.multiply(target_pos, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))
    local dest_x, _, dest_z = matrix.position(destination_pos)

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
    for _, path in pairs(path_list) do
        path.ui_id = server.getMapID()
    end

    return path_list
end

function updateVehicles()
    local vehicles = g_savedata.vehicles
    local victim_vehicles = g_savedata.victim_vehicles
    local update_rate = 60 * 2
    for vehicle_id, vehicle_object in pairs(vehicles) do

        if vehicle_object ~= nil and isTickID(vehicle_id, update_rate) then
            vehicle_object.state.timer = vehicle_object.state.timer + update_rate
            local in_combat = vehicle_object.state.s == "combat"
            local hp = vehicle_object.hp
            if g_savedata.hp_modifier ~= nil and g_savedata.hp_modifier > 0 then
                hp = hp * g_savedata.hp_modifier
            end
            local too_damaged = vehicle_object.current_damage > hp * 0.75
            if vehicle_object.state.s == "pathing" or in_combat then

                if #vehicle_object.path > 0 then

                    if isTickID(vehicle_id, update_rate*2) or in_combat then

                        local vehicle_pos = server.getVehiclePos(vehicle_id)
                        local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_pos)
                        server.setAITarget(vehicle_object.survivors[1].id, (matrix.translation(vehicle_object.path[1].x, 0, vehicle_object.path[1].z)))
                        server.setAIState(vehicle_object.survivors[1].id, 1)

                        refuel(vehicle_id)
                        reload(vehicle_id)

                        if distance < 100 then
                            vehicle_object.state.timer = 0
                            table.remove(vehicle_object.path, 1)
                        end
                    end
                else
                    server.setAIState(vehicle_object.survivors[1].id, 0)
                    --keep orbiting if is in combat and not too damaged
                    if in_combat and vehicle_object.target ~= nil and not too_damaged then
                        server.setAIState(vehicle_object.survivors[1].id, 0)
                        if createCombatDestination(vehicle_id) then
                            vehicle_object.path = createPath(vehicle_id)
                            if server.getVehicleSimulating(vehicle_id) then
                                vehicle_object.state.s = "combat"
                            else
                                vehicle_object.state.s = "pseudo"
                            end

                            refuel(vehicle_id)
                            reload(vehicle_id)
                        end
                    else
                        vehicle_object.state.s = "waiting"
                    end
                end

            elseif vehicle_object.state.s == "waiting" then

                local wait_time = 60 * 60 * 1
                --either waited enough or fleeing because took too much damage
                if vehicle_object.state.timer >= wait_time or too_damaged then
                    vehicle_object.state.timer = 0
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

                if vehicle_object.state.timer >= 60 * 15 then

                    vehicle_object.state.timer = 0

                    if #vehicle_object.path > 0 then
                        local vehicle_transform = server.getVehiclePos(vehicle_id)
                        local vehicle_x, _, vehicle_z = matrix.position(vehicle_transform)

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
                            for _, npc_object in pairs(vehicle_object.survivors) do
                                server.setObjectPos(npc_object.id, new_transform)
                            end
                        end

                        local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_transform)
                        if distance < 50 then
                            table.remove(vehicle_object.path, 1)
                        end
                    else
                        vehicle_object.state.s = "waiting"
                        server.setAIState(vehicle_object.survivors[1].id, 0)
                    end
                end
            end



            if g_savedata.show_markers then
                server.removeMapObject(-1, vehicle_object.map_id)
                server.addMapObject(-1, vehicle_object.map_id, 1, 18, 0, 0, 0, 0, vehicle_id, 0, "Hostile vessel sighted", vehicle_object.vision_radius, "A " .. vehicle_object.size .. " sized vessel flying the flag of the Bungeling Empire has been spotted at this location, moving at high speed. ", vehicle_object.icon_colour[1], vehicle_object.icon_colour[2], vehicle_object.icon_colour[3], 255)
            end
            if vehicle_object.state.s ~= "pseudo" then
                --find nearest victim vehicle in range
                local nearest_victim_id = -1
                local nearest_distance = 3000
                for victim_vehicle_id, victim_vehicle in pairs(victim_vehicles) do
                    local vehicle_pos, success = server.getVehiclePos(vehicle_id)
                    if victim_vehicle ~= nil and success then
                        if inGreedyBoxRange(victim_vehicle.transform, vehicle_pos, 3000) then
                            local distance = manhattanDistance(victim_vehicle.transform, vehicle_pos)
                            if distance < nearest_distance then
                                nearest_victim_id = victim_vehicle_id
                                nearest_distance = distance
                            end
                        end
                    end
                end
                if not g_savedata.show_markers then
                    if nearest_victim_id ~= -1 then
                        victim_vehicles[nearest_victim_id].targeted = true
                    end
                end
                if nearest_victim_id ~= -1 then
                    if not in_combat and not too_damaged then
                        --engage the victim vehicle
                        vehicle_object.path = {}
                        vehicle_object.target = nearest_victim_id
                        vehicle_object.state.s = "combat"
                    end
                else
                    vehicle_object.state.s = "pathing"
                end
                --find gunner npc
                for _, npc_object in pairs(vehicle_object.survivors) do
                    local npc_data = server.getCharacterData(npc_object.id)
                    if npc_data then
                        --check npc name contains "Gunner"
                        if npc_data.name:find("Gunner") then
                            --check there is a victim in range
                            if nearest_victim_id ~= -1 then
                                --set ai to track and fire
                                server.setAIState(npc_object.id, 1)
                                server.setAITargetVehicle(npc_object.id, nearest_victim_id)
                                vehicle_object.target = nearest_victim_id
                            else
                                --set ai to idle
                                server.setAIState(npc_object.id, 0)
                                server.setAITargetVehicle(npc_object.id, -1)
                                vehicle_object.target = nil
                            end
                        end
                    end
                end
            end

            if vehicle_object.current_damage > hp then
                vehicle_object.despawn_timer = vehicle_object.despawn_timer + 1
            end

            if vehicle_object.state.timer == 0 or (vehicle_object.despawn_timer > 60 * 2) then
                local vehicle_pos = server.getVehiclePos(vehicle_id)
                local crush_depth = -22
                if vehicle_object.ai_type == "submarine" then
                    crush_depth = -100
                end
                if vehicle_pos[14] < crush_depth or vehicle_object.despawn_timer > 0 then
                    server.despawnVehicle(vehicle_id, true) --clean up code moved further down the line for instantly destroyed vehicle
                end
            end
        end
    end
end

function trackVictims()
    local victim_vehicles = g_savedata.victim_vehicles
    --track position of victim vehicles
    for victim_vehicle_id, victim_vehicle in pairs(victim_vehicles) do
        --update every 5 seconds
        if victim_vehicle ~= nil and isTickID(victim_vehicle_id, 60*5) then
            victim_vehicle.transform = server.getVehiclePos(victim_vehicle_id)
            if not g_savedata.show_markers then
                if victim_vehicle.targeted then
                    server.removeMapID(-1, victim_vehicle.map_id)
                    server.addMapObject(-1, victim_vehicle.map_id, 1, 19, v_x, v_z, 0, 0, victim_vehicle_id, 0, "Under Attack",500,"A Mayday has been received from a civilian ship or aircraft claiming to be under attack by a hostile vessel.", 255,0,0, 255)
                    victim_vehicle.targeted = false
                else
                    server.removeMapID(-1, victim_vehicle.map_id)
                end
            end
        end
    end

end

function changeFriendlyFrequency()
    local vehicles = g_savedata.vehicles
    --change every 6 seconds
    if isTickID(0, 60 * 6) then
        friendly_frequency = math.random(100,999)
        for vehicle_id, _ in pairs(vehicles) do
            server.setVehicleKeypad(vehicle_id, "friendly frequency", friendly_frequency)
        end
    end
end

function onTick(tick_time)
    updateVehicles()
    trackVictims()
    respawnLosses(false)
    changeFriendlyFrequency()
    tick_counter = tick_counter + 1
end

function onVehicleDamaged(vehicle_id, amount, x, y, z, body_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        vehicle_object.current_damage = vehicle_object.current_damage + amount
    end
end

function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, arg1, arg2, arg3, arg4)
    if command == "?hostile_ai_respawn" then
        local result = respawnLosses(true)
        server.announce("hostile ai", "result (successful:vehicle id/failed:-1):"..tostring(result))
    end
    if command == "?hostile_ai_settings" then
        if arg1 ~= nil or arg2 ~= nil then
            setting_name = arg1
            new_value = arg2
            if setting_name == "allow_missiles" then
                g_savedata.allow_missiles = new_value == "true"
            elseif setting_name == "show_markers" then
                g_savedata.show_markers = new_value == "true"
            elseif setting_name == "max_vehicle_count" then
                g_savedata.max_vehicle_count = tonumber(new_value)
            elseif setting_name == "respawn_frequency" then
                g_savedata.respawn_frequency = tonumber(new_value)
            elseif setting_name == "max_vehicle_size" then
                g_savedata.max_vehicle_size = tonumber(new_value)
            elseif setting_name == "allow_submarines" then
                g_savedata.allow_submarines = new_value == "true"
            elseif setting_name == "hp_modifier" then
                g_savedata.hp_modifier = tonumber(new_value)
            end
        else
            server.announce("hostile_ai", "?hostile_ai_settings setting_name new_value")
        end
        server.announce("hostile ai", "allow_missiles:"..tostring(g_savedata.allow_missiles))
        server.announce("hostile ai", "allow_submarines:"..tostring(g_savedata.allow_submarines))
        server.announce("hostile ai", "show_markers:"..tostring(g_savedata.show_markers))
        server.announce("hostile_ai", "max_vehicle_count:"..tostring(g_savedata.max_vehicle_count))
        server.announce("hostile_ai", "respawn_frequency:"..tostring(g_savedata.respawn_frequency))
        server.announce("hostile_ai", "max_vehicle_size:"..tostring(g_savedata.max_vehicle_size))
        server.announce("hostile_ai", "hp_modifier:"..tostring(g_savedata.hp_modifier))
    end
    if command == "?hostile_ai_clear" then
        for vehicle_id, _ in pairs(g_savedata.vehicles) do
            server.despawnVehicle(vehicle_id, true)
        end
    end
end

function refuel(vehicle_id)
    server.setVehicleTank(vehicle_id, "diesel1", 999, 1)
    server.setVehicleTank(vehicle_id, "diesel2", 999, 1)
    server.setVehicleBattery(vehicle_id, "battery1", 1)
    server.setVehicleBattery(vehicle_id, "battery2", 1)
end

function reload(vehicle_id)
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
        for _, tag_object in pairs(object.tags) do
            if string.find(tag_object, "size=") ~= nil then
                l_size = string.sub(tag_object, 6)
            end
        end

        local object_data = {
            type = object.type,
            id = spawned_object_id,
            component_id = object.id,
            size = l_size
        }

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
        local playlist_data
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
        local location_data
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
        local object_data
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
    for _, v in pairs(tags) do
        if v == tag then
            return true
        end
    end

    return false
end

function killReward(vehicle_id)
    if g_savedata.vehicles[vehicle_id] == nil then
        return
    end

    local reward_amount = g_savedata.vehicles[vehicle_id].reward
    if reward_amount > 0 then
        server.notify(-1, "Enemy vessel destroyed", "Rewarded $ "..math.floor(reward_amount), 9)
        server.setCurrency(server.getCurrency() + reward_amount)
    end
end

function onVehicleDespawn(vehicle_id, peer_id)
    removeVictim(vehicle_id)

    killReward(vehicle_id)
    cleanupVehicle(vehicle_id)
end

function respawnLosses(instant)
    --count current number of vehicles
    local vehicle_count = 0
    for _ in pairs(g_savedata.vehicles) do
        vehicle_count = vehicle_count + 1
    end
    --check if the limit is reached
    if vehicle_count >= g_savedata.max_vehicle_count then
        return -1
    end
    --update timer
    g_savedata.respawn_timer = g_savedata.respawn_timer + 1
    --check if timer has finished
    if g_savedata.respawn_timer > g_savedata.respawn_frequency * 60 * 60 or instant then
        --reset timer
        g_savedata.respawn_timer = 0

        --get random vehicle (a location in the playlist corresponds to a vehicle)
        local location = getRandomLocation()

        if location == nil then
            return -1
        end

        --get random player position
        local players = server.getPlayers()
        local random_player = players[math.random(1, #players)]
        local random_player_transform = server.getPlayerPos(random_player.id)

        --find random ocean tile near that player (10k-40k range)
        local spawn_transform, is_success =  server.getOceanTransform(random_player_transform, 10000, 40000)
        --put the vehicle randomly in the tile
        spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

        if is_success then
            return spawnVehicle(location,spawn_transform)
        end
        return -1
    end
end

function cleanupVehicle(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object == nil then
        return
    end
    g_savedata.vehicles[vehicle_id] = nil

    local vehicle_pos = server.getVehiclePos(vehicle_id)
    server.spawnExplosion(vehicle_pos, vehicle_object.explosion_size)

    server.removeMapObject(-1, vehicle_object.map_id)
    for _, survivor in pairs(vehicle_object.survivors) do
        server.despawnObject(survivor.id, true)
    end
end

function addVictim(vehicle_id,peer_id, x,y,z)
    if peer_id ~= -1 then
        g_savedata.victim_vehicles[vehicle_id] = {
            transform = matrix.translation(x,y,z),
            map_id = server.getMapID(),
        }
        return
    end

    local vehicle_data, success = server.getVehicleData(vehicle_id)
    if not success then
        return
    end
    --just in case some other addon adds invulnerable ai vehicle we don't want to attack those
    if vehicle_data.invulnerable then
        return
    end
    --filter only ai vehicles
    if hasTag(vehicle_data.tags,"type=ai_boat") or hasTag(vehicle_data.tags,"type=ai_plane") or hasTag(vehicle_data.tags,"type=ai_heli") then
        --ignore hostile boats or midair refuel planes
        if (hasTag(vehicle_data.tags,"unique")) then
            return
        end

        g_savedata.victim_vehicles[vehicle_id] = {
            transform = matrix.translation(x,y,z),
            map_id = server.getMapID(),
        }
        return
    end
end

function removeVictim(vehicle_id)
    if g_savedata.victim_vehicles[vehicle_id] ~= nil then
        server.removeMapID(-1, g_savedata.victim_vehicles[vehicle_id].map_id)
        g_savedata.victim_vehicles[vehicle_id] = nil
    end
end

function onVehicleSpawn(vehicle_id, peer_id, x, y, z, cost)
    addVictim(vehicle_id,peer_id,x,y,z)
end

function getRandomLocation()
    local tries = 0
    while tries < 10 do
        --getting a random location, built_location must be contiguous
        local random_location_index = math.random(1, #built_locations)
        local location = built_locations[random_location_index]

        local tags = location.objects.vehicle.tags
        --using an boolean flag here to avoid messy nested if statements when more checks are added
        local allowed = true
        --check if it has missiles and missiles are allowed
        if hasTag(tags,"missiles") and not g_savedata.allow_missiles then
            allowed = false
        end

        if hasTag(tags,"size=medium") and g_savedata.max_vehicle_size < 2 then
            allowed = false
        end

        if hasTag(tags,"size=large") and g_savedata.max_vehicle_size < 3 then
            allowed = false
        end

        if hasTag(tags, "submarine") and not g_savedata.allow_submarines then
            allowed = false
        end

        if allowed then
            return location
        end
        tries = tries + 1
    end
    server.announce("hostile_ai","failed to find a suitable vehicle to deploy")
    return nil
end

function isTickID(id, rate)
    return (tick_counter + id) % rate == 0
end

function inGreedyBoxRange(transform_a, transform_b, radius)
    local x_a,y_a,z_a = matrix.position(transform_a)
    local x_b,y_b,z_b = matrix.position(transform_b)
    local dx = x_b - x_a
    if dx < -radius or dx > radius then
        return false
    end
    local dy = y_b - y_a
    if dy < -radius or dy > radius then
        return false
    end
    local dz = z_b - z_a
    if dz < -radius or dz > radius then
        return false
    end
    return true
end

function manhattanDistance(transform_a, transform_b)
    local x_a,y_a,z_a = matrix.position(transform_a)
    local x_b,y_b,z_b = matrix.position(transform_b)
    return math.abs(x_b-x_a) + math.abs(y_b-y_a) + math.abs(z_b-z_a)
end

function spawnVehicle(location, spawn_transform)
    --spawn vehicle and every object attached to it
    local all_mission_objects = {}
    local spawned_objects = {
        vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
        survivors = spawnObjects(spawn_transform, location.playlist_index,location.location_index, location.objects.survivors, all_mission_objects),
        objects = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.objects, all_mission_objects),
        zones = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.zones, all_mission_objects)
    }
    local vehicle_id = spawned_objects.vehicle.id

    --store the vehicle data into our table
    g_savedata.vehicles[vehicle_id] = {
        survivors = spawned_objects.survivors,
        destination = { x = 0, z = 0 },
        path = {},
        map_id = server.getMapID(),
        state = {
            s = "pseudo",
            timer = math.fmod(spawned_objects.vehicle.id, 300)
        },
        bounds = location.objects.vehicle.bounds,
        size = spawned_objects.vehicle.size,
        current_damage = 0,
        despawn_timer = 0,
        ai_type = spawned_objects.vehicle.ai_type
    }
    local vehicle_data,success = server.getVehicleData(vehicle_id)
    if not success then
        server.announce("hostile_ai","failed to get vehicle data when spawning")
    else
        setReward(vehicle_id, vehicle_data)
        setAIType(vehicle_id, vehicle_data)
        setSizeData(vehicle_id, vehicle_data)
    end
    return vehicle_id
end

function setReward(vehicle_id,vehicle_data)
    local threat_level = "none"
    for _, tag_object in pairs(vehicle_data.tags) do
        if tag_object:find("threat=") ~= nil then
            threat_level = tag_object:gsub("threat=","")
        end
    end
    local threat_to_reward = {
        ["low"] = 5000,
        ["medium"] = 10000,
        ["high"] = 20000,
        ["extreme"] = 30000
    }
    g_savedata.vehicles[vehicle_id].reward = threat_to_reward[threat_level]
end

function setAIType(vehicle_id, vehicle_data)
    local _ai_type = "default"
    for _, tag_object in pairs(vehicle_data.tags) do
        if tag_object == "submarine" then
            _ai_type = "submarine"
        end
    end
    g_savedata.vehicles[vehicle_id].ai_type = _ai_type
end

function setSizeData(vehicle_id, vehicle_data)
    --set vehicle data that depends on the size
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        if vehicle_object.size == "small" then
            vehicle_object.hp = 4000
            vehicle_object.vision_radius = 2000
            vehicle_object.orbit_radius = 500
            vehicle_object.explosion_size = 0.6
            vehicle_object.icon_colour = {255,255,0}
        elseif vehicle_object.size == "medium" then
            vehicle_object.hp = 10000
            vehicle_object.vision_radius = 2000
            vehicle_object.orbit_radius = 750
            vehicle_object.explosion_size = 1.0
            vehicle_object.icon_colour = {255,125,0}
        elseif vehicle_object.size == "large" then
            vehicle_object.hp = 100000
            vehicle_object.vision_radius = 2000
            vehicle_object.orbit_radius = 1000
            vehicle_object.explosion_size = 1.5
            vehicle_object.icon_colour = {255,0,0}
        else
            server.announce("hostile_ai","unexpected vehicle size")
        end
        g_savedata[vehicle_id] = vehicle_object
    end
end