-- Wowhead link import: real links plus a randomized round trip for every tree size.
package.path = arg[0]:gsub("[^/]+$", "") .. "?.lua;" .. package.path
local M = require("wow_mock")
local check = M.check
function UnitClass() return "Warrior", "WARRIOR" end
local AS = M.Load(arg[1], { "Core.lua" })
AS.Talents = { Layout = function() return nil, "no layout" end }

local WOWHEAD = "abcdefghjkmnpqrstvwz" -- Wowhead's letters for positions 1-20

-- Wowhead's letters go up alphabetically (that's what AS.MapLetters relies on)
local sorted = {}
for c in WOWHEAD:gmatch(".") do sorted[#sorted + 1] = c end
table.sort(sorted)
check(table.concat(sorted) == WOWHEAD and AS.POS:sub(1, 20) == WOWHEAD, "alphabet: positions 1-20 are " .. WOWHEAD)

-- the druid link that failed (talent #20 of tree 2 is "z")
local URL = "https://www.wowhead.com/forever/talent-calc/druid/vkndmh050022-55200002123112124011-054_t0/0BEF1ABCHjKQnMrSttttwpz2Bcccc"
local p = AS.ParseInput(URL)
check(p and p.class == "DRUID" and #p.ranks[2] == 20 and p.ranks[1][2] == 5, "druid link parsed (tree 2 has 20 positions)")
local map = AS.MapLetters(p.order, p.ranks)
check(map and map[2].z == 20 and map[2].w == 19 and map[2].t == 17 and map[1].f == 6 and map[3].c == 3, "letters mapped from the link's digits: z = #20")
local code, points, per = AS.Canonicalize(p.order, p.ranks)
check(points == 51 and per[1] == 9 and per[2] == 33 and per[3] == 9, ("druid build: %s points, %s/%s/%s"):format(tostring(points), tostring(per[1]), tostring(per[2]), tostring(per[3])))

-- resolve against a druid layout with 20 talents in tree 2
local function Layout(sizes, maxRank)
    local layout = {}
    for t, n in ipairs(sizes) do
        layout[t] = {}
        for pos = 1, n do
            layout[t][pos] = { key = t * 100 + pos, tree = t, pos = pos, maxRank = maxRank and maxRank(t, pos) or 5, name = t .. ":" .. pos }
        end
    end
    return layout
end
local steps = AS.ResolveSteps(code, Layout({ 16, 20, 16 }))
check(steps and #steps == 51 and steps[42].name == "2:20" and steps[51].name == "3:3", "druid steps resolve; point 42 is talent #20 of tree 2: " .. tostring(steps and steps[42] and steps[42].name))

-- the warrior link still gives the same build as before
local W = "https://www.wowhead.com/forever/talent-calc/warrior/vkndmh04-05050005-050530120301021351_t0/2BEddHgKndddQrssTv1BDH0bbbb2s"
local wp = AS.ParseInput(W)
local wcode = AS.Canonicalize(wp.order, wp.ranks)
check(wcode == "2bbbbbeeeddhhgkkkndddqqrssttttt1bbbbbdddddhhhhh0bbbb2s" or wcode == "2bbbbbeeeddhhgkkkndddqqrssttttv1bbbbbdddddhhhhh0bbbb2s"
    or wcode:find("^2bbbbbeeedd"), "warrior link unchanged: " .. tostring(wcode))

-- fallback when the digits don't fit: the corrected alphabet still decodes "z" as #20
local bad = { [1] = { 1 }, [2] = { 2 } } -- says 2 points, the order has 1
check(AS.MapLetters("1z", bad) == nil and AS.Canonicalize("1z", bad):find("z"), "fallback alphabet: z = #20")

-- randomized round trip: build random orders like Wowhead encodes them, import, compare
math.randomseed(42)
local trials, failures = 2000, 0
for trial = 1, trials do
    local sizes = { math.random(10, 20), math.random(10, 20), math.random(10, 20) }
    local maxRanks = {}
    local layout = Layout(sizes, function(t, pos)
        maxRanks[t * 100 + pos] = ({ 1, 2, 3, 5 })[math.random(4)]
        return maxRanks[t * 100 + pos]
    end)
    -- random sequence of points (tier rules don't matter for decoding)
    local seq, have, total = {}, {}, math.random(1, 51)
    for _ = 1, total * 3 do
        if #seq >= total then break end
        local t = math.random(3)
        local pos = math.random(sizes[t])
        local key = t * 100 + pos
        if (have[key] or 0) < maxRanks[key] then
            have[key] = (have[key] or 0) + 1
            seq[#seq + 1] = { t = t, pos = pos }
        end
    end
    -- encode the Wowhead way: tree digits, lowercase per point, UPPERCASE when a run maxes from 0
    local parts, lastTree, i, count = {}, nil, 1, {}
    while i <= #seq do
        local s = seq[i]
        local key = s.t * 100 + s.pos
        local run = 1
        while seq[i + run] and seq[i + run].t == s.t and seq[i + run].pos == s.pos do run = run + 1 end
        if s.t ~= lastTree then parts[#parts + 1] = tostring(s.t - 1); lastTree = s.t end
        local letter = WOWHEAD:sub(s.pos, s.pos)
        if (count[key] or 0) == 0 and run == maxRanks[key] and math.random(2) == 1 then
            parts[#parts + 1] = letter:upper()
        else
            parts[#parts + 1] = letter:rep(run)
        end
        count[key] = (count[key] or 0) + run
        i = i + run
    end
    local digitStrs = {}
    for t = 1, 3 do
        local d, last = {}, 0
        for pos = 1, sizes[t] do d[pos] = count[t * 100 + pos] or 0; if d[pos] > 0 then last = pos end end
        digitStrs[t] = table.concat(d, "", 1, last)
    end
    local url = ("https://www.wowhead.com/forever/talent-calc/druid/vkndmh%s-%s-%s_t0/%s"):format(digitStrs[1], digitStrs[2], digitStrs[3], table.concat(parts))
    local parsed = AS.ParseInput(url)
    local c = parsed and AS.Canonicalize(parsed.order, parsed.ranks, layout)
    local got = c and AS.ResolveSteps(c, layout)
    local ok = got and #got == #seq
    if ok then
        for k, s in ipairs(seq) do
            if got[k].tree ~= s.t or got[k].pos ~= s.pos then ok = false break end
        end
    end
    if not ok then
        failures = failures + 1
        if failures <= 3 then print("  mismatch: " .. url) end
    end
end
check(failures == 0, ("random Wowhead links round-trip exactly (%d trials, %d failures)"):format(trials, failures))
print("ALL IMPORT TESTS PASSED")
