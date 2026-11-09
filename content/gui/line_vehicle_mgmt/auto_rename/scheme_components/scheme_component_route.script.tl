local function getState()
	local scriptTable = game.res.script
	if type(scriptTable) ~= "table" then
		scriptTable = {}
		game.res.script = scriptTable
	end
	local state = scriptTable["isnightmaredream_smart_line_namer"]
	if type(state) ~= "table" then
		state = { lastComponent = "", names = {} }
		scriptTable["isnightmaredream_smart_line_namer"] = state
	end
	return state
end

local function cleanName(s)
	if not s then return nil end
	s = s:gsub("[«»\"]", "")
	s = s:gsub("^%s*[Сс]танция%s*", "")
	s = s:gsub("^%s*Station%s*", "")
	s = s:gsub("^.*[—–-]%s*", "")
	s = s:gsub("^%s+", "")
	s = s:gsub("%s+$", "")
	if s == "" then return nil end
	return s
end

local function stopPos(sg)
	local bb = api.engine.getComponent(sg, api.type.ComponentType.BOUNDING_VOLUME)
	if bb and bb.bbox and bb.bbox.min and bb.bbox.max then
		local p = (bb.bbox.max + bb.bbox.min) * 0.5
		return p.x, p.y
	end
	return nil
end

local function directionName(cx, cy, x, y)
	local dx = x - cx
	local dy = y - cy
	if math.sqrt(dx * dx + dy * dy) < 400 then
		return _("Center")
	end
	if math.abs(dy) >= math.abs(dx) then
		if dy > 0 then return _("North") else return _("South") end
	else
		if dx > 0 then return _("East") else return _("West") end
	end
end

local function join2(town, a, b)
	if a == town then a = nil end
	if b == town then b = nil end
	if a == nil then a = b; b = nil end
	if b ~= nil and b == a then b = nil end
	if a == nil then return nil end
	if b == nil then return a end
	return a .. " — " .. b
end

local function vehicleName(renameParams)
	local carriers = {}
	local vehicles = api.engine.system.transportVehicleSystem.getLineVehicles(renameParams.lineEntity)
	for __, v in ipairs(vehicles) do
		local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
		if tv and tv.carrier then carriers[tv.carrier] = true end
	end
	if next(carriers) == nil then
		for __, via in ipairs(renameParams.reactLine.path) do
			if not via.waypoint then
				local cs = api.engine.system.stationGroupSystem.getCarriers(via.stop.stationGroup, -1, -1)[1]
				for __, c in ipairs(cs) do carriers[c] = true end
			end
		end
	end
	local line = api.engine.getComponent(renameParams.lineEntity, api.type.ComponentType.LINE)
	local isPassenger = false
	for __, stop in ipairs(line.stops) do
		if stop.stopConfig and stop.stopConfig.load and stop.stopConfig.load[1] then
			isPassenger = true
			break
		end
	end
	for carrier, __ in pairs(carriers) do
		if carrier == api.type["enum"].Carrier.ROAD then return isPassenger and _("Bus") or _("Truck") end
		if carrier == api.type["enum"].Carrier.RAIL then return isPassenger and _("Train") or _("Cargo Train") end
		if carrier == api.type["enum"].Carrier.TRAM then return _("Tram") end
		if carrier == api.type["enum"].Carrier.AIR then return isPassenger and _("Plane") or _("Cargo Plane") end
		if carrier == api.type["enum"].Carrier.WATER then return isPassenger and _("Ship") or _("Cargo Ship") end
	end
	return ""
end

local Ret = {
	renameFn = function(renameParams : AutoRename.RenameParams) : string
		local line = renameParams.lineEntity
		local state = getState()

		if state.lastComponent == "stops" then
			state.names = {}
		end
		state.lastComponent = "route"

		local station2townMap = api.engine.system.stationSystem.getStation2TownMap()

		local towns = {}
		local townEntities = {}
		local seenTowns = {}
		local firstName = nil
		local lastName = nil
		local firstSG = nil
		local lastSG = nil

		for __, via in ipairs(renameParams.reactLine.path) do
			if not via.waypoint then
				local stationGroupEntity = via.stop.stationGroup

				local stationName = cleanName(api.engine.util.getEntityName(stationGroupEntity))
				if stationName then
					if not firstName then firstName = stationName end
					lastName = stationName
				end

				if not firstSG then firstSG = stationGroupEntity end
				lastSG = stationGroupEntity

				local stationGroupComp = api.engine.getComponent(stationGroupEntity, api.type.ComponentType.STATION_GROUP)
				if stationGroupComp and stationGroupComp.stations and #stationGroupComp.stations > 0 then
					local townEntity = station2townMap[stationGroupComp.stations[1]]
					if townEntity and api.engine.entityExists(townEntity) then
						local townName = api.engine.util.getEntityName(townEntity)
						if townName and not seenTowns[townName] then
							seenTowns[townName] = true
							towns[#towns + 1] = townName
							townEntities[#townEntities + 1] = townEntity
						end
					end
				end
			end
		end

		local part = nil

		if #towns >= 2 then
			part = ": " .. towns[1] .. " — " .. towns[#towns]
		else
			local townName = (#towns == 1) and towns[1] or nil

			local name1 = nil
			local name2 = nil

			if townName and firstSG and lastSG then
				local center = api.engine.util.town.getTownDistrictCenter(townEntities[1], api.type["enum"].LandUseType.COMMERCIAL)
				if center then
					local fx, fy = stopPos(firstSG)
					local lx, ly = stopPos(lastSG)
					if fx and lx then
						name1 = directionName(center.x, center.y, fx, fy)
						name2 = directionName(center.x, center.y, lx, ly)
					end
				end
			end

			if not name1 then name1 = firstName end
			if not name2 then name2 = lastName end

			local endpoint = join2(townName, name1, name2)

			if townName then
				if endpoint then
					part = " " .. townName .. ": " .. endpoint
				else
					part = " " .. townName
				end
			elseif endpoint then
				part = " " .. endpoint
			end
		end

		if not part then
			return api.engine.util.getEntityName(line) or ""
		end

		local fullName = vehicleName(renameParams) .. part

		if state.names[fullName] then
			return api.engine.util.getEntityName(line) or ""
		end
		state.names[fullName] = true

		return fullName
	end,
}

return Ret
