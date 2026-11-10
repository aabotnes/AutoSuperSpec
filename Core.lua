-- Auto Super Spec core: helpers, build codes, link parsing and the build library.
--
-- Wowhead talent-order format (the last part of a talent-calc link, e.g. "1abbbb2A"):
--   digit 0/1/2  -> switch to talent tree 1/2/3
--   lowercase    -> one point in the talent at that position of the tree
--   UPPERCASE    -> put points into that talent until it is maxed
-- Positions are lettered "abcdefghjkmnpqrstvwz" (no i, l, o, u, x, y: talent #20
-- is "z") and count a tree's talents top to bottom, left to right. Auto Super
-- Spec maps them onto the in-game talents at run time, so it follows whatever
-- trees the game has. For Wowhead links it maps letters to positions from the
-- link's own rank digits (see AS.MapLetters), so an unexpected letter can't
-- break an import.

local ADDON_NAME, AS = ...
_G.AutoSuperSpec = AS
AS.name = ADDON_NAME
AS.TITLE = "|cffc27dff[Soeta's]|r |cff33ff99Auto Super Spec|r"

-- Wowhead's letters for talent positions 1-20; "x" and "y" are only our own
-- extension for trees with more than 20 talents.
AS.POS = "abcdefghjkmnpqrstvwzxy"
AS.MAX_NAME = 40
AS.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local FALLBACK_CLASS_COLORS = {
    WARRIOR = "c69b6d", PALADIN = "f48cba", HUNTER = "aad372", ROGUE = "fff468", PRIEST = "ffffff",
    SHAMAN = "0070dd", MAGE = "3fc7eb", WARLOCK = "8788ee", DRUID = "ff7c0a",
}

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

function AS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(AS.TITLE .. ": " .. msg)
end

function AS.Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

function AS.After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

function AS.SlugToClass(slug)
    return ((slug or ""):upper():gsub("[^%a]", ""))
end

function AS.ClassToSlug(token)
    return (token or ""):lower()
end

function AS.ClassName(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    if names and names[token] then return names[token] end
    token = token or "?"
    return token:sub(1, 1) .. token:sub(2):lower()
end

function AS.ClassColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return ("%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return FALLBACK_CLASS_COLORS[token] or "ffd100"
end

function AS.ClassRGB(token)
    local hex = AS.ClassColor(token)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function AS.PlayerClass()
    local _, token = UnitClass("player")
    return token
end

function AS.CleanName(name)
    name = AS.Trim((name or ""):gsub("[%[%]|:]", ""))
    if #name > AS.MAX_NAME then name = name:sub(1, AS.MAX_NAME) end
    return name
end

local function Split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
end

------------------------------------------------------------------------------
-- Build codes
------------------------------------------------------------------------------

-- Turns a code into the ordered list of talents to learn, one entry per point.
-- layout[tree][position] = talent (see Talents.lua)
function AS.ResolveSteps(code, layout)
    local steps, counts, tree = {}, {}, nil
    for i = 1, #code do
        local c = code:sub(i, i)
        if c:match("%d") then
            tree = tonumber(c) + 1
        else
            local p = AS.POS:find(c:lower(), 1, true)
            if not p or not tree then
                return nil, "this build code is damaged (unexpected '" .. c .. "')."
            end
            local t = layout[tree] and layout[tree][p]
            if not t then
                return nil, ("the build uses talent #%d of tree %d, which your talent tree doesn't have. Type /ass debug and send the output to the addon author."):format(p, tree)
            end
            local n = 1
            if c ~= c:lower() then n = t.maxRank - (counts[t.key] or 0) end
            for _ = 1, n do
                counts[t.key] = (counts[t.key] or 0) + 1
                steps[#steps + 1] = t
            end
        end
    end
    return steps
end

-- Maps a Wowhead order's letters to talent positions using the link's rank
-- digits: Wowhead's letters go up alphabetically with the position, so the
-- n-th distinct letter used in a tree is the n-th talent with points. Every
-- letter's point count is checked against its digit. Returns
-- map[tree][letter] = position, or nil if the digits don't fit.
function AS.MapLetters(order, ranks)
    if not ranks then return nil end
    local used, tree = {}, nil
    for i = 1, #order do
        local c = order:sub(i, i)
        if c:match("%d") then
            tree = tonumber(c) + 1
        elseif tree and c:match("%a") then
            local l = c:lower()
            used[tree] = used[tree] or {}
            local e = used[tree][l] or { n = 0 }
            used[tree][l] = e
            if c ~= l then e.max = true else e.n = e.n + 1 end
        end
    end
    local map = {}
    for t, set in pairs(used) do
        local digits = ranks[t]
        if type(digits) ~= "table" then return nil end
        local letters, positions = {}, {}
        for l in pairs(set) do letters[#letters + 1] = l end
        table.sort(letters)
        for p, r in ipairs(digits) do
            if r > 0 then positions[#positions + 1] = p end
        end
        if #letters ~= #positions then return nil end
        map[t] = {}
        for i, l in ipairs(letters) do
            local p, e = positions[i], set[l]
            if (e.max and e.n > digits[p]) or (not e.max and e.n ~= digits[p]) then return nil end
            map[t][l] = p
        end
    end
    return map
end

-- Rewrites a Wowhead order into Auto Super Spec's form: one letter per point. UPPERCASE
-- "max it" letters are expanded with the in-game max rank when the build is for
-- your own class, or with the rank numbers in the Wowhead link otherwise.
-- Returns code, points (nil if some couldn't be counted), pointsPerTree.
function AS.Canonicalize(order, ranks, layout)
    local out, counts, perTree = {}, {}, {}
    local tree, lastTree, points, unknown = nil, nil, 0, false
    local map = AS.MapLetters(order, ranks)
    for i = 1, #order do
        local c = order:sub(i, i)
        if c:match("%d") then
            tree = tonumber(c) + 1
        else
            local p = map and map[tree] and map[tree][c:lower()] or AS.POS:find(c:lower(), 1, true)
            if not p or not tree then
                return nil, "the talent order in that link is damaged (unexpected '" .. c .. "')."
            end
            if tree ~= lastTree then
                out[#out + 1] = tostring(tree - 1)
                lastTree = tree
            end
            local key = tree * 1000 + p
            local n = 1
            if c ~= c:lower() then
                local maxRank
                if layout and layout[tree] and layout[tree][p] then
                    maxRank = layout[tree][p].maxRank
                elseif ranks and ranks[tree] and ranks[tree][p] then
                    maxRank = ranks[tree][p]
                end
                n = maxRank and math.max(0, maxRank - (counts[key] or 0)) or nil
            end
            local letter = AS.POS:sub(p, p)
            if letter == "" then return nil, "that tree has more talents than Auto Super Spec can store." end
            if n then
                out[#out + 1] = letter:rep(n)
                counts[key] = (counts[key] or 0) + n
                points = points + n
                perTree[tree] = (perTree[tree] or 0) + n
            else
                out[#out + 1] = letter:upper() -- keep "max it", resolved in game later
                unknown = true
            end
        end
    end
    if points == 0 and not unknown then
        return nil, "that build has no talent points in it."
    end
    return table.concat(out), (not unknown) and points or nil, perTree
end

-- Checks a resolved build against the talent rules, starting from zero points.
function AS.Validate(steps)
    local problems, rank, treePoints = {}, {}, {}
    for i, t in ipairs(steps) do
        local r = (rank[t.key] or 0) + 1
        if r > t.maxRank then
            problems[#problems + 1] = ("Point %d: %s is already at max rank."):format(i, t.name)
        end
        local need = (t.tier - 1) * 5
        if (treePoints[t.tree] or 0) < need then
            problems[#problems + 1] = ("Point %d: %s needs %d points higher up its tree first."):format(i, t.name, need)
        end
        for _, pre in ipairs(t.requires or {}) do
            if (rank[pre.key] or 0) < pre.maxRank then
                problems[#problems + 1] = ("Point %d: %s needs %s maxed first."):format(i, t.name, pre.name)
            end
        end
        rank[t.key] = r
        treePoints[t.tree] = (treePoints[t.tree] or 0) + 1
        if #problems >= 5 then break end
    end
    return problems
end

-- Compares the rank numbers in a Wowhead link with the in-game trees. A
-- mismatch means Auto Super Spec read the trees in a different order than Wowhead.
function AS.CheckRanks(ranks, layout)
    if not ranks then return true end
    for tree = 1, 3 do
        for p, r in ipairs(ranks[tree] or {}) do
            if r > 0 then
                local t = layout[tree] and layout[tree][p]
                if not t or t.maxRank < r then
                    return false, ("Wowhead puts %d point(s) in talent #%d of tree %d, but %s."):format(r, p, tree,
                        t and (t.name .. " only has " .. t.maxRank .. " rank(s)") or "that talent doesn't exist in game")
                end
            end
        end
    end
    return true
end

------------------------------------------------------------------------------
-- Parsing what the user pastes
------------------------------------------------------------------------------

-- "vkndmh04-05050005-050530120301021351_t0" -> rank digits per tree. Wowhead
-- Forever links start with a 6-letter tag glued to tree 1, so only the digits
-- at the end of the first part count.
function AS.ParseRanks(segment)
    segment = (segment or ""):gsub("_.*$", "")
    local parts = Split(segment, "-")
    while #parts > 3 do table.remove(parts, 1) end
    local ranks, offset = {}, 3 - #parts
    for i, part in ipairs(parts) do
        local list = {}
        for d in part:match("(%d*)$"):gmatch("%d") do list[#list + 1] = tonumber(d) end
        ranks[i + offset] = list
    end
    return ranks
end

-- Builds an order from rank numbers alone (link without a talent order):
-- the tree with the most points first, top to bottom.
local function OrderFromRanks(ranks)
    local trees = {}
    for tree = 1, 3 do
        local total = 0
        for _, r in ipairs(ranks[tree] or {}) do total = total + r end
        if total > 0 then trees[#trees + 1] = { tree = tree, total = total } end
    end
    table.sort(trees, function(a, b) return a.total > b.total end)
    local out = {}
    for _, info in ipairs(trees) do
        out[#out + 1] = tostring(info.tree - 1)
        for p, r in ipairs(ranks[info.tree]) do
            out[#out + 1] = AS.POS:sub(p, p):rep(r)
        end
    end
    return table.concat(out)
end

-- Accepts a Wowhead talent-calc link, an Auto Super Spec chat link, or "class:code".
function AS.ParseInput(text)
    text = AS.Trim(text)
    if text == "" then return nil, "paste a Wowhead talent calculator link first." end

    local name, slug, code = text:match("%[Auto Super Spec: (.-) %- ([%a%-]+):(%w+)%]")
    if not slug then name, slug, code = text:match("%[AutoSpec: (.-) %- ([%a%-]+):(%w+)%]") end
    if slug then
        return { class = AS.SlugToClass(slug), order = code, name = name }
    end

    local rankSeg, order
    slug, rankSeg, order = text:match("talent%-calc/([%a%-]+)/([^/%s?#]*)/(%w+)")
    if slug then
        return { class = AS.SlugToClass(slug), order = order, ranks = AS.ParseRanks(rankSeg) }
    end

    slug, rankSeg = text:match("talent%-calc/([%a%-]+)/([^/%s?#]+)")
    if slug then
        local ranks = AS.ParseRanks(rankSeg)
        local guessed = OrderFromRanks(ranks)
        if guessed == "" then
            return nil, "that link has no talents in it."
        end
        return { class = AS.SlugToClass(slug), order = guessed, ranks = ranks, guessedOrder = true }
    end

    slug, code = text:match("^([%a%-]+):(%w+)$")
    if slug then
        return { class = AS.SlugToClass(slug), order = code }
    end

    return nil, "couldn't read that. Paste a Wowhead talent calculator link (wowhead.com/.../talent-calc/...) or an Auto Super Spec build."
end

------------------------------------------------------------------------------
-- Build library (saved for the whole account)
------------------------------------------------------------------------------

-- Talent points available at max level (first point at level 10).
function AS.MaxPoints()
    local cap = (type(GetMaxPlayerLevel) == "function" and GetMaxPlayerLevel()) or 60
    if type(cap) ~= "number" or cap < 10 then cap = 60 end
    return cap - 9
end

-- Turns a list of talents (one per point, in order) into a build code.
function AS.EncodeSteps(steps)
    local out, lastTree = {}, nil
    for _, t in ipairs(steps) do
        if t.tree ~= lastTree then
            out[#out + 1] = tostring(t.tree - 1)
            lastTree = t.tree
        end
        out[#out + 1] = AS.POS:sub(t.pos, t.pos)
    end
    return table.concat(out)
end

local function TreeSummary(perTree)
    return ("%d/%d/%d"):format(perTree[1] or 0, perTree[2] or 0, perTree[3] or 0)
end

-- Saves a new build. Returns the build (or the existing copy of it).
function AS.AddBuild(class, name, code, quiet)
    local dup = AS.FindDuplicate(class, code)
    if dup then
        if not quiet then AS.Print(("you already have this build as |cffffd100%s|r."):format(dup.name)) end
        return dup, true
    end
    local _, points, perTree = AS.Canonicalize(code)
    name = AS.CleanName(name)
    if name == "" then name = AS.ClassName(class) .. " " .. TreeSummary(perTree or {}) end
    AS.db.nextId = (AS.db.nextId or 0) + 1
    local build = {
        id = AS.db.nextId, name = name, class = class, code = code,
        points = points, trees = TreeSummary(perTree or {}),
    }
    AS.db.builds[build.id] = build
    AS.RefreshUI()
    return build
end

-- Replaces a saved build's name and talents.
function AS.UpdateBuild(id, name, code)
    local b = AS.db.builds[id]
    if not b then return end
    local _, points, perTree = AS.Canonicalize(code)
    name = AS.CleanName(name)
    if name ~= "" then b.name = name end
    b.code, b.points, b.trees = code, points, TreeSummary(perTree or {})
    AS.RefreshUI()
    return b
end

function AS.GetBuild(id) return id and AS.db.builds[id] end

function AS.ActiveBuild() return AS.GetBuild(AS.char.active) end

function AS.BuildsForClass(class)
    local list = {}
    for _, b in pairs(AS.db.builds) do
        if b.class == class then list[#list + 1] = b end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

function AS.CountForClass(class)
    local n = 0
    for _, b in pairs(AS.db.builds) do if b.class == class then n = n + 1 end end
    return n
end

function AS.FindDuplicate(class, code)
    for _, b in pairs(AS.db.builds) do
        if b.class == class and b.code == code then return b end
    end
end

-- Adds a build from pasted text. Returns the build, or nil and an error.
function AS.Import(text, name, quiet)
    local parsed, err = AS.ParseInput(text)
    if not parsed then return nil, err end

    local ownClass = parsed.class == AS.PlayerClass()
    local layout
    layout, err = AS.Talents.Layout(parsed.class)
    if ownClass and not layout then return nil, err end
    if layout then
        local ok, why = AS.CheckRanks(parsed.ranks, layout)
        if not ok and not quiet then
            AS.Print("|cffff8800warning|r - " .. why .. " Auto Super Spec may be reading your trees differently from Wowhead. Type |cffffd100/ass debug|r and send the output to the addon author.")
        end
    end

    local code, points, perTree = AS.Canonicalize(parsed.order, parsed.ranks, layout)
    if not code then return nil, points end

    if layout then
        local steps, rerr = AS.ResolveSteps(code, layout)
        if not steps and ownClass then return nil, rerr end
        local problems = steps and AS.Validate(steps) or {}
        if #problems > 0 and not quiet then
            AS.Print("|cffff8800warning|r - this order breaks the talent rules and may stall:")
            for _, p in ipairs(problems) do AS.Print("  " .. p) end
        end
    end

    name = AS.CleanName(name)
    if name == "" then name = AS.CleanName(parsed.name or "") end
    local build, existed = AS.AddBuild(parsed.class, name, code, quiet)
    if existed then return build end
    build.points = points -- may be unknown for other classes' "max it" letters

    if not quiet then
        AS.Print(("imported |cff%s%s|r (%s%s)."):format(AS.ClassColor(build.class), build.name,
            AS.ClassName(build.class), points and (", " .. points .. " points") or ""))
        if parsed.guessedOrder then
            AS.Print("|cffff8800that link had no talent order|r, so points go top to bottom in your main tree. For an exact order, open \"Talent Order\" on Wowhead before you copy the link.")
        end
    end
    AS.RefreshUI()
    return build
end

function AS.Delete(id)
    local b = AS.db.builds[id]
    if not b then return end
    AS.db.builds[id] = nil
    if AS.char.active == id then AS.char.active = nil end
    AS.Print("deleted " .. b.name .. ".")
    AS.RefreshUI()
end

function AS.Rename(id, name)
    local b = AS.db.builds[id]
    name = AS.CleanName(name)
    if not b or name == "" then return end
    b.name = name
    AS.RefreshUI()
end

-- Points per tree as text, with tree names when we know them (own class).
function AS.TreeText(build, treeNames)
    local a, b, c = (build.trees or "0/0/0"):match("(%d+)/(%d+)/(%d+)")
    if treeNames and treeNames[1] then
        return ("%s %s  ·  %s %s  ·  %s %s"):format(treeNames[1], a or 0, treeNames[2] or "", b or 0, treeNames[3] or "", c or 0)
    end
    return build.trees or ""
end

function AS.RefreshUI() end -- replaced by UI.lua
