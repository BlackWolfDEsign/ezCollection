local _, ns = ...
local L = ns.L

--[[
    Meldungen: bündelt die Warnungen der anderen Bausteine an einer Stelle – volle Taschen,
    ablaufende Post, wenig oder falsche Munition, niedrige Haltbarkeit, Instanzgrenze,
    neue Fehler der ez-Module. Jeder Baustein liefert seine Warnungen selbst (def:Warnings(),
    siehe Blocks.lua) – auch, wenn er selbst nicht auf der Leiste steht. Linksklick schreibt die Meldungen in den Chat.
    Andere ez-Module melden eigene Quellen an: ezCore.API("ezPanel").AddWarning(key, name, fn) (API.lua) –
    etwa „Buff fehlt“, „ungelesene Gespräche“, „Abklingzeit fertig“.
    Jede Quelle – eigene wie fremde – lässt sich einzeln abwählen (Entscheidung des Nutzers vom 14.11.2026, Frage 17):
    im Menü des Bausteins unter „Quellen“ und sichtbar unter Einstellungen → ezPanel → Meldungen, je Quelle mit Tooltip
    (Options.lua). Beide Wege schreiben über ns.SetAlertSourceEnabled in cfg.off (im Profil); abgewählt heißt: keine
    Zeile im Tooltip, keine Zahl auf der Leiste, kein Aufruf der Quelle.
]]

local block = ns.RegisterBlock({
    id = "alerts",
    command = "meldungen",
    name = L.ALERTS_NAME,
    icon = "Interface\\Icons\\INV_Misc_Bell_01",
    fallbackIcon = ezCore.ICON_FALLBACK,
    events = { "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" },
    interval = 5,
    defaults = {
        enabled = false, zone = "right", order = 42, label = false,
        hideEmpty = true,      -- ohne Meldung ausblenden; ab Werk an (Prüfung der Einstellungen vom 19.11.2026, Nr. 98:
                               -- ein Warn-Baustein ohne Warnung belegt nur Platz, wie der Post-Baustein)
        off = {},              -- abgewählte Quellen (Baustein-IDs)
    },
    hints = function() return { L.ALERTS_HINT_LEFT } end,
})

-- Alle Bausteine, die Warnungen liefern (außer diesem), danach die Quellen anderer Module (API.lua).
local function Sources()
    local list = {}
    for _, def in ipairs(ns.blockList) do
        if def ~= block and def.cfg and type(def.Warnings) == "function" then list[#list + 1] = def end
    end
    for _, source in ipairs(ns.extraWarningList or {}) do list[#list + 1] = source end
    return list
end
ns.AlertSources = Sources

-- Gibt es die Quelle (noch)? Eine mit RemoveWarning abgemeldete verschwindet von der Einstellungsseite.
function ns.AlertSourceKnown(id)
    for _, def in ipairs(Sources()) do
        if def.id == id then return true end
    end
    return false
end

-- Zeigt der Baustein die Quelle? (Gespeichert ist nur die Abwahl: cfg.off[id] = true.)
function ns.AlertSourceEnabled(id)
    local cfg = block.cfg
    return not (cfg and type(cfg.off) == "table" and cfg.off[id])
end

-- Quelle an- oder abwählen – der eine Weg für das Menü „Quellen“ und die Einstellungsseite. → true, wenn gesetzt
function ns.SetAlertSourceEnabled(id, on)
    local cfg = block.cfg
    if not cfg or type(id) ~= "string" then return false end
    if type(cfg.off) ~= "table" then cfg.off = {} end
    cfg.off[id] = (not on) or nil
    ns.QueueUpdate(block)
    if ns.RefreshAlertSetting then ns.RefreshAlertSetting(id) end   -- Häkchen der Einstellungsseite nachziehen
    return true
end

-- Tooltip einer Quelle auf der Einstellungsseite: was sie meldet. Eigene Bausteine haben einen eigenen Text
-- (OPT_alert_<id>_TIP), eine fremde Quelle bringt ihren mit (AddWarning, vierter Wert) oder nennt Name und Kennung.
function ns.AlertSourceTip(source)
    local name = tostring(source.name or source.id)
    if source.external and not ns.blocks[source.id] then   -- Quelle aus AddWarning (kein Baustein)
        if type(source.tip) == "string" and source.tip ~= "" then return source.tip end
        return L.OPT_ALERT_EXTERNAL_TIP:format(name, tostring(source.key))
    end
    -- Baustein: def.tip beschreibt den Baustein in der Liste der Bausteine, nicht seine Meldungen
    local key = "OPT_alert_" .. tostring(source.id) .. "_TIP"
    local tip = L[key]
    if type(tip) == "string" and tip ~= key then return tip end
    return L.OPT_ALERT_BLOCK_TIP:format(name)
end

-- { { def, text } } aller eingeschalteten Quellen.
local function Collect()
    local list = {}
    for _, def in ipairs(Sources()) do
        -- Angehaltene Quellen (Fehler einer fremden Quelle, ns.BlockError in Blocks.lua) bleiben still.
        if not block.cfg.off[def.id] and not def.halted then
            local ok, warnings = pcall(def.Warnings, def)
            if not ok then
                -- eine Fehlerstelle für alle Bausteine: ezCores Fehlerliste; eine fremde Quelle hält danach an
                ns.BlockError(def, warnings, "Warnings")
            elseif type(warnings) == "table" then
                for _, text in ipairs(warnings) do list[#list + 1] = { def = def, text = tostring(text) } end
            end
        end
    end
    return list
end
ns.CollectWarnings = Collect

-- Eingeschaltete Quellen, die nach einem Fehler angehalten sind (Tooltip-Hinweis, Menü „wieder starten“).
local function Halted()
    local list = {}
    for _, def in ipairs(Sources()) do
        if def.halted and not block.cfg.off[def.id] then list[#list + 1] = def end
    end
    return list
end

function block:GetText()
    local n = #Collect()
    if n == 0 then
        if self.cfg.hideEmpty then return nil end
        return ns.Grey("0")
    end
    return ns.RED .. n .. "|r"
end

function block:OnTooltip(tooltip)
    local list, halted = Collect(), Halted()
    if #list == 0 and #halted == 0 then
        ns.TipLine(tooltip, L.ALERTS_NONE, "good")
    end
    for _, w in ipairs(list) do
        ns.TipDoubleLine(tooltip, w.text, ns.Grey(w.def.name), "bad", "highlight")
    end
    for _, def in ipairs(halted) do
        ns.TipLine(tooltip, L.ALERTS_HALTED:format(def.name), "bad", true)
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    local list = Collect()
    if #list == 0 then return ns.Print(L.ALERTS_NONE) end
    for _, w in ipairs(list) do ns.Print(("%s: %s"):format(w.def.name, w.text)) end
end

function block:OnMenu(root)
    local cfg = self.cfg
    local sources = root:CreateButton(L.ALERTS_SOURCES)
    -- „Alle auswählen / Alle abwählen“ über den Quellen (Design-System 2.11; gemerkt wie jeder Haken)
    ns.MenuAllToggle(sources, Sources(), function(def) return ns.AlertSourceEnabled(def.id) end,
        function(def, on) ns.SetAlertSourceEnabled(def.id, on) end)
    for _, def in ipairs(Sources()) do
        local id = def.id
        sources:CreateCheckbox(def.name, function() return ns.AlertSourceEnabled(id) end, function()
            ns.SetAlertSourceEnabled(id, not ns.AlertSourceEnabled(id))
            return MenuResponse and MenuResponse.Refresh
        end)
    end
    local halted = Halted()
    if #halted > 0 then
        sources:CreateDivider()
        for _, def in ipairs(halted) do
            sources:CreateButton(L.ALERTS_RESTART:format(def.name), function() ns.RestartBlock(def) end)
        end
    end
    ns.MenuCheck(root, L.ALERTS_HIDE_EMPTY, cfg, "hideEmpty", self)
end
