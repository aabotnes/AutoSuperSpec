-- The game's talent window (Talents & Spellbook): highlights the next talent of
-- the build you follow, and adds a button that opens Auto Super Spec.
-- Only reads Blizzard's frames and anchors our own frames to them; it never
-- changes their frames, so it can't cause "action blocked" problems.

local _, AS = ...
local T = AS.Talents

local overlay, openButton, ticker
local hooked = false

local function Window() return _G.PlayerSpellsFrame end

local function TalentsFrame()
    local w = Window()
    return w and w.TalentsFrame
end

-- The talent button for a node, using whatever the window offers.
local function FindButton(tf, nodeID)
    if tf.GetTalentButtonByNodeID then
        local ok, b = pcall(tf.GetTalentButtonByNodeID, tf, nodeID)
        if ok and b then return b end
    end
    if tf.EnumerateAllTalentButtons then
        local ok, f, s, v = pcall(tf.EnumerateAllTalentButtons, tf)
        if ok and type(f) == "function" then
            for b in f, s, v do
                local id = (type(b) == "table") and (b.GetNodeID and b:GetNodeID() or b.nodeID)
                if id == nodeID then return b end
            end
        end
    end
end

-- Is the window showing this character's active talents (not a shared link)?
local function ShowingActiveTalents(tf)
    if not tf.GetConfigID or not C_ClassTalents or not C_ClassTalents.GetActiveConfigID then return true end
    local ok1, shown = pcall(tf.GetConfigID, tf)
    local ok2, active = pcall(C_ClassTalents.GetActiveConfigID)
    return not (ok1 and ok2 and shown and active) or shown == active
end

-- The next point of the build you follow, if there is one for this character.
local function NextPoint()
    local b = AS.ActiveBuild()
    if not b or b.class ~= AS.PlayerClass() then return nil end
    local progress = AS.Progress(b)
    return progress and progress.next, b
end

local function CreateOverlay(parent)
    local o = CreateFrame("Frame", nil, parent)
    o:Hide()
    local function Edge(p1, p2, w, h)
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 3)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 3)
    Edge("TOPLEFT", "BOTTOMLEFT", 3, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 3, nil)
    local glow = o:CreateTexture(nil, "ARTWORK")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0, 0.18)

    o.tag = CreateFrame("Frame", nil, o)
    o.tag:SetHeight(16)
    o.tag:SetPoint("BOTTOM", o, "TOP", 0, 2)
    local bg = o.tag:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
    o.tag.text = o.tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.tag.text:SetPoint("CENTER")

    -- gentle pulse
    local ag = o.CreateAnimationGroup and o:CreateAnimationGroup()
    if ag then
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        if a then
            a:SetFromAlpha(1)
            a:SetToAlpha(0.45)
            a:SetDuration(0.8)
        end
        o:SetScript("OnShow", function() ag:Play() end)
        o:SetScript("OnHide", function() ag:Stop() end)
    end
    return o
end

local function OpenButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(AS.TITLE)
    local nxt, b = NextPoint()
    if b then
        GameTooltip:AddLine("Following: |cffffffff" .. b.name .. "|r", 1, 0.82, 0)
        if nxt then
            GameTooltip:AddLine(("Next talent: %s %d/%d (level %d)"):format(nxt.t.name, nxt.rank, nxt.t.maxRank, 9 + nxt.step), 0.4, 1, 0.4)
        else
            GameTooltip:AddLine("Build complete", 0.4, 1, 0.4)
        end
    else
        GameTooltip:AddLine("Not following a build", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Click to open Auto Super Spec", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Puts the highlight on the next talent (or hides it).
function AS.UpdateTalentWindow()
    local tf = TalentsFrame()
    if not overlay or not tf then return end
    local function hide() overlay:Hide() end
    if not tf:IsVisible() or not ShowingActiveTalents(tf) then return hide() end
    local nxt = NextPoint()
    if not nxt or not nxt.t.nodeID then return hide() end
    local button = FindButton(tf, nxt.t.nodeID)
    if not button or not button:IsVisible() then return hide() end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
    overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
    overlay:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
    overlay.tag.text:SetText(("NEXT  ·  Lvl %d  ·  %d/%d"):format(9 + nxt.step, nxt.rank, nxt.t.maxRank))
    overlay.tag:SetWidth(overlay.tag.text:GetStringWidth() + 12)
    overlay:Show()
end

local function Setup()
    local w, tf = Window(), TalentsFrame()
    if hooked or not w or not tf then return end
    hooked = true

    overlay = CreateOverlay(tf)

    openButton = CreateFrame("Button", "AutoSuperSpecTalentWindowButton", w, "UIPanelButtonTemplate")
    openButton:SetSize(170, 26)
    openButton:SetPoint("TOPRIGHT", w, "BOTTOMRIGHT", -24, 2)
    openButton:SetText("    Auto Super Spec")
    openButton.icon = openButton:CreateTexture(nil, "ARTWORK")
    openButton.icon:SetSize(18, 18)
    openButton.icon:SetPoint("LEFT", 10, 0)
    openButton.icon:SetTexture(AS.ICON)
    openButton:SetScript("OnClick", function() AS.ShowUI() end)
    openButton:SetScript("OnEnter", OpenButtonTooltip)
    openButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function refresh() AS.After(0.05, AS.UpdateTalentWindow) end
    w:HookScript("OnShow", refresh)
    tf:HookScript("OnShow", refresh)
    tf:HookScript("OnHide", function() overlay:Hide() end)

    -- keep it in place while the window is open (tree reloads, spec tabs)
    ticker = CreateFrame("Frame", nil, tf)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 1 then
            elapsed = 0
            AS.UpdateTalentWindow()
        end
    end)
    refresh()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not hooked then Setup() end
end)

-- Talent changes (our own learning included) move the highlight right away.
local refreshEvents = CreateFrame("Frame")
for _, ev in ipairs(T.Events()) do pcall(refreshEvents.RegisterEvent, refreshEvents, ev) end
refreshEvents:SetScript("OnEvent", function()
    if hooked then AS.After(0.3, AS.UpdateTalentWindow) end
end)
