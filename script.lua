g_savedata = {
    show_markers = property.checkbox("Show hostile vessels on the map", true),
    allow_missiles = property.checkbox("Allow hostile vessels with missiles", true),
    allow_submarines = property.checkbox("Allow hostile submarines", true),
    allow_helis = property.checkbox("Allow hostile aircraft", true),
    vehicles = {},
    respawn_timer = 0,
    start_vehicle_count = property.slider("Initial AI count", 0, 50, 1, 25),
    max_vehicle_count = property.slider("Max AI count", 0, 50, 1, 25),
    victim_vehicles = {},
    max_vehicle_size = property.slider("Max AI vessel size (1-Small 2-Medium 3-Large)", 1, 3, 1, 3),
    respawn_frequency = property.slider("Respawn frequency (minutes)", 0, 60, 1, 30),
    hp_modifier = property.slider("AI HP modifier", 0.3, 3, 0.1, 1.0)
}

local built_locations = {}
local unique_locations = {}

local victim_search_table = {}
local search_table_tile_size = 1600

local tick_counter = 0

local debug_mode = true
local time_multiplier = 1

local friendly_frequency = 999

local TYPE_HELICOPTER = "helicopter"
local TYPE_VESSEL = "vessel"
local TYPE_SUBMARINE = "submarine"

local STATE_COMBAT = "combat"
local STATE_PATHING = "pathing"
local STATE_WAITING = "waiting"
local STATE_PSEUDO = "pseudo"

function onCreate(is_world_create)
    for i in iterPlaylists() do
        for j in iterLocations(i) do
            build_locations(i, j)
        end
    end
    if is_world_create then
        announce("spawning " .. math.min(g_savedata.start_vehicle_count, g_savedata.max_vehicle_count) .. " ships")
        for _ = 1, math.min(g_savedata.start_vehicle_count, g_savedata.max_vehicle_count) do

            local location = getRandomLocation()

            local random_transform = matrix.translation(math.random(location.objects.vehicle.bounds.x_min, location.objects.vehicle.bounds.x_max), 0, math.random(location.objects.vehicle.bounds.z_min, location.objects.vehicle.bounds.z_max))

            local spawn_transform, is_success = server.getOceanTransform(random_transform, 1000, 10000)
            spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

            if is_success then
                spawnVehicle(location, spawn_transform)
            end
        end
    else
        for vehicle_id, vehicle_object in pairs(g_savedata.vehicles) do
            local vehicle_data, success = server.getVehicleData(vehicle_id)
            g_savedata.allow_missiles = g_savedata.allow_missiles or true
            g_savedata.allow_submarines = g_savedata.allow_submarines or true
            g_savedata.allow_helis = g_savedata.allow_helis or true
            g_savedata.show_markers = g_savedata.show_markers or true
            g_savedata.max_vehicle_count = g_savedata.max_vehicle_count or 25
            g_savedata.respawn_frequency = g_savedata.respawn_frequency or 5
            g_savedata.max_vehicle_size = g_savedata.max_vehicle_size or 3
            g_savedata.hp_modifier = g_savedata.hp_modifier or 1
            if not success then
                log("failed to get vehicle data when initiating")
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
                vehicle_object.bounds = { x_min = -40000, z_min = -40000, x_max = 40000, z_max = 140000 }
            end
            if vehicle_object.current_damage == nil then
                vehicle_object.current_damage = 0
            end
            if vehicle_object.despawn_timer == nil then
                vehicle_object.despawn_timer = 0
            end
            if vehicle_data ~= nil then
                if vehicle_object.reward == nil then
                    setReward(vehicle_id, vehicle_data)
                end
                setAIType(vehicle_id, vehicle_data)
                --setAltitude(vehicle_id)
                setSizeData(vehicle_id)
                setNPCRoles(vehicle_id)
            end

        end
    end
end

function build_locations(playlist_index, location_index)
    local location_data = server.getLocationData(playlist_index, location_index)

    local mission_objects = {
        vehicle = nil,
        survivors = {},
        objects = {},
        zones = {},
    }

    local is_valid = false
    local is_unique = false
    local bounds = { x_min = -40000, z_min = -40000, x_max = 40000, z_max = 140000 }

    for object_index, object_data in iterObjects(playlist_index, location_index) do

        object_data.index = object_index

        -- investigate tags
        for _, tag_object in pairs(object_data.tags) do
            if tag_object == "type=enemy_ai_boat" then
                is_valid = true
            elseif tag_object == "type=enemy_ai_heli" then
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
            if mission_objects.vehicle == nil and is_valid then
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
                table.insert(unique_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = mission_objects })
            else
                table.insert(built_locations, { playlist_index = playlist_index, location_index = location_index, data = location_data, objects = mission_objects })
            end
        end
    end
end

function onVehicleUnload(vehicle_id)
    setVehicleToPseudo(vehicle_id)

    --removeVictim(vehicle_id)
end

function onPlayerSit(peer_id, vehicle_id, seat_name)
    addVictim(vehicle_id, peer_id)
end

function onVehicleLoad(vehicle_id)

    setAltitude(vehicle_id)
    setNPCRoles(vehicle_id)
    setNPCSeats(vehicle_id)
    setVehicleToPathing(vehicle_id)

    --check if vehicle loaded is registered as a victim
    if g_savedata.victim_vehicles[vehicle_id] ~= nil then
        local vehicle_pos,success = server.getVehiclePos(vehicle_id)
        if success then
            g_savedata.victim_vehicles[vehicle_id].transform = vehicle_pos
        end
        insertToSearchTable(vehicle_id)
    else
        --if not a victim try make it one
        addVictim(vehicle_id, -1)
    end

end

function createCombatDestination(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object.target == nil then
        return false
    end
    local target_transform, target_success = server.getVehiclePos(vehicle_object.target)
    if not target_success then
        log("failed to find target transform")
        return false
    end

    local vehicle_transform, vehicle_success = server.getVehiclePos(vehicle_id)
    if not vehicle_success then
        log("failed to find self transform")
        return false
    end
    local gun_run = false
    if vehicle_object.ai_type == TYPE_HELICOPTER then
        gun_run = math.random() < 0.5
        vehicle_object.state.gun_run = gun_run
    end
    if gun_run then
        local target_x, target_y, target_z = matrix.position(target_transform)
        vehicle_object.destination.x = target_x
        vehicle_object.destination.y = target_y
        vehicle_object.destination.z = target_z

        return true
    else
        local target_x, _, target_z = matrix.position(target_transform)
        local vehicle_x, _, vehicle_z = matrix.position(vehicle_transform)
        local orbit_direction = (vehicle_id % 2) * 2 - 1
        local orbit_rotation = matrix.rotationY(math.rad(45) * orbit_direction)
        local delta_x = vehicle_x - target_x
        local delta_z = vehicle_z - target_z
        local distance = math.sqrt(delta_x ^ 2 + delta_z ^ 2)
        delta_x = delta_x / distance * vehicle_object.orbit_radius
        delta_z = delta_z / distance * vehicle_object.orbit_radius
        local orbit_offset = matrix.multiply(orbit_rotation, matrix.translation(delta_x, 0, delta_z))
        local offset_x, _, offset_z = matrix.position(orbit_offset)

        vehicle_object.destination.x = target_x + offset_x + math.random(-20, 20)
        vehicle_object.destination.y = getCruiseAltitude(vehicle_id)
        vehicle_object.destination.z = target_z + offset_z + math.random(-20, 20)

        return true
    end
end

function createDestination(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]

    local random_transform = matrix.translation(math.random(vehicle_object.bounds.x_min, vehicle_object.bounds.x_max), 0, math.random(vehicle_object.bounds.z_min, vehicle_object.bounds.z_max))
    local target_pos, is_success = server.getOceanTransform(random_transform, 1000, 10000)

    if is_success == false then
        return false
    end

    local destination_pos = matrix.multiply(target_pos, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))
    local dest_x, _, dest_z = matrix.position(destination_pos)

    vehicle_object.destination.x = dest_x
    vehicle_object.destination.z = dest_z

    return true
end

function createPath(vehicle_id)

    local vehicle_object = g_savedata.vehicles[vehicle_id]
    local vehicle_pos = server.getVehiclePos(vehicle_id)
    if #vehicle_object.path >= 0 then
        for i = 1, #vehicle_object.path do
            local path = vehicle_object.path[i]
            server.removeMapLine(-1, path.ui_id)
        end
    end
    local path_list = {}
    if vehicle_object.ai_type == TYPE_HELICOPTER then
        path_list[1] = { x = vehicle_object.destination.x,
                         y = vehicle_object.destination.y,
                         z = vehicle_object.destination.z,
                         ui_id = server.getMapID() }
    else
        local avoid_tags = "size=null"
        if vehicle_object.size == "large" then
            avoid_tags = "size=null,size=small,size=medium"
        end
        if vehicle_object.size == "medium" then
            avoid_tags = "size=null,size=small"
        end

        path_list = server.pathfind(vehicle_pos, (matrix.translation(vehicle_object.destination.x, 50, vehicle_object.destination.z)), "ocean_path", avoid_tags)
        for _, path in pairs(path_list) do
            path.ui_id = server.getMapID()
        end
    end
    return path_list
end

function updateVehicleInCombat(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    if vehicle_object.target == -1 then
        setVehicleToPathing(vehicle_id)
        return
    end
    if #vehicle_object.path > 0 then
        local vehicle_pos = server.getVehiclePos(vehicle_id)
        local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_pos)
        if vehicle_object.ai_type == TYPE_HELICOPTER then
            local victim_transform, target_success = server.getVehiclePos(vehicle_object.target)
            if target_success then
                local _, victim_altitude, _ = matrix.position(victim_transform)
                local target_altitude = victim_altitude + 50
                if vehicle_object.state.gun_run == true then
                    server.setAITargetVehicle(vehicle_object.driver, vehicle_object.target)
                    server.setAIState(vehicle_object.driver, 3)
                else
                    server.setAITargetVehicle(vehicle_object.driver, -1)
                    server.setAIState(vehicle_object.driver, 1)
                end
                server.setAITarget(vehicle_object.driver, (matrix.translation(vehicle_object.path[1].x, target_altitude, vehicle_object.path[1].z)))
            else
                setVehicleToWaiting(vehicle_id)
            end
        else
            server.setAITarget(vehicle_object.driver, (matrix.translation(vehicle_object.path[1].x, vehicle_object.path[1].y, vehicle_object.path[1].z)))
            server.setAIState(vehicle_object.driver, 1)
        end

        refuel(vehicle_id)
        reload(vehicle_id)

        if distance < 100 then
            vehicle_object.state.timer = 0
            server.removeMapLine(-1, vehicle_object.path[1].ui_id)
            table.remove(vehicle_object.path, 1)
        end
    else
        server.setAIState(vehicle_object.driver, 0)
        --keep engaging if is in combat and not too damaged
        local hp = vehicle_object.hp
        if g_savedata.hp_modifier ~= nil and g_savedata.hp_modifier > 0 then
            hp = hp * g_savedata.hp_modifier
        end

        if vehicle_object.current_damage < hp * 0.75 then
            setVehicleToCombat(vehicle_id)
        else
            setVehicleToWaiting(vehicle_id)
        end
    end
end

function setVehicleToCombat(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    --check vehicle can engage
    if not server.getVehicleSimulating(vehicle_id) then
        log("can't engage combat while in pseudo")
        setVehicleToPathing(vehicle_id)
        return
    end
    if vehicle_object.target == -1 then
        setVehicleToPathing(vehicle_id)
        return
    end
    local hp = vehicle_object.hp
    if g_savedata.hp_modifier ~= nil and g_savedata.hp_modifier > 0 then
        hp = hp * g_savedata.hp_modifier
    end
    if vehicle_object.current_damage > hp * 0.75 then
        setVehicleToPathing(vehicle_id)
        return
    end
    if createCombatDestination(vehicle_id) then
        vehicle_object.path = createPath(vehicle_id)
        if #vehicle_object.path > 0 then
            vehicle_object.state.s = STATE_COMBAT
            vehicle_object.state.timer = 0

            refuel(vehicle_id)
            reload(vehicle_id)
            setNPCSeats(vehicle_id)
            return
        else
            log("failed to create path to combat destination")
        end

    else
        log("failed to create combat destination")
    end
end

function updateVehicleInPathing(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    if #vehicle_object.path <= 0 then
        setVehicleToWaiting(vehicle_id)
        return
    end
    if targetNearestVictim(vehicle_id) then
        setVehicleToCombat(vehicle_id)
    end

    local vehicle_pos = server.getVehiclePos(vehicle_id)
    local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_pos)
    local cruise_altitude = getCruiseAltitude(vehicle_id)

    server.setAITarget(vehicle_object.driver, (matrix.translation(vehicle_object.path[1].x, cruise_altitude, vehicle_object.path[1].z)))
    server.setAIState(vehicle_object.driver, 1)

    refuel(vehicle_id)
    reload(vehicle_id)

    if distance < 100 then
        vehicle_object.state.timer = 0
        server.removeMapLine(-1, vehicle_object.path[1].ui_id)
        table.remove(vehicle_object.path, 1)
    end
end

function setVehicleToPathing(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    if #vehicle_object.path <= 0 then
        if createDestination(vehicle_id) then
            vehicle_object.path = createPath(vehicle_id)
        end
        if not server.getVehicleSimulating(vehicle_id) then
            setVehicleToPseudo(vehicle_id)
            return
        end
    end

    vehicle_object.state.s = STATE_PATHING
    vehicle_object.state.timer = 0
    refuel(vehicle_id)
    reload(vehicle_id)
end

function updateVehicleInPseudo(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    targetNearestVictim(vehicle_id)

    if vehicle_object.state.timer >= 60 * 15 then
        vehicle_object.state.timer = 0
        if #vehicle_object.path <= 0 then
            setVehicleToWaiting(vehicle_id)
            return
        end

        local vehicle_transform = server.getVehiclePos(vehicle_id)
        local vehicle_x, _, vehicle_z = matrix.position(vehicle_transform)

        local speed = 120
        if vehicle_object.ai_type == TYPE_SUBMARINE then
            speed = 60
        elseif vehicle_object.ai_type == TYPE_HELICOPTER then
            speed = 320
        end

        local movement_x = vehicle_object.path[1].x - vehicle_x
        local movement_z = vehicle_object.path[1].z - vehicle_z

        local length_xz = math.sqrt((movement_x * movement_x) + (movement_z * movement_z))
        if speed < length_xz then
            movement_x = movement_x / length_xz * speed
            movement_z = movement_z / length_xz * speed
        end

        local rotation_matrix = matrix.rotationToFaceXZ(movement_x, movement_z)
        local new_pos = matrix.multiply(matrix.translation(vehicle_x + movement_x, getCruiseAltitude(vehicle_id), vehicle_z + movement_z), rotation_matrix)

        if server.getVehicleLocal(vehicle_id) == false then
            local vehicle_data = server.getVehicleData(vehicle_id)
            local success, new_transform = server.moveGroupSafe(vehicle_data.group_id, new_pos)
            for _, npc_object in pairs(vehicle_object.survivors) do
                server.setObjectPos(npc_object.id, new_transform)
            end
        end

        local distance = calculate_distance_to_next_waypoint(vehicle_object.path[1], vehicle_transform)
        if distance < 100 then
            server.removeMapLine(-1, vehicle_object.path[1].ui_id)
            table.remove(vehicle_object.path, 1)
        end
    end
end

function setVehicleToPseudo(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    vehicle_object.state.s = STATE_PSEUDO
    vehicle_object.state.timer = 0
end

function updateVehicleInWaiting(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    local wait_time = 60 * 60 * 1
    if vehicle_object.state.timer >= wait_time then
        setVehicleToPathing(vehicle_id)
    end
    if targetNearestVictim(vehicle_id) then
        if server.getVehicleSimulating(vehicle_id) then
            setVehicleToCombat(vehicle_id)
        end
    end
end

function setVehicleToWaiting(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    server.setAIState(vehicle_object.driver, 0)
    vehicle_object.state.s = STATE_WAITING
    vehicle_object.state.timer = 0
end

function updateVehicleMarkers(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]

    if g_savedata.show_markers then
        server.removeMapObject(-1, vehicle_object.map_id)
        if not debug_mode then

            local label = string.format("Hostile %s sighted", vehicle_object.ai_type)
            local description = string.format("A %s sized %s belonging to the Bungeling Empire has been spotted at this location, moving at high speed. ",vehicle_object.size,vehicle_object.ai_type)

            server.addMapObject(-1, vehicle_object.map_id, 1, 18, 0, 0, 0, 0, vehicle_id, 0,
                    label, vehicle_object.vision_radius,
                    description, vehicle_object.icon_colour[1], vehicle_object.icon_colour[2], vehicle_object.icon_colour[3], 255)
        else
            local label = string.format("%d %s", vehicle_id, vehicle_object.ai_type)
            local description = string.format("state - %s\ntimer - %d", vehicle_object.state.s, vehicle_object.state.timer)

            server.addMapObject(-1, vehicle_object.map_id, 1, 18, 0, 0, 0, 0, vehicle_id, 0,
                    label, vehicle_object.vision_radius,
                    description, vehicle_object.icon_colour[1], vehicle_object.icon_colour[2], vehicle_object.icon_colour[3], 255)
        end
    end

    if debug_mode then
        if #vehicle_object.path >= 1 then
            local vehicle_pos = server.getVehiclePos(vehicle_id)
            local vehicle_x, _, vehicle_z = matrix.position(vehicle_pos)
            local previous = { x = vehicle_x, z = vehicle_z }
            for i = 1, #vehicle_object.path do
                local path = vehicle_object.path[i]
                server.removeMapLine(-1, path.ui_id)
                server.addMapLine(-1, path.ui_id, matrix.translation(previous.x, 0, previous.z), matrix.translation(path.x, 0, path.z), 0.3, 255, 0, 0, 255)
                previous = path
            end
        end
    else
        server.removeMapLine(-1, vehicle_object.map_id)
        if #vehicle_object.path >= 1 then
            for i = 1, #vehicle_object.path do
                local path = vehicle_object.path[i]
                server.removeMapLine(-1, path.ui_id)
            end
        end
    end
end

function targetNearestVictim(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    local victim_vehicles = g_savedata.victim_vehicles
    if vehicle_object == nil then
        log("nil vehicle of id "..vehicle_id.." tried to find target")
        return false
    end
    --find nearest victim vehicle in range
    local nearest_victim_id = -1
    local nearest_distance = 3000
    local vehicle_pos, success = server.getVehiclePos(vehicle_id)
    if not success then
        return false
    end
    local x,_,z = matrix.position(vehicle_pos)
    x = math.floor((x+ search_table_tile_size / 2) / search_table_tile_size)
    z = math.floor((z+ search_table_tile_size / 2) / search_table_tile_size)
    for dx=-1,1 do
        for dz=-1,1 do
            local set = victim_search_table[x+dx] and victim_search_table[x+dx][z+dz]
            if set ~= nil then
                for victim_vehicle_id, _ in pairs(set) do
                    local victim_vehicle = victim_vehicles[victim_vehicle_id]
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

            end
        end
    end
    if nearest_victim_id ~= -1 then
        victim_vehicles[nearest_victim_id].targeted = true
    end
    vehicle_object.target = nearest_victim_id
    return vehicle_object.target ~= -1
end

function updateVehicleGunners(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then
        log("tried to update gunner of nil vehicle "..vehicle_id)
        return
    end

    if type(vehicle_object.target) ~= "number" then
        vehicle_object.target = -1
    end
    for _, gunner in pairs(vehicle_object.gunners) do
        if vehicle_object.target ~= -1 then
            --set ai gunner to track and fire
            server.setAIState(gunner, 1)
        else
            --set ai to idle
            server.setAIState(gunner, 0)
        end
        server.setAITargetVehicle(gunner, vehicle_object.target)
    end
end

function updateVehicles()
    local vehicles = g_savedata.vehicles
    local update_rate = 60 * 2
    for vehicle_id, vehicle_object in pairs(vehicles) do

        if vehicle_object ~= nil and isTickID(vehicle_id, update_rate) then
            vehicle_object.state.timer = vehicle_object.state.timer + update_rate * time_multiplier

            if vehicle_object.state.s == STATE_PATHING then
                updateVehicleInPathing(vehicle_id)
            elseif vehicle_object.state.s == STATE_COMBAT then
                updateVehicleInCombat(vehicle_id)
            elseif vehicle_object.state.s == STATE_WAITING then
                updateVehicleInWaiting(vehicle_id)
            elseif vehicle_object.state.s == STATE_PSEUDO then
                updateVehicleInPseudo(vehicle_id)
            end

            updateVehicleMarkers(vehicle_id)
            updateVehicleGunners(vehicle_id)

            local hp = vehicle_object.hp
            if g_savedata.hp_modifier ~= nil and g_savedata.hp_modifier > 0 then
                hp = hp * g_savedata.hp_modifier
            end

            if vehicle_object.current_damage > hp then
                vehicle_object.despawn_timer = vehicle_object.despawn_timer + update_rate
            end
            local vehicle_pos = server.getVehiclePos(vehicle_id)
            local crush_depth = getCrushAltitude(vehicle_id)
            if vehicle_object.state.timer == 0 or (vehicle_object.despawn_timer > 60 * 2) or vehicle_pos[14] < crush_depth then
                if vehicle_pos[14] < crush_depth or vehicle_object.despawn_timer > 0 then
                    server.despawnVehicle(vehicle_id, true) --clean up code moved further down the line for instantly destroyed vehicle
                end
            end
        end
    end
end

function changeFriendlyFrequency()
    local vehicles = g_savedata.vehicles
    --change every 6 seconds
    if isTickID(0, 60 * 6) then
        friendly_frequency = math.random(100, 999)
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
        local times = 1
        if arg1 ~= nil then
            times = tonumber(arg1)
        end
        for i = 1, times do
            local result = respawnLosses(true)
            log("result (successful:vehicle id/failed:-1):" .. tostring(result))

        end
    end
    if command == "?hostile_ai_debug" then
        debug_mode = not debug_mode
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
            announce("?hostile_ai_settings setting_name new_value")
        end
        announce("allow_missiles:" .. tostring(g_savedata.allow_missiles))
        announce("allow_submarines:" .. tostring(g_savedata.allow_submarines))
        announce("show_markers:" .. tostring(g_savedata.show_markers))
        announce("max_vehicle_count:" .. tostring(g_savedata.max_vehicle_count))
        announce("respawn_frequency:" .. tostring(g_savedata.respawn_frequency))
        announce("max_vehicle_size:" .. tostring(g_savedata.max_vehicle_size))
        announce("hp_modifier:" .. tostring(g_savedata.hp_modifier))
    end
    if command == "?hostile_ai_clear" then
        for vehicle_id, _ in pairs(g_savedata.vehicles) do
            server.despawnVehicle(vehicle_id, true)
        end
    end
end

function refuel(vehicle_id)
    for i = 1, 15 do
        server.setVehicleTank(vehicle_id, "diesel" .. i, 999, 1)
        server.setVehicleTank(vehicle_id, "jet" .. i, 999, 2)
        server.setVehicleBattery(vehicle_id, "battery" .. i, 1)
    end
end

function reload(vehicle_id)
    for i = 1, 15 do
        server.setVehicleWeapon(vehicle_id, "Ammo " .. i, 999)
    end
end

function calculate_distance_to_next_waypoint(path_pos, vehicle_pos)
    local vehicle_x, vehicle_y, vehicle_z = matrix.position(vehicle_pos)

    local vector_x = path_pos.x - vehicle_x
    local vector_z = path_pos.z - vehicle_z

    return math.sqrt((vector_x * vector_x) + (vector_z * vector_z))
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
    if playlist_data ~= nil then
        location_count = playlist_data.location_count
    end
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
    if location_data ~= nil then
        object_count = location_data.component_count
    end
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
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object == nil then
        return
    end

    local reward_amount = vehicle_object.reward
    if reward_amount > 0 then
        server.notify(-1, string.format("Enemy %s destroyed", vehicle_object.ai_type), "Rewarded $ " .. math.floor(reward_amount), 9)
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
        local spawn_transform, is_success = server.getOceanTransform(random_player_transform, 5000, 30000)
        --put the vehicle randomly in the tile
        spawn_transform = matrix.multiply(spawn_transform, matrix.translation(math.random(-500, 500), 0, math.random(-500, 500)))

        if is_success then
            return spawnVehicle(location, spawn_transform)
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
    server.removeMapLine(-1, vehicle_object.map_id)
    for _, waypoint in pairs(vehicle_object.path) do
        server.removeMapLine(-1, waypoint.ui_id)
    end
    for _, survivor in pairs(vehicle_object.survivors) do
        server.despawnObject(survivor.id, true)
    end
end

function trackVictims()
    local victim_vehicles = g_savedata.victim_vehicles
    --track position of victim vehicles
    for victim_vehicle_id, victim_vehicle in pairs(victim_vehicles) do
        --update every 5 seconds
        if victim_vehicle ~= nil and isTickID(victim_vehicle_id, 60 * 5) then
            victim_vehicle.transform = server.getVehiclePos(victim_vehicle_id)
            insertToSearchTable(victim_vehicle_id)
            server.removeMapID(-1, victim_vehicle.map_id)
            if not debug_mode then
                if not g_savedata.show_markers then
                    if victim_vehicle.targeted then
                        server.addMapObject(-1, victim_vehicle.map_id, 1, 19, 0, 0, 0, 0, victim_vehicle_id, 0, "Under Attack", 500, "A Mayday has been received from a civilian ship or aircraft claiming to be under attack by a hostile vessel.", 255, 0, 0, 255)
                        victim_vehicle.targeted = false
                    end
                end
            else
                local label = string.format("Tracked victim %d %s",victim_vehicle_id, tostring(victim_vehicle.targeted))
                server.addMapObject(-1, victim_vehicle.map_id, 1, 19, 0, 0, 0, 0, victim_vehicle_id, 0, label, 700, "", 255, 0, 0, 255)
            end
        end
    end
    updateSearchTable()
end

function addVictim(vehicle_id, peer_id)
    local vehicle_transform, pos_success = server.getVehiclePos(vehicle_id)
    if not pos_success then
        return
    end
    if g_savedata.vehicles[vehicle_id] ~= nil then
        return
    end
    if peer_id ~= -1 then
        g_savedata.victim_vehicles[vehicle_id] = {
            transform = vehicle_transform,
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
    if hasTag(vehicle_data.tags, "type=ai_boat") or hasTag(vehicle_data.tags, "type=ai_plane") or hasTag(vehicle_data.tags, "type=ai_heli") then
        --ignore hostile boats or midair refuel planes
        if (hasTag(vehicle_data.tags, "unique")) then
            return
        end

        g_savedata.victim_vehicles[vehicle_id] = {
            transform = vehicle_transform,
            map_id = server.getMapID(),
        }
        insertToSearchTable(vehicle_id)

        return
    end
end

function insertToSearchTable(vehicle_id)
    local victim_transform, transform_success = server.getVehiclePos(vehicle_id)
    if transform_success then
        local x,_,z = matrix.position(victim_transform)
        x = math.floor((x+ search_table_tile_size / 2) / search_table_tile_size)
        z = math.floor((z+ search_table_tile_size / 2) / search_table_tile_size)
        if victim_search_table[x] == nil then
            victim_search_table[x] = {}
        end
        if victim_search_table[x][z] == nil then
            victim_search_table[x][z] = {}
        end
        if victim_search_table[x][z][vehicle_id] ~= true then
            victim_search_table[x][z][vehicle_id] = true
            --log(tostring(vehicle_id).." inserted at "..tostring(x)..","..tostring(z))
        end
    else
        log("failed to get victim position"..tostring(vehicle_id))
    end
end

function removeVictim(vehicle_id)
    if g_savedata.victim_vehicles[vehicle_id] ~= nil then
        removeFromSearchTable(vehicle_id)
        server.removeMapID(-1, g_savedata.victim_vehicles[vehicle_id].map_id)
        g_savedata.victim_vehicles[vehicle_id] = nil
    end
end

function removeFromSearchTable(vehicle_id)
    local victim_transform, transform_success = server.getVehiclePos(vehicle_id)
    if transform_success then
        local x,_,z = matrix.position(victim_transform)
        x = math.floor((x + search_table_tile_size / 2) / search_table_tile_size)
        z = math.floor((z + search_table_tile_size / 2) / search_table_tile_size)
        local set = victim_search_table[x] and victim_search_table[x][z]
        set[vehicle_id] = nil
    end
end

function updateSearchTable()
    if not isTickID(0,60*5) then
        return
    end
    for x, row in pairs(victim_search_table) do
        for z, set in pairs(row) do
            for vehicle_id, _ in pairs(set) do
                --log(tostring(vehicle_id).. " at (".. tostring(x).. ",".. tostring(z).. ")")
                set[vehicle_id] = nil
                insertToSearchTable(vehicle_id)
            end
        end
    end
end

function onVehicleSpawn(vehicle_id, peer_id, x, y, z, cost)
    addVictim(vehicle_id, peer_id)
end

function getRandomLocation()
    local tries = 0
    while tries < 40 do
        --getting a random location, built_location must be contiguous
        local random_location_index = math.random(1, #built_locations)
        local location = built_locations[random_location_index]

        local tags = location.objects.vehicle.tags
        --using an boolean flag here to avoid messy nested if statements when more checks are added
        local allowed = true
        --check if it has missiles and missiles are allowed
        if hasTag(tags, "missiles") and not g_savedata.allow_missiles then
            allowed = false
        end

        if hasTag(tags, "size=medium") and g_savedata.max_vehicle_size < 2 then
            allowed = false
        end

        if hasTag(tags, "size=large") and g_savedata.max_vehicle_size < 3 then
            allowed = false
        end

        if hasTag(tags, TYPE_SUBMARINE) and not g_savedata.allow_submarines then
            allowed = false
        end

        if hasTag(tags, "type=enemy_ai_heli") and not g_savedata.allow_helis then
            allowed = false
        end

        if allowed then
            return location
        end
        tries = tries + 1
    end
    log("failed to find a suitable vehicle to deploy")
    return nil
end

function isTickID(id, rate)
    return (tick_counter + id) % rate == 0
end

function inGreedyBoxRange(transform_a, transform_b, radius)
    local x_a, y_a, z_a = matrix.position(transform_a)
    local x_b, y_b, z_b = matrix.position(transform_b)
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
    local x_a, y_a, z_a = matrix.position(transform_a)
    local x_b, y_b, z_b = matrix.position(transform_b)
    return math.abs(x_b - x_a) + math.abs(y_b - y_a) + math.abs(z_b - z_a)
end

function spawnVehicle(location, spawn_transform)
    --spawn vehicle and every object attached to it
    local all_mission_objects = {}
    local spawned_objects = {
        vehicle = spawnObject(spawn_transform, location.playlist_index, location.location_index, location.objects.vehicle, 0, nil, all_mission_objects),
        survivors = spawnObjects(spawn_transform, location.playlist_index, location.location_index, location.objects.survivors, all_mission_objects),
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
    local vehicle_data, success = server.getVehicleData(vehicle_id)
    if not success then
        announce("failed to get vehicle data when spawning")
    else
        --passing in vehicle_id for modifying or accessing vehicle_object in g_savedata.vehicles
        --passing in vehicle_data mainly for the tags data
        setReward(vehicle_id, vehicle_data)
        setAIType(vehicle_id, vehicle_data)
        setAltitude(vehicle_id)
        setSizeData(vehicle_id)
        setNPCRoles(vehicle_id)
    end
    return vehicle_id
end

function setReward(vehicle_id, vehicle_data)
    local threat_level = "none"
    for _, tag_object in pairs(vehicle_data.tags) do
        if tag_object:find("threat=") ~= nil then
            threat_level = tag_object:gsub("threat=", "")
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

function getCruiseAltitude(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    local target_altitude = 0
    if vehicle_object ~= nil then
        if vehicle_object.ai_type == TYPE_SUBMARINE then
            target_altitude = -10
        elseif vehicle_object.ai_type == TYPE_HELICOPTER then
            target_altitude = 300
        end
    end
    return target_altitude
end

function getCrushAltitude(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    local crush_depth = -22
    if vehicle_object.ai_type == TYPE_SUBMARINE then
        crush_depth = -100
    elseif vehicle_object.ai_type == TYPE_HELICOPTER then
        crush_depth = 0
    end
    return crush_depth
end

function setAltitude(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    local vehicle_transform, success = server.getVehiclePos(vehicle_id)
    if success then
        local x, altitude, z = matrix.position(vehicle_transform)
        local target_altitude = getCruiseAltitude(vehicle_id)
        if math.abs(target_altitude - altitude) > 10 then
            local vehicle_data = server.getVehicleData(vehicle_id)
            local move_success, new_transform = server.moveGroupSafe(vehicle_data.group_id, matrix.translation(x, target_altitude, z))
            if not move_success then
                announce("failed to set altitude for " .. tostring(vehicle_id) .. " from " .. tostring(altitude) .. " to " .. tostring(target_altitude))
            end

        end
    end
end

function setAIType(vehicle_id, vehicle_data)
    local _ai_type = TYPE_VESSEL
    for _, tag_object in pairs(vehicle_data.tags) do
        if tag_object == TYPE_SUBMARINE then
            _ai_type = TYPE_SUBMARINE
        end
        if tag_object == "type=enemy_ai_heli" then
            _ai_type = TYPE_HELICOPTER
        end
    end
    g_savedata.vehicles[vehicle_id].ai_type = _ai_type
end

function setNPCRoles(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    vehicle_object.gunners = {}
    vehicle_object.driver = nil
    for _, npc in pairs(vehicle_object.survivors) do
        local c = server.getCharacterData(npc.id)
        if c then
            if c.name:find("Gunner") then
                table.insert(vehicle_object.gunners, npc.id)
            elseif c.name:find("Captain") or c.name:find("Pilot") then
                vehicle_object.driver = npc.id
            end
        end
    end
    if vehicle_object.driver == nil then
        log("failed to find driver npc from " .. tostring(#vehicle_object.survivors))
    end
end

function setNPCSeats(vehicle_id)
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if not vehicle_object then return end

    for _, npc in pairs(vehicle_object.survivors) do
        local c = server.getCharacterData(npc.id)
        if c then
            server.setCharacterData(npc.id, c.hp, false, true)
            server.setCharacterSeated(npc.id, vehicle_id, c.name)
        end
    end
end

function setSizeData(vehicle_id)
    --set vehicle data that depends on the size
    local vehicle_object = g_savedata.vehicles[vehicle_id]
    if vehicle_object ~= nil then
        if vehicle_object.size == "small" then
            vehicle_object.hp = 4000
            vehicle_object.vision_radius = 2000
            vehicle_object.orbit_radius = 500
            vehicle_object.explosion_size = 0.6
            vehicle_object.icon_colour = { 255, 255, 0 }
        elseif vehicle_object.size == "medium" then
            vehicle_object.hp = 10000
            vehicle_object.vision_radius = 2000
            vehicle_object.orbit_radius = 750
            vehicle_object.explosion_size = 1.0
            vehicle_object.icon_colour = { 255, 125, 0 }
        elseif vehicle_object.size == "large" then
            vehicle_object.hp = 100000
            vehicle_object.vision_radius = 2000
            vehicle_object.orbit_radius = 1000
            vehicle_object.explosion_size = 1.5
            vehicle_object.icon_colour = { 255, 0, 0 }
        else
            log("unexpected vehicle size")
        end
        g_savedata[vehicle_id] = vehicle_object
    end
end

function announce(message)
    server.announce("hostile_ai", message)
end

function log(message)
    if not debug_mode then
        return
    end
    server.announce("hostile_ai", "DEBUG:" .. message)
end