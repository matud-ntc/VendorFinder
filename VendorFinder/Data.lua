-- VendorFinder — Data
-- Capa de datos: combina QuestieDB (base) con los vendors escaneados in-game (SavedVariables).
--
-- Entrada de vendor (lo que consumen UI y Map):
--   { npcId, name, subName, uiMapId, x, y, source = "questie"|"scan", price, distance, instanceId }
--   x, y van en 0..1 relativo al mapa (HereBeDragons usa ese rango).

local _, ns = ...
local Data = {}
ns.Data = Data

local HBD = LibStub("HereBeDragons-2.0")

-------------------------------------------------------------------------------
-- Índice de nombres de items (lazy, en chunks para no pisar el límite de script)
-------------------------------------------------------------------------------
local nameIndex          -- { {id=, name=, lname=, vendor=bool}, ... }  vendor=false: existe pero nadie lo vende
local indexedIds = {}    -- [itemId] = true para los que ya están en nameIndex
local indexing = false
local indexWaiters = {}

local function finishIndex()
    indexing = false
    local waiters = indexWaiters
    indexWaiters = {}
    for _, cb in ipairs(waiters) do cb() end
end

local function addScannedNames(seen)
    for itemId, name in pairs(ns.db.items) do
        if type(name) == "string" then
            if seen[itemId] then
                seen[itemId].vendor = true
            else
                local e = { id = itemId, name = name, lname = name:lower(), vendor = true }
                seen[itemId] = e
                nameIndex[#nameIndex + 1] = e
            end
        end
    end
end

local function BuildNameIndex(onDone)
    if nameIndex and not indexing then
        if onDone then onDone() end
        return
    end
    if onDone then indexWaiters[#indexWaiters + 1] = onDone end
    if indexing then return end

    indexing = true
    nameIndex = {}
    indexedIds = {}
    local seen = indexedIds

    if not ns.HasQuestieDB() then
        addScannedNames(seen)
        finishIndex()
        return
    end

    local Item = _G.LibQuestieDB.Item
    local ok, ids = pcall(Item.GetAllIds)
    if not ok or type(ids) ~= "table" then
        ns.Debug("Data: Item.GetAllIds falló: %s", tostring(ids))
        addScannedNames(seen)
        finishIndex()
        return
    end

    local total = #ids
    local i = 0
    local vendorCount = 0
    local CHUNK = 400
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self)
        local stop = math.min(i + CHUNK, total)
        while i < stop do
            i = i + 1
            local id = ids[i]
            local okName, name = pcall(Item.name, id)
            if okName and type(name) == "string" and name ~= "" then
                local okV, vendors = pcall(Item.vendors, id)
                local hasVendor = okV and type(vendors) == "table" and #vendors > 0
                local e = { id = id, name = name, lname = name:lower(), vendor = hasVendor }
                seen[id] = e
                nameIndex[#nameIndex + 1] = e
                if hasVendor then vendorCount = vendorCount + 1 end
            end
        end
        if ns.UI.SetStatus then ns.UI.SetStatus(("Indexando items… %d/%d"):format(i, total)) end
        if i >= total then
            self:SetScript("OnUpdate", nil)
            addScannedNames(seen)
            ns.Debug("Data: índice con %d items, %d con vendedor", #nameIndex, vendorCount)
            if ns.UI.SetStatus then ns.UI.SetStatus(nil) end
            finishIndex()
        end
    end)
end
Data.BuildNameIndex = BuildNameIndex

function Data.IsIndexing() return indexing end

-- Un item visto en un mercader: lo sumamos al índice en caliente (si ya está armado).
function Data.NoteScannedItem(itemId, name)
    if type(name) ~= "string" or name == "" then return end
    ns.db.items[itemId] = name
    if nameIndex and not indexing then
        if indexedIds[itemId] then
            indexedIds[itemId].vendor = true
        else
            local e = { id = itemId, name = name, lname = name:lower(), vendor = true }
            indexedIds[itemId] = e
            nameIndex[#nameIndex + 1] = e
        end
    end
end

-------------------------------------------------------------------------------
-- Búsqueda de items
-------------------------------------------------------------------------------
local function itemIdFromLink(text)
    return tonumber(text:match("item:(%d+)"))
end

function Data.ItemName(itemId)
    if ns.HasQuestieDB() then
        local ok, name = pcall(_G.LibQuestieDB.Item.name, itemId)
        if ok and name then return name end
    end
    if ns.db.items[itemId] then return ns.db.items[itemId] end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemId)
    return name or ("item " .. itemId)
end

-- Devuelve lista de { id, name } (solo items con vendedor) ordenada: prefijo primero, luego por nombre.
-- Segundo valor: nombre del mejor match entre los items que existen pero nadie vende (para avisar), o nil.
-- Si el índice todavía no está, llama onDone cuando esté listo (y devuelve nil mientras tanto).
function Data.SearchItems(query, onDone)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return {} end

    -- link de item pegado o id numérico
    local directId = itemIdFromLink(query) or tonumber(query)
    if directId then
        return { { id = directId, name = Data.ItemName(directId) } }
    end

    if not nameIndex or indexing then
        BuildNameIndex(onDone)
        return nil
    end

    local q = query:lower()
    local prefix, contains = {}, {}
    local noVendorExact, noVendorPrefix, noVendorAny
    for _, e in ipairs(nameIndex) do
        local pos = e.lname:find(q, 1, true)
        if pos then
            if e.vendor then
                if pos == 1 then prefix[#prefix + 1] = e else contains[#contains + 1] = e end
            elseif e.lname == q then
                noVendorExact = noVendorExact or e.name
            elseif pos == 1 then
                noVendorPrefix = noVendorPrefix or e.name
            else
                noVendorAny = noVendorAny or e.name
            end
        end
    end
    table.sort(prefix, function(a, b) return a.lname < b.lname end)
    table.sort(contains, function(a, b) return a.lname < b.lname end)

    local out = {}
    for _, e in ipairs(prefix) do out[#out + 1] = { id = e.id, name = e.name } end
    for _, e in ipairs(contains) do out[#out + 1] = { id = e.id, name = e.name } end
    return out, (noVendorExact or noVendorPrefix or noVendorAny)
end

-------------------------------------------------------------------------------
-- Vendors de un item
-------------------------------------------------------------------------------
local function playerWorldPos()
    local x, y, instance = HBD:GetPlayerWorldPosition()
    return x, y, instance
end

local function addDistance(entry, px, py, pInstance)
    if not entry.uiMapId then return end
    local wx, wy, instance = HBD:GetWorldCoordinatesFromZone(entry.x, entry.y, entry.uiMapId)
    entry.instanceId = instance
    if wx and px and instance == pInstance then
        entry.distance = HBD:GetWorldDistance(instance, px, py, wx, wy)
    end
end

-- Llama a un getter de LibQuestieDB protegido; devuelve nil si falla.
local function get(fn, id)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, id)
    if ok then return value end
    ns.Debug("Data: getter falló para %s: %s", tostring(id), tostring(value))
    return nil
end

local function questieVendors(itemId, out)
    if not ns.HasQuestieDB() then return end
    local Item, Npc = _G.LibQuestieDB.Item, _G.LibQuestieDB.Npc

    local vendors = get(Item.vendors, itemId)
    if type(vendors) ~= "table" then return end

    local myFaction = ns.PlayerFactionTag()

    for _, npcId in ipairs(vendors) do
        local friendly = get(Npc.friendlyToFaction, npcId)
        -- nil = hostil a ambas facciones; "A"/"H"/"AH"
        local visible = friendly and (friendly == "AH" or friendly == myFaction)
        if visible then
            local name = get(Npc.name, npcId) or ("npc " .. npcId)
            local subName = get(Npc.subName, npcId)
            local spawns = get(Npc.spawns, npcId)
            if type(spawns) == "table" then
                for areaId, list in pairs(spawns) do
                    local uiMapId = ns.Zones.GetUiMapId(areaId)
                    for _, spawn in ipairs(list) do
                        local sx, sy = spawn[1], spawn[2]
                        -- Questie guarda coords 0..100; -1 significa "sin posición"
                        if sx and sy and sx >= 0 and sy >= 0 then
                            out[#out + 1] = {
                                npcId = npcId,
                                name = name,
                                subName = type(subName) == "string" and subName or nil,
                                uiMapId = uiMapId,
                                areaId = areaId,
                                x = sx / 100,
                                y = sy / 100,
                                source = "questie",
                            }
                        end
                    end
                end
            else
                -- vendor conocido pero sin spawns: lo listamos igual, sin mapa
                out[#out + 1] = { npcId = npcId, name = name, subName = subName, source = "questie" }
            end
        end
    end
end

local function scannedVendors(itemId, out)
    for npcId, v in pairs(ns.db.vendors) do
        if v.items and v.items[itemId] then
            out[#out + 1] = {
                npcId = npcId,
                name = v.name,
                subName = v.subName,
                uiMapId = v.uiMapId,
                x = v.x,
                y = v.y,
                price = type(v.items[itemId]) == "table" and v.items[itemId].price or nil,
                source = "scan",
            }
        end
    end
end

-- Lista de vendors para un item, ordenada por cercanía.
-- opts.onlyCurrentZone: filtra a la zona (UiMapID) actual del jugador.
function Data.VendorsForItem(itemId, opts)
    opts = opts or {}
    local out = {}
    scannedVendors(itemId, out)
    questieVendors(itemId, out)

    -- Si un NPC fue escaneado, la posición escaneada manda: sacamos los spawns de Questie de ese NPC.
    local scanned = {}
    for _, e in ipairs(out) do
        if e.source == "scan" then scanned[e.npcId] = true end
    end
    local merged = {}
    for _, e in ipairs(out) do
        if e.source == "scan" or not scanned[e.npcId] then
            merged[#merged + 1] = e
        end
    end

    local px, py, pInstance = playerWorldPos()
    for _, e in ipairs(merged) do addDistance(e, px, py, pInstance) end

    if opts.onlyCurrentZone then
        local zone = ns.Zones.PlayerZoneMap()
        local filtered = {}
        for _, e in ipairs(merged) do
            if e.uiMapId == zone then filtered[#filtered + 1] = e end
        end
        merged = filtered
    end

    table.sort(merged, function(a, b)
        -- misma instancia/continente con distancia conocida primero, luego el resto por nombre
        if a.distance and b.distance then return a.distance < b.distance end
        if a.distance then return true end
        if b.distance then return false end
        return (a.name or "") < (b.name or "")
    end)

    return merged
end

function Data.FormatDistance(d)
    if not d then return "" end
    if d >= 1000 then return ("%.1f km"):format(d / 1000) end
    return ("%d yd"):format(d)
end
