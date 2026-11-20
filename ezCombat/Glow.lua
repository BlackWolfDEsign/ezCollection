local _, ns = ...
local L = ns.L
local Core = ezCore

-- Leuchten für Aktionsknöpfe, eigene Symbole und Totemknöpfe – seit der Umstellung auf ezCores Leucht-Dienst
-- (Core.Glow, Entscheidung des Nutzers 13.11.2026) nur noch dünne Hüllen:
--   Aktionsknöpfe: ezCombat meldet Gründe an und ab (Glow.SetSpells, Glow.Flash); Rangfolge, Zuordnen, Blizzards
--     eigenes Proc-Leuchten, Leistenwechsel und die EINE Tooltip-Zeile macht der Dienst. Auf einem Knopf liegt so
--     nie mehr als ein Rahmen – auch wenn ezBuff und ezCombat dasselbe melden.
--   Eigene Ziele (Symbolplatz, DoT-Symbole, Totemknöpfe): je Ziel ein Rahmen aus Core.NewGlow.
-- Taint-sicher wie bisher: eigene Rahmen, Blizzards Knöpfe bekommen keine Werte; Rahmen an geschützten Knöpfen
-- entstehen nur außerhalb des Kampfs. Farbe nach Bedeutung (ezCore.GLOW_KINDS) – ezCombat legt keine Farben fest.
-- Alle bisherigen Funktionen bleiben (Leitlinie 8).
local Glow = {}
ns.Glow = Glow

local OWNER = "ezCombat"

-- Rangfolge der Gründe: steht jetzt in ezCore (Core.GLOW_KINDS[art].rank). Die Liste bleibt als Auskunft; das kurze
-- Leuchten „wieder bereit“ (ready) reiht sich seit der Entscheidung vom 13.11.2026 hinter Rot und Gold ein.
Glow.REASON_ORDER = { "interrupt", "reactive", "ready", "dot", "totem", "missing", "finisher", "next" }

-- Erklärzeile im Tooltip des Aktionsknopfs: was zu tun ist (geht als tip an den Leucht-Dienst).
local TIPS = {
    ready = L.GLOW_TIP_ready, reactive = L.GLOW_TIP_reactive, interrupt = L.GLOW_TIP_interrupt,
    finisher = L.GLOW_TIP_finisher, dot = L.GLOW_TIP_dot, totem = L.GLOW_TIP_totem, missing = L.GLOW_TIP_missing,
    next = L.GLOW_TIP_next,
}
Glow.TIPS = TIPS

local reasonSpells = {}     -- Grund → { [Zaubername] = true }: was ezCombat zuletzt gemeldet hat
local spellAlpha = {}       -- Zaubername → Deckkraft des Leuchtens „dot“ (darf gesperrt sein)

---------------------------------------------------------------------------
-- Aktionsknöpfe und ihr Zauber: gemeinsame Suche in ezCore (ActionHighlight liest über ActionSlots.SpellID)
---------------------------------------------------------------------------

-- Alle Aktionsknöpfe von Blizzard: die Liste des Ereignisrahmens, sonst die bekannten Leistennamen.
Glow.Buttons = Core.ActionHighlight.Buttons

-- Name des Zaubers auf einem Aktionsplatz, auch für Makros, die einen Zauber zeigen.
function Glow.SlotSpellName(slot)
    return Core.ActionHighlight.SlotSpellName(slot, ns.SpellName)
end

function Glow.SpellOf(button)
    return (Core.Call(Glow.SlotSpellName, button.action))
end

-- Sichtbare Aktionsknöpfe mit einem dieser Zauber: { button, … }
function Glow.ButtonsFor(names)
    local result = {}
    for _, button in ipairs(Glow.Buttons()) do
        if button:IsVisible() then
            local name = Glow.SpellOf(button)
            if name and names[name] then result[#result + 1] = button end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Leuchtrahmen an einem Ziel (Core.NewGlow: je Ziel genau einer)
---------------------------------------------------------------------------

local SECURE = { secure = true }

-- Rahmen für ein Ziel anlegen. secure = geschützter Knopf (Aktionsknopf): dann nur außerhalb des Kampfs.
function Glow.Prepare(target, secure)
    return Core.NewGlow(target, secure and SECURE or nil)
end

-- kind: Art aus ezCore.GLOW_KINDS (Farbe); ohne Angabe Blizzards Gold.
function Glow.Show(target, secure, kind)
    local glow = Glow.Prepare(target, secure)
    if not glow then return false end
    return glow:Show(kind) == true
end

function Glow.Hide(target)
    local glow = Core.Glow.Get(target)
    if glow then glow:Hide() end
end

-- Deckkraft des Leuchtens; darf ein gesperrter Wert sein (SetAlpha nimmt ihn an).
function Glow.SetAlpha(target, alpha)
    local glow = Core.Glow.Get(target)
    if glow then glow:SetAlpha(alpha) end
end

function Glow.IsShown(target)
    local glow = Core.Glow.Get(target)
    return glow ~= nil and glow:IsShown()
end

-- Art (Farbe) des Leuchtens an einem Ziel, solange es zu sehen ist.
function Glow.KindOf(target)
    local glow = Core.Glow.Get(target)
    return glow and glow:Kind() or nil
end

-- Art des Leuchtens auf einem Aktionsplatz (für den Tooltip des Knopfs), sonst nil.
function Glow.SlotKind(slot)
    return Core.Glow.SlotKind(slot)
end

-- Rahmen für alle Aktionsknöpfe vorab anlegen (außerhalb des Kampfs); danach hält der Dienst sie selbst nach.
function Glow.PrepareAll()
    if ns.InCombat() then return end
    return Core.Glow.PrepareAll()
end

---------------------------------------------------------------------------
-- Gründe: jede Funktion meldet die Zauber, deren Knöpfe leuchten sollen
---------------------------------------------------------------------------

local function SameSet(a, b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end

function Glow.Refresh()
    return Core.Glow.Refresh()
end

Glow.RefreshSoon = Core.Glow.RefreshSoon

-- Deckkraft für einen Zauber: gesperrter Wert unverändert (nie prüfen oder vergleichen), sonst Zahl oder 1.
function Glow.AlphaFor(name)
    local alpha = name and spellAlpha[name]
    if Core.IsSecret(alpha) then return alpha end
    if type(alpha) == "number" then return alpha end
    return 1
end

local function DotAlpha(_, name) return Glow.AlphaFor(name) end

-- Zauber setzen, deren Knöpfe aus diesem Grund leuchten (nil oder leer = keiner). Der Grund ist zugleich die Art
-- (Farbe und Rang); unbekannte Arten leuchten in ezCores Standardart.
function Glow.SetSpells(reason, set)
    set = set or {}
    local old = reasonSpells[reason] or {}
    if SameSet(old, set) then return end
    if next(set) then
        local names = {}
        for name in pairs(set) do names[name] = true end
        reasonSpells[reason] = names
        Core.Glow.Set(OWNER, reason, { names = names, kind = reason, tip = TIPS[reason], nameOf = ns.SpellName,
            alpha = reason == "dot" and DotAlpha or nil })
    else
        reasonSpells[reason] = nil
        Core.Glow.Clear(OWNER, reason)
    end
end

function Glow.Spells(reason)
    return reasonSpells[reason] or {}
end

-- Deckkraft des Leuchtens „dot“ je Zauber (gesperrte DoTs: Ergebnis von Blizzards Dauer-Objekt, wird nur an
-- SetAlpha weitergereicht). Ersetzt die bisherige Zuordnung; nicht genannte Zauber leuchten voll.
function Glow.SetSpellAlphas(map)
    spellAlpha = map or {}
    Core.Glow.SetAlpha(OWNER, "dot", DotAlpha)
end

-- Kurzes Leuchten an einem Knopf (z. B. „wieder bereit“, grün); kind: Art, Standard "ready". Es gilt der Rang der
-- Art aus ezCore (Rot vor Gold vor Grün): Kann man gerade unterbrechen oder leuchtet ein Proc, bleibt der Knopf rot
-- bzw. golden, statt kurz grün zu blinken. Bis zur Entscheidung des Nutzers vom 13.11.2026 („Alle nach Empfehlung“,
-- Frage „Wieder bereit“ in docs/roadmap/ezCore.md) ging es mit order = 0 kurz allen Gründen vor – umkehrbar mit
-- { order = 0 } in den opts.
function Glow.Flash(button, seconds, kind)
    kind = kind or "ready"
    local slot = type(button) == "table" and ns.Num(button.action)
    if not slot then return false end
    local shown = Core.Glow.Flash(OWNER, slot, seconds, kind, { tip = TIPS[kind] })
    Core.Glow.Refresh()
    return shown
end

---------------------------------------------------------------------------
-- Symbol in Aktionsknopf-Optik (Bildschirmmitte, DoT-Symbole): Blizzards Maske und Rahmen
---------------------------------------------------------------------------

-- Legt in frame ein Symbol mit Maske und Rahmen an; Rückgabe: Symbol-Textur. Seit ezCore 1.12 steht derselbe
-- Helfer als Core.StyleIcon in ezCore (EC-105, Knopf-Vorlage der Auren-Reihe; SSOT, Leitlinie 2) – hier bleibt nur
-- die Weiterleitung für den Symbolplatz und die eigene DoT-Reihe des Rückfalls.
function Glow.StyleIcon(frame)
    return Core.StyleIcon(frame)
end

-- Ein Kampf-Modul meldet seine Gründe erst im Kampf an: die Rahmen deshalb einmal vorab (außerhalb des Kampfs);
-- bei Leistenwechsel und Kampfbeginn hält der Dienst sie von da an selbst nach.
ns.OnReady(function()
    Glow.PrepareAll()
end)
