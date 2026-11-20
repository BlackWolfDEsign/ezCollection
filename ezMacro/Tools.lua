local _, ns = ...
local UI = ns.UI

-- Werkzeuge im Makro-Browser: links in der Liste, rechts die Seite des gewählten Werkzeugs anstelle der
-- Makro-Erklärung. Reiter nach Entwurf A (Frage 14): Pflege-Werkzeuge (Ränge, Sichern, ohne Leiste, lange Makros,
-- Leisten-Profile, Kleine Helfer) im Reiter „Werkzeuge“, die Ein-Tasten-Werkzeuge (Angeln, Öffnen und Entzaubern,
-- Begleiter) mit place = "oneclick" im Reiter „Ein-Klick“.
-- Ein Werkzeug meldet sich mit Tools.Register an:
--   key, order, icon (Symbolname oder Liste), name, why (Unterzeile in der Liste), desc (Text auf der Seite),
--   status() (kurzer Stand, z. B. „vor 2 Std. gesichert“), shown() (optional), build(panel), refresh(panel),
--   place (optional: Reiter, Standard „tools“)
local Tools = { defs = {} }
ns.Tools = Tools

local panels = {}

function Tools.Register(def)
    def.tool, def.category = true, "tools"
    def.id = "tool:" .. def.key
    def.desc = def.desc or ""
    def.place = def.place or "tools"
    table.insert(Tools.defs, def)
    table.sort(Tools.defs, function(a, b) return (a.order or 99) < (b.order or 99) end)
    return def
end

function Tools.Get(key)
    for _, def in ipairs(Tools.defs) do
        if def.key == key then return def end
    end
    return nil
end

-- Sichtbare Werkzeuge in ihrer Reihenfolge; place: nur die eines Reiters („tools“ oder „oneclick“), ohne: alle.
function Tools.Entries(place)
    local list = {}
    for _, def in ipairs(Tools.defs) do
        if (place == nil or def.place == place) and (not def.shown or def.shown()) then list[#list + 1] = def end
    end
    return list
end

function Tools.Status(def)
    if not def.status then return nil end
    local ok, text = pcall(def.status)
    return ok and text or nil
end

-- Seitengerüst wie die Makro-Erklärung: Symbol im UI-EmptySlot-Rahmen, Titel, Stand, Beschreibung.
-- Darunter baut das Werkzeug seinen Teil (panel.top ist der Anker, panel.width die nutzbare Breite).
local function Build(def, parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.width = ns.DETAIL_W or 400

    -- Maße wie Blizzards gewähltes Makro (Blizzard_MacroUI.xml: UI-EmptySlot 64 × 64, Symbol 36 × 36 bei 14/−14) –
    -- folgen einem Blizzard-Teil, bleiben bewusst außerhalb Core.Style.ICON (Design-System 2.3)
    local slot = panel:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    slot:SetSize(64, 64)
    slot:SetPoint("TOPLEFT", 0, 4)
    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(36, 36)
    panel.icon:SetPoint("TOPLEFT", 14, -10)
    panel.icon:SetTexture(ns.IconPath(def.icon))

    panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 18, -2)
    panel.title:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetText(def.name)

    panel.status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    panel.status:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)

    panel.desc = UI.Text(panel, "GameFontHighlightSmall", panel.width)
    panel.desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -58)
    panel.desc:SetMaxLines(3)
    panel.desc:SetText(def.desc)
    panel.top = panel.desc

    def.build(panel)
    return panel
end

function Tools.Show(def, parent)
    for key, panel in pairs(panels) do
        if key ~= def.key then panel:Hide() end
    end
    local panel = panels[def.key]
    if not panel then
        panel = Build(def, parent)
        panels[def.key] = panel
    end
    panel:Show()
    Tools.Refresh(def)
    return panel
end

function Tools.Panel(key) return panels[key] end

function Tools.Refresh(def)
    local panel = def and panels[def.key]
    if not (panel and panel:IsShown()) then return end
    panel.status:SetText(Tools.Status(def) or "")
    if def.refresh then ns.Try(def.key, def.refresh, panel) end
end

-- Seite eines Werkzeugs neu zeichnen, falls sie gerade offen ist (z. B. nach dem Sichern).
function Tools.RefreshKey(key)
    Tools.Refresh(Tools.Get(key))
end

function Tools.HideAll()
    for _, panel in pairs(panels) do panel:Hide() end
end

-- „/ezmacro status“ bzw. „Stand zeigen“ (Gerüst aus ezCore, ns.PrintStatus): je Werkzeug sein Stand, z. B.
-- „Ränge aktualisieren: 3 Stellen nutzen einen alten Rang“.
ns.AddStatusLine(function()
    local lines = {}
    if not ns.db then return lines end
    for _, def in ipairs(Tools.Entries()) do
        local status = Tools.Status(def)
        if status and status ~= "" then lines[#lines + 1] = def.name .. ": " .. status end
    end
    return lines
end)
