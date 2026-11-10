-- Minimap button: left-click opens the window, right-click shows the build you
-- follow, drag to move it around the minimap.

local _, AS = ...
local btn

-- The addon's own icon (Media\\icon.tga): a gold talent slot.
AS.ICON = "Interface\\AddOns\\" .. AS.name .. "\\Media\\icon"

local function Settings()
    AS.db.minimap = AS.db.minimap or { angle = 200, hide = false }
    return AS.db.minimap
end

local function UpdatePosition()
    local angle = math.rad(Settings().angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    Settings().angle = math.deg(math.atan2(py - my, px - mx))
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(AS.TITLE)
    local b = AS.ActiveBuild()
    if b and b.class == AS.PlayerClass() then
        GameTooltip:AddLine("Following: |cffffffff" .. b.name .. "|r", 1, 0.82, 0)
        local progress = AS.Progress(b)
        if progress then
            GameTooltip:AddLine(("%d / %d points learned"):format(progress.done, progress.total), 0.8, 0.8, 0.8)
            if progress.next then
                GameTooltip:AddLine(("Next: %s %d/%d"):format(progress.next.t.name, progress.next.rank, progress.next.t.maxRank), 0.4, 1, 0.4)
            else
                GameTooltip:AddLine("Build complete", 0.4, 1, 0.4)
            end
        end
        if AS.state.paused then GameTooltip:AddLine("Paused - /ass resume", 1, 0.3, 0.3) end
        if not AS.char.enabled then GameTooltip:AddLine("Learning on level up is off", 0.6, 0.6, 0.6) end
    else
        GameTooltip:AddLine("Not following a build", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open builds", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: view your build's talents and order", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Create()
    if btn or not Minimap then return end
    btn = CreateFrame("Button", "AutoSuperSpecMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(21, 21)
    btn.icon:SetPoint("TOPLEFT", 6, -5)
    btn.icon:SetTexture(AS.ICON)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    btn.dot = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    btn.dot:SetSize(8, 8)
    btn.dot:SetPoint("TOPRIGHT", -3, -3)
    btn.dot:SetColorTexture(1, 0.3, 0.3, 1)
    btn.dot:Hide()

    btn:SetScript("OnClick", function(_, button)
        GameTooltip:Hide()
        if button == "RightButton" then
            local b = AS.ActiveBuild()
            if b then AS.ShowBuild(b.id) else AS.ShowUI() end
        else
            AS.ToggleUI()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", ShowTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    btn:SetShown(not Settings().hide)
end

-- red dot while paused
function AS.RefreshMinimap()
    if btn then btn.dot:SetShown(AS.state.paused and AS.ActiveBuild() ~= nil) end
end

function AS.ToggleMinimapButton()
    local s = Settings()
    s.hide = not s.hide
    if btn then btn:SetShown(not s.hide) end
    AS.Print(s.hide and "minimap button hidden - type /ass minimap to show it again." or "minimap button shown.")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", Create)
