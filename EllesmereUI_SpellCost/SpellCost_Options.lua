if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SpellCost \ SpellCost_Options.lua   (standalone add-on)
--  The EXTRAS section at the bottom of every Action Bars > Bar Display tab --
--  Spell Cost text (mana / rage / energy cost on each button). Every setting
--  is per bar; the sync icon on the master row copies the whole set to other
--  bars. Runtime: SpellCost.lua.
--
--  EllesmereUIOptions loads on demand. Once it has loaded, the shared EXTRAS
--  host (ns._EUIExtras, same block in EllesmereUI_SpellRank) wraps the Action
--  Bars page builder ns.ABO_BuildBarAppearance once, draws one EXTRAS header
--  and appends each extras add-on's rows in order. No EllesmereUI file is
--  edited; each extras add-on works without the others.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local ns = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not (ns and ns.SpellCost) then return end  -- module or runtime off: no options

-------------------------------------------------------------------------------
--  Shared EXTRAS host (same block in every EllesmereUI extras add-on; the
--  first one loaded creates it, the others reuse it).
-------------------------------------------------------------------------------
local X = ns._EUIExtras
if not X then
    X = { builders = {} }
    ns._EUIExtras = X
end
if not X.Install then
    local function Pack(...) return { n = select("#", ...), ... } end
    function X.Register(id, order, fn)
        X.builders[id] = { order = order, fn = fn }
    end
    -- The EXTRAS header, once per page build (first section that shows).
    function X.Header(parent, y, W)
        if X.headerDone then return y end
        X.headerDone = true
        local _, h = W:SectionHeader(parent, "EXTRAS", y)
        return y - h
    end
    function X.Install()
        if X.hooked then return true end
        local orig = ns.ABO_BuildBarAppearance
        if type(orig) ~= "function" then return false end
        X.hooked = true
        ns.ABO_BuildBarAppearance = function(parent, y, ctx, ...)
            local r = Pack(orig(parent, y, ctx, ...))
            -- r[1] is the page's running y; the rest passes through. A
            -- failing section must never break the page.
            if type(r[1]) == "number" then
                X.headerDone = false
                local list = {}
                for _, b in pairs(X.builders) do list[#list + 1] = b end
                table.sort(list, function(a, b) return a.order < b.order end)
                for _, b in ipairs(list) do
                    local ok, newY = pcall(b.fn, parent, r[1], ctx)
                    if ok and type(newY) == "number" then
                        r[1] = newY
                    elseif not ok then
                        geterrorhandler()(newY)
                    end
                end
            end
            return unpack(r, 1, r.n)
        end
        return true
    end
end


local ANCHOR_LABELS = {
    TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}
local ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local COLOR_MODE_LABELS = { custom = "Custom Color", power = "Power Type Color" }
local COLOR_MODE_ORDER  = { "custom", "power" }

local BG_MODE_LABELS = { none = "None", custom = "Custom Color", power = "Power Type Color" }
local BG_MODE_ORDER  = { "none", "custom", "power" }

local OUTLINE_LABELS = { default = "Action Bars Default", OUTLINE = "Outline",
    THICKOUTLINE = "Thick Outline", NONE = "None (Shadow)" }
local OUTLINE_ORDER  = { "default", "OUTLINE", "THICKOUTLINE", "NONE" }

local function CopyValue(v)
    if type(v) == "table" then
        return { r = v.r, g = v.g, b = v.b, a = v.a }
    end
    return v
end

-------------------------------------------------------------------------------
--  Power Type Color sample panel: shown while the cursor is over the "Text
--  Color" or "Cost Background" label. One row per power type, each with a
--  "65" drawn exactly as the bars draw it (SC.StyleFont / SC.PaintColors with
--  the selected bar's own settings, the row's mode forced to Power Type).
-------------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SAMPLE_TYPES = { { 0, "Mana" }, { 1, "Rage" }, { 3, "Energy" }, { 2, "Focus" } }
local SAMPLE_TEXT = "65"
local panel

local function GetPanel()
    if panel then return panel end
    panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetFrameStrata("TOOLTIP")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    panel:Hide()
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.rows = {}
    for i = 1, #SAMPLE_TYPES do
        panel.rows[i] = {
            bg   = panel:CreateTexture(nil, "ARTWORK"),
            fs   = panel:CreateFontString(nil, "OVERLAY"),
            name = panel:CreateFontString(nil, "OVERLAY"),
        }
        panel.rows[i].fs:SetWordWrap(false)
    end
    return panel
end

-- owner: the hovered label; s: the bar's settings; forceKey: the mode key the
-- hovered row sets ("costColorMode" / "costBgMode"); title: panel heading.
local function ShowSamples(owner, s, forceKey, title)
    local SC = ns.SpellCost
    if not SC then return end
    local f = GetPanel()
    local view = setmetatable({ [forceKey] = "power" }, { __index = s })
    local D = SC.DEFAULTS
    local size = s.costFontSize or D.costFontSize
    local pad = s.costBgPad or D.costBgPad
    local bodyFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    local PADX, CELL_W = 12, math.max(44, size * 2 + pad * 2 + 16)
    local ROW_H = math.max(24, size + pad * 2 + 8)

    f.title:SetFont(bodyFont, 13, "")
    f.title:SetTextColor(1, 1, 1)
    f.title:SetText(title)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PADX, -10)

    local y = -10 - 13 - 10
    local nameW = 0
    for i, t in ipairs(SAMPLE_TYPES) do
        local row = f.rows[i]
        local cy = y - ROW_H / 2
        SC.StyleFont(row.fs, view)
        row.fs:SetText(SAMPLE_TEXT)
        row.fs:SetJustifyH("CENTER")
        row.fs:ClearAllPoints()
        row.fs:SetPoint("CENTER", f, "TOPLEFT", PADX + CELL_W / 2, cy)
        row.bg:ClearAllPoints()
        row.bg:SetPoint("TOPLEFT", row.fs, "TOPLEFT", -pad, pad)
        row.bg:SetPoint("BOTTOMRIGHT", row.fs, "BOTTOMRIGHT", pad, -pad)
        SC.PaintColors(row.fs, row.bg, view, t[1])

        row.name:SetFont(bodyFont, 13, "")
        local r, g, b = SC.PowerColor(t[1])
        row.name:SetTextColor(r or 1, g or 1, b or 1)
        row.name:SetText(t[2])
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", f, "TOPLEFT", PADX + CELL_W + 10, cy)
        nameW = math.max(nameW, row.name:GetStringWidth() or 0)
        y = y - ROW_H
    end

    local w = math.max(PADX + CELL_W + 10 + nameW + PADX, (f.title:GetStringWidth() or 0) + PADX * 2)
    f:SetSize(math.ceil(w), math.ceil(-y + 10))
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -6, 8)
    f:Show()
end

-- Hover area over a DualRow half's label that opens the sample panel.
local function AttachSamples(region, getSettings, forceKey, title)
    if EllesmereUI._prebuilding then return end
    local label = region and region._label
    if not label then return end
    local hit = CreateFrame("Frame", nil, region)
    hit:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
    hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
    hit:SetFrameLevel(region:GetFrameLevel() + 10)
    hit:EnableMouseMotion(true)
    hit:SetMouseClickEnabled(false)
    hit:SetScript("OnEnter", function(self) ShowSamples(self, getSettings(), forceKey, title) end)
    hit:SetScript("OnLeave", function() if panel then panel:Hide() end end)
    hit:SetScript("OnHide", function() if panel then panel:Hide() end end)
end

local function BuildSpellCost(parent, y, ctx)
    local env = ns._ABO_OptEnv
    local SC = ns.SpellCost
    if not (SC and env and env.EAB and env.SB and env.SelectedKey and ctx and ctx.W) then return y end
    local EAB, GROUP_BAR_ORDER, PP = env.EAB, env.GROUP_BAR_ORDER, env.PP
    local SB, SelectedKey, SHORT_LABELS = env.SB, env.SelectedKey, env.SHORT_LABELS
    local W = ctx.W
    local _, h

    -- Stance / pet buttons have no spell cost: no section for them.
    if not SC.IsCostBar(SelectedKey()) then return y end

    local D = SC.DEFAULTS
    local function Get(key)
        local v = SB()[key]
        if v == nil then return D[key] end
        return v
    end
    local function Apply(k) SC.ApplyBar(k) end
    local function Set(key, v)
        SB()[key] = v
        Apply(SelectedKey())
        EllesmereUI:RefreshPage()
    end

    -- Bars the sync icon may copy to (stance / pet excluded).
    local COST_BARS = {}
    for _, key in ipairs(GROUP_BAR_ORDER) do
        if SC.IsCostBar(key) then COST_BARS[#COST_BARS + 1] = key end
    end

    local function CopyTo(key)
        local src, dst = SB(), EAB.db.profile.bars[key]
        if not dst or dst == src then return end
        for _, k in ipairs(SC.KEYS) do dst[k] = CopyValue(src[k]) end
        Apply(key)
    end
    -- nil reads as the default, and a missing default as false.
    local function Norm(v, k)
        if v == nil then v = D[k] end
        if v == nil then v = false end
        return v
    end
    local function Same(key)
        local src, dst = SB(), EAB.db.profile.bars[key]
        if not dst then return true end
        for _, k in ipairs(SC.KEYS) do
            local a, b = src[k], dst[k]
            if type(a) == "table" or type(b) == "table" then
                a, b = a or {}, b or {}
                if a.r ~= b.r or a.g ~= b.g or a.b ~= b.b or a.a ~= b.a then return false end
            elseif Norm(a, k) ~= Norm(b, k) then
                return false
            end
        end
        return true
    end

    -- BuildBarAppearance already closes with a 20px spacer.
    y = X.Header(parent, y, W)

    -------------------------------------------------------------------
    --  Master row: Show Spell Cost | Font
    -------------------------------------------------------------------
    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    local masterRow
    masterRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Spell Cost",
          tooltip="Shows the mana / rage / energy cost of the spell on each button of this bar.",
          getValue=function() return SB().costEnabled and true or false end,
          -- Section gate: the rows below are built only while on.
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              SB().costEnabled = v and true or false
              Apply(SelectedKey())
          end) },
        { type="dropdown", text="Cost Font",
          values=fontValues, order=fontOrder,
          disabled=function() return not SB().costEnabled end,
          disabledTooltip="Show Spell Cost",
          getValue=function() return Get("costFont") end,
          setValue=function(v) Set("costFont", v) end });  y = y - h

    do
        local rgn = masterRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Spell Cost Settings to all Bars",
            onClick = function()
                for _, key in ipairs(COST_BARS) do CopyTo(key) end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                for _, key in ipairs(COST_BARS) do
                    if not Same(key) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = COST_BARS,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do CopyTo(key) end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    if not SB().costEnabled then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        return y
    end

    -------------------------------------------------------------------
    --  Text Size (+ position cog) | Text Color (+ swatch)
    -------------------------------------------------------------------
    local textRow
    textRow, h = W:DualRow(parent, y,
        { type="slider", text="Cost Text Size", min=6, max=30, step=1, trackWidth=120,
          getValue=function() return Get("costFontSize") end,
          setValue=function(v) Set("costFontSize", v) end },
        { type="dropdown", text="Text Color",
          values=COLOR_MODE_LABELS, order=COLOR_MODE_ORDER,
          getValue=function() return Get("costColorMode") end,
          setValue=function(v) Set("costColorMode", v) end });  y = y - h

    do
        local rgn = textRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Spell Cost Position",
            rows = {
                { type="dropdown", label="Position",
                  values=ANCHOR_LABELS, order=ANCHOR_ORDER,
                  get=function() return Get("costAnchor") end,
                  set=function(v) Set("costAnchor", v) end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return Get("costOffsetX") end,
                  set=function(v) Set("costOffsetX", v) end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return Get("costOffsetY") end,
                  set=function(v) Set("costOffsetY", v) end },
            },
        })
    end

    AttachSamples(textRow._rightRegion, SB, "costColorMode", "Power Type Color - text")

    do
        local rgn = textRow._rightRegion
        local ctrl = rgn._control
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, textRow:GetFrameLevel() + 3,
            function()
                local c = SB().costColor or SC.DEFAULT_COLOR
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                Set("costColor", { r=r, g=g, b=b })
            end,
            false, 20)
        PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = swatch
        local function SwState()
            updateSwatch()
            -- Power Type mode: the swatch is the fallback color for a
            -- spell whose power type can't be read, so keep it but dim it.
            swatch:SetAlpha(Get("costColorMode") == "custom" and 1 or 0.35)
        end
        EllesmereUI.RegisterWidgetRefresh(SwState)
        SwState()
    end

    -------------------------------------------------------------------
    --  Outline | Short Numbers
    -------------------------------------------------------------------
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Cost Text Outline",
          values=OUTLINE_LABELS, order=OUTLINE_ORDER,
          getValue=function() return Get("costOutline") end,
          setValue=function(v) Set("costOutline", v) end },
        { type="toggle", text="Short Numbers",
          tooltip="Shows 1200 as 1.2k.",
          getValue=function() return Get("costShort") and true or false end,
          setValue=function(v) Set("costShort", v and true or false) end });  y = y - h

    -------------------------------------------------------------------
    --  Background (+ swatch with opacity) | Background Padding
    -------------------------------------------------------------------
    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Cost Background",
          values=BG_MODE_LABELS, order=BG_MODE_ORDER,
          getValue=function() return Get("costBgMode") end,
          setValue=function(v) Set("costBgMode", v) end },
        { type="slider", text="Background Padding", min=0, max=8, step=1,
          disabled=function() return Get("costBgMode") == "none" end,
          disabledTooltip="Cost Background",
          getValue=function() return Get("costBgPad") end,
          setValue=function(v) Set("costBgPad", v) end });  y = y - h

    AttachSamples(bgRow._leftRegion, SB, "costBgMode", "Power Type Color - background")

    do
        local rgn = bgRow._leftRegion
        local ctrl = rgn._control
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, bgRow:GetFrameLevel() + 3,
            function()
                local c = SB().costBgColor or SC.DEFAULT_BG
                return c.r, c.g, c.b, c.a or 0.8
            end,
            function(r, g, b, a)
                Set("costBgColor", { r=r, g=g, b=b, a=a or 0.8 })
            end,
            true, 20)
        PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = swatch
        local function SwState()
            updateSwatch()
            -- In Power Type mode only the swatch's opacity is used.
            local mode = Get("costBgMode")
            swatch:SetAlpha(mode == "custom" and 1 or (mode == "power" and 0.6 or 0.25))
        end
        EllesmereUI.RegisterWidgetRefresh(SwState)
        SwState()
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    return y
end

-------------------------------------------------------------------------------
--  Register in the shared EXTRAS host once EllesmereUIOptions has loaded
-------------------------------------------------------------------------------
X.Register("SpellCost", 10, BuildSpellCost)

local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
if not (IsLoaded and IsLoaded("EllesmereUIOptions") and X.Install()) then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "EllesmereUIOptions" then
            X.Install()
            self:UnregisterAllEvents()
        end
    end)
end
