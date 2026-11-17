-- "Talent learned" popups: achievement-style banners with the talent's icon
-- and its name in yellow. Shown for talents learned on a ding (or from the
-- Learn prompt), and as one summary for "Spec now". Look, sound and position
-- are set on the Settings page and saved for the whole account.

local _, AS = ...
local Toast = {}
AS.Toast = Toast

local W, H = 330, 78
local GAP = 8
local MAX_SHOWN = 3
local FADE_IN, FADE_OUT, SLIDE = 0.3, 0.7, 18

local DEFAULTS = {
    enabled = true, specNow = true, style = "class", scale = 1, duration = 5,
    title = "Talent Learned", anim = true, sound = "talent", soundID = 0, channel = "Master",
    combat = "wait", desc = false, askSound = "readycheck",
}

Toast.STYLES = {
    { key = "achievement", name = "Achievement", border = { 1, 0.82, 0 }, inner = { 0.55, 0.4, 0.08 }, bg = { 0.08, 0.06, 0.02, 0.95 } },
    { key = "arcane", name = "Arcane", border = { 0.76, 0.49, 1 }, inner = { 0.35, 0.2, 0.55 }, bg = { 0.08, 0.05, 0.14, 0.95 } },
    { key = "class", name = "Class color", border = "class", inner = { 0.3, 0.3, 0.3 }, bg = { 0.05, 0.05, 0.06, 0.95 } },
    { key = "minimal", name = "Minimal", bg = { 0, 0, 0, 0.75 }, minimal = true },
}

Toast.SOUNDS = {
    { key = "none", name = "None" },
    { key = "talent", name = "Talent learned", id = 217825 }, -- the game's CLASS_TALENT_LEARN_TALENT
    { key = "achievement", name = "Achievement", id = 12891 },
    { key = "levelup", name = "Level up", id = 888 },
    { key = "quest", name = "Quest complete", id = 878 },
    { key = "readycheck", name = "Ready check", id = 8960 },
    { key = "raidwarning", name = "Raid warning", id = 8959 },
    { key = "custom", name = "Custom sound ID" },
}

Toast.CHANNELS = { "Master", "SFX", "Dialog", "Ambience", "Music" }

Toast.COMBAT = {
    { key = "wait", name = "After combat" },
    { key = "show", name = "Right away" },
}

local function HoldForCombat(data)
    return not data.preview and Toast.Settings().combat == "wait" and InCombatLockdown and InCombatLockdown()
end

function Toast.Settings()
    AS.db.toast = AS.db.toast or {}
    local s = AS.db.toast
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    -- 4.8.2 changed the defaults: move settings still on the old defaults
    if (s.defaults or 1) < 2 then
        if s.style == "achievement" then s.style = "class" end
        if s.sound == "achievement" then s.sound = "talent" end
        s.defaults = 2
    end
    return s
end

function Toast.Find(list, key)
    for i, item in ipairs(list) do
        if item.key == key or item == key then return item, i end
    end
    return list[1], 1
end

------------------------------------------------------------------------------
-- Sound
------------------------------------------------------------------------------

local lastSound = -1

-- which: "ask" for the "Learn now?" popup, otherwise the talent learned sound.
function Toast.PlaySound(force, which)
    local s = Toast.Settings()
    local entry = Toast.Find(Toast.SOUNDS, which == "ask" and s.askSound or s.sound)
    local id = entry.key == "custom" and tonumber(s.soundID) or entry.id
    if not id or id <= 0 or type(PlaySound) ~= "function" then return false end
    if which ~= "ask" then
        if not force and GetTime() - lastSound < 0.4 then return false end -- one sound per burst of learned popups
        lastSound = GetTime()
    end
    return pcall(PlaySound, id, s.channel)
end

------------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------------

local pool, shown, queue = {}, {}, {}
local driver

local function Edge(f, layer, sub)
    local t = f:CreateTexture(nil, layer, nil, sub)
    return t
end

local function Frame4(f, inset, width, layer)
    local e = {}
    for i = 1, 4 do e[i] = Edge(f, layer or "BORDER") end
    e[1]:SetPoint("TOPLEFT", inset, -inset); e[1]:SetPoint("TOPRIGHT", -inset, -inset); e[1]:SetHeight(width)
    e[2]:SetPoint("BOTTOMLEFT", inset, inset); e[2]:SetPoint("BOTTOMRIGHT", -inset, inset); e[2]:SetHeight(width)
    e[3]:SetPoint("TOPLEFT", inset, -inset); e[3]:SetPoint("BOTTOMLEFT", inset, inset); e[3]:SetWidth(width)
    e[4]:SetPoint("TOPRIGHT", -inset, -inset); e[4]:SetPoint("BOTTOMRIGHT", -inset, inset); e[4]:SetWidth(width)
    return e
end

local function SetColor(list, r, g, b, a)
    for _, t in ipairs(list) do t:SetColorTexture(r, g, b, a or 1) end
end

local function Dismiss(f)
    if f.t < (f.fadeOutAt or 0) then f.t = f.fadeOutAt end
end

local function CreateToast()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:Hide()

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.shade:SetPoint("TOPLEFT", 3, -3)
    f.shade:SetPoint("TOPRIGHT", -3, -3)
    f.shade:SetHeight(H / 2 - 3)
    f.shade:SetColorTexture(1, 1, 1, 0.04)
    f.outer = Frame4(f, 0, 2)
    f.inner = Frame4(f, 4, 1)

    f.iconFrame = f:CreateTexture(nil, "ARTWORK")
    f.iconFrame:SetSize(56, 56)
    f.iconFrame:SetPoint("TOPLEFT", 12, -11)
    f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.icon:SetSize(52, 52)
    f.icon:SetPoint("CENTER", f.iconFrame, "CENTER")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", 12, -2)
    f.title:SetJustifyH("LEFT")
    f.corner = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.corner:SetPoint("TOPRIGHT", -12, -12)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("LEFT", f.iconFrame, "RIGHT", 12, 0)
    f.name:SetPoint("RIGHT", -12, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.name:SetTextColor(1, 0.82, 0)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("BOTTOMLEFT", f.iconFrame, "BOTTOMRIGHT", 12, 2)
    f.sub:SetPoint("RIGHT", -12, 0)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.sub:SetTextColor(0.8, 0.8, 0.8)

    f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.desc:SetPoint("TOPLEFT", 16, -(H - 4))
    f.desc:SetWidth(W - 32)
    f.desc:SetJustifyH("LEFT")
    f.desc:SetJustifyV("TOP")
    f.desc:SetWordWrap(true)
    if f.desc.SetMaxLines then f.desc:SetMaxLines(6) end
    f.desc:SetTextColor(1, 0.82, 0) -- same gold as talent tooltips
    f.desc:SetSpacing(2)
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetHeight(1)
    f.divider:SetPoint("TOPLEFT", 14, -(H - 10))
    f.divider:SetPoint("TOPRIGHT", -14, -(H - 10))

    f.flash = f:CreateTexture(nil, "OVERLAY")
    f.flash:SetAllPoints()

    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            Dismiss(self)
        elseif self.data and self.data.buildId and AS.GetBuild(self.data.buildId) then
            AS.ShowBuild(self.data.buildId)
            Dismiss(self)
        else
            AS.ShowUI()
            Dismiss(self)
        end
    end)
    f:SetScript("OnEnter", function(self) self.hover = true end)
    f:SetScript("OnLeave", function(self) self.hover = false end)
    return f
end

local function ApplyStyle(f, s)
    local style = Toast.Find(Toast.STYLES, s.style)
    local br, bg_, bb = 1, 0.82, 0
    if style.border == "class" then
        br, bg_, bb = AS.ClassRGB(AS.PlayerClass())
    elseif style.border then
        br, bg_, bb = style.border[1], style.border[2], style.border[3]
    end
    f.bg:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.bg[4])
    local framed = not style.minimal
    SetColor(f.outer, br, bg_, bb, framed and 1 or 0)
    SetColor(f.inner, style.inner and style.inner[1] or 0, style.inner and style.inner[2] or 0, style.inner and style.inner[3] or 0, framed and 0.9 or 0)
    f.iconFrame:SetColorTexture(br, bg_, bb, framed and 1 or 0)
    f.divider:SetColorTexture(br, bg_, bb, framed and 0.35 or 0.15)
    f.flash:SetColorTexture(br, bg_, bb, 0)
    f.flashColor = { br, bg_, bb }
    f.shade:SetShown(framed)
    f:SetScale(math.max(0.5, math.min(2, s.scale or 1)))
end

local function Anchor()
    local s = Toast.Settings()
    local p = s.point
    if type(p) == "table" and p[1] then return p[1], p[2] or p[1], p[3] or 0, p[4] or 0 end
    return "TOP", "TOP", 0, -150
end

local ask -- the "learn now?" popup (Ask first)

-- Height that fits the popup's content (description, ask buttons).
local function Measure(f)
    local h = H
    if f.desc:IsShown() then h = h + (f.desc:GetStringHeight() or 0) + 12 end
    if f.ask then h = h + 34 end
    return math.floor(h + 0.5)
end

local function Layout()
    local point, relPoint, x, y = Anchor()
    local offset = 0
    local list = {}
    if ask and ask:IsShown() then list[1] = ask end
    for _, f in ipairs(shown) do list[#list + 1] = f end
    for i, f in ipairs(list) do
        local slide = 0
        if f.anim and f.t < FADE_IN then slide = SLIDE * (1 - f.t / FADE_IN) end
        f:ClearAllPoints()
        f:SetPoint(point, UIParent, relPoint, x / f:GetScale(), (y + slide) / f:GetScale() - offset / f:GetScale())
        offset = offset + ((f.height or H) + GAP) * f:GetScale()
    end
end

local function Fill(f, data)
    local s = Toast.Settings()
    ApplyStyle(f, s)
    f.data = data
    f.icon:SetTexture(data.icon or AS.ICON)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.title:SetText(((data.title or s.title or ""):upper()))
    f.name:SetText(data.name or "")
    f.sub:SetText(data.sub or "")
    f.corner:SetText(data.corner or "")
    local desc = s.desc and type(data.desc) == "string" and data.desc ~= "" and data.desc
    f.desc:SetText(desc or "")
    f.desc:SetShown(desc and true or false)
    f.divider:SetShown(desc and true or false)
    f.height = Measure(f)
    f:SetHeight(f.height)
    f.t, f.hover, f.anim = 0, false, s.anim
    f.fadeOutAt = FADE_IN + math.max(1, s.duration or 5)
    f.endAt = f.fadeOutAt + FADE_OUT
    f:SetAlpha(s.anim and 0 or 1)
    f:Show()
end

local function Pump()
    while #shown < MAX_SHOWN and #queue > 0 and not HoldForCombat(queue[1]) do
        local data = table.remove(queue, 1)
        local f = table.remove(pool) or CreateToast()
        Fill(f, data)
        shown[#shown + 1] = f
        if not data.silent then Toast.PlaySound() end
    end
    Layout()
    if driver then driver:SetShown(#shown > 0 or (ask ~= nil and ask:IsShown())) end
end

-- Fades a popup in (and out), with the flash.
local function Animate(f, fadeOut)
    local alpha = 1
    if f.anim then
        if f.t < FADE_IN then alpha = f.t / FADE_IN
        elseif fadeOut and f.t > f.fadeOutAt then alpha = 1 - (f.t - f.fadeOutAt) / FADE_OUT end
        local flash = math.max(0, 1 - f.t / 0.9) * 0.45
        f.flash:SetColorTexture(f.flashColor[1], f.flashColor[2], f.flashColor[3], flash)
    elseif fadeOut and f.t > f.fadeOutAt then
        alpha = 0
    end
    f:SetAlpha(math.max(0, math.min(1, alpha)))
end

-- Advances every popup by dt seconds (fade, slide, flash, hide).
function Toast.Update(dt)
    local i = 1
    while shown[i] do
        local f = shown[i]
        if not (f.hover and f.t >= FADE_IN and f.t < f.fadeOutAt) then f.t = f.t + dt end
        if f.t >= f.endAt then
            f:Hide()
            table.remove(shown, i)
            pool[#pool + 1] = f
        else
            Animate(f, true)
            i = i + 1
        end
    end
    if ask and ask:IsShown() then
        ask.t = ask.t + dt
        Animate(ask, false)
    end
    -- re-measure once the game has laid the text out
    for _, f in ipairs(shown) do
        local h = Measure(f)
        if h ~= f.height then f.height = h; f:SetHeight(h) end
    end
    if ask and ask:IsShown() then
        local h = Measure(ask)
        if h ~= ask.height then ask.height = h; ask:SetHeight(h) end
    end
    Pump()
end

driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, dt) Toast.Update(dt or 0) end)

-- popups held back during combat show when it ends
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function() AS.After(0.5, Pump) end)

function Toast.Waiting() return #queue end

------------------------------------------------------------------------------
-- "Learn now?" popup (Ask first)
------------------------------------------------------------------------------

local function CreateAsk()
    local f = CreateToast()
    f.ask = true
    f.yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.yes:SetSize(104, 22)
    f.yes:SetPoint("BOTTOMRIGHT", -12, 10)
    f.yes:SetText("Learn now")
    f.no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.no:SetSize(88, 22)
    f.no:SetPoint("RIGHT", f.yes, "LEFT", -6, 0)
    f.no:SetText("Not now")
    f.yes:SetScript("OnClick", function()
        local yes = f.onYes
        Toast.HideAsk()
        if yes then yes() end
    end)
    f.no:SetScript("OnClick", function() Toast.HideAsk() end)
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then Toast.HideAsk() end
    end)
    return f
end

-- Shows (or updates) the "learn now?" popup. onYes runs on "Learn now".
function Toast.ShowAsk(data, onYes)
    local again = ask ~= nil and ask:IsShown()
    ask = ask or CreateAsk()
    local t = again and ask.t or 0
    Fill(ask, data)
    ask.t = t
    ask.onYes = onYes
    if not again then Toast.PlaySound(true, "ask") end
    Pump()
end

function Toast.HideAsk()
    if ask then ask:Hide(); ask.onYes = nil end
    Pump()
end

function Toast.AskFrame() return ask end
function Toast.AskShown() return ask ~= nil and ask:IsShown() end

function Toast.Show(data)
    local s = Toast.Settings()
    if not s.enabled and not data.preview then return false end
    queue[#queue + 1] = data
    Pump()
    return true
end

function Toast.Shown() return shown end

------------------------------------------------------------------------------
-- What gets shown
------------------------------------------------------------------------------

-- learned: { { t = talent, rank = n, level = l }, ... } in the order learned.
-- mode: "auto" (ding / Learn prompt) or "spec" (Spec now).
function Toast.TalentsLearned(learned, build, mode)
    if #learned == 0 then return end
    local s = Toast.Settings()
    if mode == "spec" or #learned > MAX_SHOWN then
        if mode == "spec" and not s.specNow then return end
        local last = learned[#learned]
        Toast.Show({
            icon = last.t.icon, title = mode == "spec" and "Spec complete" or s.title,
            name = build and build.name or last.t.name,
            sub = ("%d talents learned"):format(#learned),
            corner = last.level and ("Lvl " .. last.level) or nil, buildId = build and build.id,
        })
        return
    end
    for i, l in ipairs(learned) do
        Toast.Show({
            icon = l.t.icon, name = l.t.name, desc = AS.Talents.Description(l.t, l.rank),
            sub = ("Rank %d/%d%s"):format(l.rank, l.t.maxRank, build and ("  ·  " .. build.name) or ""),
            corner = l.level and ("Lvl " .. l.level) or nil,
            buildId = build and build.id, silent = i > 1,
        })
    end
end

-- Shows the popup for the next talent of the build you follow (or an example).
-- Shows the popup for the next talent of the build you follow (or an example).
-- With Ask first on, it previews the whole flow: the "Learn now?" popup, and
-- on "Learn now" the talent learned popup (nothing is actually learned).
function Toast.Preview()
    local b = AS.ActiveBuild()
    local progress = b and b.class == AS.PlayerClass() and AS.Progress(b)
    local nxt = progress and progress.next
    local data
    if nxt then
        data = {
            preview = true, icon = nxt.t.icon, name = nxt.t.name, desc = AS.Talents.Description(nxt.t, nxt.rank),
            sub = ("Rank %d/%d  ·  %s"):format(nxt.rank, nxt.t.maxRank, b.name),
            corner = "Lvl " .. (9 + nxt.step), buildId = b.id,
        }
    else
        data = {
            preview = true, icon = AS.ICON, name = "Example Talent",
            desc = "Increases your chance to dodge by 2%. This is where the talent's effect is described.",
            sub = "Rank 1/5  ·  activate a build to preview its next talent", corner = "Lvl 10",
        }
    end
    if AS.char and AS.char.mode == "ask" then
        local learned = {}
        for k, v in pairs(data) do learned[k] = v end
        data.title = "Learn talent?"
        Toast.ShowAsk(data, function() Toast.Show(learned) end)
    else
        Toast.Show(data)
    end
end

------------------------------------------------------------------------------
-- Moving the popup
------------------------------------------------------------------------------

local mover

function Toast.IsMoving() return mover ~= nil and mover:IsShown() end

function Toast.StopMoving()
    if mover then mover:Hide() end
    if AS.RefreshUI then AS.RefreshUI() end
end

function Toast.StartMoving()
    if not mover then
        mover = CreateFrame("Button", "AutoSuperSpecToastMover", UIParent)
        mover:SetSize(W, H)
        mover:SetFrameStrata("FULLSCREEN_DIALOG")
        mover:SetMovable(true)
        mover:EnableMouse(true)
        mover:SetClampedToScreen(true)
        mover:RegisterForDrag("LeftButton")
        local bg = mover:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.6, 0.2, 0.55)
        SetColor(Frame4(mover, 0, 2), 0.3, 1, 0.4, 1)
        local text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("CENTER")
        text:SetText("Drag to move the popup\nClick when done")
        mover:SetScript("OnDragStart", mover.StartMoving)
        mover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            local scale = self:GetScale()
            Toast.Settings().point = { point, relPoint, x * scale, y * scale } -- screen units
        end)
        mover:SetScript("OnClick", Toast.StopMoving)
    end
    local s = Toast.Settings()
    local point, relPoint, x, y = Anchor()
    mover:SetScale(math.max(0.5, math.min(2, s.scale or 1)))
    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relPoint, x / mover:GetScale(), y / mover:GetScale())
    mover:Show()
end

function Toast.ResetPosition()
    Toast.Settings().point = nil
    if Toast.IsMoving() then Toast.StartMoving() end
    Layout()
end
