-- VendorFinder — Core
-- Namespace, saved variables, eventos y slash commands.

local ADDON_NAME, ns = ...
_G.VendorFinder = ns -- útil para debuggear desde /run

ns.name = ADDON_NAME
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local DEFAULTS = {
    settings = {
        onlyCurrentZone = false,  -- filtrar vendors a la zona actual
        useNativeWaypoint = true, -- C_Map.SetUserWaypoint + supertrack
        useTomTom = true,         -- si TomTom está cargado, agregar waypoint
        showMinimap = true,
    },
    -- vendors escaneados in-game: [npcId] = { name, subName, uiMapId, x, y, items = { [itemId] = true }, seen }
    vendors = {},
    -- nombres de items vistos en mercaderes: [itemId] = name
    items = {},
}

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[VF]|r " .. msg)
end

function ns.Debug(...)
    if ns.db and ns.db.settings.debug then
        ns.Print(...)
    end
end

-- Fuente de datos de Questie (addon QuestieDB, global LibQuestieDB)
function ns.HasQuestieDB()
    return type(_G.LibQuestieDB) == "table"
        and type(_G.LibQuestieDB.Item) == "table"
        and type(_G.LibQuestieDB.Npc) == "table"
end

function ns.PlayerFactionTag()
    local f = UnitFactionGroup("player")
    if f == "Alliance" then return "A" elseif f == "Horde" then return "H" end
    return nil
end

-- Event dispatcher
local frame = CreateFrame("Frame")
ns.eventFrame = frame
ns.handlers = {}

function ns.RegisterEvent(event, fn)
    ns.handlers[event] = ns.handlers[event] or {}
    table.insert(ns.handlers[event], fn)
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = ns.handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        fn(...)
    end
end)

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    VendorFinderDB = copyDefaults(VendorFinderDB or {}, DEFAULTS)
    ns.db = VendorFinderDB
    if ns.OnInit then ns.OnInit() end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    if not ns.HasQuestieDB() then
        ns.Print("QuestieDB no está cargado: solo voy a usar los vendors que escanees vos. Instalá el bundle Questie + QuestieDB para tener la base completa.")
    end
end)

-- Slash commands
SLASH_VENDORFINDER1 = "/vf"
SLASH_VENDORFINDER2 = "/vendorfinder"
SlashCmdList.VENDORFINDER = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")

    if cmd == "clear" then
        ns.Map.Clear()
        ns.Print("Marcas borradas.")
    elseif cmd == "stats" then
        local v, i = 0, 0
        for _ in pairs(ns.db.vendors) do v = v + 1 end
        for _ in pairs(ns.db.items) do i = i + 1 end
        ns.Print("Escaneados: %d vendors, %d items. QuestieDB: %s", v, i, ns.HasQuestieDB() and "sí" or "no")
    elseif cmd == "debug" then
        ns.db.settings.debug = not ns.db.settings.debug
        ns.Print("Debug %s", ns.db.settings.debug and "on" or "off")
    elseif cmd == "zone" then
        ns.db.settings.onlyCurrentZone = not ns.db.settings.onlyCurrentZone
        ns.Print("Solo zona actual: %s", ns.db.settings.onlyCurrentZone and "on" or "off")
        if ns.UI.Refresh then ns.UI.Refresh() end
    elseif cmd == "diag" then
        local v, b, _, iface = GetBuildInfo()
        ns.Print("Cliente %s (build %s, interface %s), WOW_PROJECT_ID=%s", tostring(v), tostring(b), tostring(iface), tostring(WOW_PROJECT_ID))
        local A = C_AddOns
        for _, name in ipairs({ "QuestieDB", "Questie", "VendorFinder" }) do
            local okInfo, _, title, _, loadable, reason = pcall(A.GetAddOnInfo, name)
            local loaded = A.IsAddOnLoaded(name)
            local enabled = A.GetAddOnEnableState and A.GetAddOnEnableState(name, UnitName("player")) or "?"
            ns.Print("%s: loadable=%s reason=%s loaded=%s enableState=%s", name,
                tostring(okInfo and loadable), tostring(okInfo and reason or title), tostring(loaded), tostring(enabled))
        end
        ns.Print("LibQuestieDB=%s Item=%s Npc=%s QuestieLoader=%s",
            tostring(_G.LibQuestieDB), tostring(_G.LibQuestieDB and _G.LibQuestieDB.Item),
            tostring(_G.LibQuestieDB and _G.LibQuestieDB.Npc), tostring(_G.QuestieLoader))
        if _G.LibQuestieDB and _G.LibQuestieDB.flavor then
            ns.Print("QuestieDB flavor=%s mode=%s", tostring(_G.LibQuestieDB.flavor.name), tostring(_G.LibQuestieDB.mode))
        end
        ns.Print("Para ver errores de Lua: /console scriptErrors 1 y después /reload")
    elseif cmd == "help" then
        ns.Print("/vf [item]  — abrir buscador (opcionalmente con búsqueda)")
        ns.Print("/vf clear   — borrar marcas del mapa")
        ns.Print("/vf zone    — alternar filtro de zona actual")
        ns.Print("/vf stats   — datos escaneados")
    else
        ns.UI.Toggle(msg ~= "" and msg or nil)
    end
end
