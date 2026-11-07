-- VendorFinder — Map
-- Pines en el mapa del mundo y minimapa (HereBeDragons-Pins), waypoint nativo y TomTom opcional.

local _, ns = ...
local Map = {}
ns.Map = Map

local HBD = LibStub("HereBeDragons-2.0")
local HBDPins = LibStub("HereBeDragons-Pins-2.0")

local VENDOR_ICON = "Interface\\GossipFrame\\VendorGossipIcon"

local worldPins, minimapPins = {}, {}

local function makePin(size, entry)
    local pin = CreateFrame("Frame", nil, UIParent)
    pin:SetSize(size, size)
    local tex = pin:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(VENDOR_ICON)
    pin.texture = tex
    pin.entry = entry

    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.entry.name or "?", 1, 1, 1)
        if self.entry.subName then GameTooltip:AddLine(self.entry.subName, 0.8, 0.8, 0.8) end
        if self.entry.itemName then GameTooltip:AddLine("Vende: " .. self.entry.itemName, 0.3, 0.8, 1) end
        GameTooltip:AddLine(("%s (%.1f, %.1f)"):format(ns.Zones.MapName(self.entry.uiMapId), self.entry.x * 100, self.entry.y * 100), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(self.entry.source == "scan" and "Fuente: escaneado por vos" or "Fuente: QuestieDB", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

function Map.Clear()
    HBDPins:RemoveAllWorldMapIcons(ns)
    HBDPins:RemoveAllMinimapIcons(ns)
    for _, p in ipairs(worldPins) do p:Hide() end
    for _, p in ipairs(minimapPins) do p:Hide() end
    wipe(worldPins)
    wipe(minimapPins)
    if C_Map.ClearUserWaypoint and Map.setWaypoint then
        C_Map.ClearUserWaypoint()
        Map.setWaypoint = false
    end
end

local function setNativeWaypoint(entry)
    if not ns.db.settings.useNativeWaypoint then return false end
    if not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(entry.uiMapId)) then return false end
    local point = UiMapPoint.CreateFromCoordinates(entry.uiMapId, entry.x, entry.y)
    C_Map.SetUserWaypoint(point)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    Map.setWaypoint = true
    return true
end

local function setTomTom(entry)
    if not ns.db.settings.useTomTom then return false end
    local TomTom = _G.TomTom
    if not (TomTom and TomTom.AddWaypoint) then return false end
    local ok = pcall(TomTom.AddWaypoint, TomTom, entry.uiMapId, entry.x, entry.y, {
        title = (entry.name or "Vendor") .. (entry.itemName and (" — " .. entry.itemName) or ""),
        persistent = false,
        minimap = true,
        world = true,
    })
    return ok
end

-- Marca un vendor. Si `keep` es false, borra las marcas anteriores.
function Map.ShowVendor(entry, keep)
    if not entry or not entry.uiMapId or not entry.x then
        ns.Print("Ese vendor no tiene posición conocida.")
        return
    end
    if not keep then Map.Clear() end

    local wp = makePin(20, entry)
    HBDPins:AddWorldMapIconMap(ns, wp, entry.uiMapId, entry.x, entry.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
    worldPins[#worldPins + 1] = wp

    if ns.db.settings.showMinimap then
        local mp = makePin(14, entry)
        HBDPins:AddMinimapIconMap(ns, mp, entry.uiMapId, entry.x, entry.y, true, true)
        minimapPins[#minimapPins + 1] = mp
    end

    local native = setNativeWaypoint(entry)
    local tomtom = setTomTom(entry)

    ns.Print("%s%s — %s (%.1f, %.1f)%s",
        entry.name or "?",
        entry.subName and (" <" .. entry.subName .. ">") or "",
        ns.Zones.MapName(entry.uiMapId), entry.x * 100, entry.y * 100,
        (native or tomtom) and " — waypoint activado" or "")
end

-- Marca todos los vendors de una lista (por ejemplo todos los que venden un item en la zona).
function Map.ShowVendors(list, itemName)
    Map.Clear()
    local first = true
    for _, e in ipairs(list) do
        if e.uiMapId and e.x then
            e.itemName = itemName
            if first then
                Map.ShowVendor(e, true)
                first = false
            else
                local wp = makePin(16, e)
                HBDPins:AddWorldMapIconMap(ns, wp, e.uiMapId, e.x, e.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
                worldPins[#worldPins + 1] = wp
            end
        end
    end
end

function Map.OpenMapAt(uiMapId)
    if not uiMapId then return end
    if not WorldMapFrame:IsShown() then ToggleWorldMap() end
    WorldMapFrame:SetMapID(uiMapId)
end
