-- AutoSpec against a mocked WoW: Forever trait system (warrior).
package.path = arg[0]:gsub("[^/]+$", "") .. "?.lua;" .. package.path
local M = require("wow_mock")
local check = M.check
M.level = 30
function UnitClass() return "Warrior", "WARRIOR" end

-- Warrior trees laid out so the user's Wowhead link is valid. Positions are
-- listed top-to-bottom, left-to-right: { name, row, col, maxRank }
local trees = {
    { group = 11, name = "Arms", talents = {
        { "Improved Heroic Strike", 1, 1, 3 }, { "Deflection", 1, 2, 5 }, { "Improved Rend", 1, 3, 3 },
        { "Improved Charge", 2, 1, 2 }, { "Tactical Mastery", 2, 2, 5 } } },
    { group = 12, name = "Fury", talents = {
        { "Booming Voice", 1, 2, 5 }, { "Cruelty", 1, 3, 5 }, { "Improved Demoralizing Shout", 2, 2, 5 },
        { "Unbridled Wrath", 2, 3, 5 }, { "Improved Cleave", 3, 1, 3 }, { "Piercing Howl", 3, 2, 1 },
        { "Blood Craze", 3, 3, 3 }, { "Improved Battle Shout", 3, 4, 5 } } },
    { group = 13, name = "Protection", talents = {
        { "Shield Specialization", 1, 1, 5 }, { "Anticipation", 1, 2, 5 }, { "Improved Bloodrage", 1, 3, 2 },
        { "Toughness", 2, 1, 5 }, { "Iron Will", 2, 2, 3 }, { "Improved Taunt", 2, 3, 5 },
        { "Last Stand", 3, 1, 1 }, { "Improved Shield Block", 3, 2, 2 }, { "Improved Revenge", 3, 3, 3 },
        { "Defiance", 3, 4, 3 }, { "Improved Sunder Armor", 4, 1, 1 }, { "Improved Disarm", 4, 2, 3 },
        { "Improved Shield Wall", 4, 3, 1 }, { "Concussion Blow", 4, 4, 2 }, { "Improved Shield Bash", 5, 1, 1 },
        { "One-Handed Weapon Specialization", 5, 2, 3 }, { "Shield Slam", 5, 3, 5 }, { "Focused Rage", 6, 2, 1 } } },
}

local nodes, nodeList = {}, {}
local committed, staged, resetPending = {}, {}, false
local id = 100
for ti, tree in ipairs(trees) do
    for _, d in ipairs(tree.talents) do
        id = id + 7
        local n = { id = id, name = d[1], row = d[2], col = d[3], max = d[4], group = tree.group }
        nodes[id] = n
        table.insert(nodeList, 1, id) -- reversed: API order must not matter
        committed[id], staged[id] = 0, 0
    end
end
local mageTrees = {
    { group = 21, name = "Arcane", talents = { { "Arcane Subtlety", 1, 1, 2 }, { "Arcane Focus", 1, 2, 5 }, { "Improved Arcane Missiles", 1, 3, 5 } } },
    { group = 22, name = "Fire", talents = { { "Improved Fireball", 1, 2, 5 } } },
    { group = 23, name = "Frost", talents = { { "Improved Frostbolt", 1, 2, 5 }, { "Elemental Precision", 1, 3, 3 } } },
}
local mageList = {}
for _, tree in ipairs(mageTrees) do
    for _, d in ipairs(tree.talents) do
        id = id + 7
        nodes[id] = { id = id, name = d[1], row = d[2], col = d[3], max = d[4], group = tree.group, mage = true }
        table.insert(mageList, id)
        committed[id], staged[id] = 0, 0
    end
end
local viewOpened = {}
function GetNumClasses() return 9 end -- like Forever: 9 classes, but Druid's class ID is 11
local CLASS_FILES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID" }
local readable = { [801] = true } -- specs the view mode can read (mage)
function GetClassInfo(i) return CLASS_FILES[i], CLASS_FILES[i], i end
function GetSpecializationInfoForClassID(classID, index) return classID * 100 + index end

local function current(nid) return (resetPending and 0 or committed[nid]) + staged[nid] end
local function spentNow() local s = 0; for nid, n in pairs(nodes) do if not n.mage then s = s + current(nid) end end; return s end
local function groupPoints(g) local s = 0; for nid, n in pairs(nodes) do if n.group == g then s = s + current(nid) end end; return s end
local function anyStaged() if resetPending then return true end; for _, v in pairs(staged) do if v ~= 0 then return true end end end
local canRefund = true
local edges = {}
function GetMaxPlayerLevel() return 60 end
local function nodeByName(name) for nid, n in pairs(nodes) do if n.name == name then return nid end end end
edges[nodeByName("Concussion Blow")] = { { targetNode = nodeByName("Shield Slam"), type = 3 } }
local commits = 0

C_ClassTalents = {
    GetActiveConfigID = function() return 1 end,
    GetTraitTreeForSpec = function(specID) return readable[specID] and 600 or nil end,
    InitializeViewLoadout = function(specID, level) viewOpened[#viewOpened + 1] = specID .. "@" .. level end,
    ViewLoadout = function() return true end,
    CanEditTalents = function() return true end,
    CommitConfig = function()
        if not anyStaged() then return false end
        commits = commits + 1
        C_Timer.After(0.5, function()
            for nid in pairs(nodes) do committed[nid] = current(nid); staged[nid] = 0 end
            resetPending = false
            M.Fire("TRAIT_CONFIG_UPDATED", 1)
        end)
        return true
    end,
}
C_Traits = {
    GetConfigInfo = function() return { ID = 1, treeIDs = { 500 } } end,
    GetTreeNodes = function(treeID) return treeID == 600 and mageList or nodeList end,
    GetNodeInfo = function(configID, nid)
        local n = nodes[nid]
        if n.mage and configID ~= -3 then return nil end
        return { ID = nid, posX = n.col * 600, posY = n.row * 600, entryIDs = { nid * 10 }, isVisible = true,
            activeRank = committed[nid], currentRank = current(nid), ranksPurchased = committed[nid], maxRanks = n.max,
            groupIDs = { 999, n.group }, visibleEdges = edges[nid] or {} }
    end,
    GetEntryInfo = function(_, eid) return { definitionID = eid, maxRanks = 1 } end,
    GetDefinitionInfo = function(def) return { spellID = def } end,
    GetGroupDisplayInfoByTreeID = function(treeID)
        if treeID == 600 then
            return { { groupID = 21, orderIndex = 1, displayName = "Arcane", icon = 21 },
                { groupID = 22, orderIndex = 2, displayName = "Fire", icon = 22 },
                { groupID = 23, orderIndex = 3, displayName = "Frost", icon = 23 } }
        end
        return { { groupID = 999, orderIndex = 0, displayName = "Warrior" },
            { groupID = 13, orderIndex = 3, displayName = "Protection", icon = 3 },
            { groupID = 11, orderIndex = 1, displayName = "Arms", icon = 1 },
            { groupID = 12, orderIndex = 2, displayName = "Fury", icon = 2 } }
    end,
    GetTreeCurrencyInfo = function() return { { traitCurrencyID = 7, quantity = (M.level - 9) - spentNow(), spent = spentNow() } } end,
    ConfigHasStagedChanges = function() return anyStaged() end,
    PurchaseRank = function(_, nid)
        local n = nodes[nid]
        if (M.level - 9) - spentNow() <= 0 then return false end
        if current(nid) >= n.max then return false end
        if groupPoints(n.group) < (n.row - 1) * 5 then return false end
        staged[nid] = staged[nid] + 1
        return true
    end,
    RollbackConfig = function() for nid in pairs(staged) do staged[nid] = 0 end; resetPending = false; return true end,
    ResetTree = function() if not canRefund then return false end; resetPending = true; return true end,
    GetTreeInfo = function() return { ID = 500, cannotRefund = not canRefund } end,
    CommitConfig = function() return false end,
    GetTraitDescription = function(eid, rank) return nodes[eid / 10].name .. " rank " .. rank .. " text" end,
}
local buildNumber = "70790"
function GetBuildInfo() return "1.60.1", buildNumber, "Nov 3 2026", 16001 end
C_TooltipInfo = {
    GetTraitEntry = function(eid, rank)
        local n = nodes[eid / 10]
        return { lines = {
            { leftText = n.name },
            { leftText = ("Rank %d/%d"):format(rank, n.max) },
            { leftText = "20 Rage", rightText = "Melee Range" },
            { leftText = "Instant", rightText = "6 sec cooldown" },
            { leftText = n.name .. " rank " .. rank .. " full text", leftColor = { r = 1, g = 0.82, b = 0 }, wrapText = true },
        } }
    end,
}
C_Spell = {
    GetSpellName = function(sid) return nodes[sid / 10].name end,
    GetSpellTexture = function() return 136000 end,
}

local DIR = arg[1]
local AS = M.Load(DIR, { "Core.lua", "Talents.lua", "Engine.lua", "UI.lua", "Calculator.lua", "Minimap.lua" })
check(AS.Talents.Name() == "traits", "uses the trait backend")
M.Fire("PLAYER_ENTERING_WORLD")
M.Advance(6)

-- layout
local layout, meta = AS.Talents.Layout()
check(#layout == 3 and meta.names[1] == "Arms" and meta.names[3] == "Protection", "3 trees from groups in order: " .. table.concat(meta.names, ","))
check(layout[3][2].name == "Anticipation" and layout[3][5].name == "Iron Will", "prot positions follow rows/columns")

-- the link that failed before
local URL = "https://www.wowhead.com/forever/talent-calc/warrior/vkndmh04-05050005-050530120301021351_t0/2BEddHgKndddQrssTv1BDH0bbbb2s"
local p = AS.ParseInput(URL)
check(p.ranks[1][2] == 4 and #p.ranks[1] == 2, "tree 1 ranks read past the vkndmh tag")
check(AS.CheckRanks(p.ranks, layout), "link ranks agree with the in-game trees")

-- user already specced differently: 21 points elsewhere
committed[layout[1][1].nodeID] = 3   -- Improved Heroic Strike 3
committed[layout[1][2].nodeID] = 5   -- Deflection 5
committed[layout[1][5].nodeID] = 5   -- Tactical Mastery 5
committed[layout[1][3].nodeID] = 3   -- Improved Rend 3
committed[layout[1][4].nodeID] = 2   -- Improved Charge 2

local b = AS.Import(URL, "Prot leveling")
check(b and b.points == 51 and b.trees == "4/15/32", "warrior build imported: " .. tostring(b and b.points) .. " " .. tostring(b and b.trees))
check(not M.LogHas("warning"), "no warnings on import")

-- UI: open, import through the bar, activate from the list
AS.ShowUI()
check(AutoSuperSpecFrame:IsShown(), "window opens")
AS.SetActive(b.id)
check(AS.char.active == b.id, "activated from list")
check(M.LogHas("outside this build"), "warns about off-build points")

-- learning on level-up must not happen while spec doesn't allow it? It should still add build talents.
-- Spec now -> reset & spec
AS.SpecNow(b.id)
check(M.LastPopup().which == "AUTOSUPERSPEC_RESET", "spec now offers reset when talents differ")
M.ClickPopup("AUTOSUPERSPEC_RESET")
M.Advance(3)
check(spentNow() == 21, "21 points spent after reset, got " .. spentNow())
check(committed[layout[3][2].nodeID] == 5 and committed[layout[3][5].nodeID] == 3, "anticipation 5, iron will 3")
check(committed[layout[1][1].nodeID] == 0, "old arms points refunded")
check(commits == 1, "one commit for the whole respec")
check(M.LogHas("learned .*Anticipation.* 5/5"), "reports what it learned")

-- ding: one more point, one more commit
M.level = 31
M.Fire("PLAYER_LEVEL_UP", 31)
M.Fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 500)
M.Advance(5)
check(spentNow() == 22 and commits == 2, "level 31 learns the next point (" .. spentNow() .. ", commits " .. commits .. ")")

-- player has staged changes in the talent window: AutoSpec keeps its hands off
M.level = 32
staged[layout[1][1].nodeID] = 1
local before = commits
M.Fire("PLAYER_LEVEL_UP", 32)
M.Fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 500)
M.Advance(5)
check(commits == before, "doesn't commit the player's own staged changes")
staged[layout[1][1].nodeID] = 0
M.Fire("TRAIT_CONFIG_UPDATED", 1)
M.Advance(5)
check(commits == before + 1 and spentNow() == 23, "learns the ding's point once the talent window is clean again")

-- unspent points that didn't come from a ding (second spec, talent reset, login) are never auto-spent
M.level = 40 -- 8 extra unspent points
M.Fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 500)
M.Fire("TRAIT_CONFIG_UPDATED", 1)
M.Fire("CHARACTER_POINTS_CHANGED", 8)
M.Fire("PLAYER_ENTERING_WORLD")
M.Advance(10)
check(spentNow() == 23 and commits == before + 1, "spec switch / unlearned talents / login: nothing is auto-learned")
AS.SetActive(nil, true)
AS.SetActive(b.id, true)
M.Advance(5)
check(spentNow() == 23, "activating a build doesn't spend points")
-- a ding spends only its own point, not the extra unspent ones
M.level = 41
M.Fire("PLAYER_LEVEL_UP", 41)
M.Fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 500)
M.Advance(5)
check(spentNow() == 24 and commits == before + 2, "a ding learns exactly one point (" .. spentNow() .. ")")
-- "Spec now" spends the rest when asked
M.level = 59
AS.SpecNow(b.id)
check(M.LastPopup().which == "AUTOSUPERSPEC_APPLY", "spec now asks first")
M.ClickPopup("AUTOSUPERSPEC_APPLY")
M.Advance(5)
check(spentNow() == 50, "spec now fills the free points (" .. spentNow() .. ")")

-- dinging 60: learns the last point, then stops following the build
M.level = 60
M.Fire("PLAYER_LEVEL_UP", 60)
M.Fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 500)
M.Advance(5)
check(spentNow() == 51, "level 60 ding learns the last point, got " .. spentNow())
check(AS.char.active == nil and M.LogHas("reached level 60"), "at level 60 the build is deactivated (auto spec off)")
local prog = AS.Progress(b)
check(prog.done == 51 and not prog.next, "build complete")
check(committed[layout[2][2].nodeID] == 5 and committed[layout[1][2].nodeID] == 4, "fury cruelty 5, arms deflection 4")

-- no refunds allowed -> trainer message
canRefund = false
committed[layout[1][1].nodeID] = 1
M.log = {}
AS.SpecNow(b.id)
check(M.LogHas("class trainer"), "no refund: tells you to visit a trainer")
canRefund = true
committed[layout[1][1].nodeID] = 0

-- other classes in the list, sharing
local mage = AS.Import("https://www.wowhead.com/forever/talent-calc/mage/abcdef-235-0-5/0aaBBc2A", "Frost AoE")
check(mage and mage.class == "MAGE", "imports a mage build while on a warrior")
AS.ShowUI("MAGE")
local text = AS.ChatText(b)
local _, newMsg = M.chatFilters["CHAT_MSG_GUILD"](nil, "CHAT_MSG_GUILD", text, "Bob")
check(text:find("^%[Auto Super Spec: Prot leveling %- warrior:") and newMsg:find("|Hgarrmission:autosuperspec:warrior:", 1, true), "chat link: " .. text)
AS.SetActive(nil)
check(AS.char.active == nil, "deactivate")
SlashCmdList.AUTOSUPERSPEC("debug")
check(_G.AutoSuperSpecCopyFrame and AutoSuperSpecCopyFrame:IsShown(), "/as debug opens copy window")
print(AS.Talents.DebugText():sub(1, 400))
-- calculator page (same window)
AS.ShowBuild(b.id)
local F = AutoSuperSpecFrame
local C = F.calcPage
check(F.page == "calc" and C:IsShown() and not F.listPage:IsShown(), "build opens as a page in the same window")
check(C.trees[3].title:GetText() == "Protection" and C.trees[3].points:GetText() == 32, "tree header Protection 32")
local function btn(tree, name)
    for _, x in ipairs(C.trees[tree].buttons) do if x.talent and x.talent.name == name then return x end end
end
local anti = btn(3, "Anticipation")
check(anti.rank:GetText() == "5/5" and anti.step:GetText() == 1, "Anticipation 5/5, first point at step 1")
check(btn(1, "Improved Heroic Strike").rank:GetText() == "0/3", "untaken talent shows 0/3")
anti:GetScript("OnEnter")(anti)
local tip = table.concat(M.tipLines, "|")
check(tip:find("Rank 5/5", 1, true) and tip:find("20 Rage || Melee Range", 1, true) and tip:find("Instant || 6 sec cooldown", 1, true)
    and tip:find("Anticipation rank 5 full text", 1, true), "tooltip shows the game's full talent tooltip (cost, range, cooldown, text): " .. tip)
local _, dupes = tip:gsub("Rank %d/5", "")
check(dupes == 1, "the game's own rank line isn't repeated")
local row = C.order.rows[2]
row:GetScript("OnEnter")(row)
tip = table.concat(M.tipLines, "|")
check(tip:find("Rank 2/5", 1, true) and tip:find("Anticipation rank 2 full text", 1, true) and tip:find("Right-click to remove this point", 1, true), "learning-order rows show the talent at that point's rank: " .. tip)
check(C.order.rows[1].level:GetText() == "Lvl 10" and C.order.rows[1].text:GetText() == "Anticipation" and C.order.rows[1].rank:GetText() == "1/5", "order list row 1")
C.order.rows[2]:GetScript("OnEnter")(C.order.rows[2])
local c1, c2, c6 = C.order.rows[1].bg._color, C.order.rows[2].bg._color, C.order.rows[6].bg._color
check(c1 == c2 and c1 ~= c6, "hovering highlights every point of that talent in the same color (" .. tostring(c1) .. " vs " .. tostring(c6) .. ")")
C.order.rows[2]:GetScript("OnLeave")(C.order.rows[2])
check(#C.trees[3].lines > 0 and C.trees[3].lines[1]:IsShown(), "prerequisite arrow drawn")
-- edit: can't break the prerequisite
local cb = btn(3, "Concussion Blow")
cb:GetScript("OnClick")(cb, "RightButton")
check(C.message:GetText():find("Can't remove that point") and cb.rank:GetText() == "2/2", "removing Concussion Blow is refused (Shield Slam needs it): " .. C.message:GetText())
-- full build: no points left
local ihs = btn(1, "Improved Heroic Strike")
ihs:GetScript("OnClick")(ihs, "LeftButton")
check(C.message:GetText() == "You have no talent points left." and ihs.rank:GetText() == "0/3", "51 points max")
-- remove last Focused Rage point, add Improved Heroic Strike instead, save
local fr = btn(3, "Focused Rage")
fr:GetScript("OnClick")(fr, "RightButton")
check(fr.rank:GetText() == "0/1" and C.save:IsEnabled() ~= false, "point removed")
ihs:GetScript("OnClick")(ihs, "LeftButton")
check(ihs.rank:GetText() == "1/3" and ihs.step:GetText() == 51, "point added at the end of the order (step 51)")
C.save:GetScript("OnClick")(C.save)
check(C.message:GetText() == "Saved." and AS.GetBuild(b.id).code:find("0a$"), "saved: " .. AS.GetBuild(b.id).code)
-- save as new
C.nameBox:SetText("Prot copy test")
C.saveNew:GetScript("OnClick")(C.saveNew)
check(C.message:GetText():find("already saved"), "identical build isn't saved twice")
-- back to the list
C.nameBox:SetText("Prot leveling")
C.back:GetScript("OnClick")(C.back)
check(F.page == "list" and F.listPage:IsShown() and not C:IsShown(), "Back returns to the build list")
-- new build from scratch
AS.NewBuild()
check(F.page == "calc" and C.nameBox:GetText() == "New Warrior build" and C.trees[3].points:GetText() == 0, "new build starts empty")
anti = btn(3, "Anticipation")
for _ = 1, 5 do anti:GetScript("OnClick")(anti, "LeftButton") end
local iw = btn(3, "Iron Will")
iw:GetScript("OnClick")(iw, "LeftButton")
local ls = btn(3, "Last Stand")
ls:GetScript("OnClick")(ls, "LeftButton")
check(C.message:GetText() == "Requires 10 points in Protection" and ls.rank:GetText() == "0/1", "tier rule enforced: " .. C.message:GetText())
-- unsaved changes: Back asks first
C.back:GetScript("OnClick")(C.back)
check(M.LastPopup().which == "AUTOSUPERSPEC_DISCARD" and F.page == "calc", "Back with unsaved changes asks to discard")
C.nameBox:SetText("Prot opener")
C.save:GetScript("OnClick")(C.save)
local nb
for _, x in pairs(AS.db.builds) do if x.name == "Prot opener" then nb = x end end
check(nb and nb.code == "2bbbbbe" and nb.points == 6, "new build saved: " .. tostring(nb and nb.code))
C.share:GetScript("OnClick")(C.share)
for _, r in ipairs(F.menu.rows) do if r:IsShown() and r.label:GetText() == "Chat message I'm typing" then r:GetScript("OnClick")(r) end end
check(M.chatBox:GetText():find("[Auto Super Spec: Prot opener - warrior:2bbbbbe]", 1, true), "share from calculator: " .. M.chatBox:GetText())
-- another class through the view mode: full calculator on a warrior
check(viewOpened[1] == "801@60", "mage tree read through the talent view mode: " .. tostring(viewOpened[1]))
check(AS.db.talentData.MAGE and AS.db.talentData.MAGE.source == "view", "mage tree saved for the account")
AS.ShowBuild(mage.id)
check(C.trees[1]:IsShown() and C.trees[1].title:GetText() == "Arcane" and C.trees[3].title:GetText() == "Frost", "mage build opens on the real mage trees")
local focus
for _, x in ipairs(C.trees[1].buttons) do if x.talent and x.talent.name == "Arcane Focus" then focus = x end end
check(focus.rank:GetText() == "5/5", "mage build ranks shown (Arcane Focus maxed using the real max rank)")
focus:GetScript("OnEnter")(focus)
check(table.concat(M.tipLines, "|"):find("Arcane Focus rank 5 full text", 1, true) and table.concat(M.tipLines, "|"):find("6 sec cooldown", 1, true), "mage tooltip shows the saved full tooltip on a warrior")
check(AS.db.talentData.MAGE.trees[1][2].tips[3][3].r == "Melee Range", "full tooltip lines saved for every rank")
local missiles
for _, x in ipairs(C.trees[1].buttons) do if x.talent and x.talent.name == "Improved Arcane Missiles" then missiles = x end end
missiles:GetScript("OnClick")(missiles, "LeftButton")
check(missiles.rank:GetText() == "2/5", "added a point to a mage talent")
C.save:GetScript("OnClick")(C.save)
check(C.message:GetText() == "Saved." and AS.GetBuild(mage.id).code == "0aabbbbbc2aaaaa0c", "mage build edited and saved on a warrior: " .. AS.GetBuild(mage.id).code)
check(not C.toggle:IsEnabled() and not C.spec:IsEnabled(), "can't activate a mage build on a warrior")
AS.NewBuild("MAGE")
check(F.page == "calc" and C.nameBox:GetText() == "New Mage build" and C.trees[2].title:GetText() == "Fire", "new mage build from a warrior")
-- the empty draft is unchanged, so opening another build does not ask
-- a class with no saved tree stays read-only
local druid = AS.Import("druid:0aab", "Balance")
AS.ShowBuild(druid.id)
check(C.noData:IsShown() and C.noData:GetText():find("Log in a Druid once") and C.order.rows[1].text:GetText():find("Tree 1, talent a"), "class with no saved tree: read-only order + how to get it")
check(C.scanButton:IsShown(), "calculator offers a scan button when the tree is missing")
-- scan box on the list page
local SB = F.scanBox
check(SB.title:GetText():find("Talent trees: 2 / 9") and SB.text:GetText():find("Druid") and SB.button:GetText() == "Scan talent trees", "scan box shows missing trees: " .. SB.title:GetText() .. " " .. SB.text:GetText())
-- the druid tree becomes readable: scanning from the calculator fills it in place
readable[1102] = true -- only the druid's 2nd spec has a tree
C.scanButton:GetScript("OnClick")(C.scanButton)
check(AS.db.talentData.DRUID and C.trees[1]:IsShown() and not C.scanButton:IsShown(), "scan from the calculator loads the tree right away")
C.back:GetScript("OnClick")(C.back)
check(SB.title:GetText():find("3 / 9"), "scan box updated on the list page: " .. SB.title:GetText())
-- everything readable: rescan from the list page
for _, sp in ipairs({ 201, 301, 401, 501, 701, 901 }) do readable[sp] = true end
C.back:GetScript("OnClick")(C.back)
SB.button:GetScript("OnClick")(SB.button)
check(SB.title:GetText():find("9 / 9") and SB.button:GetText() == "Rescan" and M.LogHas("talent trees saved: 9 of 9"), "all trees saved, button turns into Rescan")
M.inCombat = true
SB.button:GetScript("OnClick")(SB.button)
check(M.LogHas("can't read talent trees in combat"), "no scanning in combat")
M.inCombat = false
-- last scan date + game version
check(SB.last:GetText():find("^Scanned %d%d %a+ %d%d%d%d, %d%d:%d%d\nGame 1%.60%.1 %(70790%)$"), "last scan date and game version shown: " .. SB.last:GetText())
-- auto-scan every time the window opens: only missing/outdated trees
F:Hide()
local opened = #viewOpened
AS.ShowUI()
check(#viewOpened == opened and SB.auto:GetChecked(), "auto-scan on open skips trees that are up to date")
F:Hide()
buildNumber = "70800" -- game update
AS.ShowUI()
check(#viewOpened > opened and AS.db.talentData.MAGE.build == "70800" and SB.last:GetText():find("70800"), "after a game update, opening the window re-reads the trees")
F:Hide()
SB.auto:SetChecked(false)
SB.auto:GetScript("OnClick")(SB.auto)
check(AS.db.autoScan == false, "auto-scan can be turned off")
buildNumber = "70900"
opened = #viewOpened
AS.ShowUI()
check(#viewOpened == opened, "with auto-scan off, opening the window doesn't scan")
SB.auto:SetChecked(true)
SB.auto:GetScript("OnClick")(SB.auto)
buildNumber = "70790"
-- the warrior tree is saved too, for other characters
check(AS.db.talentData.WARRIOR and AS.db.talentData.WARRIOR.source == "live", "own tree saved on login")
function UnitClass() return "Mage", "MAGE" end
local wl, wm = AS.Talents.Layout("WARRIOR")
check(wl and wm.saved and wl[3][2].name == "Anticipation" and wl[3][2].rank == 0 and AS.Talents.Description(wl[3][2], 2) == "Anticipation rank 2 text", "another character sees the saved warrior tree")
function UnitClass() return "Warrior", "WARRIOR" end
-- sharing to any chat
local sent = {}
C_ChatInfo = { SendChatMessage = function(msg, chatType, lang, target) sent[#sent + 1] = { msg = msg, type = chatType, target = target } end }
function IsInGroup() return true end
function IsInRaid() return false end
function IsInGuild() return true end
function UnitIsPlayer(u) return u == "target" end
function UnitIsUnit() return false end
function UnitName(u) return "Bob", "Stormrage" end
function GetChannelList() return 1, "General", false, 2, "Trade", false, 5, "LookingForGroup", true end
AS.ShowUI("WARRIOR")
local card = F.cards[1]
card.more:GetScript("OnClick")(card.more)
local function menuTexts() local t = {} for _, r in ipairs(F.menu.rows) do if r:IsShown() then t[#t + 1] = r.label:GetText() end end return t end
local function clickMenu(label) for _, r in ipairs(F.menu.rows) do if r:IsShown() and r.label:GetText() == label then r:GetScript("OnClick")(r) return true end end end
check(clickMenu("Share..."), "build menu has Share...")
local labels = table.concat(menuTexts(), ",")
check(labels:find("Party") and labels:find("Guild") and labels:find("Officer") and labels:find("Whisper Bob") and labels:find("1. General") and labels:find("2. Trade") and not labels:find("LookingForGroup") and not labels:find("Raid"), "share menu lists your chats: " .. labels)
clickMenu("Guild")
check(sent[1] and sent[1].type == "GUILD" and sent[1].msg:find("^%[Auto Super Spec: "), "sent to guild")
card.more:GetScript("OnClick")(card.more); clickMenu("Share..."); clickMenu("2. Trade")
check(sent[2].type == "CHANNEL" and sent[2].target == 2, "sent to channel 2 (Trade)")
card.more:GetScript("OnClick")(card.more); clickMenu("Share..."); clickMenu("Whisper Bob")
check(sent[3].type == "WHISPER" and sent[3].target == "Bob-Stormrage", "whispered target")
card.more:GetScript("OnClick")(card.more); clickMenu("Share..."); clickMenu("Chat message I'm typing")
check(M.chatBox:GetText():find("[Auto Super Spec: ", 1, true), "inserted into chat box")
-- shift-click a card: link into the message being typed
local typing = { _text = "look at this: " }
function ChatEdit_GetActiveWindow() return { Insert = function(_, t) typing._text = typing._text .. t end } end
function IsShiftKeyDown() return true end
card:GetScript("OnClick")(card, "LeftButton")
check(typing._text:find("^look at this: %[Auto Super Spec: "), "shift-click links into the active chat input: " .. typing._text)
function IsShiftKeyDown() return false end
ChatEdit_GetActiveWindow = nil

-- minimap button
local mb = AutoSuperSpecMinimapButton
check(mb ~= nil and mb:IsShown(), "minimap button exists")
AS.SetActive(b.id)
mb:GetScript("OnEnter")(mb)
local tipText = table.concat(M.tipLines, "|")
check(tipText:find("Following: |cffffffffProt leveling", 1, true), "minimap tooltip shows the build: " .. tipText)
mb:GetScript("OnClick")(mb, "RightButton")
check(F.page == "calc" and C.nameBox:GetText() == "Prot leveling", "right-click opens the active build in the calculator")
mb:GetScript("OnClick")(mb, "LeftButton")
SlashCmdList.AUTOSUPERSPEC("minimap")
check(not mb:IsShown(), "/ass minimap hides it")
-- card click opens the calculator
AS.ShowUI("WARRIOR")
F.cards[1]:GetScript("OnClick")(F.cards[1], "LeftButton")
check(F.page == "calc" and C.nameBox:GetText() == F.cards[1].build.name, "clicking a build card opens it in the calculator")
check(M.LogHas("Soeta's"), "chat prefix carries the new name")
-- closing in combat
AS.ShowUI()
M.inCombat = true
F.CloseButton:GetScript("OnClick")(F.CloseButton)
check(not F:IsShown(), "close button works in combat")
AS.ShowUI()
SlashCmdList.AUTOSUPERSPEC("")
check(not F:IsShown(), "/ass closes it in combat")
M.inCombat = false
print("ALL TRAITS TESTS PASSED")
M.inCombat = true
M.Fire("ADDON_ACTION_BLOCKED", "AutoSuperSpec", "SomeProtectedFunction()")
M.Fire("ADDON_ACTION_BLOCKED", "AutoSuperSpec", "SomeProtectedFunction()")
M.Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
local n = 0
for _, l in ipairs(M.log) do if l:find("blocked") then n = n + 1 end end
check(n == 1 and M.LogHas("SomeProtectedFunction%(%)|r %(in combat%)"), "reports a blocked action once, only for this addon")
print("ALL BLOCK TESTS PASSED")
