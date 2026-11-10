-- Talent calculator page: shows a build on the real talent trees, with the
-- game's talent descriptions, and lets you add/remove points, save the build
-- or make a new one. The order you click points in is the learning order.

local _, AS = ...
local T = AS.Talents
local U -- UI helpers from UI.lua

local TREE_W, TREE_GAP = 214, 8
local CELL, ICON = 48, 36
local ORDER_W, ROW_H = 262, 22
local FIRST_LEVEL = 10

local calc -- the page frame and its state

------------------------------------------------------------------------------
-- Draft state
------------------------------------------------------------------------------

-- Resolves the draft (talent keys) against the current talent data.
local function Current()
    local layout, meta = T.Layout(calc.class)
    if not layout then return nil end
    local byKey = {}
    for _, tree in ipairs(layout) do
        for _, t in ipairs(tree) do byKey[t.key] = t end
    end
    local steps, counts, treePts = {}, {}, {}
    for _, key in ipairs(calc.keys or {}) do
        local t = byKey[key]
        if t then
            steps[#steps + 1] = t
            counts[key] = (counts[key] or 0) + 1
            treePts[t.tree] = (treePts[t.tree] or 0) + 1
        end
    end
    return { layout = layout, meta = meta, steps = steps, counts = counts, treePts = treePts }
end

local function TreeName(meta, i)
    return meta and meta.names and meta.names[i] or ("tree " .. i)
end

-- Can one more point go into t? Returns ok, reason.
local function CanAdd(t, cur)
    if (cur.counts[t.key] or 0) >= t.maxRank then return false end
    if #cur.steps >= AS.MaxPoints() then return false, "You have no talent points left." end
    local need = (t.tier - 1) * 5
    if (cur.treePts[t.tree] or 0) < need then
        return false, ("Requires %d points in %s"):format(need, TreeName(cur.meta, t.tree)), true
    end
    for _, pre in ipairs(t.requires or {}) do
        if (cur.counts[pre.key] or 0) < pre.maxRank then
            return false, ("Requires %d point%s in %s"):format(pre.maxRank, pre.maxRank == 1 and "" or "s", pre.name), true
        end
    end
    return true
end

local function IsDirty()
    if not calc.editable then return false end
    local code = AS.EncodeSteps(Current() and Current().steps or {})
    return code ~= (calc.savedCode or "") or AS.CleanName(calc.nameBox:GetText()) ~= (calc.savedName or "")
end

local function SetMessage(text, good)
    calc.message:SetText(text or "")
    if good then calc.message:SetTextColor(0.3, 1, 0.3) else calc.message:SetTextColor(1, 0.35, 0.35) end
end

local function Load(build, class)
    calc.buildId = build and build.id or nil
    calc.class = build and build.class or class
    calc.editable = T.Layout(calc.class) ~= nil
    calc.keys = {}
    calc.offset = 0
    calc.savedName = build and build.name or ("New " .. AS.ClassName(calc.class) .. " build")
    calc.savedCode = ""
    if build and calc.editable then
        local layout = T.Layout(calc.class)
        local steps = AS.ResolveSteps(build.code, layout)
        if steps then
            for i, t in ipairs(steps) do calc.keys[i] = t.key end
            calc.savedCode = AS.EncodeSteps(steps)
        else
            calc.editable = false
        end
    end
    calc.nameBox:SetText(calc.savedName)
    calc.nameBox:SetCursorPosition(0)
    SetMessage("")
end

------------------------------------------------------------------------------
-- Editing
------------------------------------------------------------------------------

local function AddPoint(t)
    if not calc.editable then return end
    local cur = Current()
    local ok, why = CanAdd(t, cur)
    if not ok then
        if why then SetMessage(why) end
        return
    end
    table.insert(calc.keys, t.key)
    SetMessage("")
    calc.offset = math.max(0, #calc.keys - calc.order.visible)
    AS.RefreshCalculator()
end

-- Removes the point at index (default: the talent's last point), if the rest
-- of the order still follows the talent rules.
local function RemovePoint(key, index)
    if not calc.editable then return end
    if not index then
        for i = #calc.keys, 1, -1 do
            if calc.keys[i] == key then index = i; break end
        end
    end
    if not index then return end
    local cur = Current()
    local before = #AS.Validate(cur.steps)
    local trial = {}
    for i, k in ipairs(calc.keys) do if i ~= index then trial[#trial + 1] = k end end
    local saved = calc.keys
    calc.keys = trial
    local problems = AS.Validate(Current().steps)
    if #problems > 0 and before == 0 then
        calc.keys = saved
        SetMessage("Can't remove that point: " .. problems[1]:gsub("^Point %d+: ", ""))
        AS.RefreshCalculator()
        return
    end
    SetMessage("")
    AS.RefreshCalculator()
end

local function ClearTree(tree)
    if not calc.editable then return end
    local cur = Current()
    local keep = {}
    for i, t in ipairs(cur.steps) do
        if t.tree ~= tree then keep[#keep + 1] = calc.keys[i] end
    end
    calc.keys = keep
    SetMessage("")
    AS.RefreshCalculator()
end

local function Save(asNew)
    local cur = Current()
    if not cur or #cur.steps == 0 then SetMessage("Add some talent points first.") return end
    local code = AS.EncodeSteps(cur.steps)
    local name = AS.CleanName(calc.nameBox:GetText())
    if name == "" then name = calc.savedName end
    local b, existed
    if calc.buildId and not asNew then
        b = AS.UpdateBuild(calc.buildId, name, code)
    else
        if asNew and name == calc.savedName then name = AS.CleanName(name .. " (copy)") end
        b, existed = AS.AddBuild(calc.class, name, code, true)
    end
    if existed then
        SetMessage(("This build is already saved as \"%s\"."):format(b.name))
        return
    end
    calc.buildId, calc.savedCode, calc.savedName = b.id, code, b.name
    calc.nameBox:SetText(b.name)
    SetMessage("Saved.", true)
    AS.RefreshCalculator()
end

local function Revert()
    local b = calc.buildId and AS.GetBuild(calc.buildId)
    Load(b, calc.class)
    AS.RefreshCalculator()
end

StaticPopupDialogs["AUTOSUPERSPEC_DISCARD"] = {
    text = "You have unsaved changes to |cffffd100%s|r.\nDiscard them?",
    button1 = "Discard",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, fn) (fn or self.data)() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Runs fn, after asking first if the calculator has unsaved changes.
function AS.ConfirmDiscard(fn)
    if calc and calc:IsShown() and IsDirty() then
        StaticPopup_Show("AUTOSUPERSPEC_DISCARD", AS.CleanName(calc.nameBox:GetText()), nil, fn)
    else
        fn()
    end
end

------------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------------

local function TalentTooltip(btn)
    local t = btn.talent
    if not t then return end
    local cur = Current()
    local rank = cur and cur.counts[t.key] or 0
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(t.name, 1, 1, 1)
    GameTooltip:AddLine(("Rank %d/%d"):format(rank, t.maxRank), 1, 1, 1)
    if cur and rank < t.maxRank then
        local ok, why = CanAdd(t, cur)
        if not ok and why then GameTooltip:AddLine(why, 1, 0.1, 0.1, true) end
    end
    local desc = T.Description(t, math.max(1, rank))
    if desc then GameTooltip:AddLine(desc, 1, 0.82, 0, true) end
    if rank > 0 and rank < t.maxRank then
        local nextDesc = T.Description(t, rank + 1)
        if nextDesc then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Next rank:", 1, 1, 1)
            GameTooltip:AddLine(nextDesc, 1, 0.82, 0, true)
        end
    end
    if cur and rank > 0 then
        local levels = {}
        for i, s in ipairs(cur.steps) do
            if s.key == t.key then levels[#levels + 1] = FIRST_LEVEL + i - 1 end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Learned at level " .. table.concat(levels, ", "), 0.5, 0.8, 1, true)
    end
    if calc.editable then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: add a point   Right-click: remove a point", 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
    calc.hoverKey = t.key
    AS.RefreshCalculatorHighlight()
end

------------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------------

local function CreateTalentButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetPoint("TOPLEFT", -4, 4)
    b.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    b.glow:SetColorTexture(1, 1, 1, 0.25)
    b.glow:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.rankBg = b:CreateTexture(nil, "OVERLAY")
    b.rankBg:SetColorTexture(0, 0, 0, 0.85)
    b.rankBg:SetPoint("BOTTOMRIGHT", 5, -5)
    b.rankBg:SetSize(26, 13)
    b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.rank:SetPoint("CENTER", b.rankBg, "CENTER", 0, 0)
    b.step = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.step:SetPoint("TOPLEFT", -4, 5)
    b:SetScript("OnClick", function(self, button)
        if not self.talent then return end
        if button == "RightButton" then RemovePoint(self.talent.key) else AddPoint(self.talent) end
        if GameTooltip:IsOwned(self) then TalentTooltip(self) end
    end)
    b:SetScript("OnEnter", TalentTooltip)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        calc.hoverKey = nil
        AS.RefreshCalculatorHighlight()
    end)
    return b
end

local function CreateOrderRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("RightButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.level:SetPoint("LEFT", 6, 0)
    r.level:SetWidth(42)
    r.level:SetJustifyH("LEFT")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 50, 0)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self) if self.key then RemovePoint(self.key, self.index) end end)
    r:SetScript("OnEnter", function(self)
        calc.hoverKey = self.key
        AS.RefreshCalculatorHighlight()
        if self.key and calc.editable then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Right-click to remove this point", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function()
        GameTooltip:Hide()
        calc.hoverKey = nil
        AS.RefreshCalculatorHighlight()
    end)
    return r
end

local function GuardedButton(parent, text, width, onClick, why)
    local b = U.Button(parent, text, width, 22, onClick)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then return end
        local reason = why()
        if not reason then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(reason, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

------------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------------

function AS.CreateCalculator(parent, top)
    U = AS.UI
    calc = CreateFrame("Frame", nil, parent)
    calc:SetPoint("TOPLEFT", 10, top)
    calc:SetPoint("BOTTOMRIGHT", -10, 10)
    calc.keys, calc.offset = {}, 0

    -- header
    calc.back = U.Button(calc, "< Back", 80, 24, function()
        AS.ConfirmDiscard(function() AS.ShowUI(calc.class) end)
    end)
    calc.back:SetPoint("TOPLEFT", 0, 0)
    calc.classIcon = calc:CreateTexture(nil, "ARTWORK")
    calc.classIcon:SetSize(24, 24)
    calc.classIcon:SetPoint("LEFT", calc.back, "RIGHT", 12, 0)
    local eb = U.Input(calc, 220, "Build name")
    eb:SetMaxLetters(AS.MAX_NAME)
    eb:SetPoint("LEFT", calc.classIcon, "RIGHT", 10, 0)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:HookScript("OnTextChanged", function() if calc.ready then AS.RefreshCalculatorButtons() end end)
    calc.nameBox = eb
    calc.summary = U.Text(calc, "GameFontHighlight")
    calc.summary:SetPoint("LEFT", eb, "RIGHT", 14, 0)

    calc.revert = GuardedButton(calc, "Revert", 70, Revert, function() return "No unsaved changes." end)
    calc.revert:SetPoint("TOPRIGHT", 0, -1)
    calc.saveNew = GuardedButton(calc, "Save as new", 100, function() Save(true) end, function()
        return not calc.editable and ("Log in a %s to edit this build."):format(AS.ClassName(calc.class)) or nil
    end)
    calc.saveNew:SetPoint("RIGHT", calc.revert, "LEFT", -4, 0)
    calc.save = GuardedButton(calc, "Save", 70, function() Save(false) end, function()
        return not calc.editable and ("Log in a %s to edit this build."):format(AS.ClassName(calc.class)) or "No unsaved changes."
    end)
    calc.save:SetPoint("RIGHT", calc.saveNew, "LEFT", -4, 0)

    calc.message = U.Text(calc, "GameFontNormalSmall")
    calc.message:SetPoint("TOPLEFT", 0, -32)
    calc.hint = U.Text(calc, "GameFontDisableSmall")
    calc.hint:SetPoint("TOPRIGHT", 0, -32)

    local bodyTop = -50

    -- trees
    calc.trees = {}
    for i = 1, 3 do
        local p = U.Panel(calc, 0.45)
        p:SetPoint("TOPLEFT", (i - 1) * (TREE_W + TREE_GAP), bodyTop)
        p:SetPoint("BOTTOM", 0, 0)
        p:SetWidth(TREE_W)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetSize(18, 18)
        p.icon:SetPoint("TOPLEFT", 8, -7)
        p.title = U.Text(p, "GameFontNormal")
        p.title:SetPoint("LEFT", p.icon, "RIGHT", 6, 0)
        p.clear = U.Button(p, "Clear", 48, 18, function() ClearTree(i) end)
        p.clear:SetPoint("TOPRIGHT", -6, -6)
        p.points = U.Text(p, "GameFontHighlight")
        p.points:SetPoint("RIGHT", p.clear, "LEFT", -8, 0)
        p.grid = CreateFrame("Frame", nil, p)
        p.grid:SetPoint("TOPLEFT", 8, -34)
        p.grid:SetPoint("BOTTOMRIGHT", -8, 8)
        p.buttons, p.lines = {}, {}
        calc.trees[i] = p
    end
    calc.noData = U.Text(calc, "GameFontDisable")
    calc.noData:SetPoint("CENTER", calc.trees[2], "CENTER")
    calc.noData:SetWidth(3 * TREE_W)

    -- order list
    local o = U.Panel(calc, 0.45)
    o:SetPoint("TOPRIGHT", 0, bodyTop)
    o:SetPoint("BOTTOMRIGHT", 0, 0)
    o:SetWidth(ORDER_W)
    local ot = U.Text(o, "GameFontNormal")
    ot:SetPoint("TOPLEFT", 10, -8)
    ot:SetText("Learning order")
    o.count = U.Text(o, "GameFontDisableSmall")
    o.count:SetPoint("TOPRIGHT", -10, -9)
    o.rows = {}
    local bodyH = (parent:GetHeight() or 600) + top - 10 + bodyTop
    if bodyH < 200 then bodyH = 470 end
    o.visible = math.floor((bodyH - 30 - 40) / ROW_H)
    for i = 1, o.visible do
        local r = CreateOrderRow(o)
        r:SetPoint("TOPLEFT", 4, -30 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", -8, 0)
        o.rows[i] = r
    end
    o:EnableMouseWheel(true)
    o:SetScript("OnMouseWheel", function(_, delta)
        calc.offset = math.max(0, calc.offset - delta * 3)
        AS.RefreshCalculator()
    end)
    o.thumb = o:CreateTexture(nil, "ARTWORK")
    o.thumb:SetWidth(3)
    o.thumb:SetColorTexture(1, 0.82, 0, 0.6)
    calc.order = o

    local function needsSaved()
        if calc.class ~= AS.PlayerClass() then return ("Log in a %s to use this build."):format(AS.ClassName(calc.class)) end
        if not calc.buildId then return "Save the build first." end
        if IsDirty() then return "Save your changes first." end
    end
    calc.share = U.Button(o, "Share", 70, 22, function(self)
        local build
        local cur = calc.editable and Current()
        if cur then
            if #cur.steps == 0 then SetMessage("Add some talent points first.") return end
            build = { name = AS.CleanName(calc.nameBox:GetText()), class = calc.class, code = AS.EncodeSteps(cur.steps) }
        elseif calc.buildId then
            build = AS.GetBuild(calc.buildId)
        end
        if not build then return end
        if IsShiftKeyDown() then AS.LinkToChat(build) else AS.OpenMenu(self, AS.ShareMenuItems(build), "calcshare") end
    end)
    calc.share:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Share", 1, 1, 1)
        GameTooltip:AddLine("Click: pick a chat to post it in", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift-click: put it in the chat message you're typing", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    calc.share:SetScript("OnLeave", function() GameTooltip:Hide() end)
    calc.share:SetPoint("BOTTOMRIGHT", -8, 8)
    calc.spec = GuardedButton(o, "Spec now", 80, function() AS.SpecNow(calc.buildId) end, needsSaved)
    calc.spec:SetPoint("RIGHT", calc.share, "LEFT", -4, 0)
    calc.toggle = GuardedButton(o, "Activate", 88, function()
        if AS.char.active == calc.buildId then AS.SetActive(nil) else AS.SetActive(calc.buildId) end
    end, needsSaved)
    calc.toggle:SetPoint("RIGHT", calc.spec, "LEFT", -4, 0)

    calc.ready = true
    return calc
end

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------

local function TreeGrid(list)
    local xs, seenX, maxTier = {}, {}, 1
    for _, t in ipairs(list) do
        if not seenX[t.x] then seenX[t.x] = true; xs[#xs + 1] = t.x end
        if t.tier > maxTier then maxTier = t.tier end
    end
    table.sort(xs)
    local col = {}
    for i, x in ipairs(xs) do col[x] = i end
    return col, math.max(4, #xs), maxTier
end

local function Line(p, n, x1, y1, x2, y2, r, g, b, a)
    local line = p.lines[n]
    if not line then
        line = p.grid:CreateTexture(nil, "BORDER")
        p.lines[n] = line
    end
    line:ClearAllPoints()
    if x1 == x2 then
        line:SetPoint("TOPLEFT", x1 - 1.5, math.max(y1, y2))
        line:SetSize(3, math.abs(y1 - y2))
    else
        line:SetPoint("TOPLEFT", math.min(x1, x2), y1 + 1.5)
        line:SetSize(math.abs(x1 - x2), 3)
    end
    line:SetColorTexture(r, g, b, a)
    line:Show()
end

local function DrawTree(p, i, cur)
    local list = cur.layout[i] or {}
    local meta = cur.meta
    p.title:SetText((TreeName(meta, i):gsub("^%l", string.upper)))
    if meta and meta.icons and meta.icons[i] then U.SetIcon(p.icon, meta.icons[i]); p.icon:Show() else p.icon:Hide() end
    p.points:SetText(cur.treePts[i] or 0)
    p.clear:SetEnabled(calc.editable and (cur.treePts[i] or 0) > 0)

    local first = {}
    for n, t in ipairs(cur.steps) do
        if not first[t.key] then first[t.key] = n end
    end

    local col, cols, rows = TreeGrid(list)
    local gw, gh = TREE_W - 16, p.grid:GetHeight()
    if not gh or gh <= 0 then gh = 420 end
    local cw, ch = math.min(CELL, gw / cols), math.min(CELL, gh / rows)
    local size = math.min(ICON, cw - 10, ch - 10)
    local function center(t)
        return (col[t.x] - 1) * cw + cw / 2, -((t.tier - 1) * ch + ch / 2)
    end

    -- prerequisite arrows
    local n = 0
    for _, t in ipairs(list) do
        for _, pre in ipairs(t.requires or {}) do
            if pre.tree == t.tree and col[pre.x] then
                local met = (cur.counts[pre.key] or 0) >= pre.maxRank
                local r, g, b, a = 0.45, 0.45, 0.45, 0.8
                if met then r, g, b, a = 1, 0.82, 0, 0.9 end
                local x1, y1 = center(pre)
                local x2, y2 = center(t)
                if x1 == x2 then
                    n = n + 1; Line(p, n, x1, y1 - size / 2, x2, y2 + size / 2, r, g, b, a)
                elseif y1 == y2 then
                    n = n + 1; Line(p, n, x1 + (x2 > x1 and size / 2 or -size / 2), y1, x2 + (x2 > x1 and -size / 2 or size / 2), y2, r, g, b, a)
                else
                    n = n + 1; Line(p, n, x1 + (x2 > x1 and size / 2 or -size / 2), y1, x2, y1, r, g, b, a)
                    n = n + 1; Line(p, n, x2, y1, x2, y2 + size / 2, r, g, b, a)
                end
            end
        end
    end
    for k = n + 1, #p.lines do p.lines[k]:Hide() end

    -- talents
    for j, t in ipairs(list) do
        local b = p.buttons[j] or CreateTalentButton(p.grid)
        p.buttons[j] = b
        b.talent = t
        b:SetSize(size, size)
        b:ClearAllPoints()
        local cx, cy = center(t)
        b:SetPoint("CENTER", p.grid, "TOPLEFT", cx, cy)
        U.SetIcon(b.icon, t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local rank = cur.counts[t.key] or 0
        local can, _, locked = CanAdd(t, cur)
        local available = rank > 0 or can or not locked
        b.icon:SetDesaturated(not available)
        b.icon:SetAlpha(available and 1 or 0.45)
        b.rank:SetText(("%d/%d"):format(rank, t.maxRank))
        if rank >= t.maxRank then
            b.border:SetColorTexture(1, 0.82, 0, 1)
            b.rank:SetTextColor(1, 0.82, 0)
        elseif rank > 0 then
            b.border:SetColorTexture(0.1, 1, 0.1, 1)
            b.rank:SetTextColor(0.1, 1, 0.1)
        elseif available then
            b.border:SetColorTexture(0.55, 0.55, 0.55, 1)
            b.rank:SetTextColor(1, 1, 1)
        else
            b.border:SetColorTexture(0.2, 0.2, 0.2, 1)
            b.rank:SetTextColor(0.5, 0.5, 0.5)
        end
        b.step:SetText(first[t.key] or "")
        b:Show()
    end
    for j = #list + 1, #p.buttons do p.buttons[j]:Hide() end
end

-- Steps of a build we can't resolve (another class): tree and position only.
local function RawSteps(code)
    local steps, tree = {}, nil
    for c in code:gmatch(".") do
        if c:match("%d") then
            tree = tonumber(c) + 1
        else
            steps[#steps + 1] = { tree = tree, pos = AS.POS:find(c:lower(), 1, true) or 0, maxed = c ~= c:lower() }
        end
    end
    return steps
end

local function DrawOrder(steps, raw)
    local o = calc.order
    local active = calc.buildId and AS.char.active == calc.buildId and not IsDirty()
    local need, have, nextIndex = {}, {}, nil
    if not raw then
        for i, t in ipairs(steps) do
            need[t.key] = (need[t.key] or 0) + 1
            have[i] = t.rank >= need[t.key]
            if not have[i] and not nextIndex then nextIndex = i end
        end
    end
    o.count:SetText(("%d / %d points"):format(#steps, AS.MaxPoints()))
    local maxOffset = math.max(0, #steps - o.visible)
    if calc.offset > maxOffset then calc.offset = maxOffset end
    for i, r in ipairs(o.rows) do
        local idx = i + calc.offset
        local t = steps[idx]
        if t then
            r.level:SetText("Lvl " .. (FIRST_LEVEL + idx - 1))
            if raw then
                r.key, r.index = nil, nil
                r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                r.text:SetText(("Tree %d, talent %s%s"):format(t.tree or 0, AS.POS:sub(t.pos, t.pos), t.maxed and " (max)" or ""))
                r.text:SetTextColor(0.8, 0.8, 0.8)
            else
                r.key, r.index = t.key, idx
                U.SetIcon(r.icon, t.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local n = 0
                for k = 1, idx do if steps[k].key == t.key then n = n + 1 end end
                r.text:SetText(("%s  %d/%d"):format(t.name, n, t.maxRank))
                if have[idx] then
                    r.text:SetTextColor(0.35, 1, 0.35)
                elseif idx == nextIndex and active then
                    r.text:SetTextColor(1, 0.82, 0)
                else
                    r.text:SetTextColor(1, 1, 1)
                end
            end
            if idx == nextIndex and active then
                r.baseR, r.baseG, r.baseB, r.baseA = 1, 0.82, 0, 0.18
            elseif idx % 2 == 0 then
                r.baseR, r.baseG, r.baseB, r.baseA = 1, 1, 1, 0.03
            else
                r.baseR, r.baseG, r.baseB, r.baseA = 0, 0, 0, 0
            end
            r:Show()
        else
            r.key, r.index = nil, nil
            r:Hide()
        end
    end
    if maxOffset > 0 then
        local trackH = o.visible * ROW_H
        local thumbH = math.max(16, trackH * o.visible / #steps)
        o.thumb:SetHeight(thumbH)
        o.thumb:ClearAllPoints()
        o.thumb:SetPoint("TOPRIGHT", -3, -30 - (trackH - thumbH) * calc.offset / maxOffset)
        o.thumb:Show()
    else
        o.thumb:Hide()
    end
end

function AS.RefreshCalculatorHighlight()
    if not calc then return end
    for _, p in ipairs(calc.trees) do
        for _, b in ipairs(p.buttons) do
            b.glow:SetShown(b:IsShown() and b.talent ~= nil and b.talent.key == calc.hoverKey)
        end
    end
    for _, r in ipairs(calc.order.rows) do
        if r:IsShown() and r.baseR then
            r.bg:SetColorTexture(r.baseR, r.baseG, r.baseB, (r.key and r.key == calc.hoverKey) and 0.3 or r.baseA)
        end
    end
end

function AS.RefreshCalculatorButtons()
    if not calc then return end
    local dirty = IsDirty()
    calc.save:SetEnabled(calc.editable and dirty)
    calc.saveNew:SetEnabled(calc.editable and calc.buildId ~= nil)
    calc.revert:SetEnabled(dirty and calc.buildId ~= nil)
    local usable = calc.class == AS.PlayerClass() and calc.buildId ~= nil and not dirty
    calc.toggle:SetText((calc.buildId and AS.char.active == calc.buildId) and "Deactivate" or "Activate")
    calc.toggle:SetEnabled(usable)
    calc.spec:SetEnabled(usable)
    calc.share:SetEnabled(calc.editable or calc.buildId ~= nil)
end

function AS.RefreshCalculator()
    if not calc or not calc:IsShown() or not calc.class then return end
    if calc.buildId and not AS.GetBuild(calc.buildId) then
        calc.buildId = nil -- deleted meanwhile
    end
    U.SetClassIcon(calc.classIcon, calc.class)

    local steps
    local cur = calc.editable and Current()
    if cur then
        calc.noData:Hide()
        for i, p in ipairs(calc.trees) do p:Show(); DrawTree(p, i, cur) end
        steps = cur.steps
        local pts = #steps
        calc.summary:SetText(("%s  ·  |cffffffff%d/%d/%d|r  ·  %d points left  ·  level %d"):format(
            AS.ClassName(calc.class), cur.treePts[1] or 0, cur.treePts[2] or 0, cur.treePts[3] or 0,
            AS.MaxPoints() - pts, pts > 0 and (FIRST_LEVEL + pts - 1) or FIRST_LEVEL))
        calc.summary:SetTextColor(AS.ClassRGB(calc.class))
        calc.hint:SetText("Left-click a talent to add a point, right-click to remove one. The order you add points is the learning order.")
        DrawOrder(steps, false)
    else
        for _, p in ipairs(calc.trees) do p:Hide() end
        local b = calc.buildId and AS.GetBuild(calc.buildId)
        steps = b and RawSteps(b.code) or {}
        local name = AS.ClassName(calc.class)
        calc.noData:SetText(("No %s talent tree saved yet.\nLog in a %s once and its tree is saved for all your characters.\n\nPoints per tree: %s"):format(
            name, name, b and b.trees or "?"))
        calc.noData:Show()
        calc.summary:SetText(AS.ClassName(calc.class) .. (b and b.points and ("  ·  " .. b.points .. " points") or ""))
        calc.summary:SetTextColor(AS.ClassRGB(calc.class))
        calc.hint:SetText("")
        DrawOrder(steps, true)
    end
    AS.RefreshCalculatorButtons()
    AS.RefreshCalculatorHighlight()
end

------------------------------------------------------------------------------
-- Opening
------------------------------------------------------------------------------

function AS.ShowBuild(id)
    local b = AS.GetBuild(id)
    if not b then return end
    AS.ConfirmDiscard(function()
        if not calc then AS.ShowPage("list") end
        Load(b)
        AS.ShowPage("calc")
        -- start the order list near the next point to learn
        if AS.char.active == id and b.class == AS.PlayerClass() then
            local progress = AS.Progress(b)
            if progress and progress.next then calc.offset = math.max(0, progress.next.step - 4) end
        end
        AS.RefreshCalculator()
    end)
end

function AS.NewBuild(class)
    class = class or AS.PlayerClass()
    if not T.HasData(class) then
        AS.Print(select(2, T.Layout(class)))
        return
    end
    AS.ConfirmDiscard(function()
        if not calc then AS.ShowPage("list") end
        Load(nil, class)
        AS.ShowPage("calc")
        if not calc.editable then
            AS.Print("your talent tree isn't loaded yet - try again in a moment.")
        end
        AS.RefreshCalculator()
    end)
end
