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

		state.lastComponent = "stops"

		local station2townMap = api.engine.system.stationSystem.getStation2TownMap()

		local towns = {}
		local seenTowns = {}
		local firstSG = nil
		local lastSG = nil

		for __, via in ipairs(renameParams.reactLine.path) do
			if not via.waypoint then
				local stationGroupEntity = via.stop.stationGroup
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
						end
					end
				end
			end
		end

		local part = nil

		if #towns >= 2 then
			local function displayName(sg)
				local name = cleanName(api.engine.util.getEntityName(sg))
				local townName = nil
				local sgComp = api.engine.getComponent(sg, api.type.ComponentType.STATION_GROUP)
				if sgComp and sgComp.stations and #sgComp.stations > 0 then
					local townEntity = station2townMap[sgComp.stations[1]]
					if townEntity and api.engine.entityExists(townEntity) then
						townName = api.engine.util.getEntityName(townEntity)
					end
				end
				if name and townName and name == townName then
					return _("MainStation")
				end
				return name
			end

			local name1 = firstSG and displayName(firstSG) or nil
			local name2 = lastSG and displayName(lastSG) or nil
			local endpoint = join2(nil, name1, name2)
			if endpoint then
				part = ": " .. endpoint
			else
				part = ": " .. towns[1] .. " — " .. towns[#towns]
			end
		else
			local townName = (#towns == 1) and towns[1] or nil

			local function displayName(sg)
				local name = cleanName(api.engine.util.getEntityName(sg))
				if name and townName and name == townName then
					return _("MainStation")
				end
				return name
			end

			local name1 = firstSG and displayName(firstSG) or nil
			local name2 = lastSG and displayName(lastSG) or nil

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
