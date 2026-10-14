if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SpellCost \ SpellCost.lua   (standalone add-on)
--
--  Lives in its own folder: no EllesmereUI file is changed. It attaches at run
--  time to the EllesmereUI Action Bars module through the module registry
--  (EllesmereUI._ModuleNS["EllesmereUIActionBars"]); when that module or one of
--  the pieces used here is missing (disabled, or renamed by an EllesmereUI
--  update) the add-on stays silent instead of erroring.
--
--  Spell Cost text: the resource cost (mana / rage / energy / ...) of the
--  spell on each action button, drawn as a small label (default: bottom left
--  corner). Per bar settings (EAB.db.profile.bars[key]):
--    costEnabled    bool    master switch (off = nothing is built or listened)
--    costFont       string  "__global" (Action Bars font) or a font name
--    costFontSize   number  text size
--    costOutline    string  "default" | "OUTLINE" | "THICKOUTLINE" | "NONE"
--    costColorMode  string  "custom" | "power"   text color source
--    costColor      {r,g,b} custom text color
--    costAnchor     string  TOPLEFT .. BOTTOMRIGHT (9 points)
--    costOffsetX/Y  number  offset from the anchor
--    costBgMode     string  "none" | "custom" | "power"   background source
--    costBgColor    {r,g,b,a} custom background color (a = opacity in all modes)
--    costBgPad      number  background padding around the text
--    costShort      bool    1200 -> 1.2k
--
--  Slots are read with GetAttribute("action") (never btn.action: protected).
--  Every value from the cost / action APIs is checked with issecretvalue
--  before any compare or arithmetic; a secret cost is still shown (SetText
--  accepts secrets), a secret power type falls back to the custom colors.
--  Refreshes are coalesced to one pass per burst of events.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local ns = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIActionBars"]
-- Everything used from the Action Bars module; any of it missing = stay off.
if not (ns and type(ns.EAB) == "table" and type(ns.barButtons) == "table"
        and type(ns.BAR_LOOKUP) == "table"
        and type(ns.EAB.ApplyFontsForBar) == "function") then
    return
end

local _G = _G
local ipairs, pairs, type, tonumber = ipairs, pairs, type, tonumber
local format = string.format
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local GetActionInfo = GetActionInfo
local HasAction = HasAction
local GetMacroSpell = GetMacroSpell

local EAB, barButtons, BAR_LOOKUP = ns.EAB, ns.barButtons, ns.BAR_LOOKUP
-- rawget: the module's _internals table errors on a missing key.
local FONT_PATH = (type(ns._internals) == "table" and rawget(ns._internals, "FONT_PATH"))
    or (EllesmereUI.MEDIA_PATH and (EllesmereUI.MEDIA_PATH .. "fonts\\Expressway.TTF"))
    or STANDARD_TEXT_FONT

local issecret = _G.issecretvalue or function() return false end

local SC = {}
ns.SpellCost = SC

-------------------------------------------------------------------------------
--  Defaults / helpers
-------------------------------------------------------------------------------
SC.DEFAULTS = {
    costFont = "__global", costFontSize = 11, costOutline = "default",
    costColorMode = "custom", costAnchor = "BOTTOMLEFT",
    costOffsetX = 1, costOffsetY = 1, costBgMode = "power", costBgPad = 1,
    costShort = false,
}
SC.DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
SC.DEFAULT_BG = { r = 0, g = 0, b = 0, a = 0.8 }
SC.ANCHORS = {
    TOPLEFT = "LEFT", TOP = "CENTER", TOPRIGHT = "RIGHT",
    LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT",
    BOTTOMLEFT = "LEFT", BOTTOM = "CENTER", BOTTOMRIGHT = "RIGHT",
}
-- The keys "Apply to all Bars" copies.
SC.KEYS = { "costEnabled", "costFont", "costFontSize", "costOutline", "costColorMode",
    "costColor", "costAnchor", "costOffsetX", "costOffsetY", "costBgMode",
    "costBgColor", "costBgPad", "costShort" }

-- Power type colors (Enum.PowerType numbers). Mana is brighter than the stock
-- pure blue so a small label stays readable.
local POWER_COLORS = {
    [0] = { 0.18, 0.45, 0.95 },  -- Mana
    [1] = { 0.85, 0.18, 0.18 },  -- Rage
    [2] = { 1.00, 0.50, 0.25 },  -- Focus
    [3] = { 0.90, 0.78, 0.10 },  -- Energy
    [6] = { 0.00, 0.82, 1.00 },  -- Runic Power
}
function SC.PowerColor(ptype)
    if issecret(ptype) or ptype == nil then return nil end
    local c = POWER_COLORS[ptype]
    if c then return c[1], c[2], c[3] end
    local pbc = _G.PowerBarColor and _G.PowerBarColor[ptype]
    if pbc and pbc.r then return pbc.r, pbc.g, pbc.b end
    return nil
end

local function Val(s, key)
    local v = s[key]
    if v == nil then return SC.DEFAULTS[key] end
    return v
end

local function IsCostBar(barKey)
    local info = BAR_LOOKUP[barKey]
    if not info then return false end
    return not (info.isStance or info.isPetBar)
end
SC.IsCostBar = IsCostBar

local function BarEnabled(barKey)
    local s = EAB.db and EAB.db.profile.bars[barKey]
    return s and s.costEnabled and IsCostBar(barKey) and barButtons[barKey] ~= nil
end

-------------------------------------------------------------------------------
--  Cost lookup
-------------------------------------------------------------------------------
-- spellID of an action slot (spell or macro casting a spell), else nil.
local function SlotSpell(slot)
    -- issecretvalue always first: a secret must not be tested or compared.
    if issecret(slot) or slot == nil or not HasAction(slot) then return nil end
    local aType, id, subType = GetActionInfo(slot)
    if issecret(aType) or issecret(id) or aType == nil or id == nil then return nil end
    if aType == "spell" then
        return id
    elseif aType == "macro" then
        if not issecret(subType) and subType == "spell" then
            return id
        end
        if not GetMacroSpell then return nil end
        return (GetMacroSpell(id))
    end
    return nil
end

local GetSpellPowerCost = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost

-- cost, powerType of a spell (the entry that applies now), or nil.
local function SpellCost(spellID)
    if not GetSpellPowerCost or (not issecret(spellID) and spellID == nil) then return nil end
    local ok, costs = pcall(GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return nil end
    local pick
    for i = 1, #costs do
        local c = costs[i]
        local req = c.requiredAuraID
        local has = c.hasRequiredAura
        if issecret(req) or req == nil or req == 0 or (not issecret(has) and has) then
            pick = c
            break
        end
    end
    if not pick then return nil end
    local cost = pick.cost
    if not issecret(cost) then
        if cost == nil then return nil end
        if cost <= 0 then
            local per = pick.costPerSec
            if not issecret(per) and per and per > 0 then
                cost = per
            else
                return nil
            end
        end
    end
    return cost, pick.type
end

local function FormatCost(cost, short)
    if issecret(cost) then return cost end
    if short and cost >= 1000 then
        local t = format("%.1fk", cost / 1000)
        return (t:gsub("%.0k$", "k"))
    end
    return format("%d", math.floor(cost + 0.5))
end

-------------------------------------------------------------------------------
--  Per-button widgets
-------------------------------------------------------------------------------
local widgets = setmetatable({}, { __mode = "k" })  -- btn -> { ov, fs, bg }
local pendingBuild = false

local function GetWidget(btn, create)
    local w = widgets[btn]
    if w or not create then return w end
    -- A plain (insecure) child of a protected button: built out of combat only.
    if InCombatLockdown() then
        pendingBuild = true
        return nil
    end
    local ov = CreateFrame("Frame", nil, btn)
    ov:SetAllPoints(btn)
    local bg = ov:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.8)
    local fs = ov:CreateFontString(nil, "OVERLAY")
    fs:SetWordWrap(false)
    w = { ov = ov, fs = fs, bg = bg }
    widgets[btn] = w
    return w
end

local function OverlayLevel(btn)
    local lvl = btn:GetFrameLevel()
    local cd = btn.cooldown
    if cd and cd.GetFrameLevel then lvl = math.max(lvl, cd:GetFrameLevel()) end
    local toc = btn.TextOverlayContainer
    if toc and toc.GetFrameLevel then lvl = math.max(lvl, toc:GetFrameLevel()) end
    return lvl + 1
end

-- Font, size and outline from bar settings s (shared with the options samples).
function SC.StyleFont(fs, s, fontPath)
    local size = Val(s, "costFontSize")
    local outline = Val(s, "costOutline")
    local flag
    if outline == "NONE" then
        flag = ""
    elseif outline == "OUTLINE" or outline == "THICKOUTLINE" then
        flag = EllesmereUI.SlugFlag and EllesmereUI.SlugFlag(outline .. ", SLUG") or outline
    else
        flag = EllesmereUI.GetIconTextOutlineFlag and EllesmereUI.GetIconTextOutlineFlag("actionBars") or "OUTLINE"
    end
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flag == "") end
    fs:SetFont(fontPath or SC.FontPathFor(s), size, flag)
end

-- Text and background colors for power type ptype (nil/secret = custom colors).
function SC.PaintColors(fs, bg, s, ptype)
    local pr, pg, pb = SC.PowerColor(ptype)
    if Val(s, "costColorMode") == "power" and pr then
        fs:SetTextColor(pr, pg, pb)
    else
        local c = s.costColor or SC.DEFAULT_COLOR
        fs:SetTextColor(c.r, c.g, c.b)
    end
    local bgMode = Val(s, "costBgMode")
    if bgMode == "none" then
        bg:Hide()
    else
        local c = s.costBgColor or SC.DEFAULT_BG
        local a = c.a or 0.8
        if bgMode == "power" and pr then
            bg:SetColorTexture(pr, pg, pb, a)
        else
            bg:SetColorTexture(c.r, c.g, c.b, a)
        end
        bg:Show()
    end
end

-- Style one button's widget from bar settings s (font, anchor, colors).
local function StyleWidget(btn, w, s, fontPath)
    local ov, fs, bg = w.ov, w.fs, w.bg
    if not InCombatLockdown() then ov:SetFrameLevel(OverlayLevel(btn)) end

    SC.StyleFont(fs, s, fontPath)

    local anchor = Val(s, "costAnchor")
    local justify = SC.ANCHORS[anchor]
    if not justify then anchor, justify = "BOTTOMLEFT", "LEFT" end
    fs:ClearAllPoints()
    fs:SetPoint(anchor, ov, anchor, Val(s, "costOffsetX"), Val(s, "costOffsetY"))
    fs:SetJustifyH(justify)

    local pad = Val(s, "costBgPad")
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -pad, pad)
    bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", pad, -pad)
end

-- Paint one button: text + colors from its current action.
local function PaintButton(btn, w, s)
    local slot = btn:GetAttribute("action")
    local cost, ptype = SpellCost(SlotSpell(slot))
    local fs, bg = w.fs, w.bg
    if not issecret(cost) and cost == nil then
        fs:SetText("")
        w.ov:Hide()
        return
    end
    fs:SetText(FormatCost(cost, Val(s, "costShort")))
    SC.PaintColors(fs, bg, s, ptype)
    w.ov:Show()
end

function SC.FontPathFor(s)
    local name = Val(s, "costFont")
    if name == "__global" or not name then
        return EllesmereUI.GetFontPath("actionBars") or FONT_PATH
    end
    return (EllesmereUI.ResolveFontName and EllesmereUI.ResolveFontName(name)) or FONT_PATH
end

-------------------------------------------------------------------------------
--  Bar passes
-------------------------------------------------------------------------------
local hookedButtons = setmetatable({}, { __mode = "k" })
local QueueRefresh  -- forward

local function HookButton(btn)
    if hookedButtons[btn] then return end
    hookedButtons[btn] = true
    -- Paging rewrites the secure "action" attribute; repaint after it.
    btn:HookScript("OnAttributeChanged", function(_, name)
        if name == "action" then QueueRefresh() end
    end)
end

local function HideBar(barKey)
    local buttons = barButtons[barKey]
    if not buttons then return end
    for _, btn in ipairs(buttons) do
        local w = widgets[btn]
        if w then w.fs:SetText(""); w.ov:Hide() end
    end
end

-- Full restyle + repaint of one bar (settings changed / bar rebuilt).
function SC.ApplyBar(barKey)
    if not EAB.db then return end
    if not BarEnabled(barKey) then
        HideBar(barKey)
        SC.UpdateListening()
        return
    end
    local s = EAB.db.profile.bars[barKey]
    local fontPath = SC.FontPathFor(s)
    for _, btn in ipairs(barButtons[barKey]) do
        local w = GetWidget(btn, true)
        if w then
            HookButton(btn)
            StyleWidget(btn, w, s, fontPath)
            PaintButton(btn, w, s)
        end
    end
    SC.UpdateListening()
end

function SC.ApplyAll()
    if not EAB.db then return end
    for barKey in pairs(barButtons) do SC.ApplyBar(barKey) end
end

-- Repaint only (actions / costs changed).
local function RefreshAll()
    if not EAB.db then return end
    for barKey, buttons in pairs(barButtons) do
        if BarEnabled(barKey) then
            local s = EAB.db.profile.bars[barKey]
            for _, btn in ipairs(buttons) do
                local w = widgets[btn]
                if w then
                    PaintButton(btn, w, s)
                else
                    -- Button created after the last apply (bar rebuilt / count grew).
                    pendingBuild = true
                end
            end
        end
    end
    if pendingBuild and not InCombatLockdown() then
        pendingBuild = false
        SC.ApplyAll()
    end
end
SC.RefreshAll = RefreshAll

local queued = false
QueueRefresh = function()
    if queued then return end
    queued = true
    C_Timer_After(0.1, function()
        queued = false
        RefreshAll()
    end)
end
SC.QueueRefresh = QueueRefresh

-------------------------------------------------------------------------------
--  Events (registered only while at least one bar shows costs)
-------------------------------------------------------------------------------
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "UPDATE_MACROS",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELL_UPDATE_USABLE",
    "PLAYER_EQUIPMENT_CHANGED",
    -- Conditional macros ([mod:shift], [harm]/[help], ...) switch spell on
    -- these without any action bar event.
    "MODIFIER_STATE_CHANGED", "PLAYER_TARGET_CHANGED",
}
local ev = CreateFrame("Frame")
local listening = false

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingBuild then
            pendingBuild = false
            SC.ApplyAll()
        end
        return
    end
    if event == "UNIT_MAXPOWER" and unit ~= "player" then return end
    QueueRefresh()
end)

function SC.UpdateListening()
    local want = false
    if EAB.db then
        for barKey in pairs(barButtons) do
            if BarEnabled(barKey) then want = true; break end
        end
    end
    if want == listening then return end
    listening = want
    if want then
        for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        pcall(ev.RegisterUnitEvent, ev, "UNIT_MAXPOWER", "player")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterAllEvents()
    end
end

-------------------------------------------------------------------------------
--  Hooks into the module's own apply paths
-------------------------------------------------------------------------------
-- ApplyFontsForBar runs on profile load / switch, font changes and bar
-- rebuilds: the same moments the cost text must restyle.
hooksecurefunc(EAB, "ApplyFontsForBar", function(_, barKey)
    if barKey and barButtons[barKey] then SC.ApplyBar(barKey) end
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_ENTERING_WORLD")
init:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer_After(0.5, function() SC.ApplyAll() end)
end)
