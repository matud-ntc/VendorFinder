-- VendorFinder — Scanner
-- Cada vez que abrís un mercader, registramos qué vende y dónde está parado.
-- Esto cubre lo que a QuestieDB le falta (contenido nuevo de Forever, vendors movidos, precios).

local _, ns = ...
local Scanner = {}
ns.Scanner = Scanner

local function npcIdFromGuid(guid)
    if not guid then return nil end
    -- Creature-0-[serverId]-[instanceId]-[zoneUID]-[npcId]-[spawnUID]
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    return tonumber(npcId)
end

local function playerMapPosition()
    local uiMapId = C_Map.GetBestMapForUnit("player")
    if not uiMapId then return nil end
    local pos = C_Map.GetPlayerMapPosition(uiMapId, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y then return nil end
    return uiMapId, x, y
end

function Scanner.ScanMerchant()
    local guid = UnitGUID("npc")
    local npcId = npcIdFromGuid(guid)
    if not npcId then return end

    local uiMapId, x, y = playerMapPosition()
    local name = UnitName("npc")

    local v = ns.db.vendors[npcId] or { items = {} }
    v.name = name or v.name
    v.seen = time()
    if uiMapId and x and y then
        -- la posición del jugador al abrir el mercader es "suficientemente" la del NPC
        v.uiMapId, v.x, v.y = uiMapId, x, y
    end
    v.items = v.items or {}

    local n = GetMerchantNumItems() or 0
    local added = 0
    for i = 1, n do
        local link = GetMerchantItemLink(i)
        local itemId = link and tonumber(link:match("item:(%d+)"))
        if itemId then
            local itemName, price
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = C_MerchantFrame.GetItemInfo(i)
                if info then itemName, price = info.name, info.price end
            elseif GetMerchantItemInfo then
                itemName, _, price = GetMerchantItemInfo(i)
            end
            -- Nota: en Midnight/Forever algunos valores pueden volver como "secret" dentro de combate;
            -- abrir un mercader fuera de combate es el caso normal, pero igual lo protegemos.
            if type(price) ~= "number" then price = nil end
            if not v.items[itemId] then added = added + 1 end
            v.items[itemId] = { price = price }
            local finalName = (type(itemName) == "string" and itemName ~= "") and itemName or (link and link:match("%[(.-)%]"))
            if finalName then ns.Data.NoteScannedItem(itemId, finalName) end
        end
    end

    ns.db.vendors[npcId] = v
    if added > 0 then
        ns.Print("%s: %d items nuevos registrados (%d en total).", name or ("npc " .. npcId), added, n)
    end
    ns.Debug("Scanner: npc %d en map %s (%.3f, %.3f)", npcId, tostring(uiMapId), x or -1, y or -1)
end

function Scanner.Init()
    ns.RegisterEvent("MERCHANT_SHOW", function()
        -- un frame después: a veces el inventario del mercader todavía no está poblado en MERCHANT_SHOW
        C_Timer.After(0.1, Scanner.ScanMerchant)
    end)
    -- MERCHANT_UPDATE se dispara cuando cambia el stock (items con cantidad limitada)
    ns.RegisterEvent("MERCHANT_UPDATE", function()
        if MerchantFrame and MerchantFrame:IsShown() then Scanner.ScanMerchant() end
    end)
end
