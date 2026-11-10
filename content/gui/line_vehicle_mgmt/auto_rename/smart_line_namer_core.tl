-- Smart Line Namer: "{Town} · {Vehicle}: {Route}"
--   Gukovo · Bus: Center — North        line inside one town
--   Gukovo · Bus: Loop                  circular line
--   Intercity · Train: Gukovo — Chekalin via Orel  line between towns
--   Gukovo · Truck: Mine — Plant (Coal) freight (cargo in parentheses)
-- Identical names get a stable number at the end: "... 2", "... 3".

local record Stop
	sg : Engine.Entity
	name : string
	town : string
	townEntity : Engine.Entity
	industry : string
end

local record Core
	lineName : function(Engine.Entity) : string
	stationName : function(Engine.Entity) : string
end

-- Future station names ("Town — Place"), see slnamer_stations.lua.
local record StationInfo
	town : Engine.Entity
	townName : string
	place : string
	industry : string
end

local record Stations
	info : function(Engine.Entity) : StationInfo
	fullName : function(Engine.Entity) : string
	isSingleOutputIndustry : function(string) : boolean
end

-- If the module fails to load, fall back to naming lines from the current station names.
local stations : Stations = nil
local stationsOk, stationsMod = pcall(ug_require, "/gui/line_vehicle_mgmt/auto_rename/slnamer_stations.lua")
if stationsOk then
	stations = stationsMod as Stations
else
	log.warning("[SLN] stations module failed to load: " .. tostring(stationsMod))
end

local function stationInfo(sg : Engine.Entity) : StationInfo
	if not stations then return nil end
	local ok, info = pcall(stations.info, sg)
	if ok then return info as StationInfo end
	log.warning("[SLN] stations.info failed: " .. tostring(info))
	return nil
end

local DASH = " — "
local SEP = " · "
local MIN_CENTER_RADIUS = 400
-- What the line list and the auto-rename dialog show without cutting (from screenshots).
local MAX_LINE_CHARS = 45

-- Number of characters (not bytes) in a UTF-8 string.
local function utf8Len(s : string) : integer
	local n = 0
	for i = 1, #s do
		local b = s:byte(i)
		if b < 0x80 or b >= 0xC0 then n = n + 1 end
	end
	return n
end

-- Version 0.1 cut single bytes out of names (a "[«»]" pattern removed byte 0xBB,
-- the second byte of Cyrillic "л"), leaving invalid UTF-8 that crashes the line
-- window. Returns the repaired string and whether anything was broken.
local function repairUtf8(s : string) : (string, boolean)
	local out : {string} = {}
	local i, n, broken = 1, #s, false
	while i <= n do
		local c = s:byte(i)
		local need = -1
		if c < 0x80 then need = 0
		elseif c >= 0xF0 and c < 0xF8 then need = 3
		elseif c >= 0xE0 and c < 0xF0 then need = 2
		elseif c >= 0xC2 then need = 1
		end
		local ok = need >= 0 and i + need <= n
		if ok then
			for j = 1, need do
				local b = s:byte(i + j)
				if b < 0x80 or b > 0xBF then ok = false end
			end
		end
		if ok then
			out[#out + 1] = s:sub(i, i + need)
			i = i + need + 1
		else
			broken = true
			-- a lone 0xD0 lost its 0xBB: restore "л"; drop any other stray byte
			if c == 0xD0 then out[#out + 1] = "\208\187" end
			i = i + 1
		end
	end
	return table.concat(out), broken
end

-- Repair every line name broken by version 0.1, once per game session.
local repairedThisSession = false
local function repairBrokenLineNames()
	if repairedThisSession then return end
	repairedThisSession = true
	for __, l in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
		local current = api.engine.util.getEntityName(l)
		if current then
			local fixed, broken = repairUtf8(current)
			if broken then
				log.message("[SLN] repairing broken line name " .. tostring(l) .. " -> " .. fixed)
				api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(l, fixed))
			end
		end
	end
end

local function trim(s : string) : string
	s = s:gsub("^%s+", "")
	s = s:gsub("%s+$", "")
	return s
end

-- Lua patterns work on bytes, so non-ASCII text («, —, Cyrillic) must never go into
-- a character class: "[«»]" would delete single bytes shared with Cyrillic letters.
-- All matching below is done with plain substring search instead.
local QUOTES = { "«", "»", "“", "”", "„", "\"" }
local STATION_PREFIXES = { "Станция ", "станция ", "Station ", "station " }
-- Only dashes with spaces around: "Town — Place", but not "Zheleznogorsk-Ilimsky".
local SEPARATORS = { " — ", " – ", " - " }

local function removeAll(s : string, sub : string) : string
	local parts : {string} = {}
	local i = 1
	while true do
		local a, b = s:find(sub, i, true)
		if not a then break end
		parts[#parts + 1] = s:sub(i, a - 1)
		i = b + 1
	end
	parts[#parts + 1] = s:sub(i)
	return table.concat(parts)
end

local function startsWith(s : string, prefix : string) : boolean
	return s:sub(1, #prefix) == prefix
end

-- Splits "Town — Place" at the first separator; nil when there is none.
local function splitFirst(s : string) : (string, string)
	local bestA, bestB : integer, integer = nil, nil
	for __, sep in ipairs(SEPARATORS) do
		local a, b = s:find(sep, 1, true)
		if a and (not bestA or a < bestA) then bestA, bestB = a, b end
	end
	if not bestA then return nil, nil end
	return s:sub(1, bestA - 1), s:sub(bestB + 1)
end

-- "Станция «Иваново» — Восток" -> "Восток"; "Станция «Сызрань»" -> "Сызрань".
local function cleanName(s : string, town : string) : string
	if not s then return nil end
	for __, q in ipairs(QUOTES) do s = removeAll(s, q) end
	s = trim(s)
	for __, p in ipairs(STATION_PREFIXES) do
		if startsWith(s, p) then
			s = trim(s:sub(#p + 1))
			break
		end
	end
	if town then
		local prefix, rest = splitFirst(s)
		if prefix and rest and trim(prefix) == town then s = rest end
	end
	s = trim(s)
	if s == "" then return nil end
	return s
end

local function collectStops(line : Engine.Component.Line, station2town : {Engine.Entity : Engine.Entity}) : {Stop}
	local stops : {Stop} = {}
	for __, ls in ipairs(line.stops) do
		local sg = ls.stationGroup
		local stop : Stop = { sg = sg }
		local info = stationInfo(sg)
		if info and info.place then
			-- the name the station will get after renaming
			stop.town = info.townName
			stop.townEntity = info.town
			stop.name = info.place
			stop.industry = info.industry
		else
			-- fallback: the station's current name
			local comp = api.engine.getComponent(sg, api.type.ComponentType.STATION_GROUP)
			if comp and comp.stations and #comp.stations > 0 then
				local te = station2town[comp.stations[1]]
				if te and api.engine.entityExists(te) then
					stop.townEntity = te
					stop.town = api.engine.util.getEntityName(te)
				end
			end
			stop.name = cleanName(api.engine.util.getEntityName(sg), stop.town)
		end
		stops[#stops + 1] = stop
	end
	return stops
end

local function isPassengerLine(line : Engine.Component.Line) : boolean
	for __, stop in ipairs(line.stops) do
		if stop.stopConfig and stop.stopConfig.load and stop.stopConfig.load[1] then
			return true
		end
	end
	return false
end

-- True when every stop loading this cargo is an industry with a single product
-- (mine, quarry, forest, ...): "Шахта (Уголь)" says nothing new, so the cargo is dropped.
local function cargoObvious(line : Engine.Component.Line, stops : {Stop}, k : integer) : boolean
	if not stations then return false end
	local any = false
	for i, ls in ipairs(line.stops) do
		local load = ls.stopConfig and ls.stopConfig.load
		if load and load[k] then
			local ind = stops[i] and stops[i].industry
			if not ind or not stations.isSingleOutputIndustry(ind) then return false end
			any = true
		end
	end
	return any
end

local function topCargo(line : Engine.Component.Line, stops : {Stop}) : string
	local counts : {integer : integer} = {}
	local ids : {integer} = {}
	for __, stop in ipairs(line.stops) do
		if stop.stopConfig and stop.stopConfig.load then
			for k, v in ipairs(stop.stopConfig.load) do
				if v and k > 1 then
					if not counts[k] then counts[k] = 0; ids[#ids + 1] = k end
					counts[k] = counts[k] + 1
				end
			end
		end
	end
	if #ids == 0 then return nil end
	table.sort(ids, function(a : integer, b : integer) : boolean
		if counts[a] == counts[b] then return a < b end
		return counts[a] > counts[b]
	end)
	if #ids == 1 and cargoObvious(line, stops, ids[1]) then return nil end
	local cargoType = api.res.cargoTypeRep.get(ids[1] - 1) as CargoType
	local name = cargoType.name
	if #ids > 1 then name = name .. ", +" .. tostring(#ids - 1) end
	return name
end

local function carrierOf(lineEntity : Engine.Entity, stops : {Stop}) : Carrier
	local carriers : {Carrier : boolean} = {}
	for __, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity)) do
		local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
		if tv and tv.carrier then carriers[tv.carrier] = true end
	end
	if next(carriers) == nil then
		for __, s in ipairs(stops) do
			local cs = api.engine.system.stationGroupSystem.getCarriers(s.sg, -1, -1)[1]
			for __, c in ipairs(cs) do carriers[c] = true end
		end
	end
	local E = api.type["enum"].Carrier
	for __, c in ipairs({E.RAIL, E.TRAM, E.AIR, E.WATER, E.ROAD}) do
		if carriers[c] then return c end
	end
	return nil
end

local function vehicleName(carrier : Carrier, pax : boolean) : string
	local E = api.type["enum"].Carrier
	if carrier == E.RAIL then return _("Train") end
	if carrier == E.TRAM then return _("Tram") end
	if carrier == E.AIR then return _("Plane") end
	if carrier == E.WATER then return _("Ship") end
	if carrier == E.ROAD then return pax and _("Bus") or _("Truck") end
	return _("Line")
end

local function stopPos(sg : Engine.Entity) : (number, number)
	local bb = api.engine.getComponent(sg, api.type.ComponentType.BOUNDING_VOLUME)
	if bb and bb.bbox and bb.bbox.min and bb.bbox.max then
		local c = (bb.bbox.max + bb.bbox.min) * 0.5
		return c.x, c.y
	end
	return nil, nil
end

local function directionName(dx : number, dy : number, radius : number) : string
	if math.sqrt(dx * dx + dy * dy) < radius then return _("Center") end
	if math.abs(dy) >= math.abs(dx) then
		if dy > 0 then return _("North") end
		return _("South")
	end
	if dx > 0 then return _("East") end
	return _("West")
end

local function directionEnds(first : Stop, last : Stop) : (string, string)
	if not first.townEntity then return nil, nil end
	local center = api.engine.util.town.getTownDistrictCenter(first.townEntity, api.type["enum"].LandUseType.COMMERCIAL)
	if not center then return nil, nil end
	local fx, fy = stopPos(first.sg)
	local lx, ly = stopPos(last.sg)
	if not fx or not lx then return nil, nil end
	local fdx, fdy, ldx, ldy = fx - center.x, fy - center.y, lx - center.x, ly - center.y
	local far = math.max(math.sqrt(fdx * fdx + fdy * fdy), math.sqrt(ldx * ldx + ldy * ldy))
	local radius = math.max(MIN_CENTER_RADIUS, far * 0.25)
	return directionName(fdx, fdy, radius), directionName(ldx, ldy, radius)
end

local function stationLabel(stop : Stop) : string
	if stop.name and stop.town and stop.name == stop.town then return _("MainStation") end
	return stop.name
end

local function pair(a : string, b : string) : string
	if a and b and a ~= b then return a .. DASH .. b end
	return a or b
end

local function townStats(stops : {Stop}) : ({string}, {string : integer})
	local order : {string} = {}
	local counts : {string : integer} = {}
	for __, s in ipairs(stops) do
		if s.town then
			if not counts[s.town] then counts[s.town] = 0; order[#order + 1] = s.town end
			counts[s.town] = counts[s.town] + 1
		end
	end
	return order, counts
end

local function busiestTown(order : {string}, counts : {string : integer}, skipA : string, skipB : string) : string
	local best : string = nil
	for __, t in ipairs(order) do
		if t ~= skipA and t ~= skipB and (not best or counts[t] > counts[best]) then best = t end
	end
	return best
end

-- Ends of a line that stays inside one town: station names, or directions
-- from the town center when the station names do not tell them apart.
local function localEnds(first : Stop, last : Stop) : string
	local a, b = stationLabel(first), stationLabel(last)
	if not a or not b or a == b then
		local da, db = directionEnds(first, last)
		if da and db and da ~= db then return pair(da, db) end
	end
	return pair(a, b)
end

-- Group = what the name starts with, so the alphabetical list groups lines by it.
local function groupOf(stops : {Stop}) : string
	return stops[1].town or stationLabel(stops[1])
end

local function baseName(lineEntity : Engine.Entity, station2town : {Engine.Entity : Engine.Entity}) : string
	local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE) as Engine.Component.Line
	if not line or not line.stops or #line.stops == 0 then return nil end
	local stops = collectStops(line, station2town)
	local n = #stops
	local first, last = stops[1], stops[n]
	local pax = isPassengerLine(line)
	local group = groupOf(stops)
	local order, counts = townStats(stops)
	local ring = n >= 3 and first.sg == last.sg
	local intercity = first.town ~= nil and #order >= 2
	local vehicle = vehicleName(carrierOf(lineEntity, stops), pax)
	-- Intercity lines start with one common prefix and then the vehicle, so they form
	-- their own block in the list, sorted by vehicle; local lines start with their town.
	local head : string
	if intercity then
		head = _("Intercity") .. SEP .. vehicle
	elseif group then
		head = group .. SEP .. vehicle
	else
		head = vehicle
	end

	local name : string
	local viaPart : string = nil

	if ring and intercity then
		name = head .. ": " .. first.town .. " (" .. _("Loop") .. ")"
	elseif ring then
		name = head .. ": " .. _("Loop")
	elseif intercity then
		local other = last.town
		if not other or other == first.town then other = busiestTown(order, counts, first.town, nil) end
		name = head .. ": " .. first.town .. DASH .. other
		local via = busiestTown(order, counts, first.town, other)
		if via then viaPart = " " .. _("via") .. " " .. via end
	elseif first.town then
		local ends = localEnds(first, last)
		name = ends and (head .. ": " .. ends) or head
	else
		local other = last.town or stationLabel(last)
		if other and other ~= group then name = head .. DASH .. other else name = head end
	end

	local cargoPart = ""
	if not pax then
		local cargo = topCargo(line, stops)
		if cargo then cargoPart = " (" .. cargo .. ")" end
	end
	-- "via Town" is the least important part: drop it when the name would not fit
	-- the line list / auto-rename dialog (~45-50 characters visible).
	if viaPart and utf8Len(name .. viaPart .. cargoPart) <= MAX_LINE_CHARS then
		name = name .. viaPart
	end
	return name .. cargoPart
end

-- Cheap key to skip lines that cannot have the same name before computing it fully.
local function quickKey(lineEntity : Engine.Entity, station2town : {Engine.Entity : Engine.Entity}) : string
	local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE) as Engine.Component.Line
	if not line or not line.stops or #line.stops == 0 then return nil end
	local first = collectStops({ stops = { line.stops[1] } } as Engine.Component.Line, station2town)
	return tostring(groupOf(first)) .. "|" .. tostring(carrierOf(lineEntity, first))
end

local Ret : Core = {
	-- "Town — Place" the station group should be renamed to; nil when unknown.
	stationName = function(sg : Engine.Entity) : string
		if not stations then return nil end
		local ok, n = pcall(stations.fullName, sg)
		if ok then return n as string end
		return nil
	end,

	lineName = function(lineEntity : Engine.Entity) : string
		local okRepair, errRepair = pcall(repairBrokenLineNames)
		if not okRepair then log.warning("[SLN] repair failed: " .. tostring(errRepair)) end
		local station2town = api.engine.system.stationSystem.getStation2TownMap()
		local name = baseName(lineEntity, station2town)
		if not name then return api.engine.util.getEntityName(lineEntity) or "" end

		-- Number identical names by entity id: stable regardless of the order the game
		-- renames lines in, and unaffected by names other lines currently have.
		local key = quickKey(lineEntity, station2town)
		local same : {integer} = {}
		for __, other in ipairs(api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())) do
			if other == lineEntity then
				same[#same + 1] = other as integer
			elseif quickKey(other, station2town) == key and baseName(other, station2town) == name then
				same[#same + 1] = other as integer
			end
		end
		if #same > 1 then
			table.sort(same)
			for i, id in ipairs(same) do
				if id == lineEntity as integer and i > 1 then return name .. " " .. tostring(i) end
			end
		end
		return name
	end,
}

return Ret
