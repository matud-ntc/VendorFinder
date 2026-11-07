-- VendorFinder — UI
-- Ventana de búsqueda: escribís el item, elegís el vendor, se marca en el mapa.

local _, ns = ...
local UI = {}
ns.UI = UI

local ROWS = 14
local ROW_HEIGHT = 22

local frame
local state = {
    mode = "items",     -- "items" | "vendors"
    query = "",
    items = {},
    noVendorMatch = nil, -- nombre de un item que coincide pero nadie vende
    item = nil,         -- { id, name } seleccionado
    vendors = {},
}

local function setStatus(text)
    if frame then frame.status:SetText(text or "") end
end
UI.SetStatus = setStatus

local function rowText(row, left, right, color)
    row.left:SetText(left or "")
    row.right:SetText(right or "")
    if color then row.left:SetTextColor(unpack(color)) else row.left:SetTextColor(1, 1, 1) end
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    local list = state.mode == "items" and state.items or state.vendors
    local total = #list
    FauxScrollFrame_Update(frame.scroll, total, ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(frame.scroll)

    for i = 1, ROWS do
        local row = frame.rows[i]
        local idx = i + offset
        local entry = list[idx]
        row.entry = entry
        if entry then
            if state.mode == "items" then
                rowText(row, entry.name, "#" .. entry.id)
            else
                local left = entry.name or "?"
                if entry.subName then left = left .. " |cff999999<" .. entry.subName .. ">|r" end
                local right
                if entry.uiMapId then
                    right = ns.Zones.MapName(entry.uiMapId)
                    if entry.distance then right = right .. " · " .. ns.Data.FormatDistance(entry.distance) end
                else
                    right = "|cff666666sin posición|r"
                end
                if entry.price then
                    local coin = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
                    right = (coin and coin(entry.price) or tostring(entry.price)) .. "  " .. right
                end
                rowText(row, left, right, entry.source == "scan" and { 0.6, 1, 0.6 } or nil)
            end
            row:Show()
        else
            row:Hide()
        end
    end

    if state.mode == "items" then
        frame.back:Hide()
        frame.markAll:Hide()
        frame.title:SetText("VendorFinder")
        if total == 0 and state.query ~= "" and not ns.Data.IsIndexing() then
            if state.noVendorMatch then
                setStatus(("|cffffd100%s|r existe, pero ningún NPC lo vende: seguramente se consigue por drop, quest o profesión."):format(state.noVendorMatch))
            elseif ns.HasQuestieDB() then
                setStatus("Ningún item con ese nombre. Revisá cómo está escrito (el nombre tiene que ser el que aparece en el juego, en inglés).")
            else
                setStatus("Sin resultados para \"" .. state.query .. "\" (sin QuestieDB solo conozco lo que escaneaste)")
            end
        elseif not ns.Data.IsIndexing() then
            setStatus(total > 0 and (total .. " items con vendedor") or "Escribí el nombre de un item, pegá un link o un id")
        end
    else
        frame.back:Show()
        frame.markAll:Show()
        frame.title:SetText(state.item and state.item.name or "Vendors")
        setStatus(total > 0 and (total .. " vendors" .. (ns.db.settings.onlyCurrentZone and " en esta zona" or ""))
            or ("Nadie vende esto" .. (ns.db.settings.onlyCurrentZone and " en esta zona" or " (según QuestieDB y tus escaneos)")))
    end
end
UI.Refresh = refresh

local function runSearch()
    state.mode = "items"
    local items, noVendorMatch = ns.Data.SearchItems(state.query, function()
        -- índice listo: volvemos a buscar
        if frame and frame:IsShown() then runSearch() end
    end)
    state.items = items or {}
    state.noVendorMatch = noVendorMatch
    FauxScrollFrame_SetOffset(frame.scroll, 0)
    refresh()
end

local function loadVendors(item)
    state.item = item
    state.mode = "vendors"
    state.vendors = ns.Data.VendorsForItem(item.id, { onlyCurrentZone = ns.db.settings.onlyCurrentZone })
    FauxScrollFrame_SetOffset(frame.scroll, 0)
    refresh()
end

local function onRowClick(row, button)
    local entry = row.entry
    if not entry then return end
    if state.mode == "items" then
        loadVendors(entry)
    else
        entry.itemName = state.item and state.item.name
        if button == "RightButton" then
            ns.Map.OpenMapAt(entry.uiMapId)
        else
            ns.Map.ShowVendor(entry, IsShiftKeyDown())
            if IsControlKeyDown() then ns.Map.OpenMapAt(entry.uiMapId) end
        end
    end
end

local function build()
    frame = CreateFrame("Frame", "VendorFinderFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 70 + ROWS * ROW_HEIGHT + 40)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "VendorFinderFrame") -- ESC cierra

    frame.title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not frame.TitleText then frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -5) end
    frame.title:SetText("VendorFinder")

    -- Búsqueda
    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(230, 24)
    edit:SetPoint("TOPLEFT", 16, -32)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    frame.edit = edit

    local pending
    edit:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        state.query = self:GetText()
        if pending then pending:Cancel() end
        pending = C_Timer.NewTimer(0.25, function()
            pending = nil
            if #state.query >= 2 or tonumber(state.query) then runSearch() else state.items = {}; state.mode = "items"; refresh() end
        end)
    end)
    edit:SetScript("OnEnterPressed", function(self)
        state.query = self:GetText()
        runSearch()
        -- si hay un único resultado, saltamos directo a los vendors
        if #state.items == 1 then loadVendors(state.items[1]) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Checkbox zona actual
    local zoneCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    zoneCheck:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    zoneCheck:SetSize(24, 24)
    local zoneLabel = zoneCheck.Text or zoneCheck.text
    if not zoneLabel then
        zoneLabel = zoneCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        zoneLabel:SetPoint("LEFT", zoneCheck, "RIGHT", 2, 0)
    end
    zoneLabel:SetText("Zona actual")
    zoneCheck:SetChecked(ns.db.settings.onlyCurrentZone)
    zoneCheck:SetScript("OnClick", function(self)
        ns.db.settings.onlyCurrentZone = self:GetChecked() and true or false
        if state.mode == "vendors" and state.item then loadVendors(state.item) end
    end)
    frame.zoneCheck = zoneCheck

    -- Status
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -4, -4)
    frame.status:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.status:SetJustifyH("LEFT")

    -- Volver / marcar todos
    frame.back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.back:SetSize(70, 20)
    frame.back:SetPoint("BOTTOMLEFT", 12, 10)
    frame.back:SetText("← Volver")
    frame.back:SetScript("OnClick", function()
        state.mode = "items"
        refresh()
    end)

    frame.markAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.markAll:SetSize(110, 20)
    frame.markAll:SetPoint("LEFT", frame.back, "RIGHT", 6, 0)
    frame.markAll:SetText("Marcar todos")
    frame.markAll:SetScript("OnClick", function()
        ns.Map.ShowVendors(state.vendors, state.item and state.item.name)
    end)

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(90, 20)
    clear:SetPoint("BOTTOMRIGHT", -12, 10)
    clear:SetText("Borrar marcas")
    clear:SetScript("OnClick", function() ns.Map.Clear() end)

    -- Lista
    local scroll = CreateFrame("ScrollFrame", "VendorFinderScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame.status, "BOTTOMLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 36)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refresh)
    end)
    frame.scroll = scroll

    frame.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", onRowClick)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        row.left = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.left:SetPoint("LEFT", 6, 0)
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)

        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.right:SetPoint("RIGHT", -6, 0)
        row.right:SetJustifyH("RIGHT")
        row.right:SetWordWrap(false)

        row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)

        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if state.mode == "items" then
                local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local link = getInfo and select(2, getInfo(self.entry.id))
                if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(self.entry.name) end
            else
                GameTooltip:AddLine(self.entry.name or "?", 1, 1, 1)
                GameTooltip:AddLine("Click: marcar en el mapa", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Shift+Click: agregar sin borrar las otras marcas", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Ctrl+Click / Click derecho: abrir el mapa en la zona", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.rows[i] = row
    end

    frame:SetScript("OnShow", function()
        zoneCheck:SetChecked(ns.db.settings.onlyCurrentZone)
        refresh()
    end)
end

function UI.Toggle(query)
    if not frame then build() end
    if query then
        frame:Show()
        frame.edit:SetText(query)
        state.query = query
        runSearch()
        if #state.items == 1 then loadVendors(state.items[1]) end
    elseif frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        frame.edit:SetFocus()
    end
end

function ns.OnInit()
    ns.Scanner.Init()
    -- Pre-armamos el índice de nombres unos segundos después de entrar, para que la primera búsqueda sea instantánea
    C_Timer.After(8, function() ns.Data.BuildNameIndex() end)
end
