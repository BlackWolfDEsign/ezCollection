local _, ns = ...

-- Hebt Aktionsknöpfe hervor, auf denen ein bestimmter Zauber liegt – so, wie Blizzards Zauberbuch es
-- beim Überfahren eines Zaubers tut. Umsetzung (taint-sicher, eigene Rahmen über den Knöpfen) in
-- ezCore/Widgets.lua; ezMacro vergleicht mit seinen Zaubernamen (ns.SpellName, jeder Rang zählt).
local Highlight = {}
ns.Highlight = Highlight

function Highlight.Clear()
    ezCore.ActionHighlight.Clear()
end

-- Hebt alle sichtbaren Aktionsknöpfe mit einem der Zauber hervor; Rückgabe: Anzahl der Knöpfe.
function Highlight.Show(spellIDs)
    return ezCore.ActionHighlight.Show(spellIDs, ns.SpellName)
end
