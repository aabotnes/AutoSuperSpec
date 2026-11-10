-- Auto Super Spec window: classes on the left, that class's builds on the right,
-- an import bar on top and the progress of the build you follow at the bottom.

local _, AS = ...
local T = AS.Talents

local W, H = 960, 600
local SIDEBAR_W = 178
local CARD_H, CARD_GAP, VISIBLE_CARDS = 52, 4, 5
local CLASS_ROW_H = 34

local ui
local selectedClass

------------------------------------------------------------------------------
-- Widget helpers
------------------------------------------------------------------------------

local function TemplateExists(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
        return ok and info ~= nil
    end
    return true
end

local function CreateWithTemplate(kind, name, parent, templates)
    for _, tpl in ipairs(templates) do
        if TemplateExists(tpl) then
            local ok, frame = pcall(CreateFrame, kind, name, parent, tpl)
            if ok and frame then return frame, tpl end
        end
    end
    return CreateFrame(kind, name, parent), nil
end

-- The templates' close button goes through the game's panel manager, which is
-- locked in combat. Hide the frame directly so it always closes.
local function FixCloseButton(frame)
    local close = frame.CloseButton or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if type(close) == "table" and close.SetScript then
        close:SetScript("OnClick", function() frame:Hide() end)
    end
end

local function Font(name, fallback)
    return _G[name] and name or fallback
end

local function Text(parent, font, layer)
    return parent:CreateFontString(nil, layer or "OVERLAY", font)
end

local function Panel(parent, alpha)
    local p = CreateFrame("Frame", nil, parent)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, alpha or 0.35)
    p.bg = bg
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, e in ipairs(edges) do
        local line = p:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, 0.07)
        line:SetPoint(e[1])
        line:SetPoint(e[2])
        if e[3] then line:SetWidth(e[3]) else line:SetHeight(e[4]) end
    end
    return p
end

local function Button(parent, text, width, height, onClick)
    local b, tpl = CreateWithTemplate("Button", nil, parent, { "UIPanelButtonTemplate", "UIPanelDynamicResizeButtonTemplate" })
    b:SetSize(width, height or 22)
    if not tpl then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.35, 0.05, 0.05, 0.9)
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
    end
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Check(parent, label, tooltip, onClick)
    local c, tpl = CreateWithTemplate("CheckButton", nil, parent, { "UICheckButtonTemplate", "ChatConfigCheckButtonTemplate" })
    c:SetSize(22, 22)
    if not tpl then
        c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    c.label = Text(c, "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.label:SetText(label)
    c:SetHitRectInsets(0, -c.label:GetStringWidth() - 4, 0, 0)
    c:SetScript("OnClick", onClick)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(label, 1, 1, 1)
        GameTooltip:AddLine(tooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local function Input(parent, width, placeholder)
    local eb, tpl = CreateWithTemplate("EditBox", nil, parent, { "InputBoxTemplate", "SearchBoxTemplate" })
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    if not tpl then
        eb:SetFontObject("ChatFontNormal")
        local bg = eb:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -4, 2)
        bg:SetPoint("BOTTOMRIGHT", 4, -2)
        bg:SetColorTexture(0, 0, 0, 0.6)
    end
    eb.placeholder = Text(eb, "GameFontDisable")
    eb.placeholder:SetPoint("LEFT", 2, 0)
    eb.placeholder:SetText(placeholder)
    local function update()
        eb.placeholder:SetShown(eb:GetText() == "" and not eb:HasFocus())
    end
    eb:HookScript("OnEditFocusGained", update)
    eb:HookScript("OnEditFocusLost", update)
    eb:HookScript("OnTextChanged", update)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

local function SetClassIcon(tex, class)
    tex:SetTexCoord(0, 1, 0, 1)
    local atlas = "classicon-" .. (class or ""):lower()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
    elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function SetIcon(tex, icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:SetTexture(icon)
end

AS.UI = {
    CreateWithTemplate = CreateWithTemplate, Text = Text, Panel = Panel, Button = Button,
    SetClassIcon = SetClassIcon, SetIcon = SetIcon, Font = Font, Input = Input,
}

------------------------------------------------------------------------------
-- Build menu (View / Share / Rename / Delete)
------------------------------------------------------------------------------

local function CreateMenu(parent)
    local m = Panel(parent, 0.95)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    m:Hide()
    m.rows = {}
    m:SetScript("OnUpdate", function(self)
        if IsMouseButtonDown and IsMouseButtonDown() and not self:IsMouseOver()
            and not (self.anchor and self.anchor:IsMouseOver()) then
            self:Hide()
        end
    end)
    local function Row(i)
        local row = m.rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, m)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 22)
        row:SetPoint("RIGHT", -5, 0)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.1)
        row.label = Text(row, "GameFontHighlight")
        row.label:SetPoint("LEFT", 8, 0)
        row:SetScript("OnClick", function(self)
            m:Hide()
            if self.func then self.func() end
        end)
        m.rows[i] = row
        return row
    end
    -- items: { { text = "...", func = fn } or { text = "...", title = true } }
    function m:Open(anchor, items, key)
        if self:IsShown() and key and self.key == key then self:Hide() return end
        self.key, self.anchor = key, anchor
        local width = 160
        for i, item in ipairs(items) do
            local row = Row(i)
            row.label:SetText(item.text)
            row.func = item.func
            if item.title then
                row.label:SetTextColor(1, 0.82, 0)
                row:EnableMouse(false)
            else
                row.label:SetTextColor(1, 1, 1)
                row:EnableMouse(true)
            end
            width = math.max(width, row.label:GetStringWidth() + 30)
            row:Show()
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide() end
        self:SetSize(width, #items * 22 + 10)
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
        self:Show()
    end
    return m
end

function AS.OpenMenu(anchor, items, key)
    if ui and ui.menu then ui.menu:Open(anchor, items, key) end
end

local function BuildMenuItems(b, anchor)
    return {
        { text = b.name, title = true },
        { text = "View / edit talents", func = function() AS.ShowBuild(b.id) end },
        { text = "Share...", func = function() ui.menu:Open(anchor, AS.ShareMenuItems(b), "share" .. b.id) end },
        { text = "Rename", func = function() StaticPopup_Show("AUTOSUPERSPEC_RENAME", nil, nil, b.id) end },
        { text = "|cffff5555Delete|r", func = function() StaticPopup_Show("AUTOSUPERSPEC_DELETE", b.name, nil, b.id) end },
    }
end

------------------------------------------------------------------------------
-- Class list
------------------------------------------------------------------------------

local function ClassList()
    local list, seen = {}, {}
    for _, c in ipairs(AS.CLASSES) do list[#list + 1] = c; seen[c] = true end
    local mine = AS.PlayerClass()
    if mine and not seen[mine] then list[#list + 1] = mine; seen[mine] = true end
    for _, b in pairs(AS.db.builds) do
        if not seen[b.class] then list[#list + 1] = b.class; seen[b.class] = true end
    end
    return list
end

local function CreateClassButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(CLASS_ROW_H)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 10, 0)
    b.name = Text(b, "GameFontHighlight")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.count = Text(b, "GameFontDisableSmall")
    b.count:SetPoint("RIGHT", -10, 0)
    b:SetScript("OnClick", function(self)
        selectedClass = self.class
        ui.offset = 0
        ui.menu:Hide()
        AS.RefreshUI()
    end)
    return b
end

------------------------------------------------------------------------------
-- Build cards
------------------------------------------------------------------------------

local function CardTooltip(card)
    local b = card.build
    if not b then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.name, 1, 1, 1)
    GameTooltip:AddLine(AS.ClassName(b.class) .. (b.points and (" - " .. b.points .. " points") or ""), AS.ClassRGB(b.class))
    if card.nextText then GameTooltip:AddLine(card.nextText, 0.4, 1, 0.4) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to view the talent tree and order", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift-click to put it in the chat message you're typing", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click for more options", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(CARD_H)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)
    c.bar = c:CreateTexture(nil, "ARTWORK")
    c.bar:SetPoint("TOPLEFT")
    c.bar:SetPoint("BOTTOMLEFT")
    c.bar:SetWidth(3)

    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(38, 38)
    c.icon:SetPoint("LEFT", 12, 0)

    c.name = Text(c, Font("GameFontHighlightMedium", "GameFontHighlight"))
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -2)
    c.name:SetJustifyH("LEFT")

    c.badge = Text(c, "GameFontNormalSmall")
    c.badge:SetPoint("LEFT", c.name, "RIGHT", 8, 0)

    c.detail = Text(c, "GameFontDisableSmall")
    c.detail:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 10, 3)
    c.detail:SetJustifyH("LEFT")

    c.more = Button(c, "...", 28, 24, function(self)
        if c.build then ui.menu:Open(self, BuildMenuItems(c.build, self), "build" .. c.build.id) end
    end)
    c.more:SetPoint("RIGHT", -10, 0)
    c.spec = Button(c, "Spec now", 84, 24, function() if c.build then AS.SpecNow(c.build.id) end end)
    c.spec:SetPoint("RIGHT", c.more, "LEFT", -4, 0)
    c.toggle = Button(c, "Activate", 96, 24, function()
        local b = c.build
        if not b then return end
        if AS.char.active == b.id then AS.SetActive(nil) else AS.SetActive(b.id) end
    end)
    c.toggle:SetPoint("RIGHT", c.spec, "LEFT", -4, 0)
    c.name:SetWordWrap(false)
    c.detail:SetPoint("RIGHT", c.toggle, "LEFT", -10, 0)

    for _, btn in ipairs({ c.toggle, c.spec }) do
        btn:SetMotionScriptsWhileDisabled(true)
        btn:SetScript("OnEnter", function(self)
            if self:IsEnabled() then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Log in a " .. AS.ClassName(c.build and c.build.class) .. " to use this build.", 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    c:SetScript("OnClick", function(self, button)
        if not self.build then return end
        if button == "RightButton" then
            ui.menu:Open(self.more, BuildMenuItems(self.build, self.more), "build" .. self.build.id)
        elseif IsShiftKeyDown() then
            AS.LinkToChat(self.build)
        else
            AS.ShowBuild(self.build.id)
        end
    end)
    c:SetScript("OnEnter", CardTooltip)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

-- index of the tree with the most points in "a/b/c"
local function MainTree(build)
    local best, bestN = 1, -1
    local i = 0
    for n in (build.trees or ""):gmatch("%d+") do
        i = i + 1
        if tonumber(n) > bestN then best, bestN = i, tonumber(n) end
    end
    return best
end

local function UpdateCard(c, b, own, layout, meta)
    c.build = b
    local active = AS.char.active == b.id
    local cr, cg, cb = AS.ClassRGB(b.class)

    if meta and meta.icons and meta.icons[MainTree(b)] then
        SetIcon(c.icon, meta.icons[MainTree(b)])
    else
        SetClassIcon(c.icon, b.class)
    end
    c.name:SetWidth(0)
    c.name:SetText(b.name)
    if c.name:GetStringWidth() > 210 then c.name:SetWidth(210) end
    local pts = b.points and ("   |cffaaaaaa" .. b.points .. " points|r") or ""
    c.detail:SetText(AS.TreeText(b, meta and meta.names) .. pts)

    c.nextText = nil
    if active and own then
        local progress = AS.Progress(b, layout, meta)
        if progress then
            if progress.next then
                c.badge:SetText(("|cff33ff33ACTIVE|r  |cffaaaaaa%d/%d learned|r"):format(progress.done, progress.total))
                c.nextText = ("Next: %s %d/%d"):format(progress.next.t.name, progress.next.rank, progress.next.t.maxRank)
            else
                c.badge:SetText("|cff33ff33ACTIVE|r  |cffaaaaaacomplete|r")
            end
        else
            c.badge:SetText("|cff33ff33ACTIVE|r")
        end
        c.bg:SetColorTexture(0.1, 0.22, 0.1, 0.85)
        c.bar:SetColorTexture(0.2, 1, 0.2, 1)
    else
        c.badge:SetText("")
        c.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        c.bar:SetColorTexture(cr, cg, cb, 0.8)
    end

    c.toggle:SetText(active and "Deactivate" or "Activate")
    c.toggle:SetEnabled(own)
    c.spec:SetEnabled(own)
    c:Show()
end

------------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------------

local function DoImport()
    local link, name = ui.link:GetText(), ui.buildName:GetText()
    local b, err = AS.Import(link, name)
    if not b then
        AS.Print("|cffff4444import failed|r - " .. err)
        ui.importError:SetText(err)
        return
    end
    ui.importError:SetText("")
    ui.link:SetText("")
    ui.buildName:SetText("")
    ui.link:ClearFocus()
    ui.buildName:ClearFocus()
    selectedClass = b.class
    ui.offset = 0
    if b.class == AS.PlayerClass() and not AS.ActiveBuild() then
        AS.SetActive(b.id)
    end
    AS.RefreshUI()
end

local function CreateUI()
    local tpl
    ui, tpl = CreateWithTemplate("Frame", "AutoSuperSpecFrame", UIParent,
        { "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset" })
    ui:SetSize(W, H)
    ui:SetPoint("CENTER")
    FixCloseButton(ui)
    ui:SetFrameStrata("HIGH")
    ui:SetToplevel(true)
    ui:SetMovable(true)
    ui:SetClampedToScreen(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui:Hide()
    tinsert(UISpecialFrames, "AutoSuperSpecFrame")
    ui.offset = 0

    local top = -30
    if tpl == "PortraitFrameTemplate" or tpl == "ButtonFrameTemplate" then
        top = -64
        if ui.SetTitle then ui:SetTitle(AS.TITLE) end
        if ui.SetPortraitToClassIcon then
            pcall(ui.SetPortraitToClassIcon, ui, AS.PlayerClass())
        elseif ui.SetPortraitToAsset then
            pcall(ui.SetPortraitToAsset, ui, "Interface\\Icons\\Ability_Marksmanship")
        end
        if ui.Inset then ui.Inset:Hide() end
    else
        local title = Text(ui, "GameFontHighlight")
        title:SetPoint("TOP", 0, -6)
        title:SetText(AS.TITLE)
    end
    if not tpl then
        local bg = ui:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
    end

    local tagline = Text(ui, "GameFontNormalSmall")
    tagline:SetPoint("TOPLEFT", 70, -34)
    tagline:SetText("Talent builds that learn themselves as you level")
    if top > -60 then tagline:Hide() end

    ui.menu = CreateMenu(ui)
    ui:HookScript("OnHide", function() ui.menu:Hide() end)

    -- pages: the build list, and the talent calculator (Calculator.lua)
    ui.listPage = CreateFrame("Frame", nil, ui)
    ui.listPage:SetAllPoints()
    ui.calcPage = AS.CreateCalculator(ui, top)
    ui.calcPage:Hide()
    ui.page = "list"

    -- sidebar ---------------------------------------------------------------
    local side = Panel(ui.listPage, 0.4)
    side:SetPoint("TOPLEFT", 10, top)
    side:SetPoint("BOTTOMLEFT", 10, 10)
    side:SetWidth(SIDEBAR_W)
    local sideTitle = Text(side, "GameFontNormal")
    sideTitle:SetPoint("TOPLEFT", 12, -12)
    sideTitle:SetText("Classes")
    ui.classButtons = {}
    for i = 1, 12 do
        local b = CreateClassButton(side)
        b:SetPoint("TOPLEFT", 1, -34 - (i - 1) * CLASS_ROW_H)
        b:SetPoint("RIGHT", -1, 0)
        ui.classButtons[i] = b
    end

    -- talent tree scan box (bottom of the class list)
    local scan = Panel(side, 0.5)
    scan:SetPoint("BOTTOMLEFT", 6, 6)
    scan:SetPoint("BOTTOMRIGHT", -6, 6)
    scan:SetHeight(164)
    scan.title = Text(scan, "GameFontNormal")
    scan.title:SetPoint("TOPLEFT", 8, -8)
    scan.title:SetPoint("RIGHT", -8, 0)
    scan.title:SetJustifyH("LEFT")
    scan.text = Text(scan, "GameFontHighlightSmall")
    scan.text:SetPoint("TOPLEFT", scan.title, "BOTTOMLEFT", 0, -4)
    scan.text:SetPoint("RIGHT", -8, 0)
    scan.text:SetJustifyH("LEFT")
    scan.text:SetWordWrap(true)
    scan.button = Button(scan, "Scan talent trees", SIDEBAR_W - 28, 26, function() AS.ScanTrees() end)
    scan.button:SetPoint("BOTTOM", 0, 8)
    scan.auto = Check(scan, "Auto-scan when opened",
        "Every time you open this window, read the talent trees of classes that are missing or were saved on an older game version.",
        function(self) AS.db.autoScan = self:GetChecked() and true or false end)
    scan.auto:SetPoint("BOTTOMLEFT", 6, 38)
    scan.last = Text(scan, "GameFontDisableSmall")
    scan.last:SetPoint("BOTTOMLEFT", 10, 64)
    scan.last:SetPoint("RIGHT", -8, 0)
    scan.last:SetJustifyH("LEFT")
    scan.button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Scan talent trees", 1, 1, 1)
        GameTooltip:AddLine("Reads every class's talent tree from the game again and saves it for all your characters. "
            .. "Classes the game won't show from here are saved when you log in one of them.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    scan.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.scanBox = scan

    -- right side ------------------------------------------------------------
    local main = CreateFrame("Frame", nil, ui.listPage)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", -10, 10)
    ui.main = main

    ui.headerIcon = main:CreateTexture(nil, "ARTWORK")
    ui.headerIcon:SetSize(34, 34)
    ui.headerIcon:SetPoint("TOPLEFT", 4, -2)
    ui.headerTitle = Text(main, "GameFontHighlightLarge")
    ui.headerTitle:SetPoint("TOPLEFT", ui.headerIcon, "TOPRIGHT", 10, -1)
    ui.headerSub = Text(main, "GameFontDisableSmall")
    ui.headerSub:SetPoint("BOTTOMLEFT", ui.headerIcon, "BOTTOMRIGHT", 10, 2)
    ui.newBuild = Button(main, "New build", 100, 24, function() AS.NewBuild(selectedClass) end)
    ui.newBuild:SetPoint("TOPRIGHT", 0, -6)
    ui.newBuild:SetMotionScriptsWhileDisabled(true)
    ui.newBuild:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("New build", 1, 1, 1)
        GameTooltip:AddLine(self:IsEnabled() and "Make a build from scratch in the talent calculator."
            or ("Log in a %s once to save its talent tree, then you can make builds for it on any character."):format(AS.ClassName(selectedClass)), nil, nil, nil, true)
        GameTooltip:Show()
    end)
    ui.newBuild:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- import bar
    local imp = Panel(main, 0.35)
    imp:SetPoint("TOPLEFT", 0, -44)
    imp:SetPoint("TOPRIGHT", 0, -44)
    imp:SetHeight(96)
    local impTitle = Text(imp, "GameFontNormal")
    impTitle:SetPoint("TOPLEFT", 12, -10)
    impTitle:SetText("Import a build")
    local impHint = Text(imp, "GameFontDisableSmall")
    impHint:SetPoint("LEFT", impTitle, "RIGHT", 10, 0)
    impHint:SetText("On Wowhead's talent calculator, open \"Talent Order\", then copy the link.")
    ui.link = Input(imp, 100, "Paste Wowhead link or Auto Super Spec build")
    ui.link:SetPoint("LEFT", imp, "TOPLEFT", 18, -44)
    ui.link:SetPoint("RIGHT", imp, "TOPRIGHT", -14, -44)
    ui.link:SetMaxLetters(0)
    ui.buildName = Input(imp, 240, "Build name")
    ui.buildName:SetPoint("LEFT", imp, "TOPLEFT", 18, -74)
    ui.buildName:SetMaxLetters(AS.MAX_NAME)
    local importBtn = Button(imp, "Import", 90, 24, DoImport)
    importBtn:SetPoint("LEFT", ui.buildName, "RIGHT", 12, 0)
    ui.link:SetScript("OnEnterPressed", function() ui.buildName:SetFocus() end)
    ui.link:SetScript("OnTabPressed", function() ui.buildName:SetFocus() end)
    ui.buildName:SetScript("OnEnterPressed", DoImport)
    ui.buildName:SetScript("OnTabPressed", function() ui.link:SetFocus() end)
    ui.importError = Text(imp, "GameFontRedSmall")
    ui.importError:SetPoint("LEFT", importBtn, "RIGHT", 12, 0)
    ui.importError:SetPoint("RIGHT", -12, 0)
    ui.importError:SetWordWrap(true)
    ui.importError:SetJustifyH("LEFT")

    -- footer: the build you follow
    local foot = Panel(main, 0.35)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(70)
    ui.footTitle = Text(foot, "GameFontNormal")
    ui.footTitle:SetPoint("TOPLEFT", 12, -10)
    ui.bar = CreateFrame("StatusBar", nil, foot)
    ui.bar:SetSize(250, 14)
    ui.bar:SetPoint("TOPLEFT", 12, -30)
    ui.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ui.bar:SetStatusBarColor(0.2, 0.8, 0.2)
    ui.bar:SetMinMaxValues(0, 1)
    local barBg = ui.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.6)
    ui.barText = Text(ui.bar, "GameFontHighlightSmall")
    ui.barText:SetPoint("CENTER")
    ui.nextIcon = foot:CreateTexture(nil, "ARTWORK")
    ui.nextIcon:SetSize(16, 16)
    ui.nextIcon:SetPoint("TOPLEFT", 12, -49)
    ui.nextText = Text(foot, "GameFontHighlightSmall")
    ui.nextText:SetPoint("LEFT", ui.nextIcon, "RIGHT", 6, 0)
    ui.resume = Button(foot, "Resume", 80, 22, function()
        AS.state.paused = false
        AS.TryLearn(true)
        AS.RefreshUI()
    end)
    ui.resume:SetPoint("LEFT", ui.bar, "RIGHT", 12, 0)

    ui.autoCheck = Check(foot, "Learn on level up", "Learn the next talents of the active build automatically when you ding.", function(self)
        AS.char.enabled = self:GetChecked() and true or false
        if AS.char.enabled then AS.state.paused = false; AS.TryLearn() end
        AS.RefreshUI()
    end)
    ui.autoCheck:SetPoint("TOPRIGHT", -130, -12)
    ui.askCheck = Check(foot, "Ask first", "Show a popup with a Learn button instead of learning right away.", function(self)
        AS.char.mode = self:GetChecked() and "ask" or "auto"
    end)
    ui.askCheck:SetPoint("TOPLEFT", ui.autoCheck, "BOTTOMLEFT", 0, -2)

    -- build list
    local list = CreateFrame("Frame", nil, main)
    list:SetPoint("TOPLEFT", imp, "BOTTOMLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 10)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        ui.offset = math.max(0, ui.offset - delta)
        ui.menu:Hide()
        AS.RefreshUI()
    end)
    ui.list = list
    ui.cards = {}
    for i = 1, VISIBLE_CARDS do
        local c = CreateCard(list)
        c:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP))
        c:SetPoint("RIGHT", -10, 0)
        ui.cards[i] = c
    end
    ui.track = list:CreateTexture(nil, "BACKGROUND")
    ui.track:SetPoint("TOPRIGHT", 0, 0)
    ui.track:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.track:SetWidth(4)
    ui.track:SetColorTexture(1, 1, 1, 0.05)
    ui.thumb = list:CreateTexture(nil, "ARTWORK")
    ui.thumb:SetWidth(4)
    ui.thumb:SetColorTexture(1, 0.82, 0, 0.6)

    ui.empty = Text(list, "GameFontDisable")
    ui.empty:SetPoint("CENTER", 0, 10)
    ui.empty:SetJustifyH("CENTER")
end

------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------

function AS.RefreshUI()
    if AS.RefreshMinimap then AS.RefreshMinimap() end
    if not ui or not ui:IsShown() then return end
    if ui.page == "calc" then
        AS.RefreshCalculator()
        return
    end
    local myClass = AS.PlayerClass()
    selectedClass = selectedClass or myClass
    local own = selectedClass == myClass

    local layout, meta = T.Layout(selectedClass)
    if not layout then meta = nil end

    -- classes
    local classes = ClassList()
    for i, b in ipairs(ui.classButtons) do
        local class = classes[i]
        b.class = class
        if class then
            SetClassIcon(b.icon, class)
            local r, g, bl = AS.ClassRGB(class)
            b.name:SetText(AS.ClassName(class) .. (class == myClass and " |cff888888(you)|r" or ""))
            b.name:SetTextColor(r, g, bl)
            local n = AS.CountForClass(class)
            b.count:SetText(n > 0 and n or "")
            local hasTree = T.HasData(class)
            b.icon:SetDesaturated(not hasTree)
            b.icon:SetAlpha(hasTree and 1 or 0.5)
            b.name:SetAlpha(hasTree and 1 or 0.6)
            local sel = class == selectedClass
            b.sel:SetColorTexture(r, g, bl, sel and 0.18 or 0)
            b.bar:SetColorTexture(r, g, bl, sel and 1 or 0)
            b:Show()
        else
            b:Hide()
        end
    end

    -- talent tree scan box
    local missing = AS.MissingTrees()
    local total = #AS.CLASSES
    local sb = ui.scanBox
    if #missing > 0 then
        sb.bg:SetColorTexture(0.45, 0.28, 0.02, 0.55)
        sb.title:SetText(("|cffffd100Talent trees: %d / %d|r"):format(total - #missing, total))
        local names = {}
        for _, c in ipairs(missing) do names[#names + 1] = AS.ClassName(c) end
        sb.text:SetText("Missing: " .. table.concat(names, ", "))
        sb.button:SetText("Scan talent trees")
    else
        sb.bg:SetColorTexture(0, 0, 0, 0.35)
        sb.title:SetText(("|cff33ff33Talent trees: %d / %d|r"):format(total, total))
        sb.text:SetText("All classes saved.")
        sb.button:SetText("Rescan")
    end
    local ls = AS.db.lastScan
    sb.last:SetText(ls and ("Last scan: %s\nGame %s (%s)"):format(date("%Y-%m-%d %H:%M", ls.time), tostring(ls.version), tostring(ls.build))
        or "Not scanned yet")
    sb.auto:SetChecked(AS.db.autoScan ~= false)

    -- header
    SetClassIcon(ui.headerIcon, selectedClass)
    ui.headerTitle:SetText(AS.ClassName(selectedClass) .. " builds")
    ui.headerTitle:SetTextColor(AS.ClassRGB(selectedClass))
    ui.newBuild:SetEnabled(layout ~= nil)
    local cname = AS.ClassName(selectedClass)
    if own then
        ui.headerSub:SetText("Shared by all your characters, activated per character.  Shift-click a build to link it in chat.")
    elseif layout then
        ui.headerSub:SetText(("View, edit and share %s builds here. Log in a %s to learn them."):format(cname, cname))
    else
        ui.headerSub:SetText(("Log in a %s once to save its talent tree. You can still import and share builds."):format(cname))
    end

    -- cards
    local builds = AS.BuildsForClass(selectedClass)
    local maxOffset = math.max(0, #builds - VISIBLE_CARDS)
    if ui.offset > maxOffset then ui.offset = maxOffset end
    for i, c in ipairs(ui.cards) do
        local b = builds[i + ui.offset]
        if b then UpdateCard(c, b, own, layout, meta) else c.build = nil; c:Hide() end
    end
    if maxOffset > 0 then
        local trackH = ui.list:GetHeight()
        local thumbH = math.max(20, trackH * VISIBLE_CARDS / #builds)
        ui.thumb:SetHeight(thumbH)
        ui.thumb:ClearAllPoints()
        ui.thumb:SetPoint("TOPRIGHT", 0, -(trackH - thumbH) * ui.offset / maxOffset)
        ui.thumb:Show()
        ui.track:Show()
    else
        ui.thumb:Hide()
        ui.track:Hide()
    end
    ui.empty:SetText(("No %s builds yet.\nPaste a Wowhead talent calculator link above to add one."):format(AS.ClassName(selectedClass)))
    ui.empty:SetShown(#builds == 0)

    -- footer
    local active = AS.ActiveBuild()
    local progress, err
    if active and active.class == myClass then
        progress, err = AS.Progress(active, layout, meta)
    end
    ui.resume:SetShown(AS.state.paused and active ~= nil)
    if not active then
        ui.footTitle:SetText("Not following a build")
        ui.bar:SetValue(0)
        ui.barText:SetText("")
        ui.nextIcon:Hide()
        ui.nextText:SetText("Click |cffffd100Activate|r on one of your builds to start.")
    elseif not progress then
        ui.footTitle:SetText("Following: |cffffffff" .. active.name .. "|r")
        ui.bar:SetValue(0)
        ui.barText:SetText("")
        ui.nextIcon:Hide()
        ui.nextText:SetText("|cffff5555" .. tostring(err) .. "|r")
    else
        ui.footTitle:SetText("Following: |cffffffff" .. active.name .. "|r")
        ui.bar:SetMinMaxValues(0, math.max(1, progress.total))
        ui.bar:SetValue(progress.done)
        ui.barText:SetText(("%d / %d points"):format(progress.done, progress.total))
        if progress.next then
            local t = progress.next.t
            if t.icon then SetIcon(ui.nextIcon, t.icon); ui.nextIcon:Show() else ui.nextIcon:Hide() end
            local note = AS.state.paused and "  |cffff5555(paused)|r" or (AS.char.enabled and "" or "  |cff888888(learning on level up is off)|r")
            ui.nextText:SetText(("Next: |cffffd100%s|r %d/%d%s"):format(t.name, progress.next.rank, t.maxRank, note))
        else
            ui.nextIcon:Hide()
            ui.nextText:SetText("|cff33ff33Build complete.|r")
        end
    end
    ui.autoCheck:SetChecked(AS.char.enabled)
    ui.askCheck:SetChecked(AS.char.mode == "ask")
end

-- Switches the window between the build list and the talent calculator.
local function FitToScreen()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not sw or not sh or sw <= 0 or sh <= 0 then return end
    ui:SetScale(math.min(1, (sw - 20) / W, (sh - 20) / H))
end

function AS.ShowPage(page)
    if not ui then CreateUI() end
    if not ui:IsShown() then AS.AutoScan() end -- the window is opening
    FitToScreen()
    ui.page = page
    ui.listPage:SetShown(page == "list")
    ui.calcPage:SetShown(page == "calc")
    ui.menu:Hide()
    ui:Show()
    AS.RefreshUI()
end

function AS.GetSelectedClass() return selectedClass end

function AS.ShowUI(class)
    if not ui then CreateUI() end
    if class then selectedClass = class; ui.offset = 0 end
    AS.ShowPage("list")
end

function AS.ToggleUI()
    if ui and ui:IsShown() then ui:Hide() else
        if not ui then CreateUI() end
        AS.ShowPage(ui.page or "list")
    end
end

------------------------------------------------------------------------------
-- Copy window (for /ass debug)
------------------------------------------------------------------------------

local copy
function AS.ShowCopyWindow(title, text)
    if not copy then
        copy = CreateWithTemplate("Frame", "AutoSuperSpecCopyFrame", UIParent, { "BasicFrameTemplateWithInset", "ButtonFrameTemplate" })
        copy:SetSize(620, 420)
        FixCloseButton(copy)
        copy:SetPoint("CENTER")
        copy:SetFrameStrata("DIALOG")
        copy:SetMovable(true)
        copy:EnableMouse(true)
        copy:RegisterForDrag("LeftButton")
        copy:SetScript("OnDragStart", copy.StartMoving)
        copy:SetScript("OnDragStop", copy.StopMovingOrSizing)
        tinsert(UISpecialFrames, "AutoSuperSpecCopyFrame")
        copy.title = Text(copy, "GameFontHighlight")
        copy.title:SetPoint("TOP", 0, -6)
        local scroll = CreateWithTemplate("ScrollFrame", "AutoSuperSpecCopyScroll", copy, { "UIPanelScrollFrameTemplate", "ScrollFrameTemplate" })
        scroll:SetPoint("TOPLEFT", 14, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(560)
        eb:SetScript("OnEscapePressed", function() copy:Hide() end)
        scroll:SetScrollChild(eb)
        copy.edit = eb
    end
    copy.title:SetText(title)
    copy.edit:SetText(text)
    copy:Show()
    copy.edit:SetFocus()
    copy.edit:HighlightText()
end
