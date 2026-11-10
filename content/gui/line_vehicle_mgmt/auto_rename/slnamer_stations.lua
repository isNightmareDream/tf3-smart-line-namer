-- Smart Line Namer: the name every station group SHOULD have ("Town — Place").
-- Line names are built from these names, so the auto-rename preview already shows
-- the result of renaming the stations.
--
-- Place, by priority:
--   industry stop           -> short industry name        Сызрань — Шахта
--   airport / port          -> Аэропорт / Порт
--   first rail station      -> ЖД вокзал (others: by location)
--   first bus terminal      -> Автовокзал (others: by location)
--   near the town center    -> Центр
--   near the industrial zone-> Промзона
--   otherwise               -> direction from the center: Север / Юг / Восток / Запад
--   same place twice        -> numbered by entity id: Север, Север 2
-- Industry stops belong to the closest town (like vanilla names do), other stations
-- to their own town.
--
-- Plain Lua on purpose: no Teal compiler is available to typecheck this module.

local MIN_CENTER_RADIUS = 400
local CENTER_SHARE = 0.25      -- center radius = share of the farthest station distance
local INDUSTRIAL_SHARE = 0.75  -- industrial zone radius relative to the center radius
local CACHE_SECONDS = 2        -- the dialog calls us for every line; rebuild at most this often

local M = {}

local function tr(key)
	if _ then
		local ok, v = pcall(_, key)
		if ok and type(v) == "string" and v ~= "" then return v end
	end
	return key
end

-- Industries that produce exactly one cargo: the cargo is obvious from the name.
local SINGLE_OUTPUT = {
	coal_mine = true, iron_ore_mine = true, quarry = true, sand_pit = true,
	sand_excavator = true, clay_pit = true, forest = true, oil_well = true,
	oil_platform = true, fishing_grounds = true,
}

function M.isSingleOutputIndustry(id)
	return id ~= nil and SINGLE_OUTPUT[id] == true
end

-- Short name from strings.json ("ind_coal_mine"), else the game's own full name.
function M.industryName(id)
	local key = "ind_" .. id
	local short = tr(key)
	if short ~= key then return short end
	local vkey = "INDUSTRIES_" .. id:upper() .. "_NAME"
	local full = tr(vkey)
	if full ~= vkey then return full end
	return nil
end

local function comp(e, ct)
	local ok, c = pcall(api.engine.getComponent, e, ct)
	if ok then return c end
	return nil
end

local function valid(e)
	if not e or e == -1 then return false end
	local ok, exists = pcall(api.engine.entityExists, e)
	return ok and exists
end

local function constructionFile(con)
	if not valid(con) then return nil end
	local c = comp(con, api.type.ComponentType.CONSTRUCTION)
	return c and c.fileName and tostring(c.fileName) or nil
end

local function carriers(sg)
	local set = {}
	local ok, r = pcall(api.engine.system.stationGroupSystem.getCarriers, sg, -1, -1)
	if ok and r and r[1] then
		for _, c in ipairs(r[1]) do set[c] = true end
	end
	return set
end

local function center(e)
	local bb = comp(e, api.type.ComponentType.BOUNDING_VOLUME)
	if bb and bb.bbox and bb.bbox.min and bb.bbox.max then
		return (bb.bbox.min.x + bb.bbox.max.x) / 2, (bb.bbox.min.y + bb.bbox.max.y) / 2
	end
	return nil, nil
end

local function districtCenter(town, landUse)
	local ok, v = pcall(api.engine.util.town.getTownDistrictCenter, town, api.type["enum"].LandUseType[landUse])
	if ok and v then return v end
	return nil
end

local function direction(dx, dy)
	if math.abs(dy) >= math.abs(dx) then
		if dy > 0 then return tr("North") end
		return tr("South")
	end
	if dx > 0 then return tr("East") end
	return tr("West")
end

-- What a station group is, before the town-wide decisions (main station, numbering).
local function classify(sg, st, con, station2town)
	local info = { sg = sg }
	local file = constructionFile(con)
	info.industry = file and file:match("^::/industries/([%w_]+)/") or nil

	local town
	if info.industry then
		local ok, t = pcall(api.engine.system.streetConnectorSystem.getConstructionClosestTown, con)
		if ok then town = t end
	end
	if not valid(town) then town = station2town[st] end
	if not valid(town) and valid(con) then
		local ok, t = pcall(api.engine.system.streetConnectorSystem.getConstructionClosestTown, con)
		if ok then town = t end
	end
	if valid(town) then
		info.town = town
		info.townName = api.engine.util.getEntityName(town)
	end

	-- Unknown (modded) industry: keep its current name without the "Town — " prefix.
	if info.industry then
		local cur = api.engine.util.getEntityName(sg)
		if cur and info.townName then
			local prefix = info.townName .. " — "
			if cur:sub(1, #prefix) == prefix then cur = cur:sub(#prefix + 1) end
		end
		info.fallback = (cur and cur ~= "") and cur or nil
	end

	local E = api.type["enum"].Carrier
	local cs = carriers(sg)
	if info.industry then
		info.kind = "industry"
	elseif cs[E.AIR] then
		info.kind = "air"
	elseif cs[E.WATER] then
		info.kind = "water"
	elseif file and file:find("/stations/rail/", 1, true) then
		info.kind = "rail"
	elseif file and file:find("modular_terminal", 1, true) then
		info.kind = "terminal"
	else
		info.kind = "stop"
	end
	info.x, info.y = center(sg)
	return info
end

local function decideTown(town, list)
	local com = districtCenter(town, "COMMERCIAL")
	local ind = districtCenter(town, "INDUSTRIAL")
	table.sort(list, function(a, b) return a.sg < b.sg end)

	local far = 0
	if com then
		for _, s in ipairs(list) do
			if s.kind ~= "industry" and s.x then
				far = math.max(far, math.sqrt((s.x - com.x) ^ 2 + (s.y - com.y) ^ 2))
			end
		end
	end
	local radius = math.max(MIN_CENTER_RADIUS, far * CENTER_SHARE)

	-- Main rail station / bus terminal = the one closest to the town center.
	local function closest(kind)
		local best, bestD = nil, nil
		for _, s in ipairs(list) do
			if s.kind == kind then
				local d = (com and s.x) and ((s.x - com.x) ^ 2 + (s.y - com.y) ^ 2) or math.huge
				if not best or d < bestD then best, bestD = s, d end
			end
		end
		return best
	end
	local mainRail, mainTerminal = closest("rail"), closest("terminal")

	for _, s in ipairs(list) do
		if s.kind == "industry" then
			s.place = M.industryName(s.industry) or s.fallback
		elseif s.kind == "air" then
			s.place = tr("Airport")
		elseif s.kind == "water" then
			s.place = tr("Port")
		elseif s == mainRail then
			s.place = tr("RailStation")
		elseif s == mainTerminal then
			s.place = tr("BusStation")
		end
		if not s.place and s.x and com then
			local dx, dy = s.x - com.x, s.y - com.y
			if math.sqrt(dx * dx + dy * dy) < radius then
				s.place = tr("Center")
			elseif ind and math.sqrt((s.x - ind.x) ^ 2 + (s.y - ind.y) ^ 2) < radius * INDUSTRIAL_SHARE then
				s.place = tr("IndustrialZone")
			else
				s.place = direction(dx, dy)
			end
		end
	end

	-- Number repeated places in a stable order (entity id).
	local count = {}
	for _, s in ipairs(list) do
		if s.place then
			count[s.place] = (count[s.place] or 0) + 1
			if count[s.place] > 1 then s.place = s.place .. " " .. tostring(count[s.place]) end
		end
	end
end

local cache = nil
local builtAt = nil

local function now()
	local ok, t = pcall(os.clock)
	if ok then return t end
	return nil
end

local function build()
	local byGroup, byTown = {}, {}
	local okA, s2c = pcall(api.engine.system.streetConnectorSystem.getStation2ConstructionMap)
	local okB, s2t = pcall(api.engine.system.stationSystem.getStation2TownMap)
	if not okA or not s2c then s2c = {} end
	if not okB or not s2t then s2t = {} end
	for st, con in pairs(s2c) do
		local ok, sg = pcall(api.engine.system.stationGroupSystem.getStationGroup, st)
		if ok and valid(sg) and not byGroup[sg] then
			local okC, info = pcall(classify, sg, st, con, s2t)
			if okC and info then
				byGroup[sg] = info
				if info.town then
					byTown[info.town] = byTown[info.town] or {}
					table.insert(byTown[info.town], info)
				end
			end
		end
	end
	for town, list in pairs(byTown) do
		pcall(decideTown, town, list)
	end
	return byGroup
end

local function data()
	local t = now()
	if not cache or not t or not builtAt or t - builtAt > CACHE_SECONDS then
		cache = build()
		builtAt = t
	end
	return cache
end

-- { town = entity|nil, townName = string|nil, place = string|nil, industry = id|nil }
function M.info(sg)
	local d = data()
	local i = d[sg]
	if i == nil then
		-- unknown: maybe built after the cache; rebuild once and remember a miss as false
		cache = nil
		d = data()
		i = d[sg]
		if i == nil then d[sg] = false end
	end
	return i or nil
end

-- Full name the station group should get: "Town — Place".
function M.fullName(sg)
	local i = M.info(sg)
	if not i or not i.place then return nil end
	if i.townName then return i.townName .. " — " .. i.place end
	return i.place
end

return M
