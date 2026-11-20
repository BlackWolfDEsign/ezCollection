local _, ns = ...

-- Schnittstelle für andere Module: ezCore.API("ezMacro") liefert diese Tabelle (nil, wenn ezMacro nicht
-- geladen ist – also immer prüfen). Beschreibung im README-Abschnitt „Schnittstelle“.
ns.API = {
    -- Emotes bietet die Schnittstelle nicht an: ezCore.EmoteCommand / ezCore.PerformEmote direkt aufrufen.

    -- Ansagen (z. B. ezMap: Klick auf einen Schlachtfeld-Timer sagt „Hof in 0:45“ an). Nur auf einen Klick des
    -- Spielers hin aufrufen – nichts automatisch senden.
    -- Announce(text, kind) → true, chatType | false, "empty" | "alone" | "locked" | "failed"
    --   kind: "warn" (Raidwarnung, wenn der Spieler darf) oder "group" (Standard); %t = Ziel, %z = Gebiet
    Announce = function(text, kind) return ns.Announce.Send(kind or "group", text) end,
    -- AnnounceChannel(kind) → "RAID_WARNING" | "RAID" | "INSTANCE_CHAT" | "PARTY" | nil (allein)
    AnnounceChannel = function(kind) return ns.Announce.Channel(kind or "group") end,

    -- Leisten-Profile (ezBars nutzt sie für seine Leisten). slots: Liste von Aktionsplätzen, nil = alle
    -- (ezCore.ActionSlots.USABLE: 1–120 und 145–180; 121–144 fasst ezMacro nie an).
    -- ProfileNames() → { "Name", … } sortiert
    ProfileNames = function() return ns.Profiles.Names() end,
    -- ProfileList() → { { name, class, saved = Zeit, slots = Anzahl, macros = Anzahl, partial }, … } sortiert
    ProfileList = function()
        local list = {}
        for _, name in ipairs(ns.Profiles.Names()) do
            local profile = ns.Profiles.Get(name)
            local slots, macros = ns.Profiles.Count(profile)
            list[#list + 1] = { name = name, class = profile.class, saved = profile.time, slots = slots,
                macros = macros, partial = profile.partial == true }
        end
        return list
    end,
    -- OpenProfiles() → öffnet ezMacros Werkzeug „Leisten-Profile“ (Makro-Browser, Reiter „Werkzeuge“)
    OpenProfiles = function()
        local tool = ns.Tools.Get("profiles")
        if tool then ns.Browser.ShowEntry(tool) end
        return tool ~= nil
    end,
    -- SaveProfile(name, slots) → Profil (überschreibt ein gleichnamiges; die Reihenfolge von slots wird mitgespeichert)
    SaveProfile = function(name, slots) return ns.Profiles.Save(name, { slots = slots }) end,
    -- LoadProfile(name, slots, opts) → true, wenn die Rückfrage gezeigt bzw. ausgeführt wurde.
    -- opts: macros, bindings, clearEmpty (Standard: Einstellungen von ezMacro); byOrder = true legt den k-ten
    -- gespeicherten Platz auf slots[k] (Leiste liegt auf einem anderen Charakter auf anderen Plätzen)
    LoadProfile = function(name, slots, opts)
        opts = opts or {}
        opts.slots = slots
        return ns.Profiles.Load(name, opts)
    end,
    -- CaptureSlots(slots) → { [slot] = { kind, id, name, body … }, order = { slots … } }: Inhalt ohne Speichern
    CaptureSlots = function(slots)
        local data = ns.Profiles.Capture(slots)
        if slots then
            data.order = {}
            for index, slot in ipairs(slots) do data.order[index] = slot end
        end
        return data
    end,
    -- PlaceSlots(data, slots, clearEmpty, byOrder) → belegt, geleert, fehlend; ohne Rückfrage, nur außerhalb des
    -- Kampfes. byOrder: den k-ten Platz aus data.order auf slots[k] legen
    PlaceSlots = function(data, slots, clearEmpty, byOrder)
        if byOrder and slots and type(data) == "table" and type(data.order) == "table" then
            data = ns.Profiles.Remap(data, data.order, slots)
        end
        return ns.Profiles.Place(data, { slots = slots, clearEmpty = clearEmpty })
    end,
}
