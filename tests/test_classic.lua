-- AutoSpec against a mocked classic talent API (druid).
package.path = arg[0]:gsub("[^/]+$", "") .. "?.lua;" .. package.path
local M = require("wow_mock")
local check = M.check
M.level = 9
function UnitClass() return "Druid", "DRUID" end

local trees = {
    { { "Nature's Grasp", 1, 2, 1 }, { "Improved Wrath", 1, 1, 5 }, { "Improved Nature's Grasp", 1, 3, 4 } },
    { { "Feral Aggression", 1, 3, 5 }, { "Ferocity", 1, 2, 5 }, { "Feral Instinct", 2, 1, 5 }, { "Feline Swiftness", 3, 1, 2 } },
    { { "Furor", 1, 3, 5 }, { "Improved Mark of the Wild", 1, 2, 5 } },
}
local ranks, spent = {}, 0
for t, tree in ipairs(trees) do ranks[t] = {}; for i in ipairs(tree) do ranks[t][i] = 0 end end
local function Unspent() return math.max(0, M.level - 9 - spent) end
function GetNumTalentTabs() return #trees end
function GetNumTalents(t) return #trees[t] end
function GetTalentInfo(t, i) local d = trees[t][i]; return d[1], "icon", d[2], d[3], ranks[t][i], d[4] end
function UnitCharacterPoints() return Unspent() end
local learned = {}
function LearnTalent(t, i)
    local d = trees[t][i]
    local treePts = 0
    for _, r in ipairs(ranks[t]) do treePts = treePts + r end
    if Unspent() > 0 and ranks[t][i] < d[4] and treePts >= (d[2] - 1) * 5 then
        C_Timer.After(0.1, function()
            ranks[t][i] = ranks[t][i] + 1
            spent = spent + 1
            learned[#learned + 1] = d[1]
            M.Fire("CHARACTER_POINTS_CHANGED", -1)
        end)
    end
end

local AS = M.Load(arg[1], { "Core.lua", "Talents.lua", "Engine.lua", "UI.lua", "Calculator.lua", "Minimap.lua" })
check(AS.Talents.Name() == "classic", "uses the classic backend")
local b = AS.Import("https://www.wowhead.com/forever/talent-calc/druid/vkndmh-14-5_t0/1abbbb2A", "")
check(b and b.code == "1abbbb2aaaaa" and b.points == 10 and b.trees == "0/5/5", "druid link: " .. tostring(b and b.code))
AS.SetActive(b.id)
for lvl = 10, 21 do
    M.level = lvl
    M.Fire("PLAYER_LEVEL_UP", lvl)
    M.Fire("CHARACTER_POINTS_CHANGED", 1)
    M.Advance(3)
end
local expected = { "Ferocity", "Feral Aggression", "Feral Aggression", "Feral Aggression", "Feral Aggression",
    "Improved Mark of the Wild", "Improved Mark of the Wild", "Improved Mark of the Wild", "Improved Mark of the Wild", "Improved Mark of the Wild" }
check(#learned == 10, "learned 10 points one level at a time, got " .. #learned)
for i, n in ipairs(expected) do check(learned[i] == n, ("point %d %s"):format(i, n)) end
check(M.LogHas("is complete"), "reports completion")

-- respec flow: talents wiped at a trainer, then "Spec now" with a bigger build
for t in ipairs(ranks) do for i in ipairs(ranks[t]) do ranks[t][i] = 0 end end
spent, learned = 0, {}
local b2 = AS.Import("druid:1BAccc", "Bear")
AS.SpecNow(b2.id)
check(M.LastPopup().which == "AUTOSUPERSPEC_APPLY", "spec now asks to confirm")
M.ClickPopup("AUTOSUPERSPEC_APPLY")
M.Advance(10)
check(#learned == 12 and learned[1] == "Feral Aggression" and learned[6] == "Ferocity" and learned[11] == "Feral Instinct", "spec now learns 12 points in order")

-- bad order pauses instead of looping
for t in ipairs(ranks) do for i in ipairs(ranks[t]) do ranks[t][i] = 0 end end
spent, learned, M.log = 0, {}, {}
local b3 = AS.Import("druid:1d", "Broken")
check(M.LogHas("needs 10 points"), "warns about tier requirement")
AS.SetActive(b3.id)
M.Advance(10)
check(#learned == 0, "activating doesn't learn anything")
M.level = 22
M.Fire("PLAYER_LEVEL_UP", 22)
M.Advance(10)
check(M.LogHas("paused") and #learned == 0, "pauses on a point it can't learn")

-- ask mode
AS.char.mode = "ask"
AS.state.paused = false
AS.SetActive(b.id)
M.level = 23
M.Fire("PLAYER_LEVEL_UP", 23)
M.Advance(2)
check(M.LastPopup().which == "AUTOSUPERSPEC_LEARN", "ask mode shows a Learn popup on ding")
M.ClickPopup("AUTOSUPERSPEC_LEARN")
M.Advance(3)
check(#learned > 0, "Learn button learns")

-- chat link round trip into a new build
SetItemRef("garrmission:autosuperspec:mage:0aaabbb2A:Frost AoE", "[Auto Super Spec: Frost AoE]", "LeftButton")
check(M.LastPopup().which == "AUTOSUPERSPEC_RECEIVE", "clicking a chat link offers import")
M.ClickPopup("AUTOSUPERSPEC_RECEIVE")
local found
for _, x in pairs(AS.db.builds) do if x.class == "MAGE" then found = x end end
check(found and found.name == "Frost AoE", "build from chat imported")
for _, c in ipairs({ "status", "list", "off", "on", "ask", "auto", "learn", "resume", "debug", "help", "" }) do SlashCmdList.AUTOSUPERSPEC(c) end
M.Advance(10)
check(true, "slash commands run")
print("ALL CLASSIC TESTS PASSED")
-- calculator on classic: open, add, save
AS.NewBuild()
local C = AutoSuperSpecFrame.calcPage
local fer
for _, x in ipairs(C.trees[2].buttons) do if x.talent and x.talent.name == "Ferocity" then fer = x end end
fer:GetScript("OnClick")(fer, "LeftButton")
check(fer.rank:GetText() == "1/5", "classic calculator adds a point")
C.save:GetScript("OnClick")(C.save)
check(C.message:GetText() == "Saved.", "classic calculator saves")
print("ALL CLASSIC CALC TESTS PASSED")
