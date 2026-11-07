-- VendorFinder — Zones
-- Questie guarda spawns por AreaId (ids de zona de cmangos), pero el cliente dibuja mapas por UiMapID.
-- Resolvemos AreaId -> UiMapID usando:
--   1. ZoneDB de Questie (si Questie está cargado), o
--   2. las tablas que QuestieDB publica en LibQuestieDB.Support.Get("ZoneDB") (vienen como chunks Lua serializados).

local _, ns = ...
local Zones = {}
ns.Zones = Zones

local areaToUiMap   -- [areaId] = uiMapId
local uiMapToArea   -- [uiMapId] = areaId

local function decodeChunk(src, label)
    if type(src) == "table" then return src end
    if type(src) ~= "string" then return nil end
    local chunk = loadstring(src, "=VendorFinder." .. label)
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    if ok and type(value) == "table" then return value end
    return nil
end

local function build()
    areaToUiMap, uiMapToArea = {}, {}

    if not ns.HasQuestieDB() then return end
    local Support = _G.LibQuestieDB.Support
    if type(Support) ~= "table" or type(Support.Get) ~= "function" then return end

    local ok, zoneData = pcall(Support.Get, "ZoneDB")
    if not ok or type(zoneData) ~= "table" or type(zoneData.private) ~= "table" then
        ns.Debug("Zones: no pude leer Support.Get('ZoneDB')")
        return
    end
    local p = zoneData.private

    local a2u = decodeChunk(p.areaIdToUiMapId, "areaIdToUiMapId") or {}
    local a2uOverride = decodeChunk(p.areaIdToUiMapIdOverride, "areaIdToUiMapIdOverride") or {}
    for areaId, uiMapId in pairs(a2u) do areaToUiMap[areaId] = uiMapId end
    for areaId, uiMapId in pairs(a2uOverride) do areaToUiMap[areaId] = uiMapId end

    local u2a = decodeChunk(p.uiMapIdToAreaId, "uiMapIdToAreaId") or {}
    local u2aOverride = decodeChunk(p.uiMapIdToAreaIdOverride, "uiMapIdToAreaIdOverride") or {}
    for uiMapId, areaId in pairs(u2a) do uiMapToArea[uiMapId] = areaId end
    for uiMapId, areaId in pairs(u2aOverride) do uiMapToArea[uiMapId] = areaId end

    local n = 0
    for _ in pairs(areaToUiMap) do n = n + 1 end
    ns.Debug("Zones: %d zonas mapeadas", n)
end

-- Si Questie (el addon completo) está cargado, su ZoneDB ya aplicó overrides y correcciones: lo preferimos.
local function questieZoneDB()
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, zdb = pcall(loader.ImportModule, loader, "ZoneDB")
    if ok and type(zdb) == "table" and type(zdb.GetUiMapIdByAreaId) == "function" then
        return zdb
    end
    return nil
end

function Zones.GetUiMapId(areaId)
    local zdb = questieZoneDB()
    if zdb then
        local ok, id = pcall(zdb.GetUiMapIdByAreaId, zdb, areaId)
        if ok and id then return id end
    end
    if not areaToUiMap then build() end
    return areaToUiMap[areaId]
end

function Zones.GetAreaId(uiMapId)
    local zdb = questieZoneDB()
    if zdb and type(zdb.GetAreaIdByUiMapId) == "function" then
        local ok, id = pcall(zdb.GetAreaIdByUiMapId, zdb, uiMapId)
        if ok and id then return id end
    end
    if not uiMapToArea then build() end
    return uiMapToArea[uiMapId]
end

function Zones.MapName(uiMapId)
    if not uiMapId then return "?" end
    local info = C_Map.GetMapInfo(uiMapId)
    return info and info.name or ("map " .. tostring(uiMapId))
end

-- Mapa actual del jugador y su "zona" (subiendo desde micro-dungeons / subzonas hasta el nivel de zona)
function Zones.PlayerZoneMap()
    local uiMapId = C_Map.GetBestMapForUnit("player")
    if not uiMapId then return nil end
    local info = C_Map.GetMapInfo(uiMapId)
    -- Enum.UIMapType: Cosmic 0, World 1, Continent 2, Zone 3, Dungeon 4, Micro 5, Orphan 6
    while info and info.mapType and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info and info.mapID or uiMapId
end

function Zones.Reset()
    areaToUiMap, uiMapToArea = nil, nil
end
