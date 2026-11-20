local _, ns = ...
local L = ns.L
local Core = ezCore
local UI = ns.UI

-- Makros sichern und zurückholen (wie MacroSync): Die Charakter-Makros jedes Twinks und die allgemeinen
-- Makros des Accounts liegen in ezMacroDB.backups (SavedVariables gelten für alle Charaktere des Accounts).
-- Auf einem Twink holt „Zurückholen“ sie als Charakter-Makros zurück – mit **einer** Rückfrage für alle.
-- Auf Wunsch sichert ezMacro beim Ausloggen von selbst (Einstellung backupOnLogout).
local Backup = {}
ns.Backup = Backup

local ACCOUNT = "account"

local function Snapshot(scope)
    local list = {}
    for _, macro in ipairs(ns.Macros.All(scope)) do
        list[#list + 1] = { name = macro.name, icon = macro.icon, body = ns.Import.BodyOf(macro.index) or macro.body }
    end
    return list
end

-- Uhrzeit (gespeichert mit der Sicherung): Core.Now, eine Stelle für alle Module (W-14)
local Now = Core.Now

-- Sichert die Charakter-Makros dieses Charakters und die allgemeinen Makros.
-- auto: beim Ausloggen – dann ohne Meldung und ohne eine gute Sicherung durch eine leere zu ersetzen.
function Backup.Save(auto)
    if not (ns.db and ns.Import.Available()) then return false end
    local char, account = Snapshot("char"), Snapshot("account")
    local backups = ns.db.backups
    local old = backups[ns.charKey]
    if not (auto and #char == 0 and old and #(old.macros or {}) > 0) then
        local info = Core.CharInfo(ns.charKey) or {}
        backups[ns.charKey] = { time = Now(), name = info.name, realm = info.realm, class = ns.playerClass,
            macros = char }
    end
    local oldAccount = backups[ACCOUNT]
    if not (auto and #account == 0 and oldAccount and #(oldAccount.macros or {}) > 0) then
        backups[ACCOUNT] = { time = Now(), by = ns.charKey, macros = account }
    end
    if not auto then ns.Print(L.BACKUP_SAVED:format(#char, #account)) end
    if ns.Tools then ns.Tools.RefreshKey("backup") end
    return true
end

function Backup.Get(key) return ns.db and ns.db.backups[key] end

-- Sicherungen für die Liste: zuerst die allgemeinen Makros, dann dieser Charakter, dann die Twinks.
function Backup.Keys()
    local keys = {}
    for key, data in pairs(ns.db.backups) do
        if key ~= ACCOUNT and type(data) == "table" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if (a == ns.charKey) ~= (b == ns.charKey) then return a == ns.charKey end
        return a < b
    end)
    if type(ns.db.backups[ACCOUNT]) == "table" then table.insert(keys, 1, ACCOUNT) end
    return keys
end

function Backup.Label(key)
    if key == ACCOUNT then return L.BACKUP_ACCOUNT end
    local data = ns.db.backups[key] or {}
    return Core.CharName({ name = data.name, realm = data.realm, class = data.class }, key)
end

-- Holt eine Sicherung zurück: die eines Charakters als Charakter-Makros, die allgemeine als allgemeine.
function Backup.Restore(key)
    local data = Backup.Get(key)
    if not data then return false end
    local perChar = key ~= ACCOUNT
    local list = {}
    for _, macro in ipairs(data.macros or {}) do
        list[#list + 1] = { name = macro.name, icon = macro.icon, body = macro.body, perChar = perChar }
    end
    local plan = ns.Import.Plan(list)
    local title = L.BACKUP_RESTORE_TITLE:format(Backup.Label(key))
    return ns.Import.ConfirmPlan(plan, title, function() ns.Tools.RefreshKey("backup") end)
end

function Backup.Delete(key)
    if not Backup.Get(key) then return end
    Core.Confirm(L.BACKUP_DELETE_CONFIRM:format(Backup.Label(key)), function()
        ns.db.backups[key] = nil
        ns.Tools.RefreshKey("backup")
    end)
end

ns.OnLogout(function()
    if ns.S.backupOnLogout then Backup.Save(true) end
end)

---------------------------------------------------------------------------
-- Werkzeug „Makros sichern“
---------------------------------------------------------------------------

local function Items()
    local items = {}
    for _, key in ipairs(Backup.Keys()) do
        local data = ns.db.backups[key]
        local count = #(data.macros or {})
        items[#items + 1] = {
            key = key,
            icon = ns.IconPath(key == ACCOUNT and { "INV_Misc_Note_02" } or { "INV_Scroll_03" }),
            text = Backup.Label(key) .. (key == ns.charKey and (" " .. L.BACKUP_YOU) or ""),
            sub = L.BACKUP_ROW:format(count, Core.Ago(data.time)),
            tip = key == ACCOUNT and L.BACKUP_ACCOUNT_TIP or L.BACKUP_CHAR_TIP,
        }
    end
    return items
end

ns.Tools.Register({
    key = "backup", order = 10, icon = { "INV_Scroll_03", "INV_Misc_Note_01" },
    name = L.TOOL_BACKUP, why = L.TOOL_BACKUP_WHY, desc = L.TOOL_BACKUP_DESC,
    status = function()
        local data = Backup.Get(ns.charKey)
        if not data then return L.BACKUP_NONE end
        return L.BACKUP_STATUS:format(#(data.macros or {}), Core.Ago(data.time))
    end,
    build = function(panel)
        local width = panel.width
        panel.auto = UI.SettingCheck(panel, "backupOnLogout")
        panel.auto:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -4, -4)

        panel.save = UI.Button(panel, L.BACKUP_SAVE, 120, function() Backup.Save() end, L.BACKUP_SAVE, L.BACKUP_SAVE_TIP)
        panel.save:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 26)
        panel.restore = UI.Button(panel, L.BACKUP_RESTORE, 120, function()
            local item = panel.list:Selected()
            if item then Backup.Restore(item.key) end
        end, L.BACKUP_RESTORE, L.BACKUP_RESTORE_TIP)
        panel.restore:SetPoint("LEFT", panel.save, "RIGHT", 4, 0)
        panel.delete = UI.Button(panel, Core.Word("DELETE"), 100, function()
            local item = panel.list:Selected()
            if item then Backup.Delete(item.key) end
        end, Core.Word("DELETE"), L.BACKUP_DELETE_TIP)
        panel.delete:SetPoint("LEFT", panel.restore, "RIGHT", 4, 0)

        panel.list = UI.List(panel, "ezMacroBackupList", width, function() ns.Tools.RefreshKey("backup") end,
            function(item) Backup.Restore(item.key) end)
        panel.list.frame:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -8)
        panel.list.frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 52)
    end,
    refresh = function(panel)
        panel.list:SetItems(Items(), L.BACKUP_EMPTY)
        local selected = panel.list:Selected()
        local free = not ns.InCombat()
        panel.restore:SetEnabled(selected ~= nil and free)
        panel.delete:SetEnabled(selected ~= nil)
        panel.save:SetEnabled(ns.Import.Available())
        panel.auto.Refresh()
    end,
})
