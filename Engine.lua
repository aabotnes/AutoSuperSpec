-- Auto Super Spec engine: follows the active build, learns points, chat sharing,
-- events and slash commands.

local ADDON_NAME, AS = ...
local T = AS.Talents
local Print = AS.Print

local state = { busy = false, paused = false, waitCombat = false, scheduled = false }
AS.state = state

------------------------------------------------------------------------------
-- Progress
------------------------------------------------------------------------------

-- Where the player stands against a build.
function AS.Progress(build, layout, meta)
    if not layout then
        layout, meta = T.Layout()
        if not layout then return nil, meta end
    end
    local steps, err = AS.ResolveSteps(build.code, layout)
    if not steps then return nil, err end
    local need, done, remaining = {}, 0, {}
    for i, t in ipairs(steps) do
        need[t.key] = (need[t.key] or 0) + 1
        if t.rank >= need[t.key] then
            done = done + 1
        else
            remaining[#remaining + 1] = { t = t, step = i, rank = need[t.key] }
        end
    end
    return {
        steps = steps, remaining = remaining, done = done, total = #steps,
        next = remaining[1], need = need, layout = layout, meta = meta,
    }
end

-- Talents with more points than the build wants (spent outside the build).
function AS.OffBuild(progress)
    local extra = {}
    for _, tree in ipairs(progress.layout) do
        for _, t in ipairs(tree) do
            local wanted = progress.need[t.key] or 0
            if t.rank > wanted then extra[#extra + 1] = ("%s (%d)"):format(t.name, t.rank - wanted) end
        end
    end
    return extra
end

local function SpentPoints(layout)
    local n = 0
    for _, tree in ipairs(layout) do
        for _, t in ipairs(tree) do n = n + t.rank end
    end
    return n
end

------------------------------------------------------------------------------
-- Learning
------------------------------------------------------------------------------

function AS.OnPointLearned(t, rank) -- classic backend, one point at a time
    Print(("learned |cffffd100%s|r %d/%d"):format(t.name, rank, t.maxRank))
end

local function ReportBatch(todo, count, fromZero)
    if T.Name() ~= "traits" then return end -- classic reports each point itself
    local order, ranks = {}, {}
    for i = 1, count do
        local t = todo[i]
        if not ranks[t.key] then
            order[#order + 1] = t
            ranks[t.key] = fromZero and 0 or t.rank
        end
        ranks[t.key] = ranks[t.key] + 1
    end
    local parts = {}
    for _, t in ipairs(order) do
        parts[#parts + 1] = ("|cffffd100%s|r %d/%d"):format(t.name, ranks[t.key], t.maxRank)
    end
    Print("learned " .. table.concat(parts, ", "))
end

-- manual: the player asked (button, popup or command) rather than an event.
-- opts.reset: reset the talent tree first and learn the build from scratch.
function AS.TryLearn(manual, opts)
    opts = opts or {}
    if state.busy or T.IsWaiting() then return end
    local build = AS.ActiveBuild()
    if not build then return end
    if build.class ~= AS.PlayerClass() then return end
    if not manual and (not AS.char.enabled or state.paused) then return end
    if InCombatLockdown and InCombatLockdown() then
        state.waitCombat = true
        if manual then Print("in combat - will learn talents when combat ends.") end
        return
    end
    local busy = T.Busy()
    if busy then
        if manual then Print(busy) end
        return
    end
    local progress, err = AS.Progress(build)
    if not progress then
        if manual then Print("can't follow " .. build.name .. ": " .. err) end
        return
    end
    local unspent = T.Unspent()
    local todo = {}
    if opts.reset then
        local available = (unspent or 0) + SpentPoints(progress.layout)
        for i = 1, math.min(available, #progress.steps) do todo[i] = progress.steps[i] end
    else
        if not progress.next then return end
        if unspent == 0 then
            if manual then Print("you have no unspent talent points.") end
            return
        end
        local n = unspent or #progress.remaining
        for i = 1, math.min(n, #progress.remaining) do todo[i] = progress.remaining[i].t end
    end
    if #todo == 0 then return end

    if AS.char.mode == "ask" and not manual then
        AS.ShowLearnPopup(build, todo)
        return
    end

    state.busy, state.paused = true, false
    T.Learn(todo, opts, function(count, lerr)
        state.busy = false
        if count > 0 then ReportBatch(todo, count, opts.reset) end
        if lerr then
            state.paused = true
            Print("|cffff4444" .. lerr .. "|r Auto Super Spec paused - type |cffffd100/ass resume|r to try again.")
        elseif count > 0 then
            AS.After(1, function() AS.TryLearn() end) -- in case more points arrived meanwhile
        end
        AS.RefreshUI()
    end)
end

function AS.ShowLearnPopup(build, todo)
    if StaticPopup_Visible("AUTOSUPERSPEC_LEARN") then return end
    local first = todo[1]
    local text = #todo == 1 and ("%s (rank %d)"):format(first.name, first.rank + 1)
        or ("%d points, starting with %s"):format(#todo, first.name)
    StaticPopup_Show("AUTOSUPERSPEC_LEARN", build.name, text)
end

function AS.SetActive(id, quiet)
    if not id then
        local old = AS.ActiveBuild()
        AS.char.active = nil
        if old and not quiet then Print("stopped following " .. old.name .. ".") end
        AS.RefreshUI()
        return true
    end
    local b = AS.GetBuild(id)
    if not b then return end
    if b.class ~= AS.PlayerClass() then
        Print(("%s is a %s build - log in a %s to use it."):format(b.name, AS.ClassName(b.class), AS.ClassName(b.class)))
        return
    end
    local progress, err = AS.Progress(b)
    if not progress then
        Print("can't use " .. b.name .. ": " .. err)
        return
    end
    AS.char.active = id
    state.paused = false
    if not quiet then
        Print(("now following |cffffd100%s|r - %d/%d points done."):format(b.name, progress.done, progress.total))
        local extra = AS.OffBuild(progress)
        if #extra > 0 then
            Print("|cffff8800you have points outside this build:|r " .. table.concat(extra, ", ")
                .. ". Use \"Spec now\" to respec, or reset at your class trainer.")
        end
    end
    AS.RefreshUI()
    AS.After(0.3, function() AS.TryLearn() end)
    return true
end

-- Make the character match a build right now (respec / spend all points).
function AS.SpecNow(id)
    local b = AS.GetBuild(id)
    if not b then return end
    if b.class ~= AS.PlayerClass() then
        Print(("%s is a %s build."):format(b.name, AS.ClassName(b.class)))
        return
    end
    local progress, err = AS.Progress(b)
    if not progress then
        Print("can't use " .. b.name .. ": " .. err)
        return
    end
    local busy = T.Busy()
    if busy then Print(busy) return end
    local extra = AS.OffBuild(progress)
    local unspent = T.Unspent()
    if #extra > 0 then
        if T.CanReset() then
            StaticPopup_Show("AUTOSUPERSPEC_RESET", b.name, nil, id)
            return
        end
        Print("|cffff8800your talents don't match this build|r (" .. table.concat(extra, ", ")
            .. "). Reset them at your class trainer, then click \"Spec now\" again.")
        if not unspent or unspent == 0 then return end
    end
    if not progress.next then
        Print(b.name .. " is already fully learned.")
        AS.SetActive(id, true)
        return
    end
    if unspent == 0 then
        Print("you have no unspent talent points.")
        AS.SetActive(id, true)
        return
    end
    local n = unspent and math.min(unspent, #progress.remaining) or #progress.remaining
    StaticPopup_Show("AUTOSUPERSPEC_APPLY", b.name, tostring(n), id)
end

------------------------------------------------------------------------------
-- Popups
------------------------------------------------------------------------------

local function PopupEditBox(self)
    return self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
end

StaticPopupDialogs["AUTOSUPERSPEC_LEARN"] = {
    text = AS.TITLE .. " - |cffffd100%s|r\nLearn %s?",
    button1 = "Learn",
    button2 = "Not now",
    OnAccept = function() AS.TryLearn(true) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["AUTOSUPERSPEC_APPLY"] = {
    text = "Spec into |cffffd100%s|r?\n\nThis spends %s talent point(s) following the build's order.",
    button1 = "Spec now",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, id)
        local data = id or self.data
        AS.char.active = data
        state.paused = false
        AS.RefreshUI()
        AS.TryLearn(true)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["AUTOSUPERSPEC_RESET"] = {
    text = "Reset ALL your talents and spec into |cffffd100%s|r?\n\nYour current points will be refunded and spent again following the build's order.",
    button1 = "Reset & spec",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, id)
        local data = id or self.data
        AS.char.active = data
        state.paused = false
        AS.RefreshUI()
        AS.TryLearn(true, { reset = true })
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
}

StaticPopupDialogs["AUTOSUPERSPEC_RECEIVE"] = {
    text = "Import Auto Super Spec build\n|cffffd100%s|r (%s)?",
    button1 = "Import",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        data = data or self.data
        local b, err = AS.Import(data.text, data.name)
        if b then AS.ShowUI(b.class) else Print("|cffff4444import failed|r - " .. err) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["AUTOSUPERSPEC_RENAME"] = {
    text = "Rename build:",
    button1 = OKAY or "Okay",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = AS.MAX_NAME,
    OnShow = function(self, id)
        id = id or self.data
        local eb = PopupEditBox(self)
        local b = AS.GetBuild(id)
        if eb and b then eb:SetText(b.name); eb:HighlightText() end
    end,
    OnAccept = function(self, id)
        local eb = PopupEditBox(self)
        if eb then AS.Rename(id or self.data, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        AS.Rename(parent.data, self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["AUTOSUPERSPEC_DELETE"] = {
    text = "Delete build |cffffd100%s|r?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, id) AS.Delete(id or self.data) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

------------------------------------------------------------------------------
-- Sharing in chat
------------------------------------------------------------------------------
-- A shared build is plain text: "[Auto Super Spec: name - class:code]". Players
-- with the addon see it as a clickable, class-colored link; others see the text
-- and can paste it into the import box once they install it.

local LINK_PREFIX = "garrmission:autosuperspec:"
local TAG = "Auto Super Spec"

function AS.ChatText(build)
    return ("[%s: %s - %s:%s]"):format(TAG, build.name, AS.ClassToSlug(build.class), build.code)
end

local function OpenChatWith(text)
    local getActive = ChatEdit_GetActiveWindow or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow)
    local eb = getActive and getActive()
    if eb then
        eb:Insert(text)
        return
    end
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    if open then open(text) end
end

-- Puts the build into the chat message you're typing (or opens the chat box).
function AS.LinkToChat(build)
    OpenChatWith(AS.ChatText(build))
end

local function Send(text, chatType, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return Print("this client can't send chat messages from addons.") end
    local ok, err = pcall(send, text, chatType, nil, target)
    if not ok then Print("couldn't send the build: " .. tostring(err)) end
end

local function Has(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and v
end

-- Menu entries for sharing a build: the chat box, and every chat you can post to.
function AS.ShareMenuItems(build)
    local text = AS.ChatText(build)
    local items = { { text = "Share in...", title = true } }
    local function add(label, fn) items[#items + 1] = { text = label, func = fn } end
    add("Chat message I'm typing", function() OpenChatWith(text) end)
    add("Say", function() Send(text, "SAY") end)
    if Has(IsInGroup) then add("Party", function() Send(text, "PARTY") end) end
    if Has(IsInRaid) then add("Raid", function() Send(text, "RAID") end) end
    if LE_PARTY_CATEGORY_INSTANCE and Has(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then
        add("Instance", function() Send(text, "INSTANCE_CHAT") end)
    end
    if Has(IsInGuild) then
        add("Guild", function() Send(text, "GUILD") end)
        add("Officer", function() Send(text, "OFFICER") end)
    end
    if Has(UnitIsPlayer, "target") and not Has(UnitIsUnit, "target", "player") then
        local name, realm = UnitName("target")
        if name then
            local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
            add("Whisper " .. name, function() Send(text, "WHISPER", full) end)
        end
    end
    add("Whisper someone...", function() StaticPopup_Show("AUTOSUPERSPEC_WHISPER", nil, nil, text) end)
    if type(GetChannelList) == "function" then
        local list = { GetChannelList() }
        for i = 1, #list, 3 do
            local id, name, disabled = list[i], list[i + 1], list[i + 2]
            if id and name and not disabled then
                add(("%d. %s"):format(id, name), function() Send(text, "CHANNEL", id) end)
            end
        end
    end
    return items
end

StaticPopupDialogs["AUTOSUPERSPEC_WHISPER"] = {
    text = "Whisper the build to:",
    button1 = WHISPER or "Whisper",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    OnAccept = function(self, text)
        local eb = self.editBox or self.EditBox
        local name = eb and AS.Trim(eb:GetText()) or ""
        if name ~= "" then Send(text or self.data, "WHISPER", name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = AS.Trim(self:GetText())
        if name ~= "" then Send(parent.data, "WHISPER", name) end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function ReplaceInChat(name, slug, code)
    local class = AS.SlugToClass(slug)
    return ("|H%s%s:%s:%s|h|cff%s[%s: %s]|h|r"):format(LINK_PREFIX, slug, code, name, AS.ClassColor(class), TAG, name)
end

local function ChatFilter(self, event, msg, ...)
    if type(msg) ~= "string" then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    if not (msg:find("[Auto Super Spec: ", 1, true) or msg:find("[AutoSpec: ", 1, true)) then return false end
    local newMsg, n = msg:gsub("%[Auto Super Spec: (.-) %- ([%a%-]+):(%w+)%]", ReplaceInChat)
    local n2
    newMsg, n2 = newMsg:gsub("%[AutoSpec: (.-) %- ([%a%-]+):(%w+)%]", ReplaceInChat)
    if n + n2 == 0 then return false end
    return false, newMsg, ...
end

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function OnLinkClicked(link)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return end
    local slug, code, name = link:sub(#LINK_PREFIX + 1):match("^([^:]+):([^:]+):(.*)$")
    if not slug then return end
    local text = ("[%s: %s - %s:%s]"):format(TAG, name, slug, code)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        OpenChatWith(text)
        return
    end
    local class = AS.SlugToClass(slug)
    local dup = AS.FindDuplicate(class, code)
    if dup then
        Print(("you already have this build as |cffffd100%s|r."):format(dup.name))
        AS.ShowUI(class)
        return
    end
    StaticPopup_Show("AUTOSUPERSPEC_RECEIVE", name, AS.ClassName(class), { text = text, name = name })
end

local function SetupChat()
    local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if addFilter then
        for _, ev in ipairs(CHAT_EVENTS) do pcall(addFilter, ev, ChatFilter) end
    end
    if type(SetItemRef) == "function" then
        hooksecurefunc("SetItemRef", OnLinkClicked)
    end
end

------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------

local function PrintStatus()
    local b = AS.ActiveBuild()
    if not b then
        Print("not following a build. Type /ass to open Auto Super Spec.")
        return
    end
    local progress, err = AS.Progress(b)
    if not progress then Print(b.name .. ": " .. err) return end
    Print(("%s - %d/%d points learned, learning on level-up is %s%s."):format(b.name, progress.done, progress.total,
        AS.char.enabled and "on" or "off", AS.char.mode == "ask" and " (asks first)" or ""))
    if progress.next then
        Print(("next: %s %d/%d"):format(progress.next.t.name, progress.next.rank, progress.next.t.maxRank))
    end
end

local function PrintOrder()
    local b = AS.ActiveBuild()
    if not b then Print("not following a build.") return end
    local progress, err = AS.Progress(b)
    if not progress then Print(err) return end
    local count = {}
    Print(b.name .. ":")
    for i, t in ipairs(progress.steps) do
        count[t.key] = (count[t.key] or 0) + 1
        local done = t.rank >= count[t.key]
        DEFAULT_CHAT_FRAME:AddMessage(("  %s%2d. %s %d/%d|r"):format(done and "|cff33ff33" or "|cffffffff", i, t.name, count[t.key], t.maxRank))
    end
end

SLASH_AUTOSUPERSPEC1 = "/ass"
SLASH_AUTOSUPERSPEC2 = "/autosuperspec"
SlashCmdList["AUTOSUPERSPEC"] = function(msg)
    msg = AS.Trim(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "show" then
        AS.ToggleUI()
    elseif cmd == "import" then
        local b, err = AS.Import(rest)
        if not b then Print("|cffff4444import failed|r - " .. err) end
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "list" then
        PrintOrder()
    elseif cmd == "on" or cmd == "off" then
        AS.char.enabled = cmd == "on"
        Print("learning on level-up is " .. cmd .. ".")
        if AS.char.enabled then state.paused = false; AS.TryLearn() end
        AS.RefreshUI()
    elseif cmd == "ask" or cmd == "auto" then
        AS.char.mode = cmd
        Print(cmd == "ask" and "will ask before learning." or "will learn without asking.")
        AS.RefreshUI()
    elseif cmd == "learn" or cmd == "apply" or cmd == "spec" then
        if AS.char.active then AS.SpecNow(AS.char.active) else Print("not following a build.") end
    elseif cmd == "resume" then
        state.paused = false
        AS.TryLearn(true)
        AS.RefreshUI()
    elseif cmd == "minimap" then
        AS.ToggleMinimapButton()
    elseif cmd == "view" then
        local b = AS.ActiveBuild()
        if b then AS.ShowBuild(b.id) else Print("not following a build.") end
    elseif cmd == "debug" then
        AS.ShowCopyWindow("Auto Super Spec debug - press Ctrl+C to copy", T.DebugText())
    else
        Print("commands: /ass (window), /ass view, /ass import <link>, /ass status, /ass list, /ass on|off, /ass ask|auto, /ass learn, /ass resume, /ass minimap, /ass debug")
    end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local f = CreateFrame("Frame")
local function Register(ev) pcall(f.RegisterEvent, f, ev) end
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    Register(ev)
end
for _, ev in ipairs(T.Events()) do Register(ev) end

local function ScheduleTry(delay)
    if state.scheduled then return end
    state.scheduled = true
    AS.After(delay or 0.5, function()
        state.scheduled = false
        AS.TryLearn()
        AS.RefreshUI()
    end)
end

local reportedBlocks = {}

f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- the game blamed us for a blocked action: say which one, once
        if arg1 == ADDON_NAME and not reportedBlocks[tostring(arg2)] then
            reportedBlocks[tostring(arg2)] = true
            Print(("the game blocked |cffffd100%s|r%s. Please tell the addon author what you were doing."):format(
                tostring(arg2), InCombatLockdown and InCombatLockdown() and " (in combat)" or ""))
        end
        return
    elseif event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        AutoSuperSpecDB = AutoSuperSpecDB or {}
        AutoSuperSpecDB.builds = AutoSuperSpecDB.builds or {}
        AutoSuperSpecCharDB = AutoSuperSpecCharDB or {}
        if AutoSuperSpecCharDB.enabled == nil then AutoSuperSpecCharDB.enabled = true end
        AutoSuperSpecCharDB.mode = AutoSuperSpecCharDB.mode or "auto"
        AS.db, AS.char = AutoSuperSpecDB, AutoSuperSpecCharDB
    elseif event == "PLAYER_LOGIN" then
        SetupChat()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleTry(3)
    elseif event == "PLAYER_LEVEL_UP" then
        state.paused = false
        ScheduleTry(1.5)
        AS.After(4, function()
            local b = AS.ActiveBuild()
            local unspent = T.Unspent()
            if b and not state.busy and unspent and unspent > 0 and b.class == AS.PlayerClass() then
                local progress = AS.Progress(b)
                if progress and not progress.next then
                    Print(("%s is complete - you have %d unspent point(s)."):format(b.name, unspent))
                end
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.waitCombat then
            state.waitCombat = false
            ScheduleTry(0.5)
        end
    else
        T.OnEvent(event, arg1)
        ScheduleTry(0.5)
    end
end)
