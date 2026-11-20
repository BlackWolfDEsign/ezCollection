local _, ns = ...
local L = ns.L

--[[
    Ablaufwarnung: Beim Einloggen weist ezMail auf bald verfallende Post aller Charaktere hin.
    Die Ablaufzeiten von Briefen mit Inhalt (Gold oder Gegenstände) erfasst ezCore bei jedem
    Briefkastenbesuch; gezählt wird nur über ezCore.Mail (Expiring, ExpiringAll) mit einem Grenzwert für
    ezMail und ezPanel (Mail.WarnDays). ezMail liest nur: Abgelaufene vergisst Mail.ForgetExpired, den
    Briefkasten-Stand eines Charakters Mail.ForgetMailbox – ezMail schreibt nichts in ezCores Daten.
    Sichtbar: Knöpfe „Ablaufliste“ und „Vergessen …“ auf der Einstellungsseite (Leitlinie 3), dazu
    /ezm ablaufliste und /ezm vergessen Name.
]]

local Expiry = {}
ns.Expiry = Expiry

local Core = ezCore
local Mail = Core.Mail
local LOGIN_DELAY = 8

local function CharLabel(key)
    return Core.CharName(ns.CharInfo(key), key, "-")
end

-- all = false: nur bald verfallende Post (Login). all = true: Übersicht aller Charaktere.
function Expiry.Report(all)
    local now = ezCore.Now()
    local days = Mail.WarnDays()
    local rows, expiredRows = {}, {}
    for _, info in ipairs(Mail.ExpiringAll(days, all)) do
        if info.count > 0 then rows[#rows + 1] = info end
        -- Abgelaufene einmal melden und vergessen: sie sind zurück beim Absender oder gelöscht.
        if info.expired > 0 then
            Mail.ForgetExpired(info.key)
            expiredRows[#expiredRows + 1] = info
        end
    end

    if all then
        if #rows == 0 and #expiredRows == 0 then
            ns.Print(L.LIST_EMPTY)
            return
        end
        if #rows > 0 then ns.Print(L.LIST_HEADER) end
        for _, row in ipairs(rows) do
            local line = L.LIST_LINE:format(CharLabel(row.key), row.count, ns.TimeText(row.first - now),
                Core.DateText(row.seen, "full"))
            if row.deleting > 0 then line = line .. " " .. L.EXPIRY_DELETING:format(row.deleting) end
            if row.more and row.more > 0 then line = line .. " " .. Core.More(row.more) .. " " .. L.LIST_MORE_TAIL end
            ns.Print(line)
        end
    else
        if #rows > 0 then ns.Print(L.EXPIRY_HEADER:format(days)) end
        for _, row in ipairs(rows) do
            local line = L.EXPIRY_LINE:format(CharLabel(row.key), row.count, ns.TimeText(row.first - now))
            if row.deleting > 0 then line = line .. " " .. L.EXPIRY_DELETING:format(row.deleting) end
            ns.Print(line)
        end
    end
    for _, row in ipairs(expiredRows) do
        ns.Print(L.EXPIRY_GONE:format(CharLabel(row.key), row.expired))
    end
end

---------------------------------------------------------------------------
-- Briefkasten-Stand eines Charakters vergessen (über ezCore)
---------------------------------------------------------------------------

-- Charaktere mit gespeichertem Briefkasten-Stand: { key, label } (aktueller zuerst wie in ezCore).
function Expiry.Stored()
    local list = {}
    for _, entry in ipairs(Core.CharacterList()) do
        if Mail.Expiring(entry.key, nil, true) then list[#list + 1] = { key = entry.key, label = CharLabel(entry.key) } end
    end
    return list
end

-- true, wenn ein Stand da war. Gelöscht wird in ezCore (Mail.ForgetMailbox, Nachricht MAILBOX_FORGOTTEN);
-- den Charakter selbst und seinen Postverlauf behält ezCore.
function Expiry.Forget(key)
    if Mail.ForgetMailbox(key) then
        ns.Print(L.MAIL_FORGOT:format(key))
        return true
    end
    ns.Print(L.FORGET_NOTHING:format(key))
    return false
end

-- /ezm vergessen Name → true, wenn ein Stand vergessen wurde.
-- Ohne Name: das Menü mit allen Charakteren. Passt der Name auf mehrere Charaktere (derselbe Name auf zwei Realms),
-- rät ezMail nicht: Core.FindCharKey liefert dann nil und die Kandidaten – die Meldung nennt sie mit vollem Namen,
-- und das Menü bietet genau diese zur Auswahl an.
function Expiry.ForgetCommand(rest)
    rest = Core.Trim(rest or "")
    if rest == "" then
        Expiry.ShowForgetMenu(nil)
        return false
    end
    local key, candidates = Core.FindCharKey(rest)
    if key then return Expiry.Forget(key) end
    if type(candidates) == "table" and #candidates > 0 then
        ns.Print(L.CMD_AMBIGUOUS:format(rest, table.concat(candidates, ", ")))
        Expiry.ShowForgetMenu(nil, candidates)
        return false, candidates
    end
    ns.Print(L.CMD_NOT_FOUND:format(rest))
    return false
end

-- Menü am Knopf „Vergessen …“: ein Eintrag je Charakter mit gespeichertem Stand.
-- keys (freiwillig): nur diese Charaktere anbieten (Kandidaten eines mehrdeutigen Namens), auch ohne Stand –
-- ein Klick sagt dann, dass für ihn nichts gespeichert ist.
function Expiry.ShowForgetMenu(owner, keys)
    -- Knöpfe der Einstellungsseite geben sich selbst mit; sonst hängt das Menü am Mauszeiger.
    if type(owner) ~= "table" then owner = UIParent end
    local opened = Core.Menu.Open(owner, function(root)
        Core.Menu.Title(root, L.FORGET_TITLE)
        local list = Expiry.Stored()
        if type(keys) == "table" then
            list = {}
            -- Der volle Schlüssel als Text: gleiche Namen unterscheidet nur der Realm.
            for _, key in ipairs(keys) do list[#list + 1] = { key = key, label = key } end
        end
        if #list == 0 then Core.Menu.Title(root, L.FORGET_EMPTY) end
        for _, entry in ipairs(list) do
            Core.Menu.Button(root, entry.label, function() Expiry.Forget(entry.key) end)
        end
    end)
    if not opened and type(keys) ~= "table" then ns.Print(L.NO_MENU) end
end

ns.OnReady(function()
    if not ns.S.loginWarning then return end
    C_Timer.After(LOGIN_DELAY, function() ns.Try("Expiry", Expiry.Report, false) end)
end)
