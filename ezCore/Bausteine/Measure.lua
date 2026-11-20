local _, ns = ...
local Core = ezCore

--[[
    Messungen zum Mithelfen (Welle 23a, A16; vorher je gleich in ezTalent/Measure.lua und ezCombat/RotationMeasure.lua):
    ein Feldhelfer für die Zeilen und eine Textausgabe mit demselben Ablauf für alle Messungen.

      Core.MeasureField(wert) → Text ohne „;“ und Zeilenumbruch (nil → ""), für Zeilen „kopf;wert;wert…“
      Core.Measure.Field = Core.MeasureField
      Core.Measure.Show(opts) → true, wenn der Text gezeigt wurde
          opts.text        der Messtext (nil oder "" → opts.emptyText im Chat, false)
          opts.print       fn(text) für Chatzeilen (das Print des Moduls; Pflicht)
          opts.combatText  gesetzt: im Kampf nur dieser Text im Chat, false (Kampfsperre)
          opts.emptyText   Text, wenn es nichts zu messen gab
          opts.title       Titel des Fensters      opts.hint   erste Hinweiszeile
          opts.warnings    weitere Hinweiszeilen (Liste)
          opts.sendText    Formattext mit %s für den Link zum Mithelfen; fehlt der Link, entfällt die Zeile
          opts.url         Adresse für sendText (ohne: Core.Contribute.VALUES_URL, die Vorlage „Werte messen“ –
                           Gesamtreview 18.11.2026, T11-1; bis dahin die allgemeine Vorlage beitrag.yml)
          opts.owner       Modulname für Core.TextDialog
      Ablauf: Kampfsperre → leer? → Hinweise (hint, warnings, Link) → Core.TextDialog { title, hint, text, select,
      readOnly, owner }; ohne TextDialog jede Zeile im Chat.
]]

Core.Measure = Core.Measure or {}
local Measure = Core.Measure

function Core.MeasureField(value)
    if Core.IsSecret(value) then return "" end
    return (tostring(value == nil and "" or value):gsub("[;\r\n]", " "))
end
Measure.Field = Core.MeasureField

function Measure.Show(opts)
    opts = type(opts) == "table" and opts or {}
    local say = type(opts.print) == "function" and opts.print or function() end
    if opts.combatText and Core.InCombat() then
        say(opts.combatText)
        return false
    end
    local text = opts.text
    if Core.IsSecret(text) or type(text) ~= "string" or text == "" then
        if opts.emptyText then say(opts.emptyText) end
        return false
    end
    local hint = {}
    if type(opts.hint) == "string" then hint[#hint + 1] = opts.hint end
    for _, w in ipairs(type(opts.warnings) == "table" and opts.warnings or {}) do
        if type(w) == "string" then hint[#hint + 1] = w end
    end
    local url = opts.url or (Core.Contribute and Core.Contribute.VALUES_URL)
    if type(url) == "string" and type(opts.sendText) == "string" then hint[#hint + 1] = opts.sendText:format(url) end
    if Core.TextDialog then
        Core.TextDialog({ title = opts.title, hint = table.concat(hint, "\n"), text = text, select = true,
            readOnly = true, owner = opts.owner })
    else
        for line in text:gmatch("[^\n]+") do say(line) end
    end
    return true
end
