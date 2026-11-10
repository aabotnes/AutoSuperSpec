-- Auto Super Spec talent backends.
--
-- Every backend returns the same layout: layout[tree][position] = talent, where
-- positions run top to bottom, left to right (the order Wowhead letters them).
-- A talent has: key, tree, pos, name, icon, rank, maxRank, tier, requires.
--
-- * Traits  - WoW: Forever and other modern clients (C_ClassTalents / C_Traits).
--             The three classic trees are groups of one trait tree; points are
--             staged in order and committed in one go.
-- * Classic - older clients with GetTalentInfo / LearnTalent.

local _, AS = ...
local Talents = {}
AS.Talents = Talents

local function Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- Orders a tree's talents top to bottom, left to right and numbers rows (tiers).
local function SortTree(list, tree)
    table.sort(list, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    local tier, lastY = 0, nil
    for p, t in ipairs(list) do
        if t.y ~= lastY then tier, lastY = tier + 1, t.y end
        t.pos, t.tree, t.tier = p, tree, tier
    end
    return list
end

------------------------------------------------------------------------------
-- Traits backend (WoW: Forever)
------------------------------------------------------------------------------

local Traits = { name = "traits" }

function Traits.Available()
    return type(C_Traits) == "table" and type(C_ClassTalents) == "table"
        and type(C_Traits.GetTreeNodes) == "function" and type(C_Traits.PurchaseRank) == "function"
end

local function ConfigID()
    local id = Try(C_ClassTalents.GetActiveConfigID)
    if not id and C_SpecializationInfo then
        local group = Try(C_SpecializationInfo.GetActiveSpecGroup)
        if group then id = Try(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group) end
    end
    return id
end

local function TreeID(configID)
    local config = configID and Try(C_Traits.GetConfigInfo, configID)
    return config and config.treeIDs and config.treeIDs[1]
end

local function TalentName(configID, entryID)
    local entry = Try(C_Traits.GetEntryInfo, configID, entryID)
    local def = entry and entry.definitionID and Try(C_Traits.GetDefinitionInfo, entry.definitionID)
    if not def then return nil end
    local name, icon = def.overrideName, def.overrideIcon
    if def.spellID and C_Spell then
        name = name or Try(C_Spell.GetSpellName, def.spellID)
        icon = icon or Try(C_Spell.GetSpellTexture, def.spellID)
    end
    return name, icon, def.spellID
end

-- Splits nodes into side-by-side columns when the tree has no groups.
local function SplitByColumns(nodes, count)
    local xs = {}
    for _, n in ipairs(nodes) do xs[#xs + 1] = n.x end
    table.sort(xs)
    local gaps = {}
    for i = 2, #xs do gaps[#gaps + 1] = { size = xs[i] - xs[i - 1], at = (xs[i] + xs[i - 1]) / 2 } end
    table.sort(gaps, function(a, b) return a.size > b.size end)
    local cuts = {}
    for i = 1, math.min(count - 1, #gaps) do cuts[i] = gaps[i].at end
    table.sort(cuts)
    local trees = {}
    for _, n in ipairs(nodes) do
        local tree = 1
        for _, cut in ipairs(cuts) do if n.x > cut then tree = tree + 1 end end
        trees[tree] = trees[tree] or {}
        table.insert(trees[tree], n)
    end
    return trees
end

-- Reads one trait tree as seen through a config (yours, or the "view" config).
local function ReadTree(configID, treeID)
    -- read every visible node
    local nodes, byID = {}, {}
    for _, nodeID in ipairs(Try(C_Traits.GetTreeNodes, treeID) or {}) do
        local info = Try(C_Traits.GetNodeInfo, configID, nodeID)
        if info and info.isVisible and info.entryIDs and #info.entryIDs > 0 then
            local entryID = (info.activeEntry and info.activeEntry.entryID) or info.entryIDs[1]
            local name, icon, spellID = TalentName(configID, entryID)
            local t = {
                key = nodeID, nodeID = nodeID, entryID = entryID, spellID = spellID,
                name = name or ("Talent " .. nodeID), icon = icon,
                rank = info.activeRank or info.ranksPurchased or 0,
                maxRank = info.maxRanks or 1,
                x = info.posX or 0, y = info.posY or 0,
                groupIDs = info.groupIDs or {}, edges = info.visibleEdges or {}, requires = {},
            }
            nodes[#nodes + 1] = t
            byID[nodeID] = t
        end
    end
    if #nodes == 0 then return nil, "your talent tree is empty - try again in a moment." end

    -- prerequisites: an arrow from A to B means B needs A
    for _, t in ipairs(nodes) do
        for _, edge in ipairs(t.edges) do
            local target = byID[edge.targetNode]
            if target and (edge.type or 1) ~= 0 then table.insert(target.requires, t) end
        end
    end

    -- the classic trees are node groups; use each node's smallest group
    local groups = Try(C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}
    local groupInfo, members = {}, {}
    for _, g in ipairs(groups) do groupInfo[g.groupID] = g end
    for _, t in ipairs(nodes) do
        for _, gid in ipairs(t.groupIDs) do
            if groupInfo[gid] then members[gid] = (members[gid] or 0) + 1 end
        end
    end
    local byGroup = {}
    for _, t in ipairs(nodes) do
        local best
        for _, gid in ipairs(t.groupIDs) do
            if members[gid] and (not best or members[gid] < members[best]) then best = gid end
        end
        if best then
            byGroup[best] = byGroup[best] or {}
            table.insert(byGroup[best], t)
        end
    end
    local groupOrder = {}
    for gid in pairs(byGroup) do groupOrder[#groupOrder + 1] = groupInfo[gid] end
    table.sort(groupOrder, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)

    local layout, names, icons = {}, {}, {}
    if #groupOrder >= 2 then
        for i, g in ipairs(groupOrder) do
            layout[i] = SortTree(byGroup[g.groupID], i)
            names[i] = g.displayName
            icons[i] = g.icon
        end
    else
        for i, list in ipairs(SplitByColumns(nodes, 3)) do
            layout[i] = SortTree(list, i)
        end
    end
    return layout, { names = names, icons = icons, configID = configID, treeID = treeID, groups = groups, grouped = #groupOrder >= 2 }
end

function Traits.Layout()
    local configID = ConfigID()
    if not configID then return nil, "your talents aren't loaded yet - try again in a moment." end
    local treeID = TreeID(configID)
    if not treeID then return nil, "couldn't find your talent tree." end
    return ReadTree(configID, treeID)
end

function Traits.Unspent()
    local configID = ConfigID()
    local treeID = TreeID(configID)
    if not treeID then return nil end
    local infos = Try(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
    if type(infos) ~= "table" then return nil end
    local total, seen = 0, {}
    for _, c in ipairs(infos) do
        if not seen[c.traitCurrencyID] then
            seen[c.traitCurrencyID] = true
            total = total + (c.quantity or 0)
        end
    end
    return total
end

-- Returns a reason why talents can't be changed right now, or nil.
function Traits.Busy()
    local configID = ConfigID()
    if not configID then return "your talents aren't loaded yet." end
    if Try(C_Traits.ConfigHasStagedChanges, configID) then
        return "you have unsaved changes in your talent window - apply or undo them first."
    end
    if type(C_ClassTalents.CanEditTalents) == "function" then
        local ok, canEdit, why = pcall(C_ClassTalents.CanEditTalents)
        if ok and canEdit == false then return why or "talents can't be changed right now." end
    end
end

function Traits.CanReset()
    local configID = ConfigID()
    local treeID = TreeID(configID)
    if not treeID then return false end
    local info = Try(C_Traits.GetTreeInfo, configID, treeID)
    return info ~= nil and not info.cannotRefund and type(C_Traits.ResetTree) == "function"
end

local commit -- the commit we are waiting on

-- Stages the talents in order, then commits them all at once.
-- done(learnedCount, errorText) is called when the game confirms or refuses.
function Traits.Learn(steps, opts, done)
    local configID = ConfigID()
    local treeID = TreeID(configID)
    if not treeID then return done(0, "your talents aren't loaded yet.") end
    if opts.reset and not Try(C_Traits.ResetTree, configID, treeID) then
        return done(0, "the game wouldn't reset your talents.")
    end
    local staged, failed = 0, nil
    for _, t in ipairs(steps) do
        if not Try(C_Traits.PurchaseRank, configID, t.nodeID) then
            failed = t
            break
        end
        staged = staged + 1
    end
    if staged == 0 then
        Try(C_Traits.RollbackConfig, configID)
        return done(0, failed and ("the game wouldn't let you learn %s yet."):format(failed.name) or "nothing to learn.")
    end
    local saved
    if C_SpecializationInfo and C_ClassTalents.GetLastSelectedSavedConfigID then
        local spec = Try(C_SpecializationInfo.GetSpecialization)
        local specID = spec and Try(C_SpecializationInfo.GetSpecializationInfo, spec)
        saved = specID and Try(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    end
    local ok = Try(C_ClassTalents.CommitConfig, saved)
    if not ok then ok = Try(C_Traits.CommitConfig, configID) end
    if not ok then
        Try(C_Traits.RollbackConfig, configID)
        return done(0, "the game refused the talent change.")
    end
    local c = { configID = configID, count = staged, done = done, partial = failed }
    commit = c
    AS.After(15, function()
        if commit == c then
            commit = nil
            done(0, "the game didn't confirm the talent change.")
        end
    end)
end

function Traits.IsWaiting() return commit ~= nil end

function Traits.OnEvent(event, configID)
    if not commit then return end
    if event == "TRAIT_CONFIG_UPDATED" and (configID == nil or configID == commit.configID) then
        local c = commit
        commit = nil
        c.done(c.count, c.partial and ("stopped before %s - the game wouldn't allow it yet."):format(c.partial.name) or nil)
    elseif event == "CONFIG_COMMIT_FAILED" then
        local c = commit
        commit = nil
        Try(C_Traits.RollbackConfig, c.configID)
        c.done(0, "the game couldn't apply the talents (are you moving, casting or in combat?).")
    end
end

Traits.events = { "TRAIT_CONFIG_UPDATED", "CONFIG_COMMIT_FAILED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }

------------------------------------------------------------------------------
-- Classic backend (GetTalentInfo / LearnTalent)
------------------------------------------------------------------------------

local Classic = { name = "classic" }

function Classic.Available()
    return type(GetNumTalentTabs) == "function" and type(GetTalentInfo) == "function"
        and type(LearnTalent) == "function" and type(GetNumTalents) == "function"
end

function Classic.Layout()
    local layout, names = {}, {}
    local numTabs = GetNumTalentTabs() or 0
    for tab = 1, numTabs do
        local list = {}
        for i = 1, (GetNumTalents(tab) or 0) do
            local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, i)
            if name then
                list[#list + 1] = {
                    key = tab * 1000 + i, tab = tab, index = i, name = name, icon = icon,
                    y = tier or 0, x = column or 0, rank = rank or 0, maxRank = maxRank or 0, requires = {},
                }
            end
        end
        layout[tab] = SortTree(list, tab)
        if GetTalentTabInfo then
            local a, b = GetTalentTabInfo(tab)
            names[tab] = type(a) == "string" and a or (type(b) == "string" and b) or nil
        end
    end
    if numTabs == 0 then return nil, "your talents aren't loaded yet - try again in a moment." end
    if GetTalentPrereqs then
        for tab, list in ipairs(layout) do
            for _, t in ipairs(list) do
                local pTier, pCol = GetTalentPrereqs(tab, t.index)
                if pTier then
                    for _, pre in ipairs(list) do
                        if pre.y == pTier and pre.x == pCol then table.insert(t.requires, pre) end
                    end
                end
            end
        end
    end
    return layout, { names = names }
end

function Classic.Unspent()
    if type(GetUnspentTalentPoints) == "function" then
        local ok, v = pcall(GetUnspentTalentPoints)
        if ok and type(v) == "number" then return v end
    end
    if type(UnitCharacterPoints) == "function" then
        local v = UnitCharacterPoints("player")
        if type(v) == "number" then return v end
    end
end

function Classic.Busy() end
function Classic.CanReset() return false end

local learning -- the talent we are waiting on

-- Learns the talents one at a time (each needs a reply from the server).
function Classic.Learn(steps, opts, done)
    local i, count = 1, 0
    local function nextOne()
        local t = steps[i]
        if not t then learning = nil; return done(count) end
        local _, _, _, _, before = GetTalentInfo(t.tab, t.index)
        local job = { t = t, before = before or 0, expires = GetTime() + 4 }
        learning = job
        LearnTalent(t.tab, t.index)
        local function poll()
            if learning ~= job then return end
            local _, _, _, _, rank = GetTalentInfo(t.tab, t.index)
            if (rank or 0) > job.before then
                count, i = count + 1, i + 1
                AS.OnPointLearned(t, rank)
                nextOne()
            elseif GetTime() > job.expires then
                learning = nil
                done(count, ("the game wouldn't let you learn %s."):format(t.name))
            else
                AS.After(0.2, poll)
            end
        end
        AS.After(0.2, poll)
    end
    nextOne()
end

function Classic.IsWaiting() return learning ~= nil end
function Classic.OnEvent() end
Classic.events = { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }

------------------------------------------------------------------------------
-- Pick the backend this client supports
------------------------------------------------------------------------------

local backend
local function Backend()
    if backend then return backend end
    if Traits.Available() and not Classic.Available() then
        backend = Traits
    elseif Classic.Available() then
        backend = Classic
    elseif Traits.Available() then
        backend = Traits
    end
    return backend
end

function Talents.Name()
    local b = Backend()
    return b and b.name or "none"
end

------------------------------------------------------------------------------
-- Talent data for every class
------------------------------------------------------------------------------
-- Your own class is always read live. Other classes come from data saved for
-- the whole account: each character saves its class's tree when it logs in,
-- and the addon also reads other classes' trees through the game's "view a
-- talent link" mode where the client allows it. Saved data is tagged with the
-- client build, so it's re-read after a game update.

local VIEW_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID) or -3
local DATA_FORMAT = 2 -- 2: full tooltip lines per rank
local memo = {}

local function ClientBuild()
    local _, build = GetBuildInfo()
    return tostring(build)
end

local function ClientVersion()
    local version = GetBuildInfo()
    return tostring(version)
end

------------------------------------------------------------------------------
-- Full talent tooltips (costs, range, cast time, cooldown, description)
------------------------------------------------------------------------------

local function Hex(c)
    if type(c) == "table" and type(c.r) == "number" then
        return ("%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
    end
end

local function Secret(v)
    return issecretvalue and v ~= nil and issecretvalue(v)
end

-- TooltipData -> plain lines we can save: { l = left, r = right, lc/rc = colors, w = wrap }
local function TooltipLines(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do
        local left, right = line.leftText, line.rightText
        if (left == nil and right == nil) and type(line.args) == "table" then -- older tooltip data format
            for _, arg in ipairs(line.args) do
                if arg.field == "leftText" then left = arg.stringVal end
                if arg.field == "rightText" then right = arg.stringVal end
            end
        end
        if Secret(left) or Secret(right) then return nil end
        if type(left) ~= "string" then left = nil end
        if type(right) ~= "string" or right == "" then right = nil end
        if (left and left ~= "") or right then
            out[#out + 1] = { l = left, r = right, lc = Hex(line.leftColor), rc = Hex(line.rightColor), w = line.wrapText }
        end
    end
    return #out > 0 and out or nil
end

-- The game's own tooltip for a talent at a rank, as saved lines.
function Talents.TooltipLines(t, rank)
    if t.tips then return t.tips[rank] end
    local lines
    if t.entryID and C_TooltipInfo and C_TooltipInfo.GetTraitEntry then
        lines = TooltipLines(Try(C_TooltipInfo.GetTraitEntry, t.entryID, rank))
    end
    if not lines and t.spellID and C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        lines = TooltipLines(Try(C_TooltipInfo.GetSpellByID, t.spellID))
    end
    return lines
end

local function Saved(class)
    return AS.db and AS.db.talentData and AS.db.talentData[class]
end

local function Store(class, data)
    AS.db.talentData = AS.db.talentData or {}
    AS.db.talentData[class] = data
    memo[class] = nil
end

local function Serialize(layout, meta, source)
    local data = {
        build = ClientBuild(), version = ClientVersion(), time = time(), format = DATA_FORMAT,
        source = source, names = meta.names or {}, icons = meta.icons or {}, trees = {},
    }
    for i, list in ipairs(layout) do
        local out = {}
        for _, t in ipairs(list) do
            local req = {}
            for _, pre in ipairs(t.requires or {}) do req[#req + 1] = pre.key end
            local desc, tips
            if t.entryID or t.spellID then
                desc, tips = {}, {}
                for r = 1, t.maxRank do
                    desc[r] = Talents.Description(t, r)
                    tips[r] = Talents.TooltipLines(t, r)
                end
            end
            out[#out + 1] = {
                key = t.key, name = t.name, icon = t.icon, maxRank = t.maxRank, x = t.x, y = t.y,
                entryID = t.entryID, spellID = t.spellID, req = req, desc = desc, tips = tips,
            }
        end
        data.trees[i] = out
    end
    return data
end

local function Deserialize(data)
    local layout, byKey = {}, {}
    for i, list in ipairs(data.trees or {}) do
        local tree = {}
        for _, d in ipairs(list) do
            local t = {
                key = d.key, name = d.name, icon = d.icon, maxRank = d.maxRank, x = d.x, y = d.y,
                entryID = d.entryID, spellID = d.spellID, desc = d.desc, tips = d.tips, req = d.req, rank = 0, requires = {},
            }
            tree[#tree + 1] = t
            byKey[t.key] = t
        end
        layout[i] = SortTree(tree, i)
    end
    for _, tree in ipairs(layout) do
        for _, t in ipairs(tree) do
            for _, key in ipairs(t.req or {}) do
                if byKey[key] then table.insert(t.requires, byKey[key]) end
            end
            t.req = nil
        end
    end
    return layout, { names = data.names, icons = data.icons, saved = true, build = data.build, source = data.source }
end

-- Layout for a class: live for your own class, saved data for others.
function Talents.Layout(class)
    local mine = AS.PlayerClass()
    if class == nil or class == mine then
        local b = Backend()
        if not b then return nil, "this game client has no talent functions Auto Super Spec knows." end
        return b.Layout()
    end
    local data = Saved(class)
    if not data then
        local name = AS.ClassName(class)
        return nil, ("no %s talent tree saved yet. Log in a %s once and its tree is saved for all your characters."):format(name, name)
    end
    local m = memo[class]
    if not m or m.data ~= data then
        local layout, meta = Deserialize(data)
        m = { data = data, layout = layout, meta = meta }
        memo[class] = m
    end
    return m.layout, m.meta
end

function Talents.HasData(class)
    return class == AS.PlayerClass() or Saved(class) ~= nil
end

-- Saves your own class's tree for your other characters.
function Talents.SaveOwnTree()
    local class, b = AS.PlayerClass(), Backend()
    if not class or not b then return false end
    local layout, meta = b.Layout()
    if not layout then return false end
    Store(class, Serialize(layout, meta, "live"))
    return true
end

local function ClassID(class)
    if type(GetNumClasses) ~= "function" or type(GetClassInfo) ~= "function" then return nil end
    -- class IDs can have gaps (e.g. Druid is 11), so look past the class count
    for id = 1, math.max(GetNumClasses() or 0, 20) do
        local ok, _, file = pcall(GetClassInfo, id)
        if ok and file == class then return id end
    end
end

-- Reads another class's tree through the game's talent-link view mode.
function Talents.ReadClassTree(class)
    if not Traits.Available() or type(C_ClassTalents.InitializeViewLoadout) ~= "function" then
        return nil, "this client has no talent view mode"
    end
    local classID = ClassID(class)
    if not classID then return nil, "unknown class" end
    -- the first spec that has a talent tree
    local specID, treeID
    local count = Try(C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID, classID) or 0
    for index = 1, math.max(count, 4) do
        local id = Try(GetSpecializationInfoForClassID, classID, index)
        local tree = id and Try(C_ClassTalents.GetTraitTreeForSpec, id)
        if tree then specID, treeID = id, tree; break end
    end
    if not specID then return nil, "no talent tree found for the class" end
    if not pcall(C_ClassTalents.InitializeViewLoadout, specID, AS.MaxPoints() + 9) then
        return nil, "the game refused to open the talent view"
    end
    Try(C_ClassTalents.ViewLoadout, {})
    return ReadTree(VIEW_CONFIG_ID, treeID)
end

-- Reads the trees of classes that are missing or outdated (saved on another
-- game build or in an older format). force: read every class again.
function Talents.ScanClasses(force)
    if InCombatLockdown and InCombatLockdown() then return nil end
    local results, build, mine = {}, ClientBuild(), AS.PlayerClass()
    for _, class in ipairs(AS.CLASSES) do
        local have = Saved(class)
        local outdated = not have or have.build ~= build or (have.format or 1) < DATA_FORMAT
        if class ~= mine and (force or outdated) then
            local layout, meta = Talents.ReadClassTree(class)
            if layout then
                Store(class, Serialize(layout, meta, "view"))
                results[class] = true
            else
                results[class] = meta or false
            end
        end
    end
    Talents.lastScan = results
    AS.db.lastScan = { time = time(), version = ClientVersion(), build = build }
    return results
end

function Talents.Unspent() local b = Backend(); return b and b.Unspent() end

-- The talent's text at a given rank (as the talent window shows it).
function Talents.Description(t, rank)
    if t.desc then return t.desc[rank] end
    local text
    if t.entryID and C_Traits then text = Try(C_Traits.GetTraitDescription, t.entryID, rank) end
    if (not text or text == "") and t.spellID and C_Spell then text = Try(C_Spell.GetSpellDescription, t.spellID) end
    if text and text ~= "" then return text end
end
function Talents.Busy() local b = Backend(); return b and b.Busy() end
function Talents.CanReset() local b = Backend(); return b and b.CanReset() end
function Talents.IsWaiting() local b = Backend(); return b and b.IsWaiting() end
function Talents.Learn(steps, opts, done) return Backend().Learn(steps, opts, done) end
function Talents.OnEvent(...) local b = Backend(); if b then b.OnEvent(...) end end

function Talents.Events()
    local list = {}
    for _, ev in ipairs(Traits.events) do list[#list + 1] = ev end
    for _, ev in ipairs(Classic.events) do list[#list + 1] = ev end
    return list
end

-- Text describing what Auto Super Spec sees, for bug reports.
function Talents.DebugText()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local version, build, _, toc = GetBuildInfo()
    add(("Auto Super Spec debug - client %s.%s, interface %s, backend %s"):format(tostring(version), tostring(build), tostring(toc), Talents.Name()))
    local _, class = UnitClass("player")
    add(("class %s, level %s, unspent %s"):format(tostring(class), tostring(UnitLevel("player")), tostring(Talents.Unspent())))
    local ls = AS.db and AS.db.lastScan
    add("last scan: " .. (ls and (date("%Y-%m-%d %H:%M", ls.time) .. " on " .. tostring(ls.version) .. " (" .. tostring(ls.build) .. ")") or "never"))
    for _, class in ipairs(AS.CLASSES) do
        local d = Saved(class)
        local scan = Talents.lastScan and Talents.lastScan[class]
        local sizes = {}
        for i, tree in ipairs(d and d.trees or {}) do sizes[i] = #tree end
        add(("saved %s: %s%s%s"):format(class, d and (d.source .. " on build " .. tostring(d.build)) or "none",
            #sizes > 0 and (", talents per tree " .. table.concat(sizes, "/")) or "",
            scan ~= nil and (" (last view read: " .. tostring(scan) .. ")") or ""))
    end
    local layout, meta = Talents.Layout()
    if not layout then
        add("layout error: " .. tostring(meta))
        return table.concat(lines, "\n")
    end
    if meta.configID then
        add(("config %s, tree %s, grouped %s"):format(tostring(meta.configID), tostring(meta.treeID), tostring(meta.grouped)))
        for _, g in ipairs(meta.groups or {}) do
            add(("  group %s order %s '%s'"):format(tostring(g.groupID), tostring(g.orderIndex), tostring(g.displayName)))
        end
    end
    for tree, list in ipairs(layout) do
        add(("tree %d: %s (%d talents)"):format(tree, tostring(meta.names and meta.names[tree]), #list))
        for _, t in ipairs(list) do
            add(("  %s %s %d/%d tier %d (x %s, y %s)"):format(AS.POS:sub(t.pos, t.pos), t.name, t.rank, t.maxRank, t.tier, tostring(t.x), tostring(t.y)))
        end
    end
    return table.concat(lines, "\n")
end
