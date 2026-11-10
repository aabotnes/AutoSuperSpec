-- Minimal WoW client mock shared by the AutoSpec tests.
local M = { log = {}, now = 0, timers = {}, popups = {}, frames = {}, chatFilters = {} }

local NoOp = setmetatable({}, {})
getmetatable(NoOp).__call = function() return nil end
getmetatable(NoOp).__index = function() return NoOp end

local Widget = {}
local function NewWidget()
    local w = { _scripts = {}, _shown = false, _text = "", _checked = false, _events = {} }
    return setmetatable(w, { __index = function(_, k)
        if Widget[k] then return Widget[k] end
        if type(k) == "string" and k:match("^%u") then return NoOp end -- methods / template children
        return nil -- plain fields: like real frames
    end })
end
function Widget.SetScript(self, k, fn) self._scripts[k] = fn end
function Widget.HookScript(self, k, fn) self._scripts[k] = fn end
function Widget.GetScript(self, k) return self._scripts[k] end
function Widget.Show(self) self._shown = true end
function Widget.Hide(self) self._shown = false end
function Widget.IsShown(self) return self._shown end
function Widget.SetShown(self, v) self._shown = v and true or false end
function Widget.SetText(self, t) self._text = t end
function Widget.GetText(self) return self._text end
function Widget.SetChecked(self, v) self._checked = v end
function Widget.GetChecked(self) return self._checked end
function Widget.CreateFontString() return NewWidget() end
function Widget.CreateTexture() return NewWidget() end
function Widget.Insert(self, t) self._text = self._text .. t end
function Widget.GetStringWidth() return 80 end
function Widget.GetHeight() return 300 end
function Widget.GetWidth() return 140 end
function Widget.GetCenter() return 0, 0 end
function Widget.GetEffectiveScale() return 1 end
function Widget.GetFrameLevel() return 1 end
function Widget.IsEnabled(self) return self._enabled ~= false end
function Widget.SetEnabled(self, v) self._enabled = v and true or false end
function Widget.HasFocus() return false end
function Widget.IsMouseOver() return false end
function Widget.RegisterEvent(self, ev) self._events[ev] = true end
function Widget.Click(self, button) self._scripts.OnClick(self, button or "LeftButton") end

function CreateFrame(kind, name, parent, template)
    local w = NewWidget()
    if kind == "Frame" and template and template:find("FrameTemplate") then
        w.CloseButton = NewWidget()
        -- like the real template: closing goes through the panel manager (locked in combat)
        w.CloseButton:SetScript("OnClick", function() if not M.inCombat then w:Hide() end end)
    end
    M.frames[#M.frames + 1] = w
    if name then _G[name] = w end
    return w
end

function M.Fire(ev, ...)
    for _, fr in ipairs(M.frames) do
        if fr._events[ev] and fr._scripts.OnEvent then fr._scripts.OnEvent(fr, ev, ...) end
    end
end

C_Timer = { After = function(sec, fn) M.timers[#M.timers + 1] = { t = M.now + sec, fn = fn } end }
function M.Advance(sec)
    local target = M.now + sec
    while true do
        table.sort(M.timers, function(a, b) return a.t < b.t end)
        local nxt = M.timers[1]
        if not nxt or nxt.t > target then break end
        table.remove(M.timers, 1)
        M.now = nxt.t
        nxt.fn()
    end
    M.now = target
end
function GetTime() return M.now end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) M.log[#M.log + 1] = m end }
UIParent = NewWidget()
GameTooltip = NewWidget()
local tipLines = {}
GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = tostring(t) end
GameTooltip.SetOwner = function() for k in pairs(tipLines) do tipLines[k] = nil end end
M.tipLines = tipLines
Minimap = NewWidget()
function GetCursorPosition() return 10, 10 end
UISpecialFrames = {}
tinsert = table.insert
StaticPopupDialogs = {}
function StaticPopup_Show(which, a1, a2, data)
    local d = NewWidget(); d.data = data; d.which = which; d.args = { a1, a2 }
    M.popups[#M.popups + 1] = d
    return d
end
function StaticPopup_Visible(which)
    for _, p in ipairs(M.popups) do if p.which == which and not rawget(p, "done") then return true end end
end
function M.LastPopup() return M.popups[#M.popups] end
function M.ClickPopup(which)
    for _, p in ipairs(M.popups) do
        if p.which == which and not rawget(p, "done") then
            p.done = true
            StaticPopupDialogs[which].OnAccept(p, p.data)
            return true
        end
    end
end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid", WARRIOR = "Warrior", MAGE = "Mage" }
SlashCmdList = {}
function hooksecurefunc(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...); fn(...) end end
function SetItemRef() end
function ChatFrame_AddMessageEventFilter(ev, fn) M.chatFilters[ev] = fn end
M.chatBox = NewWidget()
function ChatFrame_OpenChat(t) M.chatBox._text = t end
function IsModifiedClick() return false end
function IsShiftKeyDown() return false end
function IsMouseButtonDown() return false end
function InCombatLockdown() return M.inCombat or false end
function GetBuildInfo() return "1.60.1", "70790", "Nov 3 2026", 16001 end
function UnitLevel() return M.level end
ChatFontNormal = {}

function M.Load(dir, files)
    local AS = {}
    for _, f in ipairs(files) do
        local chunk = assert(loadfile(dir .. "/" .. f))
        chunk("AutoSuperSpec", AS)
    end
    M.Fire("ADDON_LOADED", "AutoSuperSpec")
    M.Fire("PLAYER_LOGIN")
    return AS
end

function M.LogHas(pattern)
    for _, l in ipairs(M.log) do if l:find(pattern) then return l end end
end

function M.check(cond, msg)
    if not cond then
        print("FAIL: " .. msg)
        for _, l in ipairs(M.log) do print("   log: " .. l) end
        os.exit(1)
    end
    print("ok   " .. msg)
end

return M
