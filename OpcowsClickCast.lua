-- Opcow's Click Cast: our own party frame, with rows of buttons under each member's health and
-- power bars. A button casts a spell or runs a macro on that member. Shift-click and right-click
-- cast other actions (see SetUp).
--
-- Blizzard's secure group header lays out the members' frames and gives each its unit, in combat
-- too. The buttons are children of a member's frame and take its unit when clicked, so they follow
-- it when the party changes. Making, placing and setting them up can only be done out of combat.

local OCC = {}
_G.OpcowsClickCast = OCC

-- between buttons
local GAP = 2
-- inside a member's frame, around the bars and the buttons
local PAD = 3
local HEALTH = 22
local POWER = 5
-- between members
local SPACING = 4
local MIN_WIDTH = 100
-- button size when the size option is 0
local SIZE = 24
-- the alpha of an out of range member's bars
local FADED = 0.4
-- the alpha of the tint over a health bar for a dispellable debuff
local DISPEL_ALPHA = 0.3
-- the group header's attributes for each order of the members. In a party the player is index 0, so
-- INDEX puts you first, then party1 to party4.
local SORTS = {
    group = { sortMethod = "INDEX" },
    role = { groupBy = "ASSIGNEDROLE", sortMethod = "INDEX" },
    name = { sortMethod = "NAME" },
}

local frame = CreateFrame("Frame")
-- [member frame] = { button, ... }
local buttons = {}
-- a Sync was asked for in combat, run it once combat ends
local pending = false
-- the group header lays itself out again on the next sync, see Sync
local refreshHeader = false
-- syncs on the next frame, defined below
local SyncSoon

local issecretvalue = issecretvalue or function() return false end

local function DB()
    OpcowsClickCastDB = OpcowsClickCastDB or {}
    local db = OpcowsClickCastDB
    db.actions = db.actions or {}
    -- from 0.8, buttons went on the right or left of Blizzard's party frames
    db.side = nil
    -- where our party frame is, moved by dragging it while it's unlocked
    if type(db.pos) ~= "table" or type(db.pos.x) ~= "number" or type(db.pos.y) ~= "number" then
        db.pos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -220 }
    end
    -- right-click casts the button's spell a rank lower, "down", or higher, "up"
    if db.right ~= "up" then db.right = "down" end
    -- from 0.5, shift-click has its own action now
    db.downrank = nil
    -- button size, 0 = SIZE
    if type(db.size) ~= "number" or db.size < 0 then db.size = 0 end
    -- buttons in a row under each member before the next row, 0 = all in one row
    if type(db.perRow) ~= "number" or db.perRow < 0 then db.perRow = 0 end
    -- a member's frame width, 0 = MIN_WIDTH. It's never narrower than its buttons.
    if type(db.width) ~= "number" or db.width < 0 then db.width = 0 end
    -- health bar height, 0 = HEALTH
    if type(db.barHeight) ~= "number" or db.barHeight < 0 then db.barHeight = 0 end
    -- the whole frame's scale in percent, 50 to 200
    if type(db.scale) ~= "number" or db.scale == 0 then db.scale = 100 end
    db.scale = math.min(200, math.max(50, db.scale))
    -- the bars' texture, by name, see Textures
    if type(db.texture) ~= "string" then db.texture = "Raid" end
    -- 0.10's default was Blizzard, from 0.11 it's Raid
    if not db.raidBars then
        if db.texture == "Blizzard" then db.texture = "Raid" end
        db.raidBars = true
    end
    -- from 0.7, which had 1 or 2 rows
    if db.rows == 2 and db.perRow == 0 then db.perRow = math.max(1, math.ceil(#db.actions / 2)) end
    db.rows = nil
    db.minimap = db.minimap or { angle = 225 }
    -- health bars in the member's class colour, or green
    if db.classColors == nil then db.classColors = true end
    -- buff and debuff icons on the bars, and the threat border
    if db.buffs == nil then db.buffs = true end
    if db.threat == nil then db.threat = true end
    -- from 0.16 the debuff icons are off: the dispel colour on the health bar shows what matters
    if not db.debuffsOff then
        db.debuffs = false
        db.debuffsOff = true
    end
    -- incoming heals on the health bars, role icons, and the health bar tinted by a dispellable debuff
    if db.heals == nil then db.heals = true end
    if db.roles == nil then db.roles = true end
    if db.dispel == nil then db.dispel = true end
    -- only the debuffs you can dispel tint the bar, see DispelFilter
    if db.dispelMine == nil then db.dispelMine = true end
    -- a swipe on a spell button while your buff from that spell is on the member, ex: Renew
    if db.swipes == nil then db.swipes = true end
    -- tooltips on the buttons, off: they cover the bars
    db.tooltips = db.tooltips and true or false
    -- a member's tooltip in the bottom right of the screen, as Blizzard's frames show it
    if db.memberTooltips == nil then db.memberTooltips = true end
    -- shift-right-click on a button with auto shift-click casts its spell two ranks lower, off: the
    -- same as shift-click
    db.shiftRight = db.shiftRight and true or false
    -- a frame under the party for your target when it's a friendly player not in it, see MakeTarget
    if db.targetFrame == nil then db.targetFrame = true end
    -- the members' order, see SORTS
    if not SORTS[db.sort] then db.sort = "group" end
    return db
end

local function Print(text)
    print("|cff33ff99Click Cast:|r " .. text)
end

local function Debug(text)
    if DB().debug then print("|cff999999Click Cast: " .. text .. "|r") end
end

local function Num(v)
    if type(v) == "number" and not issecretvalue(v) then return v end
    return nil
end

-- spellbook --------------------------------------------------------------------------------------

-- the rank number from a spell's subtext, ex: "Rank 3", or nil
local function RankNumber(id)
    if not (C_Spell and C_Spell.GetSpellSubtext) then return nil end
    local ok, text = pcall(C_Spell.GetSpellSubtext, id)
    if not ok or type(text) ~= "string" or issecretvalue(text) then return nil end
    return tonumber(text:match("(%d+)"))
end

local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) then return nil end
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and type(n) == "string" and not issecretvalue(n) then return n end
    return nil
end

local function SpellIcon(id)
    if not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, icon = pcall(C_Spell.GetSpellTexture, id)
    if ok and not issecretvalue(icon) then return icon end
    return nil
end

-- [lower case name] = { { id, rank }, ... } lowest rank first, for every spell in the player's
-- spellbook. Cleared when the spellbook changes.
local book

local function Book()
    if book then return book end
    book = {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return book end
    local ok, err = pcall(function()
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    local id, n = item and Num(item.spellID), item and item.name
                    if id and type(n) == "string" and not issecretvalue(n)
                        and not (future and item.itemType == future) then
                        n = n:lower()
                        book[n] = book[n] or {}
                        table.insert(book[n], { id = id, rank = RankNumber(id) })
                    end
                end
            end
        end
    end)
    if not ok then Debug("reading the spellbook failed: " .. tostring(err)) end
    for _, ranks in pairs(book) do
        table.sort(ranks, function(a, b)
            if a.rank and b.rank and a.rank ~= b.rank then return a.rank < b.rank end
            return a.id < b.id
        end)
    end
    return book
end

-- the spell to cast for an action, the one a rank below it, the one a rank above it and the one two
-- ranks below it, each { id, rank }, or nil when the spell isn't in your spellbook. With no rank set
-- it's your highest rank. A rank you don't know gives the highest one under it. With no rank below
-- or above, that one is the lowest or highest there is.
local function ResolveSpell(a)
    local ranks = Book()[a.spell:lower()]
    if not ranks or #ranks == 0 then return nil end
    local pick = #ranks
    if a.rank then
        pick = nil
        for i, r in ipairs(ranks) do
            if r.rank and r.rank <= a.rank then pick = i end
        end
        pick = pick or 1
    end
    return ranks[pick], ranks[math.max(pick - 1, 1)], ranks[math.min(pick + 1, #ranks)],
        ranks[math.max(pick - 2, 1)]
end

-- what shift-click on action a casts: "spell", { id, rank } or "macro", name, or nil when its spell
-- isn't in your spellbook. Unless one is set, it's the button's spell a rank lower, or its macro.
local function ResolveShift(a)
    local s = a.shift
    if s and s.macro then return "macro", s.macro end
    if s and s.spell then
        local r = ResolveSpell(s)
        if r then return "spell", r end
        return nil
    end
    if a.spell then
        local _, low = ResolveSpell(a)
        if low then return "spell", low end
        return nil
    end
    return "macro", a.macro
end

-- what shift-right-click on action a casts when it isn't what shift-click does: with the option on,
-- an auto shift-click's spell two ranks lower, { id, rank }. nil otherwise.
local function ResolveShiftRight(a)
    if not DB().shiftRight or a.shift or not a.spell then return nil end
    local _, low, _, lower = ResolveSpell(a)
    if lower and lower ~= low then return lower end
    return nil
end

-- what a spell attribute holds: the id, or by name with the rank, ex: "Heal(Rank 2)"
local function SpellValue(r)
    if DB().byname then
        local n = SpellName(r.id)
        if n and r.rank then return ("%s(Rank %d)"):format(n, r.rank) end
        return n or r.id
    end
    return r.id
end

local function RankText(r)
    return r.rank and ("rank %d"):format(r.rank) or ("spell %d"):format(r.id)
end

-- macros -----------------------------------------------------------------------------------------

-- a macro's icon and body by its name, or nil
local function MacroInfo(name)
    local index = GetMacroIndexByName and GetMacroIndexByName(name)
    if not index or index == 0 then return nil end
    local _, icon, body = GetMacroInfo(index)
    return icon, body
end

-- the spell a macro casts right now, for its cooldown, or nil
local function MacroSpell(name)
    if not GetMacroSpell then return nil end
    local ok, id = pcall(GetMacroSpell, name)
    return ok and id or nil
end

-- shift-click's action in a few words, ex: "rank 3 (auto)", "Flash Heal rank 2", "macro Dispel"
local function ShiftText(a)
    local kind, s = ResolveShift(a)
    local text
    if kind == "spell" then
        text = RankText(s)
        if a.shift and a.shift.spell:lower() ~= (a.spell or ""):lower() then
            text = (SpellName(s.id) or a.shift.spell) .. " " .. text
        end
    elseif kind == "macro" then
        text = "macro " .. s
        if not select(2, MacroInfo(s)) then text = text .. ", no macro by that name" end
    else
        text = (a.shift or a).spell .. ", not in your spellbook"
    end
    if not a.shift then text = text .. " (auto)" end
    local r = ResolveShiftRight(a)
    if r then text = text .. ", right-click " .. RankText(r) end
    return text
end

-- party frame ------------------------------------------------------------------------------------

-- the secure group header: a frame for you and each party member, or your subgroup in a raid
local party
-- the frames the header has made, shown or not, see Sync
local members = {}

local BAR_TEXTURES = {
    { name = "Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Flat", path = "Interface\\Buttons\\WHITE8X8" },
}

-- the bar textures to choose from, { name, path }: ours, then any other addons have shared through
-- LibSharedMedia
local function Textures()
    local list, seen = {}, {}
    for _, t in ipairs(BAR_TEXTURES) do
        table.insert(list, t)
        seen[t.name] = true
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        pcall(function()
            for _, name in ipairs(LSM:List("statusbar")) do
                if not seen[name] then
                    seen[name] = true
                    table.insert(list, { name = name, path = LSM:Fetch("statusbar", name) })
                end
            end
        end)
    end
    return list
end

-- the chosen bar texture's path, or the first one when that's gone
local function TexturePath()
    local name = DB().texture
    for _, t in ipairs(Textures()) do
        if t.name == name then return t.path end
    end
    return BAR_TEXTURES[1].path
end

-- Blizzard's party frames, hidden by moving them onto a hidden frame, and back onto their own
-- parent to show them again. Out of combat only, see Sync.
local hider = CreateFrame("Frame")
hider:Hide()
local BLIZZARD_PARTY = { "PartyFrame", "CompactPartyFrame", "PartyMemberFrame1", "PartyMemberFrame2",
    "PartyMemberFrame3", "PartyMemberFrame4" }
local blizzardParents = {}

local function HideBlizzard(hide)
    for _, name in ipairs(BLIZZARD_PARTY) do
        local f = _G[name]
        if f and f.SetParent then
            local parent = f:GetParent()
            if hide and parent ~= hider then
                blizzardParents[name] = parent
                pcall(f.SetParent, f, hider)
            elseif not hide and parent == hider then
                pcall(f.SetParent, f, blizzardParents[name] or UIParent)
            end
        end
    end
end

-- v, or nil when it's secret. In combat, Forever hides some unit info from addons.
local function Known(v)
    if issecretvalue(v) then return nil end
    return v
end

-- incoming heals in Blizzard's colours: yours, then everyone else's
local MY_HEAL = { 11 / 255, 136 / 255, 105 / 255 }
local OTHER_HEAL = { 21 / 255, 89 / 255, 72 / 255 }

-- class colours are dimmed by this much, so a priest's white doesn't drown out the name
local CLASS_DIM = 0.8
-- the health bar without class colours: a muted green, yellower than the heal bars
local GREEN = { 0.3, 0.55, 0.25 }

-- the health bar's colour for a class, ex: "PRIEST": its class colour, dimmed, or green when class
-- colours are off
local function ClassTokenColor(class)
    if not DB().classColors then return GREEN[1], GREEN[2], GREEN[3] end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r * CLASS_DIM, c.g * CLASS_DIM, c.b * CLASS_DIM end
    return GREEN[1], GREEN[2], GREEN[3]
end

-- the health bar's colour for a unit
local function ClassColor(u)
    local _, class = UnitClass(u)
    return ClassTokenColor(Known(class))
end

-- incoming heals, yours and everyone else's. In combat the amounts can be secret, so the game's
-- heal prediction calculator splits them, and they go straight to the bars.
local function UpdateHeals(m)
    local u = m.unit
    if not u or not DB().heals then
        m.myHeal:Hide()
        m.otherHeal:Hide()
        return
    end
    local mine, others
    if m.calc and UnitGetDetailedHealPrediction then
        pcall(function()
            UnitGetDetailedHealPrediction(u, "player", m.calc)
            local _
            _, mine, others = m.calc:GetIncomingHeals()
        end)
    end
    -- without the calculator, only amounts that aren't secret can be split
    if mine == nil and UnitGetIncomingHeals then
        local _, all = pcall(UnitGetIncomingHeals, u)
        local _, own = pcall(UnitGetIncomingHeals, u, "player")
        all, own = Num(all) or 0, Num(own) or 0
        mine, others = math.min(own, all), math.max(0, all - own)
    end
    pcall(function()
        local max = UnitHealthMax(u)
        m.myHeal:SetMinMaxValues(0, max)
        m.myHeal:SetValue(mine or 0)
        m.otherHeal:SetMinMaxValues(0, max)
        m.otherHeal:SetValue(others or 0)
    end)
    m.myHeal:Show()
    m.otherHeal:Show()
end

-- Health can be secret in combat: a status bar takes a secret value, but it can't be compared or
-- used in sums, so it's passed straight through
local function UpdateHealth(m)
    local u = m.unit
    if not u then return end
    pcall(function()
        m.health:SetMinMaxValues(0, UnitHealthMax(u))
        m.health:SetValue(UnitHealth(u))
    end)
    local status
    if Known(UnitIsConnected(u)) == false then
        status = "Offline"
    elseif Known(UnitIsGhost(u)) then
        status = "Ghost"
    elseif Known(UnitIsDead(u)) then
        status = "Dead"
    end
    m.status:SetText(status or "")
    if status then
        m.health:SetStatusBarColor(0.4, 0.4, 0.4)
    else
        m.health:SetStatusBarColor(ClassColor(u))
    end
    UpdateHeals(m)
end

local function UpdatePower(m)
    local u = m.unit
    if not u then return end
    pcall(function()
        m.power:SetMinMaxValues(0, UnitPowerMax(u))
        m.power:SetValue(UnitPower(u))
    end)
    local kind = Known(UnitPowerType(u))
    local c = kind and PowerBarColor and PowerBarColor[kind]
    if c then
        m.power:SetStatusBarColor(c.r, c.g, c.b)
    else
        m.power:SetStatusBarColor(0, 0.5, 1)
    end
end

local function UpdateName(m)
    if not m.unit then return end
    -- the first name only, UnitName's second value is the surname
    pcall(function() m.nameText:SetText((UnitName(m.unit))) end)
end

-- the member's role from the group finder or the raid's role check, as Blizzard's frames show it
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

-- member m's role icon for role, ex: "TANK", hidden for nil or "NONE"
local function ShowRole(m, role)
    local icon = m.role
    local atlas = role and role ~= "NONE" and (GetMicroIconForRole and GetMicroIconForRole(role) or ROLE_ATLAS[role])
    local size = icon:GetHeight()
    if atlas and pcall(icon.SetAtlas, icon, atlas) then
        icon:SetWidth(size)
        icon:Show()
    else
        -- 1 wide, so the name anchored to it moves left
        icon:SetWidth(1)
        icon:Hide()
    end
end

local function UpdateRole(m)
    if not m.role then return end
    local role
    if m.unit and DB().roles then
        local ok, r = pcall(UnitGroupRolesAssigned, m.unit)
        role = ok and Known(r)
    end
    ShowRole(m, role)
end

local function UpdateTarget(m)
    -- the target frame is always your target
    if m.isTarget then
        m.targetBorder:Hide()
        return
    end
    local t = m.unit and Known(UnitIsUnit(m.unit, "target"))
    m.targetBorder:SetShown(t and true or false)
end

-- a member out of range has faded bars
local function UpdateRange(m)
    local u = m.unit
    if not u or u == "player" then
        m.body:SetAlpha(1)
        return
    end
    local ok, inRange, checked
    if m.isTarget then
        -- UnitInRange only knows group members: the target is in range of its first spell button's
        -- spell, and with none it's never faded
        local id = m.rangeSpell
        local inRangeOf = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
        if not id or not inRangeOf then
            m.body:SetAlpha(1)
            return
        end
        ok, inRange = pcall(inRangeOf, id, u)
        -- the old API answers 1 or 0
        if not issecretvalue(inRange) and type(inRange) == "number" then inRange = inRange == 1 end
        -- nil when the spell can't be checked on it
        checked = issecretvalue(inRange) or inRange ~= nil
    else
        ok, inRange, checked = pcall(UnitInRange, u)
    end
    if not ok then return end
    if issecretvalue(inRange) then
        if m.body.SetAlphaFromBoolean then pcall(m.body.SetAlphaFromBoolean, m.body, inRange, 1, FADED) end
        return
    end
    if issecretvalue(checked) then checked = true end
    m.body:SetAlpha(checked and not inRange and FADED or 1)
end

-- a border round the member in the threat colour Blizzard uses: yellow, orange, red when it has
-- aggro. Hidden when the threat is secret.
local function UpdateThreat(m)
    local u = m.unit
    local status
    if u and DB().threat then
        local ok, s = pcall(UnitThreatSituation, u)
        status = ok and Num(s)
    end
    if status and status > 0 and GetThreatStatusColor then
        m.threat:SetBackdropBorderColor(GetThreatStatusColor(status))
        m.threat:Show()
    else
        m.threat:Hide()
    end
end

local function UpdateMember(m)
    UpdateName(m)
    UpdateRole(m)
    UpdateHealth(m)
    UpdatePower(m)
    UpdateTarget(m)
    UpdateRange(m)
    UpdateThreat(m)
end

-- auras ------------------------------------------------------------------------------------------

-- In combat, auras are secret: addon code can't read them. Blizzard's aura container shows them
-- for us: it reads a unit's auras and fills in icon buttons we give it. It only takes changes out
-- of combat.

-- the icons' size, set by Sync, read as each icon is made
local auraSize = 14
-- the first error making the icons, for /occ frames
local auraError

local function AuraError(err)
    auraError = auraError or tostring(err)
    Debug("aura icons: " .. tostring(err))
end

-- fills in one of the container's icon buttons: an icon, a cooldown swipe, a stack count and a
-- border. A debuff's border is in its dispel type's colour, Blizzard's red with none.
local function InitAura(button, debuff)
    local function try(f)
        local ok, err = pcall(f)
        if not ok then AuraError(err) end
    end
    try(function() button:SetSize(auraSize, auraSize) end)
    -- clicks and hovering go through to the member's frame: no tooltip, it'd cover the bars
    try(function() button:SetMouseClickEnabled(false) end)
    try(function() button:SetMouseMotionEnabled(false) end)
    try(function()
        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetTexture("Interface\\Buttons\\WHITE8X8")
        border:SetVertexColor(0, 0, 0)
        if debuff then
            local style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
            button:AddDispelTypeTexture(border, { style = style, showWhenHarmful = true,
                showWithoutDispelType = true })
        end
    end)
    try(function()
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button:SetIcon(icon)
    end)
    try(function()
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        button:SetDurationCooldown(cd)
    end)
    try(function()
        local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", 2, -1)
        button:SetApplicationCount(count)
    end)
end

-- a container of up to 3 icons in a bottom corner of member m's health bar, clear of the power
-- bar: debuffs on the left growing right, buffs on the right growing left. nil when the game can't
-- make one.
local function MakeAuras(m, debuff)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, m.body, "CustomAuraContainerTemplate")
    if not ok or not c then
        AuraError(ok and "no aura container" or c)
        return nil
    end
    local point = debuff and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local err
    ok, err = pcall(function()
        -- the container sizes itself to its icons, so it's anchored by one corner only
        c:SetPoint(point, m.health, point, debuff and 1 or -1, 1)
        c:SetFrameLevel(m.health:GetFrameLevel() + 3)
        local dir = AnchorUtil.FlowDirection
        c:SetFlowLayoutAnchorPoint(point)
        c:SetFlowLayoutGrowthDirection(debuff and dir.Right or dir.Left, dir.Up)
        local sort = AuraContainerSortMethod
        c:AddAuraGroup("auras", debuff and "HARMFUL" or "HELPFUL|PLAYER", {
            maxFrameCount = 3,
            sortMethod = debuff and sort and sort.UnitFrameDebuff or nil,
            layout = { elementSpacing = 1, elementWidth = auraSize, elementHeight = auraSize },
            initializeFrame = function(button) InitAura(button, debuff) end,
        })
        c:SetEnabled(true)
    end)
    if not ok then
        AuraError(err)
        return nil
    end
    return c
end

-- the containers show member m's unit's auras. They refuse changes in combat: then it's done once
-- combat ends.
local function SetAuraUnit(m)
    for _, c in ipairs({ m.buffs or false, m.debuffs or false, m.dispel or false, m.swipes or false }) do
        if c and m.unit and c.auraUnit ~= m.unit then
            if pcall(c.SetUnit, c, m.unit) then
                c.auraUnit = m.unit
            else
                pending = true
            end
        end
    end
end

-- a container showing nothing but the health bar tinted in the colour of member m's dispellable
-- debuff: blue magic, purple curse, brown disease, green poison. The container picks the debuff and
-- colours the tint, so it works in combat when debuffs are secret. nil when the game can't make one.
local DISPEL_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true }

-- RAID on harmful auras keeps the ones you can dispel, by your class and the spells you know
local function DispelFilter()
    return DB().dispelMine and "HARMFUL|RAID" or "HARMFUL"
end

local function MakeDispel(m)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, m.body, "CustomAuraContainerTemplate")
    if not ok or not c then
        AuraError(ok and "no aura container" or c)
        return nil
    end
    local err
    ok, err = pcall(function()
        c:SetPoint("TOPLEFT", m.health, "TOPLEFT")
        -- in the bars' strata, under the name, see MakeMember
        c:SetFrameStrata(m.health:GetFrameStrata())
        c:SetFrameLevel(m.health:GetFrameLevel() + 1)
        -- the fade is on the container: the game sets the tint's own colour and alpha, opaque
        c:SetAlpha(DISPEL_ALPHA)
        c.dispelFilter = DispelFilter()
        local slot = c:AddAuraSlot("dispel", c.dispelFilter, {
            candidateFilters = { includeDispelTypes = DISPEL_TYPES },
            initializeFrame = function(button)
                local function try(f)
                    local fine, e = pcall(f)
                    if not fine then AuraError(e) end
                end
                -- clicks and hovering go through to the member's frame
                try(function() button:SetMouseClickEnabled(false) end)
                try(function() button:SetMouseMotionEnabled(false) end)
                try(function()
                    local tint = button:CreateTexture(nil, "ARTWORK")
                    tint:SetAllPoints()
                    tint:SetTexture("Interface\\Buttons\\WHITE8X8")
                    button:AddDispelTypeTexture(tint, { style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
                        showWhenHarmful = true, showWithoutDispelType = false })
                end)
            end,
        })
        slot:SetAllPoints(m.health)
        c:SetEnabled(true)
    end)
    if not ok then
        AuraError(err)
        return nil
    end
    return c
end

-- a container showing your buffs as swipes on member m's spell buttons: one slot over each button,
-- taking your buff from any rank of its spell. Like the icons, it works in combat. nil when the
-- game can't make one.
local function MakeSwipes(m)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, m.body, "CustomAuraContainerTemplate")
    if not ok or not c then
        AuraError(ok and "no aura container" or c)
        return nil
    end
    local err
    ok, err = pcall(function()
        c:SetPoint("TOPLEFT", m, "TOPLEFT")
        -- above the buttons
        c:SetFrameLevel(m:GetFrameLevel() + 12)
        c:SetEnabled(true)
    end)
    if not ok then
        AuraError(err)
        return nil
    end
    m.swipeSlots = {}
    return c
end

local NO_SPELLS = {}

-- the swipe over button b, the i-th of member m's, shows your buff from b's spell. Out of combat.
local function SetSwipe(m, i, b)
    local c = m.swipes
    if not c then return end
    local ok, err = pcall(function()
        local key = "b" .. i
        local slot = m.swipeSlots[i]
        if not slot then
            slot = c:AddAuraSlot(key, "HELPFUL|PLAYER", {
                candidateFilters = { includeSpellIDs = NO_SPELLS },
                initializeFrame = function(button)
                    -- clicks and hovering go through to the spell button
                    pcall(button.SetMouseClickEnabled, button, false)
                    pcall(button.SetMouseMotionEnabled, button, false)
                    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                    cd:SetAllPoints()
                    -- bright while it's fresh, darker as it runs out
                    cd:SetReverse(true)
                    cd:SetDrawEdge(false)
                    cd:SetHideCountdownNumbers(true)
                    button:SetDurationCooldown(cd)
                end,
            })
            m.swipeSlots[i] = slot
        end
        slot:ClearAllPoints()
        slot:SetAllPoints(b)
        local ids = DB().swipes and b:IsShown() and b.spellIDs or nil
        if b.swipeIDs ~= ids then
            b.swipeIDs = ids
            c:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids or NO_SPELLS })
        end
    end)
    if not ok then AuraError(err) end
end

-- sets a container's icon size, count and whether it shows. Out of combat.
local function LayoutAuras(c, on, count)
    pcall(function()
        c:SetShown(on)
        c:SetEnabled(on)
        c:SetAuraGroupMaxFrameCount("auras", count)
        c:SetAuraGroupLayout("auras", { elementSpacing = 1, elementWidth = auraSize, elementHeight = auraSize })
        for i = 1, c:GetAuraGroupFrameCount("auras") do
            local b = c:GetAuraGroupFrame("auras", i)
            if b then b:SetSize(auraSize, auraSize) end
        end
    end)
end

-- buff reminders -----------------------------------------------------------------------------------

-- A spell button marked "remind" (a.remind) watches for its buff: when a member lacks it, its icon
-- shows beside their frame and the button glows on it, so a click puts it back. Anyone's buff counts,
-- any rank, and the group version (Prayer of Fortitude for Power Word: Fortitude). Party auras are
-- secret in combat, so the reminders hide for a fight and come back after it.

-- orange, unlike the gold target border
local REMIND_COLOR = { 1, 0.5, 0 }
-- between PLAYER_REGEN_DISABLED and _ENABLED: the first fires before InCombatLockdown is true
local fighting = false
local REMIND_GAP = 4
-- a buff and its group version, either way round. Greater Blessings are matched by name.
local GROUP_BUFFS = {
    { "power word: fortitude", "prayer of fortitude" },
    { "arcane intellect", "arcane brilliance" },
    { "mark of the wild", "gift of the wild" },
    { "divine spirit", "prayer of spirit" },
    { "shadow protection", "prayer of shadow protection" },
}

-- the lower case names of the buffs that count for a spell called name
local function BuffNames(name)
    name = name:lower()
    local names = { [name] = true, ["greater " .. name] = true }
    if name:sub(1, 8) == "greater " then names[name:sub(9)] = true end
    for _, pair in ipairs(GROUP_BUFFS) do
        if pair[1] == name then names[pair[2]] = true end
        if pair[2] == name then names[pair[1]] = true end
    end
    return names
end

-- the unit's buffs, { names = { [lower case name] = true }, ids = { [spell id] = true } }, or nil
-- when they can't be read
local function UnitBuffs(u)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local have = { names = {}, ids = {} }
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HELPFUL")
        if not ok or issecretvalue(aura) then return nil end
        if not aura then break end
        local name, id = aura.name, aura.spellId
        if issecretvalue(name) or issecretvalue(id) then return nil end
        if type(name) == "string" then have.names[name:lower()] = true end
        if id then have.ids[id] = true end
    end
    return have
end

-- the orange border on button b while its buff is missing on the member
local function Glow(b, on)
    if not on then
        if b.remindGlow then b.remindGlow:Hide() end
        return
    end
    if not b.remindGlow then
        local g = CreateFrame("Frame", nil, b, "BackdropTemplate")
        g:SetPoint("TOPLEFT", -1, 1)
        g:SetPoint("BOTTOMRIGHT", 1, -1)
        g:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        g:SetBackdropBorderColor(REMIND_COLOR[1], REMIND_COLOR[2], REMIND_COLOR[3])
        -- over the swipes, under the rank number, see NewButton
        g:SetFrameLevel(b:GetFrameLevel() + 3)
        b.remindGlow = g
    end
    b.remindGlow:Show()
end

-- the i-th reminder icon beside member frame m
local function RemindIcon(m, i)
    m.remindIcons = m.remindIcons or {}
    local f = m.remindIcons[i]
    if f then return f end
    f = CreateFrame("Frame", nil, m.body)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(REMIND_COLOR[1], REMIND_COLOR[2], REMIND_COLOR[3])
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.spell or "?")
        GameTooltip:AddLine("Missing" .. (self.who and (" on " .. self.who) or "") .. ". Its button glows: click it to "
            .. "buff them.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.remindIcons[i] = f
    return f
end

-- shows the icons of the n buttons in missing beside member frame m, in a row from its top right,
-- and glows those buttons. Every other glow and icon on m goes.
local function ShowReminders(m, missing, who)
    local list = buttons[m] or {}
    local glow = {}
    for _, b in ipairs(missing) do glow[b] = true end
    for _, b in ipairs(list) do Glow(b, glow[b]) end
    local size = DB().size > 0 and DB().size or SIZE
    for i, b in ipairs(missing) do
        local f = RemindIcon(m, i)
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", m, "TOPRIGHT", REMIND_GAP + (i - 1) * (size + REMIND_GAP), -PAD)
        f.icon:SetTexture(b.mainIcon)
        f.spell, f.who = b.label, who
        f:Show()
    end
    for i = #missing + 1, #(m.remindIcons or {}) do m.remindIcons[i]:Hide() end
end

-- member m's reminders for its marked buttons. Hidden in combat, on the target frame, and while the
-- member is dead, offline or too far away for their buffs to be known.
local function UpdateReminders(m)
    if not m.body then return end
    local u = m.unit
    local missing = {}
    local have
    if u and not m.isTarget and not fighting and not InCombatLockdown() and m:IsShown()
        and Known(UnitExists(u)) and Known(UnitIsConnected(u)) and Known(UnitIsVisible(u))
        and Known(UnitIsDeadOrGhost(u)) == false then
        for _, b in ipairs(buttons[m] or {}) do
            if b.remind and b:IsShown() then
                have = have or UnitBuffs(u)
                if not have then
                    missing = {}
                    break
                end
                local found = false
                for id in pairs(b.spellIDs or {}) do
                    if have.ids[id] then found = true end
                end
                for name in pairs(b.remindNames or {}) do
                    if have.names[name] then found = true end
                end
                if not found then table.insert(missing, b) end
            end
        end
    end
    ShowReminders(m, missing, u and Known(UnitName(u)))
end

-- what decides whether member m's reminders can show, besides their buffs: checked a few times a
-- second, as nothing fires when a member comes into sight
local function ReminderState(m)
    local u = m.unit
    if not u then return "" end
    return tostring(Known(UnitIsVisible(u))) .. tostring(Known(UnitIsDeadOrGhost(u)))
        .. tostring(Known(UnitIsConnected(u)))
end

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_NAME_UPDATE",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_HEAL_PREDICTION", "UNIT_AURA" }

-- the header gave member frame m a unit, or took it away: show that unit
-- whether member m's frame is you: only yours gets the self only buttons
local function IsMe(m)
    local u = not m.isTarget and m:GetAttribute("unit")
    if type(u) ~= "string" then return false end
    local me = UnitIsUnit(u, "player")
    return not issecretvalue(me) and me and true or false
end

local function Watch(m)
    local u = m:GetAttribute("unit")
    m.unit = u
    m.events:UnregisterAllEvents()
    if not u then return end
    for _, e in ipairs(UNIT_EVENTS) do
        pcall(m.events.RegisterUnitEvent, m.events, e, u)
    end
    SetAuraUnit(m)
    UpdateMember(m)
    UpdateReminders(m)
end

local function Bar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BAR_TEXTURES[1].path)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    return bar, bg
end

-- the member's unit tooltip, in the bottom right of the screen where Blizzard's frames put it, clear
-- of the bars. CONTAINER_OFFSET_X and Y keep it above the bags and right action bars, as Blizzard's do.
local function MemberTooltip(m)
    if not m.unit or not DB().memberTooltips then return end
    GameTooltip:SetOwner(m, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(CONTAINER_OFFSET_X or 0) - 13,
        CONTAINER_OFFSET_Y or 70)
    pcall(GameTooltip.SetUnit, GameTooltip, m.unit)
    GameTooltip:Show()
end

-- adds the bars, name and target border to a member frame the header made. Clicking the bars
-- targets the member.
local function MakeMember(m)
    if m.body then return end
    m:RegisterForClicks("AnyUp")
    m:SetAttribute("*type1", "target")
    local body = CreateFrame("Frame", nil, m)
    body:SetAllPoints()
    m.body = body
    local bg = body:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    m.bodyBg = bg

    m.health = Bar(body)
    m.health:SetPoint("TOPLEFT", PAD, -PAD)
    m.health:SetPoint("TOPRIGHT", -PAD, -PAD)
    m.power = Bar(body)
    m.power:SetPoint("TOPLEFT", m.health, "BOTTOMLEFT", 0, -1)
    m.power:SetPoint("TOPRIGHT", m.health, "BOTTOMRIGHT", 0, -1)

    -- incoming heals: bars from the end of the health fill, as wide as the health bar, so a heal
    -- for a quarter of max health fills a quarter of it. The health bar clips what goes past its end.
    m.health:SetClipsChildren(true)
    local bg
    m.myHeal, bg = Bar(m.health)
    -- no background, it'd cover the health fill
    bg:Hide()
    m.otherHeal, bg = Bar(m.health)
    bg:Hide()
    m.myHeal:SetValue(0)
    m.otherHeal:SetValue(0)
    m.myHeal:SetStatusBarColor(MY_HEAL[1], MY_HEAL[2], MY_HEAL[3])
    m.otherHeal:SetStatusBarColor(OTHER_HEAL[1], OTHER_HEAL[2], OTHER_HEAL[3])
    local ok, calc = pcall(function() return CreateUnitHealPredictionCalculator() end)
    if ok and calc then
        m.calc = calc
        pcall(function()
            calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
            calc:SetIncomingHealOverflowPercent(1)
        end)
    end

    -- the text is above the heal bars
    local text = CreateFrame("Frame", nil, m.health)
    text:SetAllPoints()
    -- above the dispel tint and the aura icons too, and the frames inside their containers
    text:SetFrameLevel(m.health:GetFrameLevel() + 6)
    m.status = text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    m.status:SetPoint("RIGHT", -4, 0)
    -- the role icon is left of the name, Sync places both
    m.role = text:CreateTexture(nil, "OVERLAY")
    m.role:SetSize(1, 12)
    m.role:Hide()
    m.nameText = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.nameText:SetPoint("LEFT", m.role, "RIGHT", 2, 0)
    m.nameText:SetPoint("RIGHT", m.status, "LEFT", -4, 0)
    m.nameText:SetJustifyH("LEFT")
    m.nameText:SetWordWrap(false)

    local border = CreateFrame("Frame", nil, body, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(1, 0.82, 0)
    border:Hide()
    m.targetBorder = border

    -- just outside the frame, so it doesn't hide the target border
    local threat = CreateFrame("Frame", nil, body, "BackdropTemplate")
    threat:SetPoint("TOPLEFT", -2, 2)
    threat:SetPoint("BOTTOMRIGHT", 2, -2)
    threat:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    threat:Hide()
    m.threat = threat

    m.dispel = MakeDispel(m)
    m.debuffs = MakeAuras(m, true)
    m.buffs = MakeAuras(m, false)
    m.swipes = MakeSwipes(m)

    m.events = CreateFrame("Frame")
    m.events:SetScript("OnEvent", function(_, event)
        if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
            UpdateThreat(m)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            UpdatePower(m)
        elseif event == "UNIT_NAME_UPDATE" then
            UpdateName(m)
            UpdateHealth(m)
        elseif event == "UNIT_AURA" then
            -- secret in combat, see UpdateReminders
            if not fighting then UpdateReminders(m) end
        else
            UpdateHealth(m)
        end
    end)
    m:HookScript("OnAttributeChanged", function(self, name)
        if name == "unit" then
            Watch(self)
            -- you've moved to another frame (sort, roster): the self only buttons follow, after combat
            if IsMe(self) ~= self.isMe then SyncSoon() end
        end
    end)
    m:HookScript("OnEnter", MemberTooltip)
    -- the tooltip calls it while it's showing, so it follows the member when the frame's unit changes
    m.UpdateTooltip = MemberTooltip
    m:HookScript("OnLeave", function() GameTooltip:Hide() end)
    Watch(m)
end

-- every frame the header has made, shown or not
local function Children()
    local list = {}
    if not party then return list end
    local i = 1
    while party:GetAttribute("child" .. i) do
        table.insert(list, party:GetAttribute("child" .. i))
        i = i + 1
    end
    return list
end

local function Place()
    local pos = DB().pos
    party:ClearAllPoints()
    party:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "TOPLEFT", pos.x, pos.y)
end

-- makes the header, out of combat only
local function MakeParty()
    if party then return end
    party = CreateFrame("Frame", "OpcowsClickCastParty", UIParent, "SecureGroupHeaderTemplate")
    party:SetAttribute("template", "SecureUnitButtonTemplate")
    party:SetAttribute("showPlayer", true)
    party:SetAttribute("showParty", true)
    party:SetAttribute("point", "TOP")
    party:SetAttribute("yOffset", -SPACING)
    party:SetAttribute("sortMethod", "INDEX")
    -- for sorting by role, see SORTS. Set before groupBy is: the header needs it then.
    party:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    party:SetMovable(true)
    party:SetClampedToScreen(true)
    -- the saved position is in the saved scale
    party:SetScale(DB().scale / 100)
    Place()
    party:Show()
    -- the header only lays out while it's visible, which it may not be yet at login. When it shows,
    -- set up whatever frames it made.
    party:HookScript("OnShow", function() SyncSoon() end)
    refreshHeader = true
end

-- a negative starting index makes the frames for a full party now, out of combat, so they can all
-- be set up before anyone joins. Only while the header is visible, so it's tried again each sync.
local function MakeChildren()
    if party:GetAttribute("child5") or not party:IsVisible() then return end
    party:SetAttribute("showSolo", true)
    party:SetAttribute("startingIndex", -4)
    party:SetAttribute("startingIndex", 1)
    refreshHeader = true
end

local function SetHeader(key, value)
    if party:GetAttribute(key) ~= value then party:SetAttribute(key, value) end
end

-- your subgroup's number as text, when you're in a raid
local function RaidGroup()
    if not IsInRaid() then return nil end
    for i = 1, GetNumGroupMembers() do
        if Known(UnitIsUnit("raid" .. i, "player")) then
            local _, _, sub = GetRaidRosterInfo(i)
            return Known(sub) and tostring(sub) or nil
        end
    end
    return nil
end

-- the handle above the frame while it's unlocked, drag it to move the frame
local mover

local function MakeMover()
    local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    f:SetSize(150, 18)
    f:SetPoint("BOTTOMLEFT", party, "TOPLEFT", 0, 2)
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1 })
    f:SetBackdropColor(0.1, 0.3, 0.6, 0.8)
    f:SetBackdropBorderColor(0.4, 0.7, 1)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText("Click Cast: drag to move")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            Print("the frame can't move in combat.")
            return
        end
        party:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        party:StopMovingOrSizing()
        pcall(party.SetUserPlaced, party, false)
        local point, _, relPoint, x, y = party:GetPoint()
        DB().pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click Cast")
        GameTooltip:AddLine("Drag to move the party frame. Lock it in the options or with /occ lock.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function UpdateMover()
    if not party or not (DB().unlocked or mover) then return end
    mover = mover or MakeMover()
    mover:SetShown(DB().unlocked and true or false)
end

-- the target frame: your target, under the party, when it's a friendly player the party frame
-- doesn't show. Out of combat our code shows and hides it. In combat only a secure state driver
-- can, and macro conditionals can't tell a player from an NPC, so then it's any friendly target
-- not in your party. It never shows someone the party frame does: without the [party]
-- conditional it stays hidden in combat.
local target
-- room above the target frame for its label
local TARGET_GAP = 14
-- the target frame's outline, its background is a dark shade of it
local TARGET_COLOR = { 0.7, 0.45, 1 }
-- the preview of a full party is showing, see UpdatePreview: the real frames are see-through
local previewOn = false

local function Parse(s)
    local ok, v = pcall(SecureCmdOptionParse, s)
    return ok and v or nil
end

-- the driver's states: show or hide in combat, "ooc" out of combat, when our code decides. The
-- driver checks again whenever the target changes, so it hides party members in combat too.
local function TargetDriver()
    -- an unknown conditional is false both ways
    if Parse("[@player,party] y; [@player,noparty] y; n") ~= "y" then return "[combat] hide; ooc" end
    local s = "[combat,@target,party] hide; "
    -- in a raid the party frame is your subgroup, and [party] may not mean that: hide anyone in the
    -- raid, or without [raid], hide it in combat in a raid
    if Parse("[@player,raid] y; [@player,noraid] y; n") == "y" then
        s = s .. "[combat,@target,raid] hide; "
    else
        s = s .. "[combat,group:raid] hide; "
    end
    -- the driver can't tell you from another player when [party] doesn't cover you alone: in combat
    -- UpdateTargetFrame makes the frame see-through when it's you (hiding it in combat while alone
    -- hid strangers you were healing too)
    return s .. "[combat,@target,help] show; [combat] hide; ooc"
end

-- the target frame m (or the preview's) unlike a party member at a glance: a purple background and
-- outline, and a gold label above it
local function StyleTarget(m)
    m.bodyBg:SetColorTexture(TARGET_COLOR[1] * 0.25, TARGET_COLOR[2] * 0.25, TARGET_COLOR[3] * 0.25, 0.85)
    local outline = CreateFrame("Frame", nil, m.body, "BackdropTemplate")
    outline:SetAllPoints()
    outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    outline:SetBackdropBorderColor(TARGET_COLOR[1], TARGET_COLOR[2], TARGET_COLOR[3])
    local label = m.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 1, 2)
    label:SetText("Your target (not in your party)")
end

-- makes the target frame, out of combat only
local function MakeTarget()
    if target then return end
    target = CreateFrame("Button", "OpcowsClickCastTarget", UIParent, "SecureUnitButtonTemplate")
    target.isTarget = true
    target:SetAttribute("unit", "target")
    target:Hide()
    MakeMember(target)
    -- the driver shows it in combat: show who the target is now
    target:HookScript("OnShow", function(self) UpdateMember(self) end)
    StyleTarget(target)
    local driver = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    driver:SetFrameRef("target", target)
    driver:SetAttribute("_onstate-occtarget", [[
        local t = self:GetFrameRef("target")
        if newstate == "show" then t:Show() elseif newstate == "hide" then t:Hide() end
    ]])
    target.driver = driver
end

-- your target is a friendly player, not you, and not on the party frame
local function WantTarget()
    if not DB().targetFrame or not Known(UnitExists("target")) then return false end
    if not Known(UnitIsPlayer("target")) or Known(UnitIsUnit("target", "player")) ~= false then return false end
    if not Known(UnitCanAssist("player", "target")) then return false end
    -- the member loop below can't tell when UnitIsUnit is secret
    if IsInGroup() and not IsInRaid() and Known(UnitInParty("target")) then return false end
    for _, m in ipairs(members) do
        if m:IsShown() and m.unit and Known(UnitIsUnit(m.unit, "target")) then return false end
    end
    return true
end

-- your target changed, or the party did: show or hide the target frame, and show the new target.
-- Its aura icons are set to the target again, out of combat only.
local function UpdateTargetFrame()
    if not target then return end
    -- in combat the driver may show you, or (its [party] seen to fail on Forever) a party member the
    -- party frame shows already: then the frame is see-through, as it can't be hidden. In a party,
    -- UnitInParty covers you too. In a raid the party frame is only your subgroup, so only you.
    local me = false
    if InCombatLockdown() then
        if IsInGroup() and not IsInRaid() then
            local ok, v = pcall(UnitInParty, "target")
            me = ok and v or false
        else
            me = UnitIsUnit("target", "player")
        end
    end
    if previewOn then
        target:SetAlpha(0)
    elseif issecretvalue(me) then
        if target.SetAlphaFromBoolean then pcall(target.SetAlphaFromBoolean, target, me, 0, 1) end
    else
        target:SetAlpha(me and 0 or 1)
    end
    if not InCombatLockdown() then
        target:SetShown(WantTarget())
        for _, c in ipairs({ target.buffs or false, target.debuffs or false, target.dispel or false,
            target.swipes or false }) do
            if c then
                pcall(c.SetUnit, c, nil)
                c.auraUnit = pcall(c.SetUnit, c, "target") and "target" or nil
            end
        end
    end
    -- shown or not: in combat the driver shows it after this, and a name read only while it showed
    -- stayed the last target's (an enemy's) on a party member's bars
    UpdateMember(target)
end

-- out of range members fade, checked a few times a second
local rangeFrame = CreateFrame("Frame")
local sinceRange = 0
rangeFrame:SetScript("OnUpdate", function(_, elapsed)
    sinceRange = sinceRange + elapsed
    if sinceRange < 0.25 then return end
    sinceRange = 0
    local combat = fighting or InCombatLockdown()
    for _, m in ipairs(members) do
        if m.body and m:IsVisible() then
            UpdateRange(m)
            if not combat then
                local state = ReminderState(m)
                if state ~= m.reminderState then
                    m.reminderState = state
                    UpdateReminders(m)
                end
            end
        end
    end
    if target and target:IsVisible() then UpdateRange(target) end
end)

-- buttons ----------------------------------------------------------------------------------------

-- runs in the secure environment before each click: a macro button fills in the unit of the member
-- frame it's on wherever its macros say @unit, for the plain click and for shift-click. A self only
-- button has its own unit, player.
local FILL_IN = [[
    local t = self:GetAttribute("occ-template")
    local st = self:GetAttribute("occ-shift-template")
    if not (t or st) then return end
    local p = self:GetParent()
    local u = self:GetAttribute("unit") or p and p:GetAttribute("unit")
    if not u then return end
    if t then
        self:SetAttribute("macrotext", (string.gsub(t, "@unit", "@" .. u)))
    end
    if st then
        self:SetAttribute("shift-macrotext*", (string.gsub(st, "@unit", "@" .. u)))
    end
]]

-- the secure handler FILL_IN runs on
local wrapper

local function Wrapper()
    if not wrapper then
        wrapper = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    end
    return wrapper
end

-- the button whose right-click cast is going on, it shows that rank until the cast ends
local rightCast
-- the player is casting or channelling
local casting = false

-- the spell's own cooldown on button b, not the global cooldown: the shift-click spell's while shift
-- is held. Duration objects can be secret in combat, they only go to the Cooldown frame.
local function UpdateCooldown(b)
    local cd = b.cooldown
    local id = IsShiftKeyDown() and b.shiftCdSpell or b.cdSpell
    local ok, d
    if id and C_Spell and C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
        ok, d = pcall(C_Spell.GetSpellCooldownDuration, id, true)
        if ok and d then ok = pcall(cd.SetCooldownFromDurationObject, cd, d, true) end
    elseif id and C_Spell and C_Spell.GetSpellCooldown then
        ok, d = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(d) == "table" then
            ok = pcall(cd.SetCooldown, cd, d.startTime, d.duration, d.modRate)
            d = true
        end
    end
    if not (ok and d) then cd:Clear() end
end

-- every button's cooldown, on SPELL_UPDATE_COOLDOWN
local function UpdateCooldowns()
    for _, list in pairs(buttons) do
        for _, b in ipairs(list) do
            if b:IsShown() then UpdateCooldown(b) end
        end
    end
end

-- what a click casts right now: the shift-click action's icon and rank while shift is held, the
-- right-click (or shift-right-click) rank while its cast goes on, else the button's own. Ranks other than its own are
-- yellow.
local function ShowRank(b)
    if not b.mainIcon then return end
    local icon, r, other = b.mainIcon, b.rank, false
    if rightCast == b then
        icon, r, other = b.castIcon, b.castRank, true
    elseif IsShiftKeyDown() then
        icon, r, other = b.shiftIcon, b.shiftRank, true
    end
    b.icon:SetTexture(icon)
    b.rankText:SetText(r and tostring(r) or "")
    if other then
        b.rankText:SetTextColor(1, 0.82, 0)
    else
        b.rankText:SetTextColor(1, 1, 1)
    end
    UpdateCooldown(b)
end

local function OnEnter(self)
    if not DB().tooltips then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText((IsShiftKeyDown() and self.shiftLabel or self.label) or "?")
    local p = self:GetParent()
    local unit = self.selfOnly and "player" or p and p.unit
    if type(unit) == "string" then
        local n = UnitName(unit)
        if n and not issecretvalue(n) then GameTooltip:AddLine("On " .. n, 0.7, 0.7, 0.7) end
    end
    GameTooltip:Show()
end

-- a right-click cast is over: the button shows its own rank again
local function EndRightCast()
    local b = rightCast
    rightCast = nil
    if b then ShowRank(b) end
end

local function PostClick(self, button, down)
    -- with shift held, either button does the shift-click action, unless shift-right-click has its own
    local shiftRight = IsShiftKeyDown() and self.shiftRightRank
    if button == "RightButton" and self.rightRank and (shiftRight or not IsShiftKeyDown()) then
        self.castIcon = shiftRight and self.shiftIcon or self.mainIcon
        self.castRank = shiftRight or self.rightRank
        rightCast = self
        ShowRank(self)
        -- an instant cast, or one that fails, never starts casting: show it a moment anyway
        C_Timer.After(1, function()
            if rightCast == self and not casting then EndRightCast() end
        end)
    end
    if not DB().debug then return end
    local p = self:GetParent()
    local unit = self:GetAttribute("unit") or p and p:GetAttribute("unit")
    local shift = IsShiftKeyDown() and "shift-" or ""
    local suffix = button == "RightButton" and "2" or "1"
    if shift ~= "" and not self:GetAttribute(shift .. "type" .. suffix) then suffix = "*" end
    local what
    if self:GetAttribute(shift .. "type" .. suffix) == "macro" then
        local text = self:GetAttribute(shift .. "macrotext" .. suffix) or self:GetAttribute("macrotext")
        what = "macro: " .. tostring(text):gsub("\n", " | ")
    else
        what = "spell " .. tostring(self:GetAttribute(shift .. "spell" .. suffix))
    end
    Debug(("%s%s %s, unit %s, %s"):format(shift, tostring(button), down and "down" or "up",
        tostring(unit), what))
end

-- a button on member frame m. A preview's button looks the same but casts nothing.
local function NewButton(m, preview)
    local b = CreateFrame("Button", nil, m, not preview and "SecureActionButtonTemplate" or nil)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetFrameLevel(m:GetFrameLevel() + 10)
    -- the spell's cooldown, under the buff swipe (m + 12, see MakeSwipes)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    b.cooldown:SetDrawEdge(false)
    b.cooldown:SetFrameLevel(m:GetFrameLevel() + 11)
    -- the rank number sits above both swipes
    local text = CreateFrame("Frame", nil, b)
    text:SetAllPoints()
    text:SetFrameLevel(m:GetFrameLevel() + 14)
    b.rankText = text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.rankText:SetPoint("BOTTOMRIGHT", -1, 1)
    if preview then return b end
    b:SetScript("PostClick", PostClick)
    -- the template casts on the press or the release, whichever the game is set to
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useparent-unit", true)
    SecureHandlerWrapScript(b, "OnClick", Wrapper(), FILL_IN)
    return b
end

local function Clear(b)
    for _, k in ipairs({ "type1", "shift-type1", "spell1", "shift-spell1", "type2", "shift-type2", "spell2",
        "shift-spell2", "shift-type*", "shift-spell*", "macrotext", "shift-macrotext*", "occ-template",
        "occ-shift-template", "unit" }) do
        b:SetAttribute(k, nil)
    end
end

-- sets the type, and the spell when it's one, for a click: button 1, 2 or "*" (any), shift held or not
local function SetClick(b, shift, button, type, spell)
    local prefix = shift and "shift-" or ""
    b:SetAttribute(prefix .. "type" .. button, type)
    b:SetAttribute(prefix .. "spell" .. button, spell)
end

-- sets button b up for action a, false when it can't be (spell not known, macro gone)
local function SetUp(b, a)
    Clear(b)
    b.label, b.mainIcon, b.rank, b.rightRank = nil, nil, nil, nil
    b.shiftLabel, b.shiftIcon, b.shiftRank, b.shiftRightRank = nil, nil, nil, nil
    b.spellIDs, b.spellID, b.cdSpell, b.shiftCdSpell = nil, nil, nil, nil
    b.remind, b.remindNames = nil, nil
    b.rankText:SetText("")
    -- a self only button casts on you whichever member it's on: its own unit comes before its
    -- parent's (useparent-unit). For racials and other spells you can only cast on yourself.
    b.selfOnly = a.self and true or nil
    if a.self then b:SetAttribute("unit", "player") end
    -- the click and right-click: a spell's rank a step down or up, a macro the same macro
    if a.spell then
        local main, low, high = ResolveSpell(a)
        if not main then return false end
        local right = DB().right == "up" and high or low
        SetClick(b, false, 1, "spell", SpellValue(main))
        SetClick(b, false, 2, "spell", SpellValue(right))
        b.label = SpellName(main.id) or a.spell
        b.mainIcon = SpellIcon(main.id) or 134400
        b.rank, b.rightRank, b.spellID, b.cdSpell = main.rank, right.rank, main.id, main.id
        -- the swipe shows your buff from any rank of it, see SetSwipe
        b.spellIDs = {}
        for _, r in ipairs(Book()[a.spell:lower()]) do b.spellIDs[r.id] = true end
        -- a reminder when its buff is missing on the member, see UpdateReminders
        if a.remind then
            b.remind = true
            b.remindNames = BuffNames(a.spell)
        end
    elseif a.macro then
        local icon, body = MacroInfo(a.macro)
        if not body then return false end
        SetClick(b, false, 1, "macro")
        SetClick(b, false, 2, "macro")
        b:SetAttribute("occ-template", body)
        b:SetAttribute("macrotext", body)
        b.label = "Macro: " .. a.macro
        b.mainIcon = icon or 134400
        b.cdSpell = MacroSpell(a.macro)
    else
        return false
    end
    -- shift-click, with either button
    local kind, s = ResolveShift(a)
    local icon, body
    if kind == "macro" then icon, body = MacroInfo(s) end
    if kind == "spell" then
        SetClick(b, true, "*", "spell", SpellValue(s))
        b.shiftLabel = SpellName(s.id) or a.shift and a.shift.spell or a.spell
        b.shiftIcon, b.shiftRank, b.shiftCdSpell = SpellIcon(s.id) or 134400, s.rank, s.id
        local r = ResolveShiftRight(a)
        if r then
            SetClick(b, true, 2, "spell", SpellValue(r))
            b.shiftRightRank = r.rank
        end
    elseif body then
        SetClick(b, true, "*", "macro")
        b:SetAttribute("occ-shift-template", body)
        b:SetAttribute("shift-macrotext*", body)
        b.shiftLabel, b.shiftIcon, b.shiftCdSpell = "Macro: " .. s, icon or 134400, MacroSpell(s)
    else
        -- its spell isn't known or its macro is gone: shift-click does what a click does
        SetClick(b, true, "*", b:GetAttribute("type1"), b:GetAttribute("spell1"))
        b.shiftLabel, b.shiftIcon, b.shiftRank, b.shiftCdSpell = b.label, b.mainIcon, b.rank, b.cdSpell
    end
    ShowRank(b)
    return true
end

-- layout -----------------------------------------------------------------------------------------

-- the sizes the member frames are laid out in, from the options
local function Dims()
    local db = DB()
    local health = db.barHeight > 0 and db.barHeight or HEALTH
    -- the icons take the bottom of the bars, the name moves up to the top
    auraSize = math.max(8, math.floor(health / 2))
    return {
        size = db.size > 0 and db.size or SIZE,
        health = health,
        -- the power bar keeps to about a quarter of the health bar
        power = math.max(2, math.floor(health * POWER / HEALTH + 0.5)),
        texture = TexturePath(),
        auras = db.buffs or db.debuffs,
        roleSize = math.max(8, math.min(12, health - 4)),
    }
end

-- lays out member frame m's bars, text and buttons in sizes d (see Dims). Self only buttons go on
-- it only when isMe. new(m) makes a button. Returns m's buttons and how many are in use.
local function LayoutMember(m, d, isMe, new)
    local db = DB()
    MakeMember(m)
    m.health:SetHeight(d.health)
    m.power:SetHeight(d.power)
    m.health:SetStatusBarTexture(d.texture)
    m.power:SetStatusBarTexture(d.texture)
    -- your heals start where the health fill ends, everyone else's where yours end
    local fill = m.health:GetStatusBarTexture()
    for _, bar in ipairs({ m.myHeal, m.otherHeal }) do
        bar:SetStatusBarTexture(d.texture)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", fill, "TOPRIGHT")
        bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
        fill = bar:GetStatusBarTexture()
    end
    m.nameText:ClearAllPoints()
    m.status:ClearAllPoints()
    m.role:ClearAllPoints()
    m.role:SetHeight(d.roleSize)
    if d.auras then
        m.role:SetPoint("TOPLEFT", 3, -1)
        m.status:SetPoint("TOPRIGHT", -4, -2)
    else
        m.role:SetPoint("LEFT", 3, 0)
        m.status:SetPoint("RIGHT", -4, 0)
    end
    m.nameText:SetPoint("LEFT", m.role, "RIGHT", 2, 0)
    m.nameText:SetPoint("RIGHT", m.status, "LEFT", -4, 0)
    UpdateRole(m)
    UpdateThreat(m)
    local list = buttons[m] or {}
    buttons[m] = list
    -- everyone's frame is as wide as yours, self only buttons and all
    local n, skipped = 0, 0
    for _, a in ipairs(db.actions) do
        if a.self and not isMe then
            -- counted only when your own frame shows it: a spell you don't know or a deleted macro shows
            -- on no one, so it takes no room
            local usable
            if a.spell then
                usable = ResolveSpell(a) ~= nil
            elseif a.macro then
                usable = select(2, MacroInfo(a.macro)) ~= nil
            end
            if usable then skipped = skipped + 1 end
        else
            local b = list[n + 1] or new(m)
            list[n + 1] = b
            if SetUp(b, a) then n = n + 1 end
        end
    end
    -- rows of up to perRow buttons under the bars, 0 = all in one row, from the frame's left edge
    local size = d.size
    local function Columns(count) return math.max(1, db.perRow > 0 and math.min(db.perRow, count) or count) end
    local columns = Columns(n)
    local rows = n > 0 and math.ceil(n / columns) or 0
    local full = Columns(n + skipped)
    local width = math.max(db.width > 0 and db.width or MIN_WIDTH, full * size + (full - 1) * GAP + 2 * PAD)
    local top = PAD + d.health + 1 + d.power + PAD
    m:SetSize(width, top + (rows > 0 and rows * (size + GAP) - GAP + PAD or 0))
    m.myHeal:SetWidth(width - 2 * PAD)
    m.otherHeal:SetWidth(width - 2 * PAD)
    UpdateHeals(m)
    -- as many icons as fit in half the bars' width, up to 3 a side
    local count = math.max(1, math.min(3, math.floor((width / 2 - PAD - 2) / (auraSize + 1))))
    if m.debuffs then LayoutAuras(m.debuffs, db.debuffs and true or false, count) end
    if m.buffs then LayoutAuras(m.buffs, db.buffs and true or false, count) end
    if m.dispel then
        pcall(function()
            m.dispel:SetShown(db.dispel and true or false)
            m.dispel:SetEnabled(db.dispel and true or false)
            local filter = DispelFilter()
            if m.dispel.dispelFilter ~= filter then
                m.dispel:SetAuraSlotFilterString("dispel", filter)
                m.dispel.dispelFilter = filter
            end
        end)
    end
    for i = 1, n do
        local b = list[i]
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", m, "TOPLEFT", PAD + col * (size + GAP), -(top + row * (size + GAP)))
        b:Show()
    end
    for i = n + 1, #list do
        Clear(list[i])
        list[i]:Hide()
    end
    return list, n
end

-- preview ----------------------------------------------------------------------------------------

-- A made-up full party and target, drawn over the real frames (which go see-through) so the layout
-- and options can be seen without a group. Plain frames, not secure ones: the buttons cast nothing.
-- It ends when combat starts or you join a group.

-- the made-up members: you first, then the party, showing each thing the frames can show
local PREVIEW = {
    { you = true, health = 1, power = 0.8 },
    { name = "Tankard", class = "WARRIOR", role = "TANK", health = 0.72, power = 0.4, powerType = "RAGE",
        threat = 3, buff = true, unbuffed = true },
    { name = "Thistle", class = "ROGUE", role = "DAMAGER", health = 0.45, power = 0.8, powerType = "ENERGY",
        curse = true, mine = 0.2, others = 0.1, buff = true },
    { name = "Emberly", class = "MAGE", role = "DAMAGER", health = 0.9, power = 0.6, powerType = "MANA",
        far = true },
    { name = "Gravel", class = "HUNTER", role = "DAMAGER", health = 0, power = 0, powerType = "MANA",
        dead = true },
}
local PREVIEW_TARGET = { name = "Wanderer", class = "PALADIN", health = 0.6, power = 0.7, powerType = "MANA" }
local POWER_COLORS = { MANA = { 0, 0, 1 }, RAGE = { 1, 0, 0 }, ENERGY = { 1, 1, 0 } }
local CURSE = { 0.6, 0, 1 }

-- the preview's frames: previewRoot holds previewMembers and previewTarget
local previewRoot, previewMembers, previewTarget

local function PreviewButton(m) return NewButton(m, true) end

local function MakePreviewMember(isTarget)
    local m = CreateFrame("Button", nil, previewRoot)
    MakeMember(m)
    -- the clicks land on the preview, not on the see-through frames under it
    m:EnableMouse(true)
    m:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click Cast preview")
        GameTooltip:AddLine("Made-up members, to see how the frames look. The buttons cast nothing. It "
            .. "ends with the Preview button, /occ preview, combat or joining a group.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    m:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- a curse's tint over the health bar, under the name, as the dispel container shows one
    local tint = CreateFrame("Frame", nil, m.body)
    tint:SetAllPoints(m.health)
    tint:SetFrameLevel(m.health:GetFrameLevel() + 1)
    tint:SetAlpha(DISPEL_ALPHA)
    local t = tint:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(CURSE[1], CURSE[2], CURSE[3])
    m.previewTint = tint
    -- one of your buffs, where the buff icons go
    local icons = CreateFrame("Frame", nil, m.body)
    icons:SetAllPoints(m.health)
    icons:SetFrameLevel(m.health:GetFrameLevel() + 3)
    m.previewBuff = icons:CreateTexture(nil, "ARTWORK")
    m.previewBuff:SetPoint("BOTTOMRIGHT", -1, 1)
    m.previewBuff:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if isTarget then StyleTarget(m) end
    return m
end

-- shows made-up member p on preview frame m, after LayoutMember
local function FillPreview(m, p, list, n)
    local db = DB()
    local name, class, role, powerType = p.name, p.class, p.role, p.powerType
    if p.you then
        name = Known(UnitName("player")) or "You"
        class = Known(select(2, UnitClass("player")))
        local ok, r = pcall(UnitGroupRolesAssigned, "player")
        role = ok and Known(r)
        if not role or role == "NONE" then role = "HEALER" end
        powerType = Known(select(2, UnitPowerType("player")))
    end
    m.nameText:SetText(name)
    ShowRole(m, db.roles and role or nil)
    m.health:SetMinMaxValues(0, 1)
    m.health:SetValue(p.health)
    m.status:SetText(p.dead and "Dead" or "")
    if p.dead then
        m.health:SetStatusBarColor(0.4, 0.4, 0.4)
    else
        m.health:SetStatusBarColor(ClassTokenColor(class))
    end
    m.power:SetMinMaxValues(0, 1)
    m.power:SetValue(p.power)
    local c = PowerBarColor and powerType and PowerBarColor[powerType]
    if c then
        m.power:SetStatusBarColor(c.r, c.g, c.b)
    else
        c = POWER_COLORS[powerType] or { 0, 0.5, 1 }
        m.power:SetStatusBarColor(c[1], c[2], c[3])
    end
    local heals = db.heals and (p.mine or p.others)
    m.myHeal:SetShown(heals and true or false)
    m.otherHeal:SetShown(heals and true or false)
    if heals then
        m.myHeal:SetMinMaxValues(0, 1)
        m.myHeal:SetValue(p.mine or 0)
        m.otherHeal:SetMinMaxValues(0, 1)
        m.otherHeal:SetValue(p.others or 0)
    end
    if db.threat and p.threat and GetThreatStatusColor then
        m.threat:SetBackdropBorderColor(GetThreatStatusColor(p.threat))
        m.threat:Show()
    else
        m.threat:Hide()
    end
    m.previewTint:SetShown(db.dispel and p.curse and true or false)
    -- the first spell button's icon stands in for your buff
    local icon
    for i = 1, n do
        if list[i].spellID then
            icon = list[i].mainIcon
            break
        end
    end
    m.previewBuff:SetSize(auraSize, auraSize)
    m.previewBuff:SetTexture(icon)
    m.previewBuff:SetShown(db.buffs and p.buff and icon and true or false)
    -- the buttons marked to remind: their buffs are missing on one member
    local missing = {}
    if p.unbuffed then
        for i = 1, n do
            if list[i].remind then table.insert(missing, list[i]) end
        end
    end
    ShowReminders(m, missing, name)
    m.body:SetAlpha(p.far and FADED or 1)
end

-- shows or hides the preview, laid out by the options as they are now. Not protected, so it can end
-- in combat.
local function UpdatePreview()
    if not previewOn or not party then
        if previewRoot then previewRoot:Hide() end
        if party then party:SetAlpha(1) end
        UpdateTargetFrame()
        return
    end
    if not previewRoot then
        previewRoot = CreateFrame("Frame", "OpcowsClickCastPreview", UIParent)
        previewRoot:SetSize(1, 1)
        previewMembers = {}
        for i = 1, #PREVIEW do previewMembers[i] = MakePreviewMember() end
        previewTarget = MakePreviewMember(true)
    end
    -- over the real frames, at their place and scale
    previewRoot:SetScale(DB().scale / 100)
    previewRoot:ClearAllPoints()
    previewRoot:SetPoint("TOPLEFT", party, "TOPLEFT")
    previewRoot:SetFrameStrata(party:GetFrameStrata())
    previewRoot:SetFrameLevel(party:GetFrameLevel() + 30)
    local d = Dims()
    local above
    for i, m in ipairs(previewMembers) do
        FillPreview(m, PREVIEW[i], LayoutMember(m, d, i == 1, PreviewButton))
        m:ClearAllPoints()
        if above then
            m:SetPoint("TOP", above, "BOTTOM", 0, -SPACING)
        else
            m:SetPoint("TOPLEFT", previewRoot, "TOPLEFT")
        end
        above = m
    end
    FillPreview(previewTarget, PREVIEW_TARGET, LayoutMember(previewTarget, d, false, PreviewButton))
    previewTarget:ClearAllPoints()
    previewTarget:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -TARGET_GAP)
    previewTarget:SetShown(DB().targetFrame and true or false)
    previewRoot:Show()
    party:SetAlpha(0)
    UpdateTargetFrame()
end

-- the preview is showing
function OCC.Previewing()
    return previewOn
end

-- sync -------------------------------------------------------------------------------------------

-- makes the party frame and sets up every member's buttons. Out of combat only, in combat it waits until it ends.
function OCC.Sync()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local db = DB()
    MakeParty()
    MakeChildren()
    HideBlizzard(db.hideBlizzard)
    -- a new scale keeps the frame where it is: its offsets are in its own scale
    local scale = db.scale / 100
    local old = party:GetScale()
    if math.abs(old - scale) > 0.001 then
        db.pos.x, db.pos.y = db.pos.x * old / scale, db.pos.y * old / scale
        party:SetScale(scale)
        Place()
    end
    members = Children()
    MakeTarget()
    -- the target frame is set up like a member
    local frames = { unpack(members) }
    table.insert(frames, target)
    local d = Dims()
    for _, m in ipairs(frames) do
        -- self only buttons go on your own frame only
        m.isMe = IsMe(m)
        local list, n = LayoutMember(m, d, m.isMe, NewButton)
        SetAuraUnit(m)
        for i = 1, #list do SetSwipe(m, i, list[i]) end
        UpdateReminders(m)
        -- for the target frame's range, see UpdateRange. Self only buttons don't reach the target.
        m.rangeSpell = nil
        for i = n, 1, -1 do
            if not list[i].selfOnly then m.rangeSpell = list[i].spellID or m.rangeSpell end
        end
    end
    -- after the members are set up. Alone, your own frame shows only with the solo option on. In a
    -- raid it's your subgroup: the filter is set before the raid is shown, so the header never lays
    -- out the whole raid. Just made, or after a loading screen, the header is made to lay itself out
    -- again by turning showSolo off first: setting an attribute to the value it has does nothing.
    if refreshHeader then
        refreshHeader = false
        party:SetAttribute("showSolo", false)
    end
    SetHeader("showSolo", db.solo and true or false)
    local sort = SORTS[db.sort]
    SetHeader("groupBy", sort.groupBy)
    SetHeader("sortMethod", sort.sortMethod)
    local group = RaidGroup()
    if group then
        SetHeader("groupFilter", group)
        SetHeader("showRaid", true)
    else
        SetHeader("showRaid", false)
        SetHeader("groupFilter", nil)
    end
    -- under the party, so it moves with it and with the members shown
    target:SetScale(scale)
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", party, "BOTTOMLEFT", 0, -TARGET_GAP)
    if db.targetFrame then
        RegisterStateDriver(target.driver, "occtarget", TargetDriver())
    else
        UnregisterStateDriver(target.driver, "occtarget")
    end
    UpdateTargetFrame()
    UpdateMover()
    UpdatePreview()
end

-- shift went down or up: show what each button casts now
local function ModifierChanged()
    for _, list in pairs(buttons) do
        for _, b in ipairs(list) do
            ShowRank(b)
            if GameTooltip.IsOwned and GameTooltip:IsOwned(b) then OnEnter(b) end
        end
    end
end

-- the player's casts, to show a right-click's lower rank until its cast ends
local castFrame = CreateFrame("Frame")
castFrame:SetScript("OnEvent", function(_, event)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        casting = true
    else
        casting = false
        EndRightCast()
    end
end)
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    pcall(castFrame.RegisterUnitEvent, castFrame, e, "player")
end

-- for Config.lua
OCC.DB, OCC.Print, OCC.Book, OCC.ResolveSpell, OCC.RankNumber = DB, Print, Book, ResolveSpell, RankNumber
OCC.SpellName, OCC.SpellIcon, OCC.RankText, OCC.MacroInfo = SpellName, SpellIcon, RankText, MacroInfo
OCC.ResolveShift, OCC.ShiftText = ResolveShift, ShiftText
OCC.ResolveShiftRight = ResolveShiftRight
OCC.Textures = Textures
-- the member frames that are showing
function OCC.ShownMembers()
    local n = 0
    for _, m in ipairs(members) do
        if m:IsShown() then n = n + 1 end
    end
    return n
end

-- changes waiting for combat to end
function OCC.Pending()
    return pending
end

-- once, however often it's asked for in the same frame
local syncQueued = false

function SyncSoon()
    if syncQueued then return end
    syncQueued = true
    -- after Blizzard has made or updated its frames for the same event
    C_Timer.After(0, function()
        syncQueued = false
        OCC.Sync()
        if OCC.RefreshConfig then OCC.RefreshConfig() end
    end)
end

-- slash command ----------------------------------------------------------------------------------

local function Describe(i, a)
    local text
    if a.spell then
        local main, low, high = ResolveSpell(a)
        if not main then
            return ("%d. %s%s: not in your spellbook"):format(i, a.spell, a.rank and (" rank " .. a.rank) or "")
        end
        local right = DB().right == "up" and high or low
        text = ("%d. %s: %s (%d), right-click %s (%d)"):format(i, SpellName(main.id) or a.spell, RankText(main),
            main.id, RankText(right), right.id)
    else
        local _, body = MacroInfo(a.macro)
        if not body then return ("%d. macro %s: no macro by that name"):format(i, a.macro) end
        text = ("%d. macro %s%s"):format(i, a.macro, body:find("@unit") and "" or " (has no @unit)")
    end
    return text .. ", shift-click " .. ShiftText(a) .. (a.self and ", on you only" or "")
        .. (a.remind and ", reminds when missing" or "")
end

local function Changed()
    if InCombatLockdown() then Print("changes apply when combat ends.") end
    OCC.Sync()
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- spell buttons cast by name and rank, ex: "Heal(Rank 2)", or by spell id
function OCC.SetByName(on)
    DB().byname = on and true or false
    Changed()
end

-- button i casts on you only, whichever member it's on, or on the member again
function OCC.SetSelfOnly(i, on)
    local a = DB().actions[i]
    if not a then return end
    a.self = on and true or nil
    Changed()
end

-- spell button i's buff shows beside a member's frame, and the button glows on it, when the member
-- doesn't have it. See UpdateReminders.
function OCC.SetRemind(i, on)
    local a = DB().actions[i]
    if not a then return end
    a.remind = on and true or nil
    Changed()
end

-- turns showing your own frame when you're not in a group on or off
function OCC.SetSolo(on)
    DB().solo = on and true or false
    Changed()
end

-- hides or shows Blizzard's party frames
function OCC.SetHideBlizzard(on)
    DB().hideBlizzard = on and true or false
    Changed()
end

-- health bars in class colours or green. Not protected, so it changes in combat too.
function OCC.SetClassColors(on)
    DB().classColors = on and true or false
    for _, m in ipairs(members) do
        if m.body then UpdateHealth(m) end
    end
    if previewOn then UpdatePreview() end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- your buffs on each member, and their debuffs. Out of combat only, see Sync.
function OCC.SetBuffs(on)
    DB().buffs = on and true or false
    Changed()
end

function OCC.SetDebuffs(on)
    DB().debuffs = on and true or false
    Changed()
end

-- the health bar tinted by a dispellable debuff. Out of combat only, see Sync.
function OCC.SetDispel(on)
    DB().dispel = on and true or false
    Changed()
end

-- only the debuffs you can dispel tint the bar, or any curse, poison, disease or magic. Out of
-- combat only.
function OCC.SetDispelMine(on)
    DB().dispelMine = on and true or false
    Changed()
end

-- the members' order: "group", "role" or "name". Out of combat only.
function OCC.SetSort(sort)
    if not SORTS[sort] then return end
    DB().sort = sort
    Changed()
end

-- swipes on the buttons for your buffs. Out of combat only, see Sync.
function OCC.SetSwipes(on)
    DB().swipes = on and true or false
    Changed()
end

-- tooltips on the buttons. Not protected, so it changes in combat too.
function OCC.SetTooltips(on)
    DB().tooltips = on and true or false
    if not on then GameTooltip:Hide() end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- the members' tooltips, bottom right of the screen. Not protected, so it changes in combat too.
-- the frame under the party for a friendly player you target who isn't in it
function OCC.SetTargetFrame(on)
    DB().targetFrame = on and true or false
    Changed()
end

-- shift-right-click casts an auto shift-click's spell two ranks lower
function OCC.SetShiftRight(on)
    DB().shiftRight = on and true or false
    Changed()
end

function OCC.SetMemberTooltips(on)
    DB().memberTooltips = on and true or false
    if not on then GameTooltip:Hide() end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- role icons left of the names. Not protected, so it changes in combat too.
function OCC.SetRoles(on)
    DB().roles = on and true or false
    for _, m in ipairs(members) do
        if m.body then UpdateRole(m) end
    end
    if previewOn then UpdatePreview() end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- incoming heals on the health bars. Not protected, so it changes in combat too.
function OCC.SetHeals(on)
    DB().heals = on and true or false
    for _, m in ipairs(members) do
        if m.body then UpdateHeals(m) end
    end
    if previewOn then UpdatePreview() end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- the threat border. Not protected, so it changes in combat too.
function OCC.SetThreat(on)
    DB().threat = on and true or false
    for _, m in ipairs(members) do
        if m.body then UpdateThreat(m) end
    end
    if previewOn then UpdatePreview() end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- shows or hides the handle for moving the party frame
function OCC.SetUnlocked(on)
    DB().unlocked = on and true or false
    UpdateMover()
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- shows or ends the preview of a full party, see UpdatePreview. Only out of combat and out of a
-- group; it can always end.
function OCC.SetPreview(on)
    on = on and true or false
    if on and InCombatLockdown() then
        Print("the preview can't start in combat.")
        return
    end
    if on and IsInGroup() then
        Print("the preview is for when you're not in a group: your frames already show your party.")
        return
    end
    if on == previewOn then return end
    previewOn = on
    if on and not party then OCC.Sync() end
    UpdatePreview()
    if on then Print("preview on: made-up members to see the frames by. /occ preview again ends it.") end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- button sets ------------------------------------------------------------------------------------

-- A set is the buttons and the right-click direction, saved by name for every character of a class
-- in OpcowsClickCastSets[class]. Saving and loading copy them, so editing the buttons leaves a set
-- alone until it's saved again. db.set is the one last loaded or saved.

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, x in pairs(a) do
        if not Same(x, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- your class's sets
function OCC.Sets()
    if type(OpcowsClickCastSets) ~= "table" then OpcowsClickCastSets = {} end
    local all = OpcowsClickCastSets
    local _, class = UnitClass("player")
    class = class or "UNKNOWN"
    -- 0.17.0 kept every class's sets together, each with its class
    local old = {}
    for name, set in pairs(all) do
        if type(set) == "table" and set.actions then old[name] = set end
    end
    for name, set in pairs(old) do
        local to = set.class or class
        all[name] = nil
        all[to] = all[to] or {}
        if all[to][name] == nil then all[to][name] = set end
        set.class = nil
    end
    all[class] = all[class] or {}
    return all[class]
end

-- the sets' names, in alphabetical order
function OCC.SetNames()
    local names = {}
    for name, set in pairs(OCC.Sets()) do
        if type(set) == "table" then table.insert(names, name) end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- the set's name as saved, whatever its case, or nil
function OCC.FindSet(name)
    local sets = OCC.Sets()
    if sets[name] then return name end
    for n in pairs(sets) do
        if n:lower() == name:lower() then return n end
    end
end

function OCC.SaveSet(name)
    local db = DB()
    OCC.Sets()[name] = { actions = Copy(db.actions), right = db.right }
    db.set = name
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

function OCC.LoadSet(name)
    local set = OCC.Sets()[name]
    if type(set) ~= "table" then return false end
    local db = DB()
    db.actions = Copy(set.actions) or {}
    db.right = set.right == "up" and "up" or "down"
    db.set = name
    Changed()
    return true
end

function OCC.DeleteSet(name)
    OCC.Sets()[name] = nil
    local db = DB()
    if db.set == name then db.set = nil end
    if OCC.RefreshConfig then OCC.RefreshConfig() end
end

-- the buttons aren't saved: they differ from the set last loaded or saved, or there's no set and
-- there are buttons
function OCC.Unsaved()
    local db = DB()
    local set = db.set and OCC.Sets()[db.set]
    if type(set) ~= "table" then return #db.actions > 0 end
    return not (Same(db.actions, set.actions or {}) and db.right == (set.right or "down"))
end

-- prints the party frame's state and what unit info is secret right now, to find out why a frame
-- or a bar doesn't show
local function FrameReport()
    local function secret(v) return issecretvalue(v) and "secret" or tostring(v) end
    Print(("in group %s, in raid %s, solo option %s, in combat %s"):format(tostring(IsInGroup()),
        tostring(IsInRaid()), tostring(DB().solo == true), tostring(InCombatLockdown())))
    Print(("your health %s / %s, in range %s, SetAlphaFromBoolean %s"):format(secret(UnitHealth("player")),
        secret(UnitHealthMax("player")), secret(UnitInRange("player")),
        tostring(rangeFrame.SetAlphaFromBoolean ~= nil)))
    local ok, threat = pcall(UnitThreatSituation, "player")
    Print(("aura icons %s, your threat %s"):format(auraError and ("failed: " .. auraError) or "ok",
        ok and secret(threat) or "error"))
    local okHeal, heal = pcall(UnitGetIncomingHeals, "player")
    Print(("heal calculator %s, heals on you %s"):format(
        tostring(CreateUnitHealPredictionCalculator ~= nil and UnitGetDetailedHealPrediction ~= nil),
        okHeal and secret(heal) or "error"))
    Print(("target frame %s, in combat: %s"):format(target and (target:IsShown() and "shown" or "hidden")
        or "not made", TargetDriver()))
    if not party then
        Print("the party frame isn't made yet, it's made out of combat.")
        return
    end
    local x, y = party:GetLeft(), party:GetTop()
    Print(("party frame shown %s, at %s,%s, showSolo %s, showRaid %s, groupFilter %s, groupBy %s, sortMethod %s"):format(
        tostring(party:IsShown()), tostring(x and math.floor(x)), tostring(y and math.floor(y)),
        tostring(party:GetAttribute("showSolo")), tostring(party:GetAttribute("showRaid")),
        tostring(party:GetAttribute("groupFilter")), tostring(party:GetAttribute("groupBy")),
        tostring(party:GetAttribute("sortMethod"))))
    for i, m in ipairs(members) do
        local ok, role = pcall(UnitGroupRolesAssigned, m.unit or "none")
        Print(("member %d: unit %s, shown %s, %.0fx%.0f, buttons %d, buffs %s, debuffs %s, dispel %s, role %s"):format(i,
            tostring(m:GetAttribute("unit")), tostring(m:IsShown()), m:GetWidth(), m:GetHeight(),
            buttons[m] and #buttons[m] or 0, tostring(m.buffs and m.buffs.auraUnit or m.buffs ~= nil),
            tostring(m.debuffs and m.debuffs.auraUnit or m.debuffs ~= nil),
            tostring(m.dispel and m.dispel.auraUnit or m.dispel ~= nil) .. " " .. tostring(m.dispel and m.dispel.dispelFilter),
            ok and secret(role) or "error"))
        Print(("  swipes %s"):format(tostring(m.swipes and m.swipes.auraUnit or m.swipes ~= nil)))
    end
end

OCC.FrameReport = FrameReport
OCC.Print = Print

local RIGHT = { down = "a rank lower", up = "a rank higher" }
OCC.RIGHT = RIGHT

local HELP = {
    "/occ - open the options window",
    "/occ add <spell> [rank] - add a spell button, no rank = your highest",
    "/occ macro <name> - add a button for one of your macros, @unit in it = the clicked member",
    "/occ remove <n> - remove button n",
    "/occ list - list the buttons",
    "/occ debug - print each click",
    "/occ byname - cast by name and rank instead of spell id",
    "/occ sync - set up the party frame again",
    "/occ lock - lock or unlock the party frame, unlocked it can be dragged",
    "/occ shift <n> <spell> [rank] - what shift-click on button n casts",
    "/occ shift <n> macro <name> - shift-click on button n runs a macro",
    "/occ shift <n> - shift-click on button n back to auto, a rank lower",
    "/occ right down|up - right-click casts a rank lower or higher",
    "/occ self <n> - button n casts on you only, whichever member it's on, or on the member again",
    "/occ remind <n> - spell button n's buff shows beside members who don't have it, and the button glows (out of combat)",
    "/occ perrow <n> - buttons in each row before the next, 0 = all in one row",
    "/occ width <n> - each member's frame width, 0 = 100, never narrower than its buttons",
    "/occ barheight <n> - health bar height, 0 = 22",
    "/occ scale <n> - the whole frame's size in percent, 50 to 200",
    "/occ bar [name] - the bars' style, no name lists them",
    "/occ blizzard - hide or show Blizzard's party frames",
    "/occ classcolors - health bars in class colours or green",
    "/occ solo - show your own frame when you're not in a group",
    "/occ buffs - show or hide your buffs on each member",
    "/occ debuffs - show or hide each member's debuffs",
    "/occ threat - show or hide the threat border",
    "/occ dispel - tint the health bar by a curse, poison, disease or magic debuff",
    "/occ dispelmine - tint only for debuffs you can dispel, or for all of them",
    "/occ roles - show or hide role icons",
    "/occ swipes - a swipe on a button while your buff from its spell is on the member",
    "/occ tooltips - tooltips on the buttons",
    "/occ membertooltips - the members' tooltips, bottom right of the screen",
    "/occ target - a frame under the party for a friendly player you target who isn't in it",
    "/occ shiftright - shift-right-click casts an auto shift-click's spell two ranks lower",
    "/occ sort group|role|name - the members' order",
    "/occ heals - show or hide incoming heals",
    "/occ sets - list the button sets, saved for all your characters of this class",
    "/occ save <name> - save the buttons as a set",
    "/occ load <name> - load a set's buttons",
    "/occ delete <name> - delete a set",
    "/occ preview - show or end a made-up full party, to see how the frames look (not in a group or combat)",
    "/occ frames - print the party frame's state, for finding problems",
}

SLASH_OPCOWSCLICKCAST1 = "/occ"
SlashCmdList.OPCOWSCLICKCAST = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local db = DB()
    if cmd == "add" and rest ~= "" then
        local name, rank = rest:match("^(.-)%s+(%d+)$")
        name = name or rest
        table.insert(db.actions, { spell = name, rank = tonumber(rank) })
        Print(Describe(#db.actions, db.actions[#db.actions]))
        Changed()
    elseif cmd == "macro" and rest ~= "" then
        table.insert(db.actions, { macro = rest })
        Print(Describe(#db.actions, db.actions[#db.actions]))
        Changed()
    elseif cmd == "remove" and tonumber(rest) and db.actions[tonumber(rest)] then
        table.remove(db.actions, tonumber(rest))
        Print("removed.")
        Changed()
    elseif cmd == "list" then
        if #db.actions == 0 then Print("no buttons yet, /occ add <spell> to add one.") end
        for i, a in ipairs(db.actions) do Print(Describe(i, a)) end
    elseif cmd == "debug" then
        db.debug = not db.debug
        Print("debug " .. (db.debug and "on" or "off"))
    elseif cmd == "byname" then
        OCC.SetByName(not db.byname)
        Print(db.byname and "casting by name and rank" or "casting by spell id")
    elseif cmd == "sync" then
        Changed()
        Print(("%d members showing."):format(OCC.ShownMembers()))
    elseif cmd == "lock" then
        OCC.SetUnlocked(not db.unlocked)
        Print(db.unlocked and "party frame unlocked, drag the handle above it." or "party frame locked.")
    elseif cmd == "classcolors" then
        OCC.SetClassColors(not db.classColors)
        Print("health bars in " .. (db.classColors and "class colours." or "green."))
    elseif cmd == "blizzard" then
        OCC.SetHideBlizzard(not db.hideBlizzard)
        Print("Blizzard's party frames " .. (db.hideBlizzard and "hidden" or "shown") .. ".")
    elseif cmd == "buffs" then
        OCC.SetBuffs(not db.buffs)
        Print("buff icons " .. (db.buffs and "on" or "off") .. ".")
    elseif cmd == "debuffs" then
        OCC.SetDebuffs(not db.debuffs)
        Print("debuff icons " .. (db.debuffs and "on" or "off") .. ".")
    elseif cmd == "heals" then
        OCC.SetHeals(not db.heals)
        Print("incoming heals " .. (db.heals and "on" or "off") .. ".")
    elseif cmd == "dispelmine" then
        OCC.SetDispelMine(not db.dispelMine)
        Print(db.dispelMine and "tint only for debuffs you can dispel." or "tint for any curse, poison, disease or magic.")
    elseif cmd == "dispel" then
        OCC.SetDispel(not db.dispel)
        Print("dispel colours " .. (db.dispel and "on" or "off") .. ".")
    elseif cmd == "swipes" then
        OCC.SetSwipes(not db.swipes)
        Print("buff swipes on the buttons " .. (db.swipes and "on" or "off") .. ".")
    elseif cmd == "tooltips" then
        OCC.SetTooltips(not db.tooltips)
        Print("button tooltips " .. (db.tooltips and "on" or "off") .. ".")
    elseif cmd == "target" then
        OCC.SetTargetFrame(not db.targetFrame)
        Print("target frame " .. (db.targetFrame and "on" or "off") .. ".")
    elseif cmd == "shiftright" then
        OCC.SetShiftRight(not db.shiftRight)
        Print("shift-right-click " .. (db.shiftRight and "casts two ranks lower." or "does what shift-click does."))
    elseif cmd == "membertooltips" then
        OCC.SetMemberTooltips(not db.memberTooltips)
        Print("member tooltips " .. (db.memberTooltips and "on" or "off") .. ".")
    elseif cmd == "roles" then
        OCC.SetRoles(not db.roles)
        Print("role icons " .. (db.roles and "on" or "off") .. ".")
    elseif cmd == "sort" and SORTS[rest:lower()] then
        OCC.SetSort(rest:lower())
        Print("sorted by " .. rest:lower() .. ".")
    elseif cmd == "threat" then
        OCC.SetThreat(not db.threat)
        Print("threat border " .. (db.threat and "on" or "off") .. ".")
    elseif cmd == "solo" then
        OCC.SetSolo(not db.solo)
        Print("your frame when not in a group " .. (db.solo and "on" or "off"))
    elseif cmd == "shift" and db.actions[tonumber(rest:match("^%d+") or "")] then
        local n, what = rest:match("^(%d+)%s*(.-)$")
        local a = db.actions[tonumber(n)]
        local macro = what:match("^[Mm][Aa][Cc][Rr][Oo]%s+(.+)$")
        if what == "" then
            a.shift = nil
        elseif macro then
            a.shift = { macro = macro }
        else
            local name, rank = what:match("^(.-)%s+(%d+)$")
            a.shift = { spell = name or what, rank = tonumber(rank) }
        end
        Print(Describe(tonumber(n), a))
        Changed()
    elseif cmd == "self" and db.actions[tonumber(rest) or 0] then
        local n = tonumber(rest)
        OCC.SetSelfOnly(n, not db.actions[n].self)
        Print(Describe(n, db.actions[n]))
    elseif cmd == "remind" and db.actions[tonumber(rest) or 0] then
        local n = tonumber(rest)
        if not db.actions[n].spell then
            Print("only spell buttons can remind: a macro's buff isn't known.")
            return
        end
        OCC.SetRemind(n, not db.actions[n].remind)
        Print(Describe(n, db.actions[n]))
    elseif cmd == "perrow" and tonumber(rest) and tonumber(rest) >= 0 then
        db.perRow = math.floor(tonumber(rest))
        Print(db.perRow == 0 and "buttons all in one row." or ("%d buttons in each row."):format(db.perRow))
        Changed()
    elseif cmd == "width" and tonumber(rest) and tonumber(rest) >= 0 then
        db.width = math.floor(tonumber(rest))
        Print(db.width == 0 and "frame width 100, or as wide as the buttons." or ("frame width %d."):format(db.width))
        Changed()
    elseif cmd == "barheight" and tonumber(rest) and tonumber(rest) >= 0 then
        db.barHeight = math.floor(tonumber(rest))
        Print(("health bar height %d."):format(db.barHeight > 0 and db.barHeight or HEALTH))
        Changed()
    elseif cmd == "scale" and tonumber(rest) then
        db.scale = math.min(200, math.max(50, math.floor(tonumber(rest))))
        Print(("scale %d%%."):format(db.scale))
        Changed()
    elseif cmd == "bar" then
        local names = {}
        for _, t in ipairs(Textures()) do
            if rest ~= "" and t.name:lower() == rest:lower() then
                db.texture = t.name
                Print("bar style " .. t.name .. ".")
                Changed()
                return
            end
            table.insert(names, t.name)
        end
        Print("bar styles: " .. table.concat(names, ", ") .. ". Now: " .. db.texture .. ".")
    elseif cmd == "right" and RIGHT[rest:lower()] then
        db.right = rest:lower()
        Print("right-click casts " .. RIGHT[db.right] .. ".")
        Changed()
    elseif cmd == "sets" then
        local names = OCC.SetNames()
        if #names == 0 then Print("no button sets yet, /occ save <name> to save one.") end
        for _, name in ipairs(names) do
            local set = OCC.Sets()[name]
            local n = #(set.actions or {})
            Print(("%s%s: %d button%s"):format(name, name == db.set and " (current)" or "", n, n == 1 and "" or "s"))
        end
    elseif cmd == "save" and rest ~= "" then
        local name = OCC.FindSet(rest) or rest
        OCC.SaveSet(name)
        Print(("buttons saved as %s."):format(name))
    elseif cmd == "load" and rest ~= "" then
        local name = OCC.FindSet(rest)
        if name and OCC.LoadSet(name) then
            Print(("loaded %s."):format(name))
        else
            Print(("no button set called %s, /occ sets lists them."):format(rest))
        end
    elseif cmd == "delete" and rest ~= "" then
        local name = OCC.FindSet(rest)
        if name then
            OCC.DeleteSet(name)
            Print(("deleted %s."):format(name))
        else
            Print(("no button set called %s, /occ sets lists them."):format(rest))
        end
    elseif cmd == "frames" then
        FrameReport()
    elseif cmd == "preview" then
        local was = previewOn
        OCC.SetPreview(not previewOn)
        if was and not previewOn then Print("preview ended.") end
    elseif cmd == "" then
        OCC.ToggleConfig()
    else
        for _, line in ipairs(HELP) do Print(line) end
    end
end

-- events -----------------------------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event)
    if event == "MODIFIER_STATE_CHANGED" then
        ModifierChanged()
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        UpdateCooldowns()
    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, m in ipairs(members) do
            if m.body then UpdateTarget(m) end
        end
        UpdateTargetFrame()
    elseif event == "PLAYER_REGEN_ENABLED" then
        fighting = false
        -- the buffs can be read again
        for _, m in ipairs(members) do UpdateReminders(m) end
        if pending then
            OCC.Sync()
            if OCC.RefreshConfig then OCC.RefreshConfig() end
        else
            -- in combat the driver showed it for any friendly target
            UpdateTargetFrame()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        refreshHeader = true
        SyncSoon()
    elseif event == "PLAYER_LOGIN" then
        OCC.UpdateMinimap()
        SyncSoon()
    elseif event == "SPELLS_CHANGED" then
        book = nil
        SyncSoon()
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        -- the header re-sorts itself, the icons are ours
        for _, m in ipairs(members) do
            if m.body then UpdateRole(m) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- the buffs are secret now: the reminders hide until it ends
        fighting = true
        for _, m in ipairs(members) do UpdateReminders(m) end
        -- the real frames are needed now
        if previewOn then
            OCC.SetPreview(false)
            Print("preview ended for combat.")
        end
    else
        if event == "GROUP_ROSTER_UPDATE" and previewOn and IsInGroup() then
            OCC.SetPreview(false)
            Print("preview ended: you're in a group.")
        end
        SyncSoon()
    end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "UPDATE_MACROS",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "MODIFIER_STATE_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_ROLES_ASSIGNED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES" }) do
    pcall(frame.RegisterEvent, frame, e)
end
