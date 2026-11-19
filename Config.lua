-- Options window, minimap button and addon compartment entry. Built on first use. None of it is
-- protected, so it works in combat; changes to the buttons wait until combat ends.

local OCC = OpcowsClickCast
local ROW_HEIGHT = 20
-- the options checkboxes' grid: column width, row height
local CHECK_COLUMN = 220
local CHECK_ROW = 26
local ICON = "Interface\\Icons\\Spell_Holy_Heal"

local config

local issecretvalue = issecretvalue or function() return false end

local function Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

-- widget helpers ---------------------------------------------------------------------------------

local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- text can be a function of the widget, for tooltips that describe the current state
local function Tooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        local t = type(text) == "function" and text(self) or text
        if t then GameTooltip:AddLine(t, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EditBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    return e
end

local function Check(parent, text, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = Label(c, text, "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 0, 1)
    c:SetHitRectInsets(0, -100, 0, 0)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

local function Box(parent, bg)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({
        bgFile = bg or "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if not bg then b:SetBackdropColor(0, 0, 0, 0.5) end
    b:SetBackdropBorderColor(0.6, 0.6, 0.6)
    return b
end

-- scrolling list of rows with an icon, text and an optional remove button. onDrop, if given, runs
-- when something is dropped on the list from the cursor, with the row's item when it's on a row.
local function ScrollList(parent, width, height, onDrop)
    local box = Box(parent)
    box:SetSize(width, height)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(width - 30, 1)
    sf:SetScrollChild(child)
    box.rows = {}

    local function Droppable(f)
        if not onDrop then return end
        f:EnableMouse(true)
        f:SetScript("OnReceiveDrag", function() onDrop() end)
        f:HookScript("OnMouseUp", function() if GetCursorInfo() then onDrop() end end)
    end
    Droppable(box)
    Droppable(sf)

    local function NewRow(i)
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", child, "RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.25)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(20, 20)
        row.remove:SetPoint("RIGHT", 0, 0)
        row.remove:SetScript("OnClick", function() row.item.onRemove() end)
        Tooltip(row.remove, "Remove", function() return row.item.removeTip end)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if GetCursorInfo() and onDrop then
                onDrop(self.item)
            elseif self.item.onClick then
                self.item.onClick()
            end
        end)
        if onDrop then row:SetScript("OnReceiveDrag", function(self) onDrop(self.item) end) end
        row:SetScript("OnEnter", function(self)
            if not (self.item.spell or self.item.tip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.item.spell then
                GameTooltip:SetSpellByID(self.item.spell)
            else
                GameTooltip:SetText(self.item.tip[1])
                for i = 2, #self.item.tip do GameTooltip:AddLine(self.item.tip[i], 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        box.rows[i] = row
        return row
    end

    -- items = { { text, icon, selected, onClick, onRemove, removeTip, spell, tip }, ... }
    function box:SetItems(items)
        for i, item in ipairs(items) do
            local row = self.rows[i] or NewRow(i)
            row.item = item
            row.icon:SetTexture(item.icon)
            row.text:SetText(item.text)
            row.sel:SetShown(item.selected and true or false)
            row.remove:SetShown(item.onRemove ~= nil)
            row:Show()
        end
        for i = #items + 1, #self.rows do
            self.rows[i]:Hide()
        end
        child:SetHeight(math.max(1, #items * ROW_HEIGHT))
    end

    return box
end

-- searchable popup list beside the window. Its source returns every row, each with a name to
-- search by.
local function Picker(parent, title, width, height)
    local p = Box(parent, "Interface\\DialogFrame\\UI-DialogBox-Background")
    p:SetSize(width, height)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:Hide()
    p.title = Label(p, title)
    p.title:SetPoint("TOPLEFT", 10, -9)
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() p:Hide() end)
    local searchLabel = Label(p, "Search:", "GameFontHighlightSmall")
    searchLabel:SetPoint("TOPLEFT", 12, -34)
    p.search = EditBox(p, width - 76)
    p.search:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    p.search:SetScript("OnTextChanged", function() p:Update() end)
    p.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.list = ScrollList(p, width - 16, height - 62)
    p.list:SetPoint("TOPLEFT", 8, -54)

    function p:Update()
        if not self.rows then return end
        local filter = Trim(self.search:GetText()):lower()
        local items = {}
        for _, row in ipairs(self.rows) do
            if row.name == nil or filter == "" or row.name:lower():find(filter, 1, true) then
                table.insert(items, row)
            end
        end
        self.list:SetItems(items)
    end

    -- noSearch: a short list with no search box, as tall as its rows
    function p:Open(title, source, noSearch)
        self.title:SetText(title)
        self.rows = source()
        self.search:SetText("")
        searchLabel:SetShown(not noSearch)
        self.search:SetShown(not noSearch)
        self.list:ClearAllPoints()
        if noSearch then
            local listHeight = math.min(#self.rows * ROW_HEIGHT + 8, height - 38)
            self.list:SetPoint("TOPLEFT", 8, -30)
            self.list:SetHeight(listHeight)
            self:SetHeight(listHeight + 38)
        else
            self.list:SetPoint("TOPLEFT", 8, -54)
            self.list:SetHeight(height - 62)
            self:SetHeight(height)
        end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
        self:Show()
        self:Update()
    end

    return p
end

-- what can be added ------------------------------------------------------------------------------

-- your spells that can be cast, one row per name, sorted
local function SpellRows(onPick)
    local byName, rows = {}, {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return rows end
    pcall(function()
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    local id, n = item and item.spellID, item and item.name
                    if type(id) == "number" and not issecretvalue(id) and type(n) == "string"
                        and not issecretvalue(n) and not item.isPassive
                        and (spellType == nil or item.itemType == spellType) then
                        local r = byName[n]
                        if r then
                            if id > r.spell then r.spell = id end
                        else
                            r = { name = n, text = n, icon = item.iconID, spell = id }
                            r.onClick = function() onPick(n) end
                            byName[n] = r
                            table.insert(rows, r)
                        end
                    end
                end
            end
        end
    end)
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

-- your account and character macros
local function MacroRows(onPick)
    local rows = {}
    if not GetNumMacros then return rows end
    local account, char = GetNumMacros()
    local function add(index, where)
        local name, icon, body = GetMacroInfo(index)
        if not name then return end
        local unit = body and body:find("@unit") and "" or "  |cff808080no @unit|r"
        table.insert(rows, {
            name = name, text = name .. "  |cff808080" .. where .. "|r" .. unit, icon = icon,
            tip = { name, body or "" },
            onClick = function() onPick(name) end,
        })
    end
    for i = 1, account or 0 do add(i, "account") end
    for i = 1, char or 0 do add((MAX_ACCOUNT_MACROS or 120) + i, "character") end
    return rows
end

-- the window -------------------------------------------------------------------------------------

local selected
-- the list being edited: "click", the buttons, or "shift", what shift-click on each one casts
local tab = "click"
-- what clicking a row does after selecting it, set by the window: opens the rank list
local OnSelect

local function Changed()
    OCC.Sync()
    OCC.RefreshConfig()
end

local function Add(a)
    local actions = OCC.DB().actions
    table.insert(actions, a)
    selected = #actions
    Changed()
end

-- sets what shift-click on the selected button casts
local function SetShift(s)
    local a = selected and OCC.DB().actions[selected]
    if not a then
        OCC.Print("select a button first.")
        return
    end
    a.shift = s
    Changed()
end

-- a spell or macro dropped on the list from the spellbook or the macro window. A spell dragged at
-- your highest rank follows your highest rank; a lower one keeps that rank. On the shift-click list
-- it's the shift-click action of the button it's dropped on, or of the selected one.
local function Drop(item)
    local kind, a1, _, a3 = GetCursorInfo()
    local a
    if kind == "spell" then
        local id = type(a3) == "number" and a3 or nil
        local name = id and OCC.SpellName(id)
        if name then
            local rank = OCC.RankNumber(id)
            local ranks = OCC.Book()[name:lower()]
            if rank and ranks and ranks[#ranks] and ranks[#ranks].rank == rank then rank = nil end
            a = { spell = name, rank = rank }
        end
    elseif kind == "macro" then
        local name = GetMacroInfo(a1)
        if name then a = { macro = name } end
    else
        return
    end
    ClearCursor()
    if not a then return end
    if tab == "shift" then
        if item and item.index then selected = item.index end
        SetShift(a)
    else
        Add(a)
    end
end

-- the list row for action a, selected by clicking it
local function Item(i)
    local item = { index = i, selected = i == selected }
    item.onClick = function()
        local again = selected == i
        selected = i
        if OnSelect then OnSelect(i, again) end
        OCC.RefreshConfig()
    end
    return item
end

-- the button's name, as the list shows it
local function ActionName(a)
    if a.macro then return a.macro end
    local main = OCC.ResolveSpell(a)
    return main and OCC.SpellName(main.id) or a.spell
end

-- the click list's row for action a
local function ActionItem(i, a)
    local item = Item(i)
    item.onRemove = function()
        table.remove(OCC.DB().actions, i)
        if selected and selected >= i then selected = selected > 1 and selected - 1 or nil end
        Changed()
    end
    if a.spell then
        local main, low, high = OCC.ResolveSpell(a)
        if main then
            item.icon = OCC.SpellIcon(main.id)
            item.spell = main.id
            local right = OCC.DB().right == "up" and high or low
            local other = right ~= main and ("right-click: " .. OCC.RankText(right))
                or a.noDownrank and OCC.DB().right ~= "up" and "never downranked"
                or ("no rank " .. (OCC.DB().right == "up" and "higher" or "lower"))
            if a.noDownrank and right ~= main then other = other .. ", never downranked" end
            item.text = ("%s  |cff808080%s%s%s, %s|r"):format(ActionName(a), a.self and "on you, " or "",
                a.remindOnly and "reminder only, " or a.remind and "remind, " or "", OCC.RankText(main), other)
        else
            item.icon = 134400
            item.text = ("%s  |cffff4040not in your spellbook|r"):format(a.spell)
        end
    else
        local icon, body = OCC.MacroInfo(a.macro)
        item.icon = icon or 134400
        if not body then
            item.text = ("%s  |cffff4040no macro by that name|r"):format(a.macro)
        else
            item.text = ("%s  |cff808080macro%s%s|r"):format(a.macro, a.self and ", on you" or "",
                body:find("@unit") and "" or ", no @unit")
            item.tip = { a.macro, body }
        end
    end
    local classes = OCC.ClassesText(a)
    if classes then item.text = item.text .. "  |cff808080for " .. classes .. "|r" end
    return item
end

-- the shift-click list's row for action a: the button, then what shift-click on it casts
local function ShiftItem(i, a)
    local item = Item(i)
    if a.shift then
        item.onRemove = function()
            a.shift = nil
            Changed()
        end
        item.removeTip = "Back to auto: the button's spell a rank lower, or its macro."
    end
    local kind, s = OCC.ResolveShift(a)
    local color = kind and "|cffffd100" or "|cffff4040"
    if kind == "spell" then
        item.icon = OCC.SpellIcon(s.id)
        item.spell = s.id
    elseif kind == "macro" then
        local icon, body = OCC.MacroInfo(s)
        item.icon = icon or 134400
        if body then
            item.tip = { s, body }
        else
            color = "|cffff4040"
        end
    else
        item.icon = 134400
    end
    item.text = ("%s  %s%s|r"):format(ActionName(a), color, OCC.ShiftText(a))
    return item
end

-- rank choices for a spell action: false (your highest) then each rank you know
local function RankChoices(spell)
    local list = { false }
    for _, r in ipairs(OCC.Book()[spell:lower()] or {}) do
        if r.rank then table.insert(list, r.rank) end
    end
    return list
end

-- the shift-click spell of action a and its rank choices, "auto" first when it's the button's own
-- spell, or nil when shift-click runs a macro
local function ShiftRankChoices(a)
    local spell = a.shift and a.shift.spell or not a.shift and a.spell
    if not spell then return nil end
    local list = RankChoices(spell)
    if a.spell and spell:lower() == a.spell:lower() then table.insert(list, 1, "auto") end
    return spell, list
end

-- the spell whose rank the tab sets for action a, its rank choices and the one set now, or nil for
-- a macro
local function RankState(a)
    if tab == "shift" then
        local spell, choices = ShiftRankChoices(a)
        if not spell then return nil end
        local value = "auto"
        if a.shift then value = a.shift.rank or false end
        return spell, choices, value
    end
    if not a.spell then return nil end
    return a.spell, RankChoices(a.spell), a.rank or false
end

-- sets the tab's rank for action a: a number, false for your highest, or "auto" for shift-click
local function SetRank(a, spell, value)
    if tab ~= "shift" then
        a.rank = value or nil
    elseif value == "auto" then
        a.shift = nil
    else
        a.shift = { spell = spell, rank = value or nil }
    end
    Changed()
end

-- button sets ------------------------------------------------------------------------------------

-- the set last loaded or saved, if it's still there
local function CurrentSet()
    local name = OCC.DB().set
    return name and type(OCC.Sets()[name]) == "table" and name or nil
end

local function PopupEditBox(self)
    return self.GetEditBox and self:GetEditBox() or self.editBox or self.EditBox
end

local function LoadNow(name)
    if OCC.LoadSet(name) then
        selected = nil
        OCC.Print(("loaded %s."):format(name))
    end
end

-- saves the buttons under a name typed in, asking first when it's taken
local function SaveNamed(name)
    name = Trim(name)
    if name == "" then return end
    local taken = OCC.FindSet(name)
    if taken then
        StaticPopup_Show("OCC_REPLACE_SET", taken, nil, taken)
    else
        OCC.SaveSet(name)
        OCC.Print(("buttons saved as %s."):format(name))
    end
end

StaticPopupDialogs.OCC_SAVE_SET = {
    text = "Save your buttons as a new set, for all your characters of this class. Name:",
    button1 = SAVE or "Save",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 20,
    OnShow = function(self)
        local e = PopupEditBox(self)
        if e then
            e:SetText("")
            e:SetFocus()
        end
    end,
    OnAccept = function(self)
        local e = PopupEditBox(self)
        if e then SaveNamed(e:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText()
        self:GetParent():Hide()
        SaveNamed(name)
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.OCC_REPLACE_SET = {
    text = "Replace the button set %s with your buttons?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, name)
        OCC.SaveSet(name)
        OCC.Print(("buttons saved as %s."):format(name))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.OCC_LOAD_SET = {
    text = "Load the button set %s? Your buttons have changes that aren't saved in a set.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, name) LoadNow(name) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.OCC_DELETE_SET = {
    text = "Delete the button set %s? It's deleted for all your characters of this class.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, name)
        OCC.DeleteSet(name)
        OCC.Print(("deleted %s."):format(name))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- loads a set, asking first when the buttons aren't saved
function OCC.ChooseSet(name)
    if OCC.Unsaved() then
        StaticPopup_Show("OCC_LOAD_SET", name, nil, name)
    else
        LoadNow(name)
    end
end

-- a set's icon: its first button's
local function SetIcon(set)
    local a = set.actions and set.actions[1]
    if a and a.spell then
        local main = OCC.ResolveSpell(a)
        return main and OCC.SpellIcon(main.id) or 134400
    elseif a and a.macro then
        return OCC.MacroInfo(a.macro) or 134400
    end
    return 134400
end

-- the row for set name: its button count, and its buttons in the tooltip
local function SetItem(name, onClick)
    local set = OCC.Sets()[name]
    local n = #(set.actions or {})
    local names = {}
    for _, a in ipairs(set.actions or {}) do table.insert(names, ActionName(a)) end
    return {
        name = name, icon = SetIcon(set), selected = name == CurrentSet(), onClick = onClick,
        text = ("%s  |cff808080%d button%s|r"):format(name, n, n == 1 and "" or "s"),
        tip = { name, #names > 0 and table.concat(names, ", ") or "No buttons." },
    }
end

-- the options window's list of sets: save as new, save to the current one, then each set
local function SetRows()
    local rows = {
        {
            text = "|cffffd100Save as a new set...|r",
            tip = { "Save as a new set", "Saves your buttons and the right-click setting under a new name, "
                .. "for all your characters of this class." },
            onClick = function() StaticPopup_Show("OCC_SAVE_SET") end,
        },
    }
    local cur = CurrentSet()
    if cur then
        table.insert(rows, {
            text = ("|cffffd100Save to %s|r"):format(cur),
            tip = { "Save to " .. cur, "Saves your buttons over this set." },
            onClick = function()
                OCC.SaveSet(cur)
                OCC.Print(("buttons saved as %s."):format(cur))
            end,
        })
    end
    for _, name in ipairs(OCC.SetNames()) do
        local item = SetItem(name, function() OCC.ChooseSet(name) end)
        item.onRemove = function() StaticPopup_Show("OCC_DELETE_SET", name, nil, name) end
        item.removeTip = "Delete this set, for all your characters of this class."
        table.insert(rows, item)
    end
    return rows
end

local function CreateConfig()
    local f = CreateFrame("Frame", "OpcowsClickCastConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(460, 890)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    table.insert(UISpecialFrames, "OpcowsClickCastConfig")

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Opcow's Click Cast")

    local help = Label(f, "", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -32)
    help:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    help:SetWordWrap(true)

    local picker = Picker(f, "", 260, 380)

    -- which list is edited
    local function ShowTab(t)
        tab = t
        picker:Hide()
        OCC.RefreshConfig()
    end
    local clickTab = Button(f, "Click", 100, function() ShowTab("click") end)
    clickTab:SetPoint("TOPLEFT", 14, -78)
    local shiftTab = Button(f, "Shift-click", 100, function() ShowTab("shift") end)
    shiftTab:SetPoint("LEFT", clickTab, "RIGHT", 4, 0)
    Tooltip(shiftTab, "Shift-click", "What shift-click on each button casts. Unless you set one, it's the "
        .. "button's spell a rank lower, or its macro.")

    -- the button sets: save, load and delete them in the picker
    local sets = Button(f, "Set", 220, function()
        if picker:IsShown() and picker.kind == "sets" then picker:Hide() return end
        picker.kind = "sets"
        picker:Open("Button sets", SetRows)
    end)
    sets:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -78)
    sets:SetNormalFontObject("GameFontNormalSmall")
    sets:SetHighlightFontObject("GameFontHighlightSmall")
    sets:GetFontString():SetWidth(204)
    sets:GetFontString():SetWordWrap(false)
    Tooltip(sets, "Button sets", "Your buttons and the right-click setting, saved by name for all your "
        .. "characters of this class. Click to save, load or delete them.\n\nRight-click the minimap button to load one.")

    -- a spell or macro picked: a new button, or the selected button's shift-click
    local function Picked(a)
        if tab == "shift" then SetShift(a) else Add(a) end
        picker:Hide()
    end
    local addSpell = Button(f, "Add spell...", 120, function()
        if picker:IsShown() and picker.kind == "spell" then picker:Hide() return end
        picker.kind = "spell"
        picker:Open(tab == "shift" and "Shift-click spell" or "Add a spell", function()
            return SpellRows(function(name) Picked({ spell = name }) end)
        end)
    end)
    addSpell:SetPoint("TOPLEFT", 14, -104)
    local addMacro = Button(f, "Add macro...", 120, function()
        if picker:IsShown() and picker.kind == "macro" then picker:Hide() return end
        picker.kind = "macro"
        picker:Open(tab == "shift" and "Shift-click macro" or "Add a macro", function()
            return MacroRows(function(name) Picked({ macro = name }) end)
        end)
    end)
    addMacro:SetPoint("LEFT", addSpell, "RIGHT", 4, 0)
    local dropHint = Label(f, "", "GameFontDisableSmall")
    dropHint:SetPoint("LEFT", addMacro, "RIGHT", 8, 0)

    local list = ScrollList(f, 432, 200, Drop)
    list:SetPoint("TOPLEFT", 14, -130)

    -- the selected button: order and rank
    local up = Button(f, "Up", 60, function()
        local actions = OCC.DB().actions
        if selected and selected > 1 then
            actions[selected], actions[selected - 1] = actions[selected - 1], actions[selected]
            selected = selected - 1
            Changed()
        end
    end)
    up:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
    local down = Button(f, "Down", 60, function()
        local actions = OCC.DB().actions
        if selected and selected < #actions then
            actions[selected], actions[selected + 1] = actions[selected + 1], actions[selected]
            selected = selected + 1
            Changed()
        end
    end)
    down:SetPoint("LEFT", up, "RIGHT", 4, 0)
    local rank = Button(f, "Rank", 140, nil)
    rank:SetPoint("LEFT", down, "RIGHT", 4, 0)
    rank:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rank:SetScript("OnClick", function(_, button)
        local a = selected and OCC.DB().actions[selected]
        if not a then return end
        local spell, choices, value = RankState(a)
        if not spell then return end
        local cur = 1
        for i, v in ipairs(choices) do
            if v == value then cur = i end
        end
        local n = #choices
        cur = button == "RightButton" and (cur - 2) % n + 1 or cur % n + 1
        SetRank(a, spell, choices[cur])
    end)
    Tooltip(rank, "Rank", function()
        if tab == "shift" then
            return "The rank shift-click casts. |cffffffffAuto|r is a rank below the button's rank. "
                .. "|cffffffffHighest|r follows your highest rank as you learn new ones.\n\n"
                .. "Left-click for the next rank, right-click for the one before."
        end
        return "The rank a click casts. Right-click casts the one below it, or above it (see Options). "
            .. "|cffffffffHighest|r follows your highest rank as you learn new ones.\n\n"
            .. "Left-click for the next rank, right-click for the one before. Or click a spell in the list "
            .. "to pick from its ranks."
    end)

    -- the classes the selected button shows under, picked in the list beside the window
    local function ClassRows(i)
        local a = OCC.DB().actions[i]
        if not a then return nil end
        local any = type(a.classes) == "table" and next(a.classes) ~= nil
        local rows = { {
            text = "Everyone  |cff808080no filter|r", selected = not any,
            tip = { "Everyone", "The button shows under every member, whatever their class." },
            onClick = function() OCC.SetClass(i, nil) end,
        } }
        for _, c in ipairs(OCC.CLASSES) do
            local on = any and a.classes[c] and true or false
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
            local hex = color and ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) or "|cffffffff"
            table.insert(rows, {
                text = hex .. OCC.ClassName(c) .. "|r" .. (on and "  |cff808080shown|r" or ""),
                selected = on,
                tip = { OCC.ClassName(c), "Click to show the button under " .. OCC.ClassName(c)
                    .. " members, or click again to stop. Tick as many classes as you like." },
                onClick = function() OCC.SetClass(i, c, not on) end,
            })
        end
        return rows
    end
    local classes = Button(f, "Classes: all", 120, function()
        if not selected then return end
        if picker:IsShown() and picker.kind == "class" then picker:Hide() return end
        picker.kind = "class"
        local i = selected
        picker:Open("Show under", function() return ClassRows(i) or {} end, true)
    end)
    classes:SetPoint("LEFT", rank, "RIGHT", 4, 0)
    -- kept on the rank button: Refresh is at Lua 5.1's limit of 60 upvalues
    rank.classes, classes.Rows = classes, ClassRows
    Tooltip(classes, "Classes", "Show the selected button only under members of the classes you pick, ex: "
        .. "Arcane Intellect under mana users, or a Blessing under warriors. With none picked it shows under "
        .. "everyone.\n\nThe frames keep the same width: a button another class doesn't get leaves its room. "
        .. "The target frame shows every button.\n\nChanges apply out of combat. If someone joins in combat, "
        .. "their buttons follow their class when combat ends.")

    -- the selected button casts on you and shows only on your own frame
    local selfOnly = Check(f, "Self only", function(v)
        if selected then OCC.SetSelfOnly(selected, v) end
    end)
    -- the button's checkboxes in one row under Up, Down and Rank, each after the one before's label
    selfOnly:SetPoint("TOPLEFT", up, "BOTTOMLEFT", -2, -2)
    local function After(c, prev)
        c:SetPoint("LEFT", prev.label, "RIGHT", 10, -1)
    end
    -- its label only, so the box after it gets its own clicks
    local function LabelHit(c)
        c:SetHitRectInsets(0, -math.ceil(c.label:GetStringWidth() or 40), 0, 0)
    end
    Tooltip(selfOnly, "Self only", "The selected button shows only on your own frame and casts on you: for "
        .. "racials and other spells you can only cast on yourself. Its click, right-click and shift-click "
        .. "all do, and @unit in its macros is you. It isn't on the target frame.\n\nChanges apply out of "
        .. "combat. If your place in the party changes in combat, the button moves to your frame when combat "
        .. "ends, and casts on you until then.")
    LabelHit(selfOnly)

    -- the selected spell's buff shows beside members missing it, and its button glows on them
    local remind = Check(f, "Remind", function(v)
        if selected then OCC.SetRemind(selected, v) end
    end)
    After(remind, selfOnly)
    LabelHit(remind)
    Tooltip(remind, "Remind when missing", "When a party member doesn't have the selected spell's buff, its "
        .. "icon shows beside their frame and this button glows on their frame: click it to buff them. "
        .. "Anyone's buff counts, at any rank, and the group version too (Prayer of Fortitude for Power Word: "
        .. "Fortitude).\n\nFor spells only. Buffs can't be read in combat, so the reminders hide for a fight and "
        .. "come back after it.")

    -- the selected spell isn't in the row: it shows beside members missing its buff, to click
    local remindOnly = Check(f, "Reminder only", function(v)
        if selected then OCC.SetRemindOnly(selected, v) end
    end)
    After(remindOnly, remind)
    LabelHit(remindOnly)
    Tooltip(remindOnly, "Reminder only", "The selected spell's button isn't in the row under the bars. It "
        .. "shows beside a party member's frame only while they're missing its buff: click it there to buff "
        .. "them. For buffs you cast now and then, so they don't take room in the row.\n\nFor spells only. "
        .. "Out of combat only: buffs can't be read in a fight, so these buttons hide when it starts and "
        .. "come back after it.")

    -- the selected spell never casts a lower rank
    local noDownrank = Check(f, "Never downrank", function(v)
        if selected then OCC.SetNoDownrank(selected, v) end
    end)
    After(noDownrank, remindOnly)
    LabelHit(noDownrank)
    Tooltip(noDownrank, "Never downrank", "The selected spell always casts the rank set for its click. "
        .. "Right-click casts that rank too when it would go a rank lower, and so does shift-click when it's "
        .. "Auto, and shift-right-click. A rank higher on right-click, or a shift-click spell you picked, still "
        .. "works.\n\nFor spells only.")

    -- the rank list beside the window, for the selected spell: one row a rank, with its tooltip
    local function RankRows(a)
        local spell, choices, value = RankState(a)
        if not spell or #choices < 2 then return nil end
        local ranks = OCC.Book()[spell:lower()] or {}
        local top = ranks[#ranks]
        local rows = {}
        for _, v in ipairs(choices) do
            local r, text
            if v == "auto" then
                local _, low = OCC.ResolveSpell(a)
                r = low
                text = "Auto  |cff808080" .. (a.noDownrank and "the button's own rank (never downrank)"
                    or "a rank below the button's")
                    .. (low and low.rank and (", rank " .. low.rank) or "") .. "|r"
            elseif v == false then
                r = top
                text = "Highest  |cff808080follows new ranks" .. (top and top.rank and (", rank " .. top.rank) or "")
                    .. "|r"
            else
                r = OCC.ResolveSpell({ spell = spell, rank = v })
                text = "Rank " .. v
            end
            table.insert(rows, {
                text = text, selected = v == value, icon = r and OCC.SpellIcon(r.id) or 134400,
                spell = r and r.id,
                onClick = function()
                    picker:Hide()
                    SetRank(a, spell, v)
                end,
            })
        end
        return rows, spell
    end

    -- clicking a spell in the list opens its ranks, clicking it again closes them. An open spell or
    -- macro list stays: it's for the selected button.
    OnSelect = function(i, again)
        -- an open class list follows the selected button, see Refresh
        if picker:IsShown() and (picker.kind == "spell" or picker.kind == "macro" or picker.kind == "class") then
            return
        end
        if again and picker:IsShown() and picker.kind == "rank" then
            picker:Hide()
            return
        end
        local a = OCC.DB().actions[i]
        local rows, spell = RankRows(a)
        if not rows then
            if picker.kind == "rank" then picker:Hide() end
            return
        end
        picker.kind = "rank"
        picker:Open((tab == "shift" and "Shift-click: " or "") .. spell, function() return rows end, true)
    end

    -- options
    local optTitle = Label(f, "Options")
    -- below the Reminder only box under Self only
    optTitle:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 2, -36)

    local lock = Button(f, "Unlock frame", 130, function()
        OCC.SetUnlocked(not OCC.DB().unlocked)
    end)
    lock:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", -2, -6)
    Tooltip(lock, "Move the party frame", "Unlocked, a handle shows above the party frame. Drag it to move "
        .. "the frame, then lock it again. It can't move in combat.")

    -- a labelled box for a whole number setting, saved when it loses focus
    local function NumberBox(text, anchor, key, max)
        local label = Label(f, text, "GameFontHighlightSmall")
        label:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
        local box = EditBox(f, 40)
        box:SetPoint("LEFT", label, "RIGHT", 8, 0)
        box:SetNumeric(true)
        box:SetMaxLetters(3)
        local function Save(self)
            local n = tonumber(self:GetText())
            if n and n <= max then OCC.DB()[key] = n end
            Changed()
        end
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEditFocusLost", Save)
        box:SetScript("OnEscapePressed", function(self)
            self:SetScript("OnEditFocusLost", nil)
            self:ClearFocus()
            self:SetScript("OnEditFocusLost", Save)
            OCC.RefreshConfig()
        end)
        return box
    end

    local size = NumberBox("Size:", lock, "size", 200)
    local sizeHint = Label(f, "0 = 24", "GameFontDisableSmall")
    sizeHint:SetPoint("LEFT", size, "RIGHT", 6, 0)

    local preview = Button(f, "Preview", 110, function()
        OCC.SetPreview(not OCC.Previewing())
    end)
    preview:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    preview:SetPoint("TOP", lock, "TOP")
    Tooltip(preview, "Preview", "Shows a made-up full party and a target where your party frame is, to "
        .. "see how the frames look with the options as they are. It changes as you change them. The "
        .. "buttons cast nothing.\n\nOnly when you're not in a group. Combat or joining a group ends it.")

    local right = Button(f, "Right-click", 220, function()
        local db = OCC.DB()
        db.right = db.right == "up" and "down" or "up"
        Changed()
    end)
    right:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -6)
    Tooltip(right, "Right-click", "Right-click on a spell button casts it a rank lower or a rank higher. "
        .. "Click to change it.\n\nThe number on the button changes to that rank once you click, until "
        .. "the cast ends. A macro button runs its macro.")

    local perRow = NumberBox("Per row:", right, "perRow", 99)
    Tooltip(perRow, "Buttons per row", "How many buttons go in a row under each member's bars before the "
        .. "next row starts, to keep the frame narrower. 0 puts them all in one row.")

    -- the bars' texture: left-click for the next one, right-click for the one before
    local style = Button(f, "Bars", 220, nil)
    style:SetPoint("TOPLEFT", right, "BOTTOMLEFT", 0, -6)
    style:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    style:SetScript("OnClick", function(_, button)
        local list, db = OCC.Textures(), OCC.DB()
        local cur = 1
        for i, t in ipairs(list) do
            if t.name == db.texture then cur = i end
        end
        cur = button == "RightButton" and (cur - 2) % #list + 1 or cur % #list + 1
        db.texture = list[cur].name
        Changed()
    end)
    Tooltip(style, "Bar style", "The texture of the health and power bars. Bar textures other addons "
        .. "share are in the list too.\n\nLeft-click for the next one, right-click for the one before.")

    local barHeight = NumberBox("Bar height:", style, "barHeight", 99)
    Tooltip(barHeight, "Bar height", "The health bar's height. The power bar under it keeps to about a "
        .. "quarter of that. 0 = 22.")

    -- a row of number boxes starts from this, NumberBox puts its label to the right of it
    local sizeRow = CreateFrame("Frame", nil, f)
    sizeRow:SetSize(1, 22)
    sizeRow:SetPoint("TOPLEFT", style, "BOTTOMLEFT", -12, -6)
    local width = NumberBox("Width:", sizeRow, "width", 999)
    Tooltip(width, "Width", "Each member's frame width. It's never narrower than its buttons. 0 = 100.")
    local scale = NumberBox("Scale %:", width, "scale", 200)
    Tooltip(scale, "Scale", "The size of the whole party frame, buttons too, from 50 to 200 percent.")
    local gap = NumberBox("Spacing:", scale, "gap", 30)
    Tooltip(gap, "Button spacing", "Pixels between the buttons, side by side and between rows, from 0 to "
        .. "30. 2 by default.")

    -- the checkboxes go in a grid of two columns, related ones side by side
    local checks = CreateFrame("Frame", nil, f)
    checks:SetSize(1, 1)
    checks:SetPoint("TOPLEFT", sizeRow, "BOTTOMLEFT", 12, -6)
    local function Grid(c, row, col, full)
        c:SetPoint("TOPLEFT", checks, "TOPLEFT", (col - 1) * CHECK_COLUMN, -(row - 1) * CHECK_ROW)
        -- the label is clickable too, up to the next column
        c:SetHitRectInsets(0, full and -(2 * CHECK_COLUMN - 30) or -(CHECK_COLUMN - 30), 0, 0)
    end

    local solo = Check(f, "My frame when solo", function(v)
        OCC.SetSolo(v)
    end)
    Grid(solo, 1, 1)
    Tooltip(solo, "Your frame when not in a group", "Shows your own frame when you're not in a group, "
        .. "so you can cast the buttons' spells on yourself.")
    local targetFrame = Check(f, "Target frame", function(v)
        OCC.SetTargetFrame(v)
    end)
    Grid(targetFrame, 1, 2)
    Tooltip(targetFrame, "Target frame", "When you target a friendly player who isn't in your party, a "
        .. "frame for them shows under the party, with your buttons, so you can heal them too.\n\nIn "
        .. "combat it can show for friendly NPCs too: the game only lets it check that much then. It "
        .. "never shows anyone the party frame shows.")

    local hideBlizzard = Check(f, "Hide Blizzard's party frames", function(v)
        OCC.SetHideBlizzard(v)
    end)
    Grid(hideBlizzard, 2, 1)
    Tooltip(hideBlizzard, "Hide Blizzard's party frames", "Hides Blizzard's own party frames, so only this "
        .. "one shows. Changes apply out of combat.")
    local classColors = Check(f, "Class colours", function(v)
        OCC.SetClassColors(v)
    end)
    Grid(classColors, 2, 2)
    Tooltip(classColors, "Class colours", "Health bars in each member's class colour, a little dimmed so "
        .. "names stay readable. Off, they're green.")

    local roles = Check(f, "Role icons", function(v)
        OCC.SetRoles(v)
    end)
    Grid(roles, 3, 1)
    Tooltip(roles, "Role icons", "A tank, healer or damage icon left of each member's name, from the "
        .. "group finder or a role check.")
    local heals = Check(f, "Incoming heals", function(v)
        OCC.SetHeals(v)
    end)
    Grid(heals, 3, 2)
    Tooltip(heals, "Incoming heals", "Heals being cast on a member show on their health bar past its end, "
        .. "yours in bright green, everyone else's in darker green.")

    local buffs = Check(f, "Buffs", function(v)
        OCC.SetBuffs(v)
    end)
    Grid(buffs, 4, 1)
    Tooltip(buffs, "Buffs", "Your buffs on each member, ex: Renew, at the bottom right of their health bar. "
        .. "Changes apply out of combat.")
    local debuffs = Check(f, "Debuffs", function(v)
        OCC.SetDebuffs(v)
    end)
    Grid(debuffs, 4, 2)
    Tooltip(debuffs, "Debuff icons", "Each member's debuffs at the bottom left of their bars, bordered in "
        .. "the colour of their dispel type. Changes apply out of combat.")

    local dispel = Check(f, "Dispel colours", function(v)
        OCC.SetDispel(v)
    end)
    Grid(dispel, 5, 1)
    Tooltip(dispel, "Dispel colours", "A member's health bar tinted when they have a debuff that can be "
        .. "dispelled: blue magic, purple curse, brown disease, green poison. Changes apply out of combat.")
    local dispelMine = Check(f, "Only debuffs I can dispel", function(v)
        OCC.SetDispelMine(v)
    end)
    Grid(dispelMine, 5, 2)
    Tooltip(dispelMine, "Only debuffs I can dispel", "The tint shows only for debuffs you can dispel, by "
        .. "your class and the spells you know. Off, any curse, poison, disease or magic debuff tints the "
        .. "bar. Changes apply out of combat.")

    local threat = Check(f, "Threat border", function(v)
        OCC.SetThreat(v)
    end)
    Grid(threat, 6, 1)
    Tooltip(threat, "Threat border", "A border round a member with threat: yellow, orange, then red when "
        .. "they have aggro.")
    local swipes = Check(f, "Buff swipes", function(v)
        OCC.SetSwipes(v)
    end)
    Grid(swipes, 6, 2)
    Tooltip(swipes, "Buff swipes", "A swipe on a spell button while your buff from that spell is on the "
        .. "member, ex: Renew. It darkens as the buff runs out. Not on macro buttons. Changes apply out "
        .. "of combat.")
    local dispelGlow = Check(f, "Dispel glow", function(v)
        OCC.SetDispelGlow(v)
    end)
    Grid(dispelGlow, 7, 1)
    -- its label only, so the style button beside it gets its own clicks
    dispelGlow:SetHitRectInsets(0, -70, 0, 0)
    Tooltip(dispelGlow, "Dispel button glow", "A dispel spell's button lights up while the member "
        .. "has a debuff it can remove, in the debuff's colour: blue magic, purple curse, brown disease, "
        .. "green poison. Ex: Dispel Magic, Cure Disease, Remove Curse, Cleanse. Works in combat. Pick its "
        .. "look with the button beside it. Changes apply out of combat.")
    -- the glow's look: left-click for the next one, right-click for the one before
    local dispelStyle = Button(f, "Border", 100, nil)
    dispelStyle:SetPoint("LEFT", dispelGlow, "LEFT", 104, 0)
    dispelStyle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    dispelStyle:SetScript("OnClick", function(_, button)
        local styles, cur = OCC.DISPEL_STYLES, 1
        for i, s in ipairs(styles) do
            if s == OCC.DispelStyle() then cur = i end
        end
        cur = button == "RightButton" and (cur - 2) % #styles + 1 or cur % #styles + 1
        OCC.SetDispelStyle(styles[cur])
    end)
    Tooltip(dispelStyle, "Dispel glow look", "|cffffffffBorder|r: a thin border round the button.\n"
        .. "|cffffffffThick border|r: a wider one.\n|cffffffffGlow|r: the action bar's glowing edge, past the "
        .. "button's sides.\n|cffffffffTint|r: the colour over the whole icon.\n|cffffffffCorner|r: a square "
        .. "in the top right corner.\n|cffffffffSpell alert|r: the action bar's gold proc glow, "
        .. "whatever the debuff.\n\nLeft-click for the next one, right-click for the one before. Try "
        .. "them with Preview. Changes apply out of combat.")
    local blocked = Check(f, "Can't-cast marks", function(v)
        OCC.SetBlocked(v)
    end)
    Grid(blocked, 7, 2)
    Tooltip(blocked, "Can't-cast marks", "A red mark on a spell button while the member has a debuff that "
        .. "stops you casting it on them: Weakened Soul for Power Word: Shield, Forbearance for Blessing "
        .. "of Protection. A swipe shows when it wears off. Macro buttons get it too, by the macro's spell. "
        .. "Changes apply out of combat.")

    local memberTooltips = Check(f, "Member tooltips", function(v)
        OCC.SetMemberTooltips(v)
    end)
    Grid(memberTooltips, 8, 1)
    Tooltip(memberTooltips, "Member tooltips", "Hovering a member shows their tooltip in the bottom right "
        .. "of the screen, like Blizzard's party frames, clear of the bars.")
    local tooltips = Check(f, "Button tooltips", function(v)
        OCC.SetTooltips(v)
    end)
    Grid(tooltips, 8, 2)
    Tooltip(tooltips, "Button tooltips", "Tooltips on the buttons, by the button. Off, they don't cover the bars.")

    local minimap = Check(f, "Minimap button", function(v)
        OCC.DB().minimap.hide = not v
        OCC.UpdateMinimap()
    end)
    Grid(minimap, 9, 1)
    local debug = Check(f, "Print each click in chat (debug)", function(v)
        OCC.DB().debug = v
    end)
    Grid(debug, 9, 2)

    -- the members' order: left-click for the next one, right-click for the one before
    local SORT_NAMES = { group = "Group", role = "Role", name = "Name" }
    local SORT_ORDER = { "group", "role", "name" }
    local sort = Button(f, "Sort", 220, nil)
    sort:SetPoint("TOPLEFT", checks, "TOPLEFT", 0, -9 * CHECK_ROW - 4)
    sort:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sort:SetScript("OnClick", function(_, button)
        local cur = 1
        for i, s in ipairs(SORT_ORDER) do
            if s == OCC.DB().sort then cur = i end
        end
        cur = button == "RightButton" and (cur - 2) % #SORT_ORDER + 1 or cur % #SORT_ORDER + 1
        OCC.SetSort(SORT_ORDER[cur])
    end)
    Tooltip(sort, "Sort", "The members' order. Group: you, then the party in group order. Role: tanks, "
        .. "healers, then damage. Name: alphabetical.\n\nLeft-click for the next one, right-click for the "
        .. "one before. Changes apply out of combat.")
    -- beside Sort, so the window keeps its height
    local shiftRight = Check(f, "Shift-right: 2 ranks lower", function(v)
        OCC.SetShiftRight(v)
    end)
    Grid(shiftRight, 10, 2)
    Tooltip(shiftRight, "Shift-right-click two ranks lower", "On a spell button whose shift-click is "
        .. "auto (a rank lower), shift-right-click casts it two ranks lower. Off, shift-right-click does "
        .. "what shift-click does. Buttons with their own shift-click action don't change.\n\nChanges "
        .. "apply out of combat.")

    local byName = Check(f, "Cast by name and rank", function(v)
        OCC.SetByName(v)
    end)
    Grid(byName, 11, 1)
    local rangeRed = Check(f, "Red when out of range", function(v)
        OCC.SetRangeRed(v)
    end)
    -- under Cast by name: beside it is the Rebuild button
    Grid(rangeRed, 12, 1)
    -- the reminder glow's look, beside Red when out of range: left-click for the next, right for the one
    -- before. Kept on dispelStyle: Refresh is at Lua 5.1's limit of 60 upvalues.
    local remindGlow = Button(f, "Reminder glow", 212, nil)
    remindGlow:SetPoint("TOPLEFT", checks, "TOPLEFT", CHECK_COLUMN, -11 * CHECK_ROW - 2)
    remindGlow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    remindGlow:SetScript("OnClick", function(_, button)
        local list, cur = OCC.REMIND_GLOWS, 1
        for i, s in ipairs(list) do
            if s == OCC.DB().remindGlow then cur = i end
        end
        cur = button == "RightButton" and (cur - 2) % #list + 1 or cur % #list + 1
        OCC.SetRemindGlowStyle(list[cur])
    end)
    Tooltip(remindGlow, "Reminder glow", "The glow on a button, and on its icon beside the frame, while a "
        .. "member is missing its buff, as Buff Reminder has them.\n|cffffffffPulse|r: fades in and out.\n"
        .. "|cffffffffFlash|r: fades fast.\n|cffffffffSteady|r: stays lit.\n|cffffffffSpell alert|r: the "
        .. "game's proc glow, or Pulse where the game doesn't have it.\n|cffffffffNone|r: no glow.\n\n"
        .. "Left-click for the next one, right-click for the one before. Try them with Preview.")
    dispelStyle.remindGlow = remindGlow
    Tooltip(rangeRed, "Red when out of range", "A red overlay on a member's buttons while they're out of "
        .. "range, as well as the faded bars. Works in combat.")
    Tooltip(byName, "Cast by name and rank", "Spell buttons cast by name and rank, ex: Heal(Rank 2), "
        .. "instead of by spell id. Try it if a button casts the wrong rank or nothing at all.\n\n"
        .. "Changes apply out of combat.")
    -- the slash commands that do something now rather than set something
    local rebuild = Button(f, "Rebuild", 106, function()
        OCC.Sync()
        OCC.Print(("%d members showing."):format(OCC.ShownMembers()))
        OCC.RefreshConfig()
    end)
    rebuild:SetPoint("TOPLEFT", checks, "TOPLEFT", CHECK_COLUMN, -10 * CHECK_ROW - 4)
    Tooltip(rebuild, "Rebuild", "Sets up the party frame and its buttons again, in case something looks "
        .. "out of date. In combat it waits until combat ends.")
    local report = Button(f, "Frame report", 106, function() OCC.FrameReport() end)
    report:SetPoint("LEFT", rebuild, "RIGHT", 4, 0)
    Tooltip(report, "Frame report", "Prints the party frame's state in chat, and what unit info the game "
        .. "hides right now, for finding problems.")

    local status = Label(f, "", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 14)
    status:SetPoint("RIGHT", f, "RIGHT", -16, 0)

    function f:Refresh()
        local db = OCC.DB()
        local actions = db.actions
        if selected and not actions[selected] then selected = nil end
        local shift = tab == "shift"
        if shift then
            help:SetText("What |cffffffffshift-click|r on each button casts. |cffffd100Auto|r is the button's "
                .. "spell a rank lower, or its macro. Select a button, then set a spell or macro, or drag one "
                .. "onto it. The X goes back to auto.")
        else
            help:SetText("These buttons go under each party member's bars. |cffffffffClick|r one to cast on "
                .. "that member, |cffffffffshift-click|r for its shift-click action, |cffffffffright-click|r for "
                .. OCC.RIGHT[db.right] .. ". In a macro, write |cffffffff@unit|r where the member goes, ex: "
                .. "/cast [@unit] Renew")
        end
        if shift then
            clickTab:UnlockHighlight()
            shiftTab:LockHighlight()
        else
            clickTab:LockHighlight()
            shiftTab:UnlockHighlight()
        end
        addSpell:SetText(shift and "Set spell..." or "Add spell...")
        addMacro:SetText(shift and "Set macro..." or "Add macro...")
        addSpell:SetEnabled(not shift or selected ~= nil)
        addMacro:SetEnabled(not shift or selected ~= nil)
        if shift and not selected and picker.kind ~= "sets" then picker:Hide() end
        local cur = CurrentSet()
        local mark = OCC.Unsaved() and (cur and "  |cff808080(changed)|r" or "  |cff808080(not saved)|r") or ""
        sets:SetText("Set: " .. (cur or "none") .. mark)
        if picker:IsShown() and picker.kind == "sets" then
            picker.rows = SetRows()
            picker:Update()
        elseif picker:IsShown() and picker.kind == "rank" then
            local rows = selected and RankRows(actions[selected])
            if rows then
                picker.rows = rows
                picker:Update()
            else
                picker:Hide()
            end
        end
        dropHint:SetText(shift and "or drag one onto a button" or "or drag them here")

        local items = {}
        for i, a in ipairs(actions) do table.insert(items, shift and ShiftItem(i, a) or ActionItem(i, a)) end
        if #items == 0 then
            items[1] = { text = "|cff808080No buttons yet. Add a spell or a macro.|r" }
        end
        list:SetItems(items)

        local a = selected and actions[selected]
        rank.classes:SetEnabled(a and true or false)
        local filter = a and OCC.ClassesText(a)
        if filter and #filter > 12 then
            local n = 0
            for _ in pairs(a.classes) do n = n + 1 end
            filter = n .. " classes"
        end
        rank.classes:SetText("Classes: " .. (filter or "all"))
        if picker:IsShown() and picker.kind == "class" then
            local rows = selected and rank.classes.Rows(selected)
            if rows then
                picker.rows = rows
                picker:Update()
            else
                picker:Hide()
            end
        end
        up:SetEnabled(selected ~= nil and selected > 1)
        down:SetEnabled(selected ~= nil and selected < #actions)
        selfOnly:SetEnabled(a and true or false)
        selfOnly:SetChecked(a and a.self and true or false)
        if a then
            selfOnly.label:SetTextColor(1, 1, 1)
        else
            selfOnly.label:SetTextColor(0.5, 0.5, 0.5)
        end
        local canRemind = a and a.spell and true or false
        remind:SetEnabled(canRemind)
        remind:SetChecked(canRemind and a.remind and true or false)
        remindOnly:SetEnabled(canRemind)
        remindOnly:SetChecked(canRemind and a.remindOnly and true or false)
        noDownrank:SetEnabled(canRemind)
        noDownrank:SetChecked(canRemind and a.noDownrank and true or false)
        if canRemind then
            remind.label:SetTextColor(1, 1, 1)
            remindOnly.label:SetTextColor(1, 1, 1)
            noDownrank.label:SetTextColor(1, 1, 1)
        else
            remind.label:SetTextColor(0.5, 0.5, 0.5)
            remindOnly.label:SetTextColor(0.5, 0.5, 0.5)
            noDownrank.label:SetTextColor(0.5, 0.5, 0.5)
        end
        -- the rank button: the spell it sets the rank of, the rank that casts now, and the rank set
        local spell, r, set, auto
        if shift and a then
            local kind, s = OCC.ResolveShift(a)
            spell = ShiftRankChoices(a)
            r = kind == "spell" and s or nil
            set, auto = a.shift and a.shift.rank, not a.shift
        elseif a and a.spell then
            spell, r, set = a.spell, OCC.ResolveSpell(a), a.rank
        end
        if spell then
            rank:Enable()
            local shown = auto and "Auto" or set and ("Rank " .. set) or "Highest"
            if not set and r and r.rank then shown = shown .. " (" .. r.rank .. ")" end
            rank:SetText("Rank: " .. shown)
        else
            rank:Disable()
            rank:SetText(a and "Rank: macro" or "Rank")
        end

        lock:SetText(db.unlocked and "Lock frame" or "Unlock frame")
        preview:SetText(OCC.Previewing() and "End preview" or "Preview")
        right:SetText("Right-click: " .. OCC.RIGHT[db.right])
        if not perRow:HasFocus() then perRow:SetText(tostring(db.perRow)) end
        if not size:HasFocus() then size:SetText(tostring(db.size)) end
        if not width:HasFocus() then width:SetText(tostring(db.width)) end
        if not barHeight:HasFocus() then barHeight:SetText(tostring(db.barHeight)) end
        if not scale:HasFocus() then scale:SetText(tostring(db.scale)) end
        if not gap:HasFocus() then gap:SetText(tostring(db.gap)) end
        style:SetText("Bars: " .. db.texture)
        minimap:SetChecked(not db.minimap.hide)
        debug:SetChecked(db.debug and true or false)
        byName:SetChecked(db.byname and true or false)
        solo:SetChecked(db.solo and true or false)
        hideBlizzard:SetChecked(db.hideBlizzard and true or false)
        classColors:SetChecked(db.classColors and true or false)
        buffs:SetChecked(db.buffs and true or false)
        debuffs:SetChecked(db.debuffs and true or false)
        threat:SetChecked(db.threat and true or false)
        heals:SetChecked(db.heals and true or false)
        roles:SetChecked(db.roles and true or false)
        dispel:SetChecked(db.dispel and true or false)
        dispelMine:SetChecked(db.dispelMine and true or false)
        dispelMine:SetEnabled(db.dispel and true or false)
        swipes:SetChecked(db.swipes and true or false)
        blocked:SetChecked(db.blocked and true or false)
        dispelGlow:SetChecked(db.dispelGlow and true or false)
        dispelStyle:SetText(OCC.DISPEL_STYLE_NAMES[OCC.DispelStyle()])
        dispelStyle:SetEnabled(db.dispelGlow and true or false)
        dispelStyle.remindGlow:SetText("Reminder glow: " .. (OCC.REMIND_GLOW_NAMES[db.remindGlow] or "Pulse"))
        rangeRed:SetChecked(db.rangeRed and true or false)
        memberTooltips:SetChecked(db.memberTooltips and true or false)
        targetFrame:SetChecked(db.targetFrame and true or false)
        shiftRight:SetChecked(db.shiftRight and true or false)
        tooltips:SetChecked(db.tooltips and true or false)
        sort:SetText("Sort: " .. (SORT_NAMES[db.sort] or db.sort))

        local frames = OCC.ShownMembers()
        if OCC.Pending() or InCombatLockdown() then
            status:SetText("|cffffd100In combat: changes apply when combat ends.|r")
        elseif frames == 0 then
            status:SetText("|cff808080The party frame shows when you're in a group, or tick \"Show my frame "
                .. "when not in a group\".|r")
        else
            status:SetText(("|cff808080Showing %d member%s.|r"):format(frames, frames == 1 and "" or "s"))
        end
    end

    f:SetScript("OnShow", function(self) self:Refresh() end)
    f:SetScript("OnHide", function() picker:Hide() end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self) if self:IsShown() then self:Refresh() end end)
    return f
end

function OCC.RefreshConfig()
    if config and config:IsShown() then config:Refresh() end
end

function OCC.ToggleConfig()
    config = config or CreateConfig()
    config:SetShown(not config:IsShown())
end

-- the sets menu, from right-clicking the minimap button ------------------------------------------

local MENU_ROWS = 10
local setsMenu
local minimapButton

local function CreateSetsMenu()
    local m = Box(UIParent, "Interface\\DialogFrame\\UI-DialogBox-Background")
    _G.OpcowsClickCastSetsMenu = m
    table.insert(UISpecialFrames, "OpcowsClickCastSetsMenu")
    m:SetWidth(220)
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:Hide()
    local title = Label(m, "Button sets")
    title:SetPoint("TOPLEFT", 10, -9)
    m.list = ScrollList(m, 204, 100)
    m.list:SetPoint("TOPLEFT", 8, -26)

    function m:Fill()
        local items = {}
        for _, name in ipairs(OCC.SetNames()) do
            table.insert(items, SetItem(name, function()
                self:Hide()
                OCC.ChooseSet(name)
            end))
        end
        if #items == 0 then
            items[1] = { text = "|cff808080No sets yet, save one in Options.|r" }
        end
        table.insert(items, {
            text = "|cffffd100Options...|r",
            onClick = function()
                self:Hide()
                config = config or CreateConfig()
                config:Show()
            end,
        })
        self.list:SetItems(items)
        local height = math.min(#items, MENU_ROWS) * ROW_HEIGHT + 8
        self.list:SetHeight(height)
        self:SetHeight(height + 34)
    end

    -- a click anywhere else closes it. The minimap button's own click toggles it.
    m:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver()
            and not (minimapButton and minimapButton:IsMouseOver()) then
            self:Hide()
        end
    end)
    m:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    m:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    return m
end

-- opens or closes the sets menu, by anchor or by the cursor when there's none
local function ToggleSetsMenu(anchor)
    setsMenu = setsMenu or CreateSetsMenu()
    if setsMenu:IsShown() then
        setsMenu:Hide()
        return
    end
    GameTooltip:Hide()
    setsMenu:ClearAllPoints()
    if anchor then
        setsMenu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        setsMenu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    setsMenu:Fill()
    setsMenu:Show()
end

-- addon compartment (the addons button by the minimap) -------------------------------------------

function OpcowsClickCast_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        ToggleSetsMenu()
    else
        OCC.ToggleConfig()
    end
end

function OpcowsClickCast_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Opcow's Click Cast")
    GameTooltip:AddLine("Left-click: options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: button sets", 1, 1, 1)
    local cur = CurrentSet()
    GameTooltip:AddLine("Set: " .. (cur or "none") .. (OCC.Unsaved() and (cur and " (changed)" or " (not saved)")
        or ""), 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function OpcowsClickCast_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- minimap button, drag to move it around the minimap ---------------------------------------------

local function PlaceMinimapButton()
    local angle = math.rad(OCC.DB().minimap.angle or 225)
    -- on the edge of the minimap, whatever size it is
    local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "OpcowsClickCastMinimapButton", Minimap)
    -- same layout as LibDBIcon so it matches other addons' buttons
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER")
    -- round it off, or the square icon's corners show outside the border
    if b.CreateMaskTexture then
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ToggleSetsMenu(self)
        else
            if setsMenu then setsMenu:Hide() end
            OCC.ToggleConfig()
        end
    end)
    b:SetScript("OnEnter", function(self) OpcowsClickCast_OnAddonCompartmentEnter(nil, self) end)
    b:SetScript("OnLeave", OpcowsClickCast_OnAddonCompartmentLeave)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            OCC.DB().minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

function OCC.UpdateMinimap()
    if not Minimap then return end
    local hide = OCC.DB().minimap.hide
    if hide and not minimapButton then return end
    minimapButton = minimapButton or CreateMinimapButton()
    PlaceMinimapButton()
    minimapButton:SetShown(not hide)
end
