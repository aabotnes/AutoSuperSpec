-- Settings page (inside the main window): the "talent learned" popup's look,
-- sound and position, plus the general options.

local _, AS = ...
local U
local page
local controls = {}

local ROW = 32

local function Label(parent, y, text, x)
    local fs = U.Text(parent, "GameFontNormal")
    fs:SetPoint("TOPLEFT", x or 16, y)
    fs:SetText(text)
    return fs
end

local function Refresh()
    for _, c in ipairs(controls) do c() end
end

-- [<] value [>] for picking one item of a list.
local function Cycler(parent, y, label, list, get, set)
    Label(parent, y - 4, label)
    local value = U.Text(parent, "GameFontHighlight")
    local prev = U.Button(parent, "<", 26, 22, nil)
    prev:SetPoint("TOPLEFT", 150, y)
    value:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    value:SetWidth(140)
    local nextB = U.Button(parent, ">", 26, 22, nil)
    nextB:SetPoint("LEFT", value, "RIGHT", 6, 0)
    local function step(d)
        local _, i = AS.Toast.Find(list, get())
        i = ((i - 1 + d) % #list) + 1
        set(list[i].key or list[i])
        AS.RefreshUI()
    end
    prev:SetScript("OnClick", function() step(-1) end)
    nextB:SetScript("OnClick", function() step(1) end)
    controls[#controls + 1] = function()
        local item = AS.Toast.Find(list, get())
        value:SetText(item.name or item)
    end
    return nextB
end

-- [-] value [+] for numbers.
local function Stepper(parent, y, label, min, max, step, fmt, get, set)
    Label(parent, y - 4, label)
    local value = U.Text(parent, "GameFontHighlight")
    local minus = U.Button(parent, "-", 26, 22, function()
        set(math.max(min, (get() or min) - step))
        AS.RefreshUI()
    end)
    minus:SetPoint("TOPLEFT", 150, y)
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(140)
    local plus = U.Button(parent, "+", 26, 22, function()
        set(math.min(max, (get() or min) + step))
        AS.RefreshUI()
    end)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    controls[#controls + 1] = function() value:SetText(fmt(get() or min)) end
end

local function Toggle(parent, y, label, tooltip, get, set, x)
    local c = U.Check(parent, label, tooltip, function(self)
        set(self:GetChecked() and true or false)
        AS.RefreshUI()
    end)
    c:SetPoint("TOPLEFT", x or 12, y)
    controls[#controls + 1] = function() c:SetChecked(get() and true or false) end
    return c
end

function AS.CreateSettingsPage(parent, top)
    U = AS.UI
    local T = AS.Toast
    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 10, top)
    page:SetPoint("BOTTOMRIGHT", -10, 10)

    local back = U.Button(page, "< Back", 80, 24, function() AS.ShowUI() end)
    back:SetPoint("TOPLEFT", 0, 0)
    local title = U.Text(page, "GameFontHighlightLarge")
    title:SetPoint("LEFT", back, "RIGHT", 14, 0)
    title:SetText("Settings")

    -- left: the popup ---------------------------------------------------------
    local left = U.Panel(page, 0.35)
    left:SetPoint("TOPLEFT", 0, -36)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(520)
    local lt = U.Text(left, "GameFontNormalLarge")
    lt:SetPoint("TOPLEFT", 14, -12)
    lt:SetText("Talent learned popup")
    local lsub = U.Text(left, "GameFontDisableSmall")
    lsub:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -2)
    lsub:SetText("Your talent's icon and name, when a talent is learned.")

    local s = function() return T.Settings() end
    local y = -54
    Toggle(left, y, "Show a popup when a talent is learned", "Achievement-style popup with the talent's icon and name.",
        function() return s().enabled end, function(v) s().enabled = v end)
    y = y - ROW + 4
    Toggle(left, y, "Also for \"Spec now\" (one summary popup)", "When Spec now learns many talents at once, show one popup that sums it up.",
        function() return s().specNow end, function(v) s().specNow = v end)
    y = y - ROW - 4
    Cycler(left, y, "Style", T.STYLES, function() return s().style end, function(v) s().style = v end)
    y = y - ROW
    Stepper(left, y, "Size", 0.5, 2, 0.1, function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
        function() return s().scale end, function(v) s().scale = math.floor(v * 10 + 0.5) / 10 end)
    y = y - ROW
    Stepper(left, y, "Duration", 2, 15, 1, function(v) return ("%d seconds"):format(v) end,
        function() return s().duration end, function(v) s().duration = v end)
    y = y - ROW
    Label(left, y - 4, "Title text")
    local titleBox = U.Input(left, 220, "Talent Learned")
    titleBox:SetPoint("TOPLEFT", 156, y)
    titleBox:SetMaxLetters(40)
    titleBox:SetScript("OnEnterPressed", titleBox.ClearFocus)
    titleBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput == false then return end
        local text = AS.Trim(self:GetText())
        s().title = text ~= "" and text or "Talent Learned"
    end)
    controls[#controls + 1] = function()
        if not titleBox:HasFocus() then titleBox:SetText(s().title ~= "Talent Learned" and s().title or "") end
    end
    y = y - ROW
    Toggle(left, y, "Animation (slide in and flash)", "Slide and fade the popup in, with a short flash.",
        function() return s().anim end, function(v) s().anim = v end)
    y = y - ROW + 4
    Toggle(left, y, "Show the talent's description", "Add the talent's effect text (for the rank you learned) to the popup.",
        function() return s().desc end, function(v) s().desc = v end)
    y = y - ROW - 4
    local soundNext = Cycler(left, y, "Sound", T.SOUNDS, function() return s().sound end, function(v) s().sound = v end)
    local play = U.Button(left, "Play", 60, 22, function() T.PlaySound(true) end)
    play:SetPoint("LEFT", soundNext, "RIGHT", 10, 0)
    y = y - ROW
    Label(left, y - 4, "Custom sound ID")
    local idBox = U.Input(left, 100, "e.g. 12891")
    idBox:SetPoint("TOPLEFT", 156, y)
    idBox:SetNumeric(true)
    idBox:SetMaxLetters(9)
    idBox:SetScript("OnEnterPressed", idBox.ClearFocus)
    idBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput == false then return end
        s().soundID = tonumber(self:GetText()) or 0
    end)
    local idHint = U.Text(left, "GameFontDisableSmall")
    idHint:SetPoint("LEFT", idBox, "RIGHT", 10, 0)
    idHint:SetText("used when Sound is \"Custom sound ID\"")
    controls[#controls + 1] = function()
        if not idBox:HasFocus() then idBox:SetText((s().soundID or 0) > 0 and tostring(s().soundID) or "") end
        local custom = s().sound == "custom"
        idBox:SetAlpha(custom and 1 or 0.5)
        idHint:SetAlpha(custom and 1 or 0.5)
    end
    y = y - ROW
    Cycler(left, y, "Sound channel", T.CHANNELS, function() return s().channel end, function(v) s().channel = v end)
    y = y - ROW
    Cycler(left, y, "In combat", T.COMBAT, function() return s().combat end, function(v) s().combat = v end)
    y = y - ROW - 4
    Label(left, y - 4, "Position")
    local move = U.Button(left, "Move popup", 110, 22, function()
        if T.IsMoving() then T.StopMoving() else T.StartMoving() end
        AS.RefreshUI()
    end)
    move:SetPoint("TOPLEFT", 150, y)
    local reset = U.Button(left, "Reset", 70, 22, function() T.ResetPosition() end)
    reset:SetPoint("LEFT", move, "RIGHT", 6, 0)
    controls[#controls + 1] = function() move:SetText(T.IsMoving() and "Done" or "Move popup") end

    local preview = U.Button(left, "Preview popup", 150, 28, function() T.Preview() end)
    preview:SetPoint("TOPRIGHT", -14, -12)
    preview:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Preview popup", 1, 1, 1)
        GameTooltip:AddLine("Shows the popup for the next talent of the build you follow, with your current settings and sound. With Ask first on, it shows the Learn now? version (its buttons only close the preview).", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.preview = preview

    -- right: general ------------------------------------------------------------
    local right = U.Panel(page, 0.35)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    local rt = U.Text(right, "GameFontNormalLarge")
    rt:SetPoint("TOPLEFT", 14, -12)
    rt:SetText("General")
    local ry = -54
    Toggle(right, ry, "Learn on level up (this character)", "Learn the active build's next talent automatically when you ding.",
        function() return AS.char.enabled end, function(v) AS.char.enabled = v; if v then AS.state.paused = false end end)
    ry = ry - ROW + 4
    Toggle(right, ry, "Ask first (this character)", "Show a Learn prompt on a ding instead of learning right away.",
        function() return AS.char.mode == "ask" end, function(v) AS.char.mode = v and "ask" or "auto" end)
    ry = ry - ROW + 4
    Toggle(right, ry, "Auto-scan talent trees on open", "Read missing or outdated class trees every time the window opens.",
        function() return AS.db.autoScan ~= false end, function(v) AS.db.autoScan = v end)
    ry = ry - ROW + 4
    Toggle(right, ry, "Show minimap button", "The talent icon on the minimap.",
        function() return AS.MinimapButtonShown() end, function(v) AS.SetMinimapButtonShown(v) end)
    ry = ry - ROW + 4
    Toggle(right, ry, "Highlight next talent in the talent window", "Gold frame on the next talent in the game's talent window (N).",
        function() return AS.db.talentWindowHighlight ~= false end,
        function(v) AS.db.talentWindowHighlight = v; if AS.UpdateTalentWindow then AS.UpdateTalentWindow() end end)
    local note = U.Text(right, "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 16, ry - 40)
    note:SetPoint("RIGHT", -14, 0)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText("\"This character\" options are saved per character. Everything else is saved for all your characters.")

    page.Refresh = Refresh
    return page
end

function AS.RefreshSettings()
    if page and page:IsShown() then Refresh() end
end
