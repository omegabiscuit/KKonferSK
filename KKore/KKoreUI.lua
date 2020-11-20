--[[
   KahLua Kore - core library functions for KahLua addons.
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com

   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2010 James Kean Johnston. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
]]

local addonName, addonPrivate = ...
local texpath
if (string.lower (addonName) == "kkore") then
  texpath = "Interface\\Addons\\KKore\\Textures\\"
else
  texpath = "Interface\\Addons\\" .. addonName .. "\\KKore\\Textures\\"
end

local KKOREUI_MAJOR = "KKoreUI"
local KKOREUI_MINOR = 700

local KUI = LibStub:NewLibrary(KKOREUI_MAJOR, KKOREUI_MINOR)

if (not KUI) then
  return
end

KUI.TEXTURE_PATH = texpath

local _G = _G
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local UIParent = UIParent
local safecall
local floor = math.floor
local ceil = math.ceil
local CreateFrame = CreateFrame

local K, KM = LibStub:GetLibrary("KKore")
assert (K, "KKoreUI requires KKore")
assert (tonumber(KM) >= 732, "KKoreUI requires KKore r732 or later")
K:RegisterExtension (KUI, KKOREUI_MAJOR, KKOREUI_MINOR)

local safecall = K.pvt.safecall

local borders = {
  { -- Thin
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
    offset = 6,
  },
  { -- Thick
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
    offset = 12,
  }
}

local cfbackdrop = {
  bgFile = "Interface/ChatFrame/ChatFrameBackground",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

KUI.emptydropdown = {
  {
    text = "",
    notcheckable = true,
    notclickable = true,
    enabled = false,
  },
}

local function fixframelevels(parent, ...)
  local l = 1
  local c = select(l, ...)
  local pl = parent:GetFrameLevel () + 1
  while (c) do
    c:SetFrameLevel (pl)
    fixframelevels (c, c:GetChildren ())
    l = l + 1
    c = select(l, ...)
  end
end

function KUI.MakeFrame (ftype, fname, parent, templ)
  local f = CreateFrame (ftype, fname, parent, templ)
  local p = f:GetParent ()
  if (p and p.GetFrameLevel) then
    hooksecurefunc (f, "SetFrameLevel", function (this, level)
      fixframelevels (this, this:GetChildren ())
    end)
  end
  return f
end

local MakeFrame = KUI.MakeFrame

KUI.wcounters = KUI.wcounters or {}

local function add_escclose (fname)
  for k,v in pairs (UISpecialFrames) do
    if (v == fname) then
      return
    end
  end
  tinsert (UISpecialFrames, fname)
end

local function remove_escclose (fname)
  for k,v in pairs (UISpecialFrames) do
    if (v == cfgname) then
      tremove (UISpecialFrames, k)
      return
    end
  end
end

--
-- This invisible frame is used to measure text width.
--
local mframe = CreateFrame ("Frame")
mframe:Hide ()
mframe:SetHeight (64)
mframe:SetWidth (4192)
local mtt = mframe:CreateFontString (nil, "OVERLAY", "GameFontNormal")
mtt:ClearAllPoints ()
mtt:SetPoint ("LEFT", mframe, "LEFT", 0, 0)
mtt:SetPoint ("RIGHT", mframe, "RIGHT", 0, 0)

local lastfont = "GameFontNormal"

function KUI.MeasureStrWidth (str, font)
  if (font and font ~= lastfont) then
    mtt:SetFontObject (font)
    lastfont = font
  end
  mtt:SetText (str or "")
  local w, h = mtt:GetStringWidth (), mtt:GetStringHeight ()
  return w+4,h
end

function KUI.GetFontColor (font, rgbtab)
  if (font and font ~= lastfont) then
    mtt:SetFontObject (font)
    lastfont = font
  end
  local r,g,b,a = mtt:GetTextColor ()
  if (rgbtab) then
    return { r = r, g = g, b = b, a = a or 1 }
  else
    return r,g,b,a
  end
end

function KUI:GetWidgetNum (wtype)
  if (not self.wcounters[wtype]) then
    self.wcounters[wtype] = 0
  end
  self.wcounters[wtype] = self.wcounters[wtype] + 1
  return self.wcounters[wtype]
end

function KUI.GetFramePos (frame, tbl)
  local w, h = frame:GetWidth () or 0, frame:GetHeight () or 0
  local t, b = frame:GetTop () or 0, frame:GetBottom () or 0
  local l, r = frame:GetLeft () or 0, frame:GetRight () or 0
  if (tbl) then
    return { w=w, h=h, t=t, b=b, l=l, r=r }
  else
    return w, h, t, b, l, r
  end
end
--
-- Base class for a widget "object"
--
KUI.BaseClass = KUI.BaseClass or {}

local BC = KUI.BaseClass

function BC.Catch (self, event, handler)
  if (handler and type(handler) == "function") then
    self.events[event] = handler
  elseif (handler and type(handler) == "string") then
    if (self[handler] and type(self[handler]) == "function") then
      self.events[event] = self[handler]
    elseif (_G[handler] and type(_G[handler]) == "function") then
      self.events[event] = _G[handler]
    end
  elseif (not handler and self.events[event]) then
    return self.events[event]
  end
end

--
-- For each event we throw, we check two places for a handler. The first
-- is an actual function of the event name itself in the self object.
-- This is intended for internal use and should not be overwritten. The
-- second is a user-defined hander that they install with Catch().
--
function BC.Throw (self, event, ...)
  local ok,rv

  if (self[event] and type(self[event]) == "function") then
    ok, fail = safecall (self[event], self, event, ...)
    if (ok and fail) then
      return fail
    end
  end

  if (self.events[event] and type(self.events[event] == "function")) then
    ok, rv = safecall (self.events[event], self, event, ...)
    if (ok) then
      return rv
    end
  end
end

local function hook_SetWidth (fr)
  if (fr.SetWidth) then
    hooksecurefunc (fr, "SetWidth", function (self, width)
      self:Throw ("OnWidthSet", width)
    end)
  end
end

local function hook_SetHeight (fr)
  if (fr.SetHeight) then
    hooksecurefunc (fr, "SetHeight", function (self, height)
      self:Throw ("OnHeightSet", height)
    end)
  end
end

local function hook_Enable (fr)
  if (fr.Enable) then
    hooksecurefunc (fr, "Enable", function (self, ...)
      self.enabled = true
      self:Throw ("OnEnable", true)
    end)
  end
end

local function hook_Disable (fr)
  if (fr.Disable) then
    hooksecurefunc (fr, "Disable", function (self, ...)
      self.enabled = false
      self:Throw ("OnEnable", false)
    end)
  end
end

local function hook_Show (fr)
  if (fr.Show) then
    hooksecurefunc (fr, "Show", function (self, ...)
      self:Throw ("OnShow", false)
    end)
  end
end

local function hook_Hide (fr)
  if (fr.Hide) then
    hooksecurefunc (fr, "Hide", function (self, ...)
      self:Throw ("OnHide", false)
    end)
  end
end

function BC.SetEnabled (self, onoff)
  if (onoff == nil) then
    onoff = true
  end

  if (not self.Enable or not self.Disable) then
    self.enabled = onoff
    self:Throw ("OnEnable", onoff)
    return
  end

  if (onoff) then
    self:Enable ()
  else
    self:Disable ()
  end
  self:Throw ("OnEnable", onoff)
end

function BC.SetShown (self, onoff)
  if (onoff == nil) then
    onoff = true
  end
  if (onoff) then
    self:Show ()
  else
    self:Hide ()
  end
end

local function generic_OnEnter (this)
  this:Throw ("OnEnter")
end

local function generic_OnLeave (this)
  this:Throw ("OnLeave")
end

local function do_tooltip_onenter (this, enabled)
  if ((not this.tiptitle) and (not this.tiptext)) then
    return
  end
  local d = enabled and 1 or 2
  local tf = GameTooltip.SetText
  local r, g, b

  GameTooltip_SetDefaultAnchor (GameTooltip, this)
  if (this.tiptitle) then
    tf = GameTooltip.AddLine
    r = HIGHLIGHT_FONT_COLOR.r / d
    g = HIGHLIGHT_FONT_COLOR.g / d
    b = HIGHLIGHT_FONT_COLOR.b / d
    GameTooltip:SetText (this.tiptitle, r, g, b, 1)
  end

  if (this.tiptext) then
    r = NORMAL_FONT_COLOR.r / d
    g = NORMAL_FONT_COLOR.g / d
    b = NORMAL_FONT_COLOR.b / d
    tf (GameTooltip, this.tiptext, r, g, b, 1)
  end

  GameTooltip:Show ()
  if (this.tipfunc) then
    GameTooltip:SetOwner (this, "ANCHOR_NONE")
    GameTooltip:SetPoint ("TOPLEFT", this, "TOPRIGHT", 5, 0)
    this.tipfunc (this)
  end
end

local function tip_OnEnter (this, event)
  do_tooltip_onenter (this, this.enabled)
end

local function tip_OnLeave (this, event)
  GameTooltip:Hide ()
end

local function apply_hooks (fr)
  hook_SetWidth (fr)
  hook_SetHeight (fr)
  hook_Enable (fr)
  hook_Disable (fr)
  hook_Show (fr)
  hook_Hide (fr)
  fr:HookScript ("OnEnter", generic_OnEnter)
  fr:HookScript ("OnLeave", generic_OnLeave)
end

local function newobj(cfg, kparent, defwt, defht, fname, ftype, template)
  local defh, defw
  local lx = 0
  local ly = 0

  if (cfg.template) then
    template = cfg.template
  end
  if (template == "") then
    template = ""
  end

  if (type (defwt) == "table") then
    defw = defwt[1]
    lx = defwt[2]
  else
    defw = defwt
  end
  if (type (defht) == "table") then
    defh = defht[1]
    ly = defht[2]
  else
    defh = defht
  end

  local parent

  --
  -- If defh and defw are both 0 it means we have a somewhat special case
  -- here, and kparent isn't a typical KahLua KoreUI return, but instead
  -- any simple frame. Set parent accordingly.
  --
  if (defh == 0 and defw == 0) then
    parent = kparent
  else
    if (cfg.parent) then
      parent = cfg.parent
    elseif (kparent and kparent.content) then
      parent = kparent.content
    elseif (kparent) then
      parent = kparent
    else
      parent = UIParent
    end
  end

  local frame = MakeFrame (ftype or "Frame", fname, parent, template)
  frame:Show ()
  if (cfg.level) then
    frame:SetFrameLevel (cfg.level)
  end
  local width  = cfg.width or defw or 100
  local height = cfg.height or defh or 100

  frame.Catch = BC.Catch
  frame.Throw = BC.Throw
  frame.SetEnabled = BC.SetEnabled
  frame.SetShown = BC.SetShown

  --
  -- I'd like to, but can't use setmetatable to create a real base class.
  -- The base frame also uses setmetatable for its own internal methods
  -- and this overwrites it.
  --
  -- setmetatable (frame, {__index=BC})

  frame.events = {}
  apply_hooks (frame)
  frame.groupname = cfg.group or nil

  if (width > 0) then
    frame:SetWidth (width)
  end
  if (height > 0) then
    frame:SetHeight (height)
  end

  --
  -- If defh and defw are both 0, it means we have a "special" case on our
  -- hands, where the calling function will do all the placement.
  --
  if (defw ~= 0 and defh ~= 0) then
    if (cfg.x) then
      if (cfg.x ~= "CENTER") then
        frame:SetPoint ("LEFT", parent, "LEFT", cfg.x + lx, 0)
        frame.centerx = nil
      else
        local pw = floor(width / -2)
        frame:SetPoint ("LEFT", parent, "CENTER", pw, 0)
        frame.centerx = true
      end
    end

    if (cfg.y) then
      if (cfg.y ~= "MIDDLE") then
        frame:SetPoint ("TOP", parent, "TOP", 0, cfg.y + ly)
        frame.centery = nil
      else
        frame:SetPoint ("TOP", parent, "CENTER", 0, height / 2)
        frame.centery = true
      end
    end
  end

  if (cfg.tooltip) then
    frame.tiptitle = cfg.tooltip.title
    frame.tiptext = cfg.tooltip.text
    frame.tipfunc = cfg.tooltip.func
  end

  if (cfg.newobjhook) then
    cfg.newobjhook (frame, cfg, parent, width, height)
  end

  if (cfg.debug) then
    local ttt = frame:CreateTexture (nil, "ARTWORK")
    ttt:SetAllPoints (frame)
    ttt:SetColorTexture (0.3, 0.3, 0.3, 0.5)
  end
  return frame, parent, width, height
end

local function check_tooltip_title (frame, cfg, title)
  if (cfg.tooltip and cfg.tooltip.title == "$$") then
    frame.tiptitle = title
  end
end

local function parent_StartMoving (this)
  local pf = this:GetParent ()
  pf:StartMoving ()
  if (pf.Throw) then
    pf:Throw ("OnStartMoving")
  end
end

local function parent_StopMoving (this)
  local pf = this:GetParent ()
  pf:StopMovingOrSizing ()
  if (pf.Throw) then
    pf:Throw ("OnStopMoving")
  end
end

local function hs_OnSizeChanged (this, w, h)
  local hst = this.hstextures
  local tx = w - hst.adjust
  hst.middle:SetWidth (tx)
  hst.middle:SetTexCoord (0, tx / 1024.0, 0, 1)
end

function KUI:CreateHSplit (cfg, kparent)
  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)

  frame.hstextures = {}
  local hst = frame.hstextures
  hst.inset = cfg.inset or 0

  if (cfg.placeframe) then
    cfg.placeframe (frame)
  else
    frame:SetPoint ("LEFT", parent, "LEFT", hst.inset, 0)
    frame:SetPoint ("RIGHT", parent, "RIGHT", 0 - hst.inset, 0)
    if (cfg.topanchor) then
      frame:SetPoint ("TOP", parent, "TOP", 0, 0 - hst.inset)
    else
      frame:SetPoint ("BOTTOM", parent, "BOTTOM", 0, hst.inset)
    end
  end
  frame:SetHeight (cfg.height or 24)

  local left = frame:CreateTexture (nil, "ARTWORK")
  if (cfg.leftsplit) then
    left:SetTexture (texpath .. "HDIV-LeftSplit")
  else
    left:SetTexture (texpath .. "HDIV-Left")
  end
  left:SetWidth (16)
  left:SetHeight (16)
  if (cfg.setleft) then
    hst.leftshift = cfg.setleft (frame, left)
  else
    local ls = cfg.leftshift or (-10 - hst.inset)
    if (cfg.leftsplit) then
      ls = ls - 2
    end
    hst.leftshift = ls
    if (cfg.topanchor) then
      local vs = -12 - hst.inset
      left:SetPoint ("BOTTOMLEFT", frame, "BOTTOMLEFT", ls, vs)
    else
      local vs = 12 + hst.inset
      left:SetPoint ("TOPLEFT", frame, "TOPLEFT", ls, vs)
    end
  end
  hst.left = left

  local right = frame:CreateTexture (nil, "ARTWORK")
  if (cfg.rightsplit) then
    right:SetTexture (texpath .. "HDIV-RightSplit")
  else
    right:SetTexture (texpath .. "HDIV-Right")
  end
  right:SetWidth (16)
  right:SetHeight (16)
  if (cfg.setright) then
    hst.rightshift = cfg.setright (frame, right)
  else
    local rs = cfg.rightshift or (12 + hst.inset)
    if (cfg.rightsplit) then
      rs = rs - 4
    end
    hst.rightshift = rs
    if (cfg.topanchor) then
      local vs = -12 - hst.inset
      right:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", rs, vs)
    else
      local vs = 12 + hst.inset
      right:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", rs, vs)
    end
  end
  hst.right = right

  local middle = frame:CreateTexture (nil, "ARTWORK")
  middle:SetTexture (texpath .. "HDIV-Mid")
  middle:SetHeight (16)
  if (cfg.setmiddle) then
    hst.midshift = cfg.setmiddle (frame, middle)
  else
    local ms = cfg.midshift or 0
    middle:SetPoint ("TOPLEFT", left, "TOPRIGHT", ms, 0)
    hst.midshift = ms
  end
  hst.middle = middle

  if (cfg.resizeadjust ~= nil) then
    hst.adjust = cfg.resizeadjust
  else
    hst.adjust = (8 - (hst.inset * 2)) + hst.rightshift + hst.leftshift
  end

  frame:HookScript ("OnSizeChanged", hs_OnSizeChanged)

  --
  -- Set two frame pointers for the two halves
  --
  if (cfg.topanchor) then
    frame.topframe = frame
    frame.bottomframe = MakeFrame ("Frame", nil, parent)
    frame.bottomframe:SetPoint ("TOPLEFT", frame, "BOTTOMLEFT", 0, -6 - (2 * hst.inset))
    frame.bottomframe:SetPoint ("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 - hst.inset, hst.inset)
  else
    frame.bottomframe = frame
    frame.topframe = MakeFrame ("Frame", nil, parent)
    frame.topframe:SetPoint ("TOPLEFT", parent, "TOPLEFT", hst.inset, 0 - hst.inset)
    frame.topframe:SetPoint ("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 8 + (2 * hst.inset))
  end

  return frame
end

local function vs_OnSizeChanged (this, w, h)
  local vst = this.vstextures
  local ty = h - vst.adjust
  vst.middle:SetHeight (ty)
  vst.middle:SetTexCoord (0, 1, 0, ty / 1024.0)
end

function KUI:CreateVSplit (cfg, kparent)
  local frame, parent = newobj(cfg, kparent, 0, 0, cfg.name)

  frame.vstextures = {}
  local vst = frame.vstextures
  vst.inset = cfg.inset or 0

  if (cfg.placeframe) then
    cfg.placeframe (frame)
  else
    frame:SetPoint ("TOP", parent, "TOP", 0, 0 - vst.inset)
    frame:SetPoint ("BOTTOM", parent, "BOTTOM", 0, vst.inset)
    if (cfg.rightanchor) then
      frame:SetPoint ("RIGHT", parent, "RIGHT", 0 - vst.inset, 0)
    else
      frame:SetPoint ("LEFT", parent, "LEFT", vst.inset, 0)
    end
  end
  frame:SetWidth (cfg.width or 24)

  local top = frame:CreateTexture (nil, "ARTWORK")
  if (cfg.topsplit) then
    top:SetTexture (texpath .. "VDIV-TopSplit")
  else
    top:SetTexture (texpath .. "VDIV-Top")
  end
  top:SetWidth (16)
  top:SetHeight (16)
  if (cfg.settop) then
    vst.topshift = cfg.settop (frame, top)
  else
    local ts = cfg.topshift or (2 + vst.inset)
    vst.topshift = ts
    if (cfg.rightanchor) then
      local vs = 2 - vst.inset
      top:SetPoint ("TOPRIGHT", frame, "TOPLEFT", vs, ts)
    else
      local vs = -4 + vst.inset
      top:SetPoint ("TOPLEFT", frame, "TOPRIGHT", vs, ts)
    end
  end
  vst.top = top

  local bottom = frame:CreateTexture (nil, "ARTWORK")
  if (cfg.bottomsplit) then
    bottom:SetTexture (texpath .. "VDIV-BotSplit")
  else
    bottom:SetTexture (texpath .. "VDIV-Bot")
  end
  bottom:SetWidth (16)
  bottom:SetHeight (16)
  if (cfg.setbottom) then
    vst.bottomshift = cfg.setbottom (frame, bottom)
  else
    local bs = cfg.bottomshift or (-10 - vst.inset)
    vst.bottomshift = bs
    if (cfg.rightanchor) then
      local ls = 2 - vst.inset
      bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", ls, bs)
    else
      local ls = -4 + vst.inset
      bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", ls, bs)
    end
  end
  vst.bottom = bottom

  local middle = frame:CreateTexture (nil, "ARTWORK")
  middle:SetTexture (texpath .. "VDIV-Mid")
  middle:SetWidth (16)
  if (cfg.setmiddle) then
    vst.midshift = cfg.setmiddle (frame, middle)
  else
    local ms = cfg.midshift or 0
    middle:SetPoint ("TOPLEFT", top, "BOTTOMLEFT", 0, ms)
    vst.midshift = ms
  end
  vst.middle = middle

  if (cfg.resizeadjust ~= nil) then
    vst.adjust = cfg.resizeadjust
  else
    vst.adjust = vst.bottomshift + vst.topshift + 28 - (vst.inset * 2)
  end

  frame:HookScript ("OnSizeChanged", vs_OnSizeChanged)

  --
  -- Set two frame pointers for the two halves
  --
  if (cfg.rightanchor) then
    frame.rightframe = frame
    frame.leftframe = MakeFrame ("Frame", nil, parent)
    frame.leftframe:SetPoint ("TOPLEFT", parent, "TOPLEFT", vst.inset, 0 - vst.inset)
    frame.leftframe:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMLEFT", -10 - (2 * vst.inset), 0)
  else
    frame.leftframe = frame
    frame.rightframe = MakeFrame ("Frame", nil, parent)
    frame.rightframe:SetPoint ("TOPLEFT", frame, "TOPRIGHT", 8 + (2 * vst.inset), 0)
    frame.rightframe:SetPoint ("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0 -vst.inset, vst.inset)
  end

  return frame
end

--
-- Helper function called when we stop resizing a frame.
--
local function resize_OnMouseUp (this)
  local pf = this:GetParent ()
  pf:StopMovingOrSizing ()
  if (pf.content) then
    local cw = pf.content:GetWidth ()
    local ch = pf.content:GetHeight ()
    pf:Throw ("OnContentSizeChanged", cw, ch)
  end
  if (pf.Throw) then
    pf:Throw ("OnStopSizing")
  end
end

local function resize_OnMouseDown (this)
  local pf = this:GetParent ()
  pf:StartSizing (this.resize_direction)
  if (pf.Throw) then
    pf:Throw ("OnStartSizing")
  end
end

--
-- Helper function to make a frame resizable. Takes as its parameters the
-- parent frame that is to be resizable, the height of the corner frames,
-- and the direction(s) in which the frame is to be resized. This can be
-- a boolean (true means resize both vertically and horizontally, false
-- means don't resize at all), or a string which case have the values
-- "HEIGHT" to resize the height only, "WIDTH" to resize the width only,
-- or "BOTH" to resize both.
-- Returns the southeast, southwest and southern frame pointers or nil for
-- any of them not used.
--
local function make_resizeable (frame, height, opt, swframe, seframe, soframe)
  if (not opt) then
    frame:SetResizable (false)
    return
  end

  local resize

  if (type(opt) == "boolean" or (type(opt) == "string" and opt == "BOTH")) then
    resize = { [1] = "BOTTOMLEFT", [2] = "BOTTOMRIGHT" }
  elseif (type(opt) == "string" and opt == "WIDTH") then
    resize = { [1] = "LEFT", [2] = "RIGHT" }
  elseif (type(opt) == "string" and opt == "HEIGHT") then
    resize = { [1] = "BOTTOM", [2] = "BOTTOM" }
  else
    frame:SetResizable (false)
    return nil, nil, nil
  end

  frame:SetResizable (true)

  --
  -- South-west corner. Size down and to the left.
  --
  local swframe = swframe
  if (not swframe) then
    swframe = MakeFrame ("Frame", nil, frame)
  end
  swframe.resize_direction = resize[1]
  swframe:ClearAllPoints ()
  swframe:SetPoint ("BOTTOMLEFT", frame, "BOTTOMLEFT", -5, -5)
  swframe:SetHeight (height)
  swframe:SetWidth (height)
  swframe:EnableMouse (true)
  swframe:SetScript ("OnMouseDown", resize_OnMouseDown)
  swframe:SetScript ("OnMouseUp", resize_OnMouseUp)

  --
  -- South-east corner. Size down and to the right.
  --
  local seframe = seframe
  if (not seframe) then
    seframe = MakeFrame ("Frame", nil, frame)
  end
  seframe.resize_direction = resize[2]
  seframe:ClearAllPoints ()
  seframe:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
  seframe:SetHeight (height)
  seframe:SetWidth (height)
  seframe:EnableMouse (true)
  seframe:SetScript ("OnMouseDown", resize_OnMouseDown)
  seframe:SetScript ("OnMouseUp", resize_OnMouseUp)

  local soframe = soframe
  if (type (opt) == "boolean" or (type(opt) == "string" and (opt == "BOTH" or opt == "HEIGHT"))) then
    --
    -- Southern edge. Size down only.
    --
    if (not soframe) then
      soframe = MakeFrame ("Frame", nil, frame)
    end
    soframe.resize_direction = "BOTTOM"
    soframe:ClearAllPoints ()
    soframe:SetPoint ("TOPLEFT", swframe, "TOPRIGHT", 0, 0)
    soframe:SetPoint ("BOTTOMRIGHT", seframe, "BOTTOMLEFT", 0, 0)
    soframe:EnableMouse (true)
    soframe:SetScript ("OnMouseDown", resize_OnMouseDown)
    soframe:SetScript ("OnMouseUp", resize_OnMouseUp)
  end

  return seframe, swframe, soframe
end

local function xbutton_OnClick (this)
  this:GetParent():Hide ()
  this:GetParent():Throw ("OnClose")
end

function KUI:CreateDialogFrame (cfg, kparent)
  local fname = cfg.name or ("KUIDlgFrame" .. self:GetWidgetNum ("dialog"))
  local frame,parent,width,height = newobj(cfg, kparent, 300, 300, fname,nil,"BackdropTemplate")
  local bstyle = 2 -- Thick
  local offset = 0
  local topheight = 0

  if (cfg.border ~= nil) then
    if (type (cfg.border) == "boolean") then
      if (cfg.border) then
        bstyle = 2
      else
        bstyle = 0
      end
    elseif (type (cfg.border) == "string") then
      if (cfg.border == "THICK") then
        bstyle = 2
      elseif (cfg.border == "THIN") then
        bstyle = 1
      elseif (cfg.border == "NONE") then
        bstyle = 0
      end
    end
  end

  if (cfg.canmove ~= nil) then
    frame:SetMovable (cfg.canmove)
  else
    frame:SetMovable (true)
  end

  local seframe, swframe, soframe = make_resizeable (frame, 25, cfg.canresize)

  frame:EnableMouse(true)
  frame:EnableKeyboard(true)
  frame:SetFrameStrata (cfg.strata or "FULLSCREEN_DIALOG")

  local bdrop = {}

  if (bstyle > 0) then
    bdrop.bgFile = borders[bstyle].bgFile
    bdrop.edgeFile = borders[bstyle].edgeFile
    bdrop.tileSize = borders[bstyle].tileSize
    bdrop.edgeSize = borders[bstyle].edgesize
    bdrop.insets = borders[bstyle].insets
    offset = borders[bstyle].offset
    bdrop.tile = true
  end

  if (cfg.blackbg) then
    bdrop.bgFile = texpath .. "TDF-Fill"
    bdrop.tile = true
  end

  frame.borderoffset = offset

  frame:SetBackdrop (bdrop)
  frame:SetBackdropColor (0, 0, 0, 1)

  if (frame:IsResizable ()) then
    frame:SetMinResize (cfg.minwidth or width, cfg.minheight or height)
    frame:SetMaxResize (cfg.maxwidth or width, cfg.maxheight or height)
  end

  if (cfg.xbutton) then
    local xbutton = MakeFrame ("Button", nil, frame,"UIPanelCloseButton")
    xbutton:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    xbutton:SetScript ("OnClick", xbutton_OnClick)
  end

  frame:Hide()

  if (cfg.title and bstyle > 0) then
    local title = MakeFrame ("Frame", nil, frame)
    frame.title = title
    title:EnableMouse (true)
    if (frame:IsMovable ()) then
      title:SetScript ("OnMouseDown", parent_StartMoving)
      title:SetScript ("OnMouseUp", parent_StopMoving)
    end

    local titletext = title:CreateFontString (nil, "OVERLAY",
      cfg.titlefont or "GameFontNormal")
    titletext:SetText (cfg.title)
    frame.titletext = titletext

    local titlebg = frame:CreateTexture (nil, "OVERLAY")
    titlebg:SetTexture ("Interface/DialogFrame/UI-DialogBox-Header")
    titlebg:SetTexCoord (0.31, 0.67, 0, 0.63)
    titlebg:SetPoint ("TOP", frame, "TOP", 0, 12)
    titlebg:SetWidth (cfg.titlewidth or 150)
    titlebg:SetHeight (cfg.titleheight or 40)

    local titlebg_l = frame:CreateTexture (nil, "OVERLAY")
    titlebg_l:SetTexture ("Interface/DialogFrame/UI-DialogBox-Header")
    titlebg_l:SetTexCoord (0.21, 0.31, 0, 0.63)
    titlebg_l:SetPoint ("RIGHT", titlebg, "LEFT", 0, 0)
    titlebg_l:SetWidth (30)
    titlebg_l:SetHeight (cfg.titleheight or 40)

    local titlebg_r = frame:CreateTexture (nil, "OVERLAY")
    titlebg_r:SetTexture ("Interface/DialogFrame/UI-DialogBox-Header")
    titlebg_r:SetTexCoord (0.67, 0.77, 0, 0.63)
    titlebg_r:SetPoint ("LEFT", titlebg, "RIGHT", 0, 0)
    titlebg_r:SetWidth (30)
    titlebg_r:SetHeight (cfg.titleheight or 40)

    title:SetAllPoints(titlebg)
    titletext:SetPoint ("TOP", titlebg, "TOP", 0, -14)

    frame.SetTitleText = function (this, text)
      this.titletext:SetText (text or "")
    end
  else
    if (frame:IsMovable ()) then
      local mframe = MakeFrame ("Frame", nil, frame)
      frame.mframe = mframe
      mframe:EnableMouse (true)
      mframe:ClearAllPoints ()
      mframe:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 5)
      mframe:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 0, -5)
      mframe:SetHeight (25)
      mframe:SetScript ("OnMouseDown", parent_StartMoving)
      mframe:SetScript ("OnMouseUp", parent_StopMoving)
    end
  end

  local rightmost = frame
  local rightpoint = "BOTTOMRIGHT"
  local xoffs, yoffs = -15, 12
  local addheight = 0

  if (frame.title or cfg.xbutton) then
    topheight = topheight + 14
  end

  if (cfg.cancelbutton) then
    local cancel
    cancel = MakeFrame ("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetScript ("OnClick", function (this)
      this:GetParent():Throw ("OnCancel")
    end)
    cancel:SetPoint ("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    cancel:SetHeight (cfg.cancelbutton.height or 20)
    cancel:SetWidth (cfg.cancelbutton.width or 100)
    cancel:SetText (cfg.cancelbutton.text or K.CANCEL_STR)
    addheight = max(addheight, cancel:GetHeight())

    rightmost = cancel
    rightpoint = "BOTTOMLEFT"
    xoffs = -5
    yoffs = 0
  end

  if (cfg.okbutton) then
    local ok = MakeFrame ("Button", nil, frame, "UIPanelButtonTemplate")
    ok:SetScript ("OnClick", function (this)
      this:GetParent():Throw ("OnAccept")
    end)
    ok:SetPoint ("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    ok:SetHeight (cfg.okbutton.height or 20)
    ok:SetWidth (cfg.okbutton.width or 100)
    ok:SetText (cfg.okbutton.text or K.OK_STR)
    addheight = max(addheight, ok:GetHeight())

    rightmost = ok
    rightpoint = "BOTTOMLEFT"
    xoffs = -5
    yoffs = 0
  end

  --
  -- The statusbar idea and code comes from "Cmouse". Thank you.
  --
  if (cfg.statusbar) then
    local statusbg = MakeFrame ("Frame", nil, frame)
    frame.statusframe = statusbg
    statusbg:SetPoint ("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, offset)
    statusbg:SetPoint ("BOTTOMRIGHT", rightmost, rightpoint, xoffs, yoffs)
    statusbg:SetHeight (20)
    statusbg:SetBackdrop (cfbackdrop)
    statusbg:SetBackdropColor (0.1, 0.1, 0.1)
    statusbg:SetBackdropBorderColor (0.4, 0.4, 0.4)
    addheight = max(addheight, 20)

    local statustext = statusbg:CreateFontString (nil, "OVERLAY",
      cfg.statusfont or "GameFontNormal")
    frame.statustext = statustext
    statustext:SetPoint ("TOPLEFT", statusbg, "TOPLEFT", 7, -2)
    statustext:SetPoint ("BOTTOMRIGHT", statusbg, "BOTTOMRIGHT", -7, 2)
    statustext:SetHeight (20)
    statustext:SetJustifyH ("LEFT")
    statustext:SetText ("")
    frame.SetStatusText = function (this, text)
      this.statustext:SetText (text or "")
    end
  end

  local content = MakeFrame ("Frame", nil, frame)
  frame.content = content
  content:SetPoint ("TOPLEFT", frame, "TOPLEFT", offset, -(offset+topheight))
  content:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offset, offset+addheight)

  if (cfg.escclose) then
    add_escclose (fname)
  end

  frame.OnAccept = function (this)
    this:Hide ()
  end

  frame.OnCancel = function (this)
    this:Hide()
  end

  return frame
end

local function sl_SetTextColor (this, r, g, b, a)
  this.rgb = {r = r, g = g, b = b, a = a or 1}
  local d = this.enabled and 1 or 2
  this.label:SetTextColor (r/d, g/d, b/d, a or 1)
end

local function sl_OnEnable (this, event, onoff)
  local onoff = onoff or false
  this.enabled = onoff
  local d = onoff and 1 or 2
  this.label:SetTextColor(this.rgb.r/d, this.rgb.g/d, this.rgb.b/d, this.rgb.a)
end

local function sl_SetText (this, text)
  if (this.autosize) then
    local sw, sh = KUI.MeasureStrWidth (text, this.font)
    this:SetWidth (sw + this.xtrawidth)
    this:SetHeight (sh + this.xtraheight)
    if (this.centerx) then
      local pw = (sw + this.xtrawidth) / -2
      this:SetPoint ("LEFT", this:GetParent (), "CENTER", pw, 0)
    end
    if (this.centery) then
      this:SetPoint ("TOP", this:GetParent(), "CENTER", 0, (sh + this.xtraheight) / 2)
    end
  end
  this.label:SetText (text)
end

function KUI:CreateStringLabel (cfg, kparent)
  local dw = 200
  local dh = 16
  if (cfg.border) then
    dw = 216
    dh = 24
  end
  local frame,parent,width,height = newobj(cfg, kparent, dw, dh, cfg.name,nil,"BackdropTemplate")
  frame.font = cfg.font or "GameFontHighlightSmall"
  local label = frame:CreateFontString (nil, "ARTWORK", frame.font)
  frame.autosize = true
  if (cfg.autosize ~= nil) then
    frame.autosize = cfg.autosize
  end

  label:SetJustifyH (cfg.justifyh or "LEFT")
  label:SetJustifyV (cfg.justifyv or "MIDDLE")
  frame.label = label
  local r,g,b,a = label:GetTextColor()
  frame.rgb = {r = r, g = g, b = b, a = a}
  if (cfg.color) then
    frame.rgb = { r = cfg.color.r, g = cfg.color.g, b = cfg.color.b, a = cfg.color.a or 1 }
  end

  local adj = 0
  if (cfg.border) then
    frame:SetBackdrop (cfbackdrop)
    frame:SetBackdropColor (0, 0, 0, 0)
    if (cfg.bordercolor) then
      frame:SetBackdropBorderColor (cfg.bordercolor.r,
        cfg.bordercolor.g, cfg.bordercolor.b, cfg.bordercolor.a or 1)
    else
      frame:SetBackdropBorderColor (0.4, 0.4, 0.4, 1)
    end
    frame.xtrawidth = 16
    frame.xtraheight = 12
    adj = 2
  else
    frame.xtrawidth = 0
    frame.xtraheight = 0
  end
  label:SetPoint ("TOPLEFT", frame, "TOPLEFT", (frame.xtrawidth/4)+adj, frame.xtraheight/-4)
  label:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", (frame.xtrawidth/-4)-adj, frame.xtraheight/4)

  frame.SetText = sl_SetText
  frame.SetTextColor = sl_SetTextColor
  frame.OnEnable = sl_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetText (cfg.text or "")
  frame:SetEnabled (cfg.enabled)

  return frame
end

local function eb_OnEnterPressed (this)
  local val = this:GetText()
  local err = this:Throw ("OnEnterPressed", val)
  if (err) then
    this:SetFocus ()
  else
    this:ClearFocus ()
    this:Throw ("OnValueChanged", val, true)
    this.setvalue = val
  end
end

local function eb_SetText (this, text)
  this.setvalue = text
  this:Throw ("OnValueChanged", text, false)
end

local function eb_OnTextChanged (this, user)
  local newv = this:GetText ()
  if (user) then
    this:Throw ("OnValueChanged", newv, true)
  end
end

local function eb_OnEscapePressed (this)
  this:ClearFocus()
  this:SetText (this.setvalue or "")
  this:Throw ("OnEscapePressed", this:GetText ())
end

local function eb_OnEnable (this, event, onoff)
  local onoff = onoff or false
  local d = onoff and 1 or 2
  this:EnableMouse (onoff)
  this:SetTextColor (this.trgb.r/d, this.trgb.g/d, this.trgb.b/d, this.trgb.a)
  if (this.label) then
    this.label:SetTextColor (this.lrgb.r/d, this.lrgb.g/d, this.lrgb.b/d, this.lrgb.a)
  end
  this.enabled = onoff
  return false
end

function KUI:CreateEditBox (cfg, kparent)
  local frname = cfg.name
  if (not cfg.name) then
    frname = "KUIEditBox" .. self:GetWidgetNum ("edit")
  end
  local dwe = 0
  if (cfg.x ~= "CENTER") then
    dwe = 8
  end
  local frame,ppf,width,height = newobj(cfg, kparent, { 200, dwe }, 24, frname, "EditBox", "InputBoxTemplate")

  frame:SetTextInsets (0, 0, 3, 3)
  frame:SetMaxLetters (cfg.len or 128)
  frame:SetCursorPosition (0)
  frame:SetAutoFocus (false)
  frame:SetFontObject (cfg.font or "ChatFontNormal")
  frame:EnableMouse (true)
  frame:EnableKeyboard (true)
  if (cfg.numeric) then
    frame:SetNumeric (true)
  end
  frame:HookScript ("OnEnterPressed", eb_OnEnterPressed)
  frame:HookScript ("OnEscapePressed", eb_OnEscapePressed)
  frame:HookScript ("OnTextChanged", eb_OnTextChanged)
  hooksecurefunc (frame, "SetText", eb_SetText)

  if (cfg.label) then
    local lfont = cfg.label.font or "GameFontNormal"
    local lw,lh = KUI.MeasureStrWidth (cfg.label.text or "", lfont)
    local label = frame:CreateFontString (nil, "ARTWORK", lfont)
    frame.label = label
    local r,g,b,a = label:GetTextColor ()
    if (cfg.label.color) then
      r = cfg.label.color.r or r
      g = cfg.label.color.g or g
      b = cfg.label.color.b or b
      a = cfg.label.color.a or 1
    end
    frame.lrgb = {r = r, g = g, b = b, a = a}
    if (lh < height) then
      lh = height
    end
    label:SetHeight (lh)
    label:SetWidth (lw+4)
    label:SetJustifyH (cfg.label.justifyh or "LEFT")
    label:SetJustifyV (cfg.label.justifyv or "MIDDLE")
    label:SetText (cfg.label.text or "")
    check_tooltip_title (frame, cfg, cfg.label.text)

    if (cfg.label.pos == "TOP") then
      label:SetPoint ("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
      if (cfg.y) then
        if (cfg.y ~= "MIDDLE") then
          frame:SetPoint ("TOP", ppf, "TOP", 0, cfg.y - lh)
        else
          frame:SetPoint ("TOP", ppf, "CENTER", 0, (height - lh) / 2)
        end
      end
    elseif (cfg.label.pos == "RIGHT") then
      label:SetPoint ("TOPLEFT", frame, "TOPRIGHT", 4, 0)
      if (cfg.x and cfg.x == "CENTER") then
        frame:SetPoint ("LEFT", ppf, "CENTER", (width + lw + 8) / -2, 0)
      end
    elseif (cfg.label.pos == "BOTTOM") then
      label:SetPoint ("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
      if (cfg.y and cfg.y == "MIDDLE") then
        frame:SetPoint ("TOP", ppf, "CENTER", 0, (height + lh) / 2)
      end
    else -- Assume LEFT
      label:SetPoint ("TOPRIGHT", frame, "TOPLEFT", -4, 0)
      if (cfg.x) then
        if (cfg.x ~= "CENTER") then
          frame:SetPoint ("LEFT", ppf, "LEFT", cfg.x + lw + 8, 0)
        else
          frame:SetPoint ("LEFT", ppf, "CENTER", (width - lw + 8) / -2, 0)
        end
      end
    end
  end

  local r,g,b,a = frame:GetTextColor ()
  if (cfg.color) then
    r = cfg.color.r or r
    g = cfg.color.g or g
    b = cfg.color.b or b
    a = cfg.color.a or 1
  end
  frame.trgb = {r = r, g = g, b = b, a = a}

  frame.OnEnable = eb_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetEnabled (cfg.enabled)
  frame:SetCursorPosition (0)
  frame:ClearFocus ()
  frame:SetText (cfg.initialvalue or "")
  return frame
end

local function cb_OnMouseDown (this)
  if (this.enabled and this.text) then
    local t = this.text
    t:SetPoint ("LEFT", t.ipoints[1], t.ipoints[2], 1, -1)
  end
end

local function cb_OnMouseUp (this)
  if (this.enabled) then
    if (this.ToggleChecked) then
      this:ToggleChecked ()
    else
      this:SetChecked ()
    end
    if (this.text) then
      local t = this.text
      t:SetPoint ("LEFT", t.ipoints[1], t.ipoints[2], 0, 0)
    end
    this:Throw ("OnClick", this.checked)
    this:Throw ("OnValueChanged", this.checked, true, this.groupname and this.value or nil)
  end
end

local function cb_SetText (this, text)
  if (this.text) then
    this.text:SetText (text or "")
    if (this.autosize) then
      this:SetWidth (this.text:GetStringWidth () + 36)
    end
    if (this.centerx) then
      local pw = floor (this:GetWidth () / -2)
      this:SetPoint ("LEFT", this:GetParent (), "CENTER", pw, 0)
    end
  end
end

local function cb_GetChecked (this)
  return this.checked
end

local function cb_ToggleChecked (this)
  this:SetChecked (not this.checked, true)
end

local function cb_OnEnable (this, event, onoff)
  local onoff = onoff or false
  this.enabled = onoff
  local d = onoff and 1 or 2
  SetDesaturation (this.check, not onoff)
  if (this.text) then
    this.text:SetTextColor(this.rgb.r/d, this.rgb.g/d, this.rgb.b/d, this.rgb.a)
  end
end

local function kui_checkradio(cfg, kparent, size, dh)
  local dw = size
  if (cfg.label) then
    dw = 200
  end
  local frame, parent, width, height = newobj (cfg, kparent, dw, dh, cfg.name, "Button")

  frame.checked = cfg.checked or false
  frame.autosize = cfg.autosize
  frame:HookScript ("OnMouseDown", cb_OnMouseDown)
  frame:HookScript ("OnMouseUp", cb_OnMouseUp)
  frame:EnableMouse (true)

  local bg = frame:CreateTexture (nil, "ARTWORK")
  bg:SetWidth (size)
  bg:SetHeight (size)
  bg:SetPoint ("LEFT", frame, "LEFT", 0, 0)

  local check = frame:CreateTexture (nil, "OVERLAY")
  frame.check = check
  check:SetWidth (size)
  check:SetHeight (size)
  check:SetPoint ("CENTER", bg, "CENTER", 0, 0)
  if (not frame.checked) then
    check:Hide()
  end

  if (cfg.label) then
    assert (cfg.label.pos == nil or cfg.label.pos == "LEFT" or cfg.label.pos == "RIGHT", "checkbox label position can only be LEFT or RIGHT (default)")
    local font = cfg.label.font or "GameFontHighlight"
    local text = frame:CreateFontString (nil, "OVERLAY", font)
    frame.rgb = KUI.GetFontColor (font, true)
    if (cfg.label.color) then
      frame.rgb.r = cfg.label.color.r
      frame.rgb.g = cfg.label.color.g
      frame.rgb.b = cfg.label.color.b
      frame.rgb.a = cfg.label.color.a
    end
    frame.text = text
    local dh = "LEFT"
    text:ClearAllPoints ()
    if (cfg.label.pos == "LEFT") then
      bg:ClearAllPoints ()
      bg:SetPoint ("RIGHT", frame, "RIGHT", 0, 0)
      text:SetPoint ("RIGHT", bg, "LEFT", -4, 0)
      text:SetPoint ("LEFT", frame, "LEFT", 0, 0)
      text.ipoints = { frame, "LEFT" }
      dh = "RIGHT"
      if (cfg.autosize == nil) then
        frame.autosize = false
      end
    else
      text:SetPoint ("LEFT", bg, "RIGHT", 0, 0)
      text:SetPoint ("RIGHT", frame, "RIGHT", 0, 0)
      text.ipoints = { bg, "RIGHT" }
      if (cfg.autosize == nil) then
        frame.autosize = true
      end
    end
    text:SetJustifyH (cfg.label.justifyh or dh)
    text:SetJustifyV (cfg.label.justifyv or "MIDDLE")
  end

  frame.SetText = cb_SetText
  frame.GetChecked = cb_GetChecked
  frame.OnEnable = cb_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  if (cfg.label) then
    frame:SetText (cfg.label.text or "")
    check_tooltip_title (frame, cfg, cfg.label.text)
  end
  frame:SetEnabled (cfg.enabled)
  return frame, bg, check
end

local function cb_SetChecked (self, onoff, nothrow)
  local onoff = onoff or false
  local c = self.check
  local old = self.checked

  self.checked = onoff
  if (onoff) then
    c:Show()
  else
    c:Hide()
  end

  if (not nothrow) then
    self:Throw ("OnValueChanged", onoff, false)
  end
end

function KUI:CreateCheckBox (cfg, kparent)
  local frame, bg, check = kui_checkradio (cfg, kparent, 24, 24)

  bg:SetTexture ("Interface/Buttons/UI-CheckBox-Up")
  bg:SetTexCoord (0, 1, 0, 1)

  check:SetTexture ("Interface/Buttons/UI-CheckBox-Check")
  check:SetTexCoord (0, 1, 0, 1)
  check:SetBlendMode ("BLEND")

  frame.SetChecked = cb_SetChecked
  frame.ToggleChecked = cb_ToggleChecked
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetChecked (cfg.checked)
  frame:SetEnabled (cfg.enabled)
  return frame
end

local function rb_uncheck_group (t, g, ...)
  local l = 1
  local c = select (l, ...)
  while (c) do
    local rc = c
    if (t.getbutton) then
      rc = t.getbutton (c)
    end
    if (rc ~= t and rc.groupname ~= nil and rc.groupname == g) then
      if (rc.checked) then
        rc.checked = false
        rc.check:Hide ()
        rc:Throw ("OnValueChanged", false, false, rc.value)
      end
    end
    l = l + 1
    c = select (l, ...)
  end
end

local function rb_SetChecked (this)
  if (this.checked) then
    return
  end

  --
  -- Find and set to the OFF state any other buttons in the group
  --
  rb_uncheck_group (this, this.groupname, this.groupparent:GetChildren())
  this.checked = true
  this.check:Show ()
  this:Throw ("OnValueChanged", true, false, this.value)
end

local function rb_OnValueChanged (this, evt, onoff, user, val)
  local onoff = onoff or false
  if (this.cvfunc) then
    this.cvfunc (this, onoff, val, user)
  end
end

local function rb_getsetvalue (t, g, v, n, set, ...)
  local l = 1
  local c = select (l, ...)
  while (c) do
    local rc = c
    if (t.getbutton) then
      rc = t.getbutton (c)
    end
    if (rc.groupname ~= nil and rc.groupname == g) then
      if ((not set) and rc.checked) then
        return rc.value
      elseif (set) then
        if (rc.value ~= v) then
          if (rc.checked) then
            rc.checked = false
            rc.check:Hide ()
            if (not n) then
              rc:Throw ("OnValueChanged", false, false, c.value)
            end
          end
        else
          rb_uncheck_group (t, g, ...)
          rc.checked = true
          rc.check:Show ()
          if (not n) then
            rc:Throw ("OnValueChanged", true, false, rc.value)
          end
        end
      end
    end
    l = l + 1
    c = select (l, ...)
  end
end

local function rb_SetValue (this, val, nothrow)
  if (this.checked and this.value and this.value == val) then
    return
  end
  rb_getsetvalue (this, this.groupname, val, nothrow, true,
    this.groupparent:GetChildren ())
end

local function rb_GetValue (this)
  if (this.checked) then
    return this.value
  end
  return rb_getsetvalue (this, this.groupname, nil, nil, false,
    this.groupparent:GetChildren ())
end

--
-- For radio boxes, we must have a group name. When one button in the
-- group is checked, all others become unchecked. All radio boxes in the
-- same group must have the same parent frame.
--
function KUI:CreateRadioButton (cfg, kparent)
  assert (cfg.group, "must supply radio button group name")
  local frame, bg, check = kui_checkradio (cfg, kparent, 16, 16)

  frame.groupname = cfg.group
  frame.groupparent = cfg.groupparent or frame:GetParent ()
  frame.value = cfg.value
  frame.cvfunc = cfg.func
  frame.getbutton = cfg.getbutton

  bg:SetTexture ("Interface/Buttons/UI-RadioButton")
  bg:SetTexCoord (0, 0.25, 0, 1)

  check:SetTexture ("Interface/Buttons/UI-RadioButton")
  check:SetTexCoord (0.25, 0.5, 0, 1)

  frame.SetChecked = rb_SetChecked
  frame.OnValueChanged = rb_OnValueChanged
  frame.SetValue = rb_SetValue
  frame.GetValue = rb_GetValue

  frame.checked = nil
  if (cfg.checked) then
    frame:SetChecked ()
  end
  frame:SetEnabled (cfg.enabled)
  return frame
end

-- JKJ FIXME: Add a convenience widget type for a group of radio buttons
-- where the user can specify a list of choices, and have a single event
-- thrown when the choice changes. Possibly allow the group to have a frame
-- and a title. Then lay out the buttons appropriately. Allow for either
-- vertical or horizontal placement.
function KUI:CreateRadioGroup (cfg, kparent)
end

local function update_eb_text(this)
  local val = this.value or 0
  this.editbox:SetText (floor ((val * 100) + 0.5) / 100)
end

local function update_editbox(this)
  if (not this.setup) then
    local val = this:GetValue()
    if (this.step and this.step > 0) then
      local mv = this.minval or 0
      val = (floor ((val - mv) / this.step + 0.5) * this.step) + mv
    end
    if (val ~= this.value) then
      this.value = val
      this:Throw ("OnValueChanged", this.value, this.mousedown and true or false)
    end
    if (this.value) then
      update_eb_text (this)
    end
  end
end

local function sde_OnEscapePressed (this)
  this:SetText (this:GetParent():GetValue ())
  this:ClearFocus ()
end

local function sde_OnEnterPressed (this)
  local val = tonumber(this:GetText ())
  local p = this:GetParent ()
  local minv, maxv = p:GetMinMaxValues ()
  if (val >= minv and val <= maxv) then
    p:SetValue (val)
    p:Throw ("OnValueChanged", p:GetValue (), true)
    this:ClearFocus ()
  end
end

local function sd_OnEnable (this, event, onoff)
  if (onoff == nil) then
    onoff = true
  end
  this.enabled = onoff
  local d = onoff and 1 or 2

  if (onoff) then
    this:EnableMouse (true)
    this.editbox:EnableMouse (true)
  else
    this:EnableMouse (false)
    this.editbox:EnableMouse (false)
    this.editbox:ClearFocus ()
  end

  local tr = this.mrgb
  this.mintxt:SetTextColor (tr.r/d, tr.g/d, tr.b/d, tr.a)
  this.maxtxt:SetTextColor (tr.r/d, tr.g/d, tr.b/d, tr.a)

  tr = this.ergb
  this.editbox:SetTextColor (tr.r/d, tr.g/d, tr.b/d, tr.a)

  if (this.label) then
    tr = this.lrgb
    this.label:SetTextColor (tr.r/d, tr.g/d, tr.b/d, tr.a)
  end
  return false
end

local function sd_OnMouseWheel (this, delta)
  local cv = this:GetValue ()
  local vs = this:GetValueStep ()
  if (delta > 0) then
    cv = cv - vs
  else
    cv = cv + vs
  end
  local mn,mx = this:GetMinMaxValues ()
  if (cv < mn) then
    cv = mn
  elseif (cv > mx) then
    cv = mx
  end
  this:SetValue (cv)
  this:Throw ("OnValueChanged", this:GetValue (), true)
end

local function sd_OnMouseDown (this)
  this.mousedown = true
end

local function sd_OnMouseUp (this)
  this.mousedown = nil
end

function KUI:CreateSlider (cfg, kparent)
  local orientation = cfg.orientation or "HORIZONTAL"
  local dheight, dwidth
  if (orientation == "HORIZONTAL") then
    dwidth = 200
    dheight = 16
    if (cfg.label) then
      dheight = { 16, -16 }
    end
  else
    dheight = 200
    dwidth = 16
  end

  local frame,parent,width,height = newobj(cfg, kparent, dwidth, dheight, cfg.name, "Slider","BackdropTemplate")

  local minval = cfg.minval or 0
  local maxval = cfg.maxval or 100
  local value = cfg.initialvalue or minval

  frame.setup = true

  frame:EnableMouse (true)
  frame:EnableMouseWheel (true)

  frame:SetOrientation (orientation)
  if (orientation == "HORIZONTAL") then
    frame:SetHeight (height)
    frame:SetHitRectInsets (0, 0, -10, 0)
  else
    frame:SetWidth (width)
  end
  frame:SetMinMaxValues (minval, maxval)
  frame:SetValueStep (cfg.step or 1)
  frame.minval = minval
  frame.maxval = maxval
  frame.step = cfg.step or 1

  local sliderbg = {
    bfFile = "Interface/Buttons/UI-SliderBar-Background",
    edgeFile = "Interface/Buttons/UI-SliderBar-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  }
  if (orientation == "HORIZONTAL") then
    frame:SetBackdrop (sliderbg)
    frame:SetThumbTexture ("Interface/Buttons/UI-SliderBar-Button-Horizontal")
    local tt = frame:GetThumbTexture ()
    tt:SetHeight (height+8)
  else
    sliderbg.insets.top = 3
    sliderbg.insets.bottom = 3
    frame:SetBackdrop (sliderbg)
    frame:SetThumbTexture ("Interface/Buttons/UI-SliderBar-Button-Vertical")
    local tt = frame:GetThumbTexture ()
    tt:SetWidth (width+8)
  end

  -- The min and max labels
  local mmfont = cfg.minmaxfont or "GameFontHighlightSmall"
  local mintxt = frame:CreateFontString (nil, "ARTWORK", mmfont)
  local maxtxt = frame:CreateFontString (nil, "ARTWORK", mmfont)
  frame.mintxt = mintxt
  frame.maxtxt = maxtxt
  local r, g, b, a = mintxt:GetTextColor ()
  if (cfg.minmaxcolor) then
    r = cfg.minmaxcolor.r or r
    g = cfg.minmaxcolor.g or g
    b = cfg.minmaxcolor.b or b
    a = cfg.minmaxcolor.a or a
  end
  frame.mrgb = {r = r, g = g, b = b, a = a}

  -- The edit box for typing in values
  local editbox = MakeFrame ("EditBox", nil, frame)
  frame.editbox = editbox
  editbox:SetAutoFocus (false)
  editbox:EnableMouse (true)
  editbox:SetNumeric (true)
  editbox:SetMaxLetters (4)
  editbox:SetFontObject (cfg.editfont or "GameFontHighlightSmall")
  r,g,b,a = editbox:GetTextColor ()
  if (cfg.editcolor) then
    r = cfg.editcolor.r or r
    g = cfg.editcolor.g or g
    b = cfg.editcolor.b or b
    a = cfg.editcolor.a or a
  end
  frame.ergb = {r = r, g = g, b = b, a = a}
  editbox:SetHeight (14)
  editbox:SetWidth (45)
  editbox:HookScript ("OnEscapePressed", sde_OnEscapePressed)
  editbox:HookScript ("OnEnterPressed", sde_OnEnterPressed)

  if (orientation == "HORIZONTAL") then
    editbox:SetJustifyH ("CENTER")
    -- The label above the slider (only for horizontal sliders)
    if (cfg.label) then
      local label = frame:CreateFontString (nil, "OVERLAY", cfg.label.font or "GameFontNormal")
      r,g,b,a = label:GetTextColor ()
      if (cfg.label.color) then
        r = cfg.label.color.r or r
        g = cfg.label.color.g or g
        b = cfg.label.color.b or b
        a = cfg.label.color.a or a
      end
      frame.lrgb = {r = r, g = g, b = b, a = a}
      frame.label = label
      label:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 16)
      label:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 0, 16)
      label:SetJustifyH (cfg.label.justifyh or "CENTER")
      label:SetJustifyV (cfg.label.justifyv or "MIDDLE")
      label:SetHeight (16)
      label:SetText (cfg.label.text or "")
      check_tooltip_title (frame, cfg, cfg.label.text)
    end
    mintxt:SetPoint ("TOPLEFT", frame, "BOTTOMLEFT", 2, 3)
    maxtxt:SetPoint ("TOPRIGHT", frame, "BOTTOMRIGHT", -2, 3)
    editbox:SetPoint ("TOP", frame, "BOTTOM", 0, 0)
  else
    editbox:SetJustifyH ("LEFT")
    mintxt:SetPoint ("TOPLEFT", frame, "TOPRIGHT", 4, -4)
    maxtxt:SetPoint ("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 4)
    editbox:SetPoint ("LEFT", frame, "RIGHT", 4, 0)
  end

  mintxt:SetText (tostring (minval))
  maxtxt:SetText (tostring (maxval))

  local bg = editbox:CreateTexture (nil, "BACKGROUND")
  bg:SetTexture ("Interface/ChatFrame/ChatFrameBackground")
  bg:SetVertexColor (0, 0, 0, 0.25)
  bg:SetAllPoints (editbox)
  editbox.bg = bg

  frame:HookScript ("OnValueChanged", update_editbox)
  frame:HookScript ("OnMouseWheel", sd_OnMouseWheel)
  frame:HookScript ("OnMouseDown", sd_OnMouseDown)
  frame:HookScript ("OnMouseUp", sd_OnMouseUp)

  frame.OnEnable = sd_OnEnable
  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame.value = value
  frame:SetValue (value)
  frame:SetEnabled (cfg.enabled)

  frame.setup = nil

  update_eb_text (frame)

  return frame
end

function KUI:CreateButton (cfg, kparent)
  local frame, parent, width, height =
    newobj(cfg, kparent, 100, 24, cfg.name, "Button", "UIPanelButtonTemplate")

  if (cfg.hook) then
    frame:HookScript ("OnClick", function (this, ...)
      this:Throw ("OnClick", ...)
    end)
  else
    frame:SetScript ("OnClick", function (this, ...)
      this:Throw ("OnClick", ...)
    end)
  end

  frame.OnEnter = tip_OnEnter
  frame.OnLeave = tip_OnLeave

  frame:SetText (cfg.text or "")
  check_tooltip_title (frame, cfg, cfg.text)

  local fs = frame:GetFontString ()
  fs:SetWidth (width - 6)
  fs:SetHeight (height - 6)

  frame:SetEnabled (cfg.enabled)
  return frame
end

local function td_SetTab (self, tab, subtab)
  local seltab = 0
  local sseltab = 0

  if (not tab) then
    if (self.deftab) then
      tab = self.deftab
    else
      tab = self.currenttab or 1
    end
  end

  if (tonumber (tab) ~= nil) then
    seltab = tonumber (tab)
  else
    for k,v in ipairs (self.tabs) do
      if (v.name == tab) then
        seltab = tonumber (k)
      end
    end
  end

  if (not seltab) then
    return nil
  end

  PanelTemplates_SetTab (self, seltab)
  local tl = self.tabs
  for k,v in ipairs (tl) do
    if (k == seltab) then
      v.frame:Show ()
    else
      v.frame:Hide ()
    end
  end
  self.currenttab = seltab

  if (self.onclick and not subtab) then
    self.onclick (seltab, 0)
  end

  if (self.tabs[seltab].title) then
    self.title:SetText (self.tabs[seltab].title)
  elseif (self.titletext and self.titletext ~= "") then
    self.title:SetText (self.titletext)
  elseif (self.maintitle and self.maintitle ~= "") then
    self.title:SetText (self.maintitle)
  end

  --
  -- Set the "tabcontent" pointer to this current new content.
  --
  self.tabcontent = self.tabs[seltab].content

  if (not self.tabs[seltab].tabs) then
    return seltab
  end

  --
  -- If this page has subtabs and an explicit subtab was not specified,
  -- see if we have have a current subtab or not, and if not, select the
  -- first subtab.
  --
  if (self.tabs[seltab].tabs) then
    if (not subtab) then
      if (self.tabs[seltab].deftab) then
        subtab = self.tabs[seltab].deftab
      else
        subtab = self.tabs[seltab].currenttab or 1
      end
    end
  end

  if (subtab) then
    if (not self.tabs[seltab].tabs) then
      return seltab
    end

    if (tonumber(subtab) ~= nil) then
      sseltab = tonumber(subtab)
    else
      for k,v in ipairs(self.tabs[seltab].tabs) do
        if (v.name == subtab) then
          sseltab = tonumber(k)
        end
      end
    end

    if (not sseltab) then
      return seltab
    end

    PanelTemplates_SetTab (self.tabs[seltab].frame, sseltab)
    local tl = self.tabs[seltab].tabs
    for k,v in ipairs(tl) do
      if (k == sseltab) then
        v.content:Show ()
      else
        v.content:Hide ()
      end
    end
    self.tabs[seltab].currenttab = sseltab
    self.tabcontent = tl[sseltab].content

    if (self.onclick) then
      self.onclick (seltab, sseltab)
    end

    if (self.tabs[seltab].onclick) then
      self.tabs[seltab].onclick (seltab, sseltab)
    end

    if (tl[sseltab].onclick) then
      tl[sseltab].onclick (seltab, sseltab)
    end
  end
  return seltab
end

local function td_OnSizeChanged (this, w, h)
  local tx = w-160
  local ty = h-144
  local ta = this.texs
  ta.tc:SetWidth (tx)
  ta.tc:SetTexCoord (0, tx / 1024.0, 0, 1)
  ta.bc:SetWidth (tx)
  ta.bc:SetTexCoord (0, tx / 1024.0, 0, 1)
  ta.ls:SetHeight (ty)
  ta.ls:SetTexCoord (0, 1, 0, ty/1024.0)
  ta.rs:SetHeight (ty)
  ta.rs:SetTexCoord (0, 1, 0, ty/1024.0)
  this:Throw ("OnSizeChanged", w, h)
end

function KUI:CreateTabbedDialog (cfg, kparent)
  local fname = cfg.name or ("KUITabbedDlg"..self:GetWidgetNum("tabbeddialog"))
  local frame, parent, width, height = newobj (cfg, kparent, 512, 512, fname,nil,"BackdropTemplate")

  frame:SetMovable (cfg.canmove or true)
  frame:EnableMouse (true)
  frame:SetFrameStrata (cfg.strata or "FULLSCREEN_DIALOG")
  frame:Hide ()

  frame.texs = {}
  frame.maintitle = cfg.title or ""
  frame.onclick = cfg.onclick
  frame.deftab = cfg.deftab

  local it = frame:CreateTexture (nil, "BACKGROUND")
  it:SetTexture (cfg.tltexture or "Interface/FriendsFrame/FriendsFrameScrollIcon")
  it:SetWidth (60)
  it:SetHeight (60)
  it:SetPoint ("TOPLEFT", frame, "TOPLEFT", 7, -6)

  local tl = frame:CreateTexture (nil, "ARTWORK")
  tl:SetTexture (texpath .. "TDF-TopLeft")
  tl:SetWidth (128)
  tl:SetHeight (128)
  tl:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.texs.tl = tl

  local tr = frame:CreateTexture (nil, "ARTWORK")
  tr:SetTexture (texpath .. "TDF-TopRight")
  tr:SetWidth (32)
  tr:SetHeight (128)
  tr:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  frame.texs.tr = tr

  local tc = frame:CreateTexture (nil, "ARTWORK")
  tc:SetTexture (texpath .. "TDF-Top")
  tc:SetHeight (128)
  tc:SetPoint ("TOPLEFT", tl, "TOPRIGHT", 0, 0)
  frame.texs.tc = tc

  local bl = frame:CreateTexture (nil, "ARTWORK")
  bl:SetTexture (texpath .. "TDF-BotLeft")
  bl:SetWidth (128)
  bl:SetHeight (16)
  bl:SetPoint ("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  frame.texs.bl = bl

  local br = frame:CreateTexture (nil, "ARTWORK")
  br:SetTexture (texpath .. "TDF-BotRight")
  br:SetWidth (32)
  br:SetHeight (16)
  br:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.texs.bl = br

  local bc = frame:CreateTexture (nil, "ARTWORK")
  bc:SetTexture (texpath .. "TDF-Bot")
  bc:SetHeight (16)
  bc:SetPoint ("TOPLEFT", bl, "TOPRIGHT", 0, 0)
  frame.texs.bc = bc

  local ls = frame:CreateTexture (nil, "ARTWORK")
  ls:SetTexture (texpath .. "TDF-Left")
  ls:SetWidth (32)
  ls:SetPoint ("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
  frame.texs.ls = ls

  local rs = frame:CreateTexture (nil, "ARTWORK")
  rs:SetTexture (texpath .. "TDF-Right")
  rs:SetWidth (32)
  rs:SetPoint ("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
  frame.texs.rs = rs

  local bdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    tile = true,
    tileSize = 32,
    insets = { left = 32, top = 128, right = 32, bottom = 16 }
  }
  print(texpath)
--  frame:SetBackdrop (bdrop)
  frame:SetBackdropColor (0, 0, 0, 1)

  frame:HookScript ("OnSizeChanged", td_OnSizeChanged)

  local xbutton = MakeFrame ("Button", nil, frame,"UIPanelCloseButton")
  xbutton:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 4, -8)
  xbutton:SetScript ("OnClick", xbutton_OnClick)

  local tframe = MakeFrame ("Frame", nil, frame)
  tframe:EnableMouse (true)
  tframe:SetPoint ("TOPLEFT", frame, "TOPLEFT", 80, -16)
  tframe:SetPoint ("BOTTOMRIGHT", frame, "TOPRIGHT", -32, -32)

  local title = tframe:CreateFontString (nil, "OVERLAY", cfg.titlefont or "GameFontNormal")
  title:SetPoint ("TOPLEFT", tframe, "TOPLEFT", 0, 0)
  title:SetPoint ("BOTTOMRIGHT", tframe, "BOTTOMRIGHT", 0, 0)
  title:SetJustifyH ("CENTER")
  title:SetText ("")
  frame.title = title

  if (cfg.canmove) then
    tframe:SetScript ("OnMouseDown", parent_StartMoving)
    tframe:SetScript ("OnMouseUp", parent_StopMoving)
  end

  local seframe, swframe, soframe = make_resizeable (frame, 25, cfg.canresize)
  if (seframe) then
    frame:SetMinResize (cfg.minwidth or 192, cfg.minheight or 192)
    frame:SetMaxResize (cfg.maxwidth or 1024, cfg.maxheight or 1024)

    -- This "draws" the little chevron at the bottom right corner that the user
    -- can drag to resize.
    local line1 = seframe:CreateTexture (nil, "BACKGROUND")
    line1:SetTexture ("Interface/Tooltips/UI-Tooltip-Border")
    line1:SetWidth (8)
    line1:SetHeight (8)
    line1:SetPoint ("BOTTOMRIGHT", -8, 8)
    line1:SetTexCoord (-0.03, 0.05, 0.05, 0.13, 0.05, 0.42, 0.58, 0.5)
  end

  --
  -- For convenience sake and to keep things consistent with the rest of
  -- this code, we set a content frame. This will remain static no matter
  -- what tab is selected. However, we also set a tabcontent frame. This
  -- will be updated in the returned table each time a different tab is
  -- selected. The user can also select any individual tab's content
  -- pointer using ret.tabs[id].content.
  --
  frame.content = MakeFrame ("Frame", fname .. "Content", frame)
  frame.content:SetPoint ("TOPLEFT", frame, "TOPLEFT", 22, -75)
  frame.content:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
  frame.topbar = MakeFrame ("Frame", fname .. "TopBar", frame)
  frame.topbar:SetPoint ("TOPLEFT", frame, "TOPLEFT", 75, -36)
  frame.topbar:SetPoint ("BOTTOMRIGHT", frame, "TOPRIGHT", -12, -68)

  if (cfg.escclose) then
    add_escclose (fname)
  end

  local function sorter(a,b)
    if (tonumber(a.id) < tonumber(b.id)) then
      return true
    end
    return false
  end

  frame.tabs = {}
  for k,v in pairs(cfg.tabs) do
    local tval = { name = k, title = v.title, text = v.text, id=v.id,
      hsplit = v.hsplit, vsplit = v.vsplit, tabframe = v.tabframe,
      onclick = v.onclick}
    if (v.tabs) then
      tval.tabs = {}
      tval.deftab = v.deftab
      for kk, vv in pairs(v.tabs) do
        local stval = { name = kk, text = vv.text, id = vv.id,
          hsplit = vv.hsplit, vsplit = vv.vsplit, onclick = vv.onclick }
        tinsert (tval.tabs, stval)
      end
      table.sort(tval.tabs, sorter)
    end
    tinsert (frame.tabs, tval)
  end
  table.sort (frame.tabs, sorter)

  local nt = table.maxn(frame.tabs)
  local rtp = "BOTTOMLEFT"
  local rf = frame
  local rx, ry = 15, 5
  for k,v in ipairs (frame.tabs) do
    local thistab = frame.tabs[k]
    thistab.subtab = 1

    -- Full frame for this page
    local pf = MakeFrame ("Frame", fname .. "Page" .. k, frame)
    pf:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pf:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    pf.tabnum = k
    thistab.frame = pf
    pf:Hide ()

    -- Content frame for this page
    local pcf = MakeFrame ("Frame", pf:GetName() .. "Content", pf)
    pcf:SetPoint ("TOPLEFT", pf, "TOPLEFT", 22, -75)
    pcf:SetPoint ("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -12, 12)
    pcf.tabnum = k
    thistab.content = pcf

    local function do_hsplit (cframe, arg)
      local oname = arg.name
      if (not arg.name) then
        arg.name = cframe:GetName() .. "HSplit";
      end
      cframe.hsplit = self:CreateHSplit (arg, cframe)
      arg.name = oname
    end

    local function do_vsplit (cframe, arg)
      local oname = arg.name
      if (not arg.name) then
        arg.name = cframe:GetName() .. "VSplit";
      end
      cframe.vsplit = self:CreateVSplit (arg, cframe)
      arg.name = oname
    end

    --
    -- If the user has requested it, reserve space at the bottom for buttons
    -- or other stuff. Draw the horizontal divider and set two frame pointers,
    -- for the top half and the bottom half.
    --
    if (thistab.hsplit) then
      do_hsplit (pcf, thistab.hsplit)
    end

    --
    -- Also if the user has requested a vertical split, do that too.
    --
    if (thistab.vsplit) then
      do_vsplit (pcf, thistab.vsplit)
    end

    -- Header bar for this page
    local ptb = MakeFrame ("Frame", pf:GetName() .. "Topbar", pf)
    ptb:SetPoint ("TOPLEFT", pf, "TOPLEFT", 73, -36)
    ptb:SetPoint ("BOTTOMRIGHT", pf, "TOPRIGHT", -12, -68)
    ptb.tabnum = k
    thistab.topbar = ptb

    -- Create the actual tab button for the bottom edge of the frame
    local tb = MakeFrame ("Button", fname .. "Tab" .. k, frame,
      "CharacterFrameTabButtonTemplate")
    tb:SetID (k)
    tb:SetText (v.text)
    tb:SetPoint ("TOPLEFT", rf, rtp, rx, ry)
    tb.onclick = v.onclick
    PanelTemplates_SelectTab (tb)
    PanelTemplates_TabResize (tb, 0)
    tb:SetScript ("OnClick", function (this)
      local tnum = this:GetID ()
      this:GetParent():SetTab (tnum)
    end)
    thistab.tbutton = tb
    tb.SetShown = BC.SetShown
    rf = tb
    rtp = "TOPRIGHT"
    rx = -16
    ry = 0

    --
    -- Now see if this main tab has sub-tabs that are displayed on the top bar.
    -- The frames created by this cover only the content portion. The header
    -- frame remains under the domain of the containing tab page. Each sub-
    -- tab will get its own content frame though. However, because these
    -- sub-frames are children of the page's content frame, they are
    -- automatically hidden when the page is hidden and the user selects
    -- a different page using the bottom tabs. When this page frame is
    -- shown, however, it will revert back to the last sub-frame selected,
    -- unless that has been changed by some other function.
    --
    if (thistab.tabs) then
      local snt = table.maxn(thistab.tabs)
      local srtp = "BOTTOMLEFT"
      local srf = thistab.topbar
      local srx, sry = 0, 28

      for kk,vv in ipairs(thistab.tabs) do
        local subtab = thistab.tabs[kk]

        --
        -- First the sub-tab content frame. If the main tab has a horizontal
        -- or vertical split (but not both, this code doesn't handle that
        -- case well), and they have requested that the subtab control one of
        -- those sides of the split, ensure we cover only that portion.
        --
        local stcontent = thistab.content

        if (thistab.tabframe and (thistab.vsplit or thistab.hsplit)) then
          if (thistab.vsplit) then
            if (thistab.tabframe == "LEFT") then
              stcontent = pcf.vsplit.leftframe
            elseif (thistab.tabframe == "RIGHT") then
              stcontent = pcf.vsplit.rightframe
            end
          elseif (thistab.hsplit) then
            if (thistab.tabframe == "TOP") then
              stcontent = pcf.hsplit.topframe
            elseif (thistab.tabframe == "BOTTOM") then
              stcontent = pcf.hsplit.bottomframe
            end
          end
        end

        local scf = MakeFrame ("Frame",
          thistab.content:GetName() .. "Sub" .. kk, stcontent)
        scf:SetPoint ("TOPLEFT", stcontent, "TOPLEFT", 0, 0)
        scf:SetPoint ("BOTTOMRIGHT", stcontent, "BOTTOMRIGHT", 0, 0)
        scf.tabnum = kk
        scf:Hide ()
        subtab.content = scf
        if (subtab.hsplit) then
          do_hsplit (scf, subtab.hsplit)
        end

        if (subtab.vsplit) then
          do_vsplit (scf, subtab.vsplit)
        end

        -- Now the actual button for the top bar. This is made a child of the
        -- page's main frame, even though it is anchored to the topbar frame.
        local stb = MakeFrame ("Button",
          thistab.frame:GetName() .. "Tab" .. kk, thistab.frame,
          "TabButtonTemplate")
        stb:SetID (kk)
        stb:SetText (vv.text)
        stb.pbuttonid = k
        stb:SetPoint ("TOPLEFT", srf, srtp, srx, sry)
        PanelTemplates_SelectTab (stb)
        PanelTemplates_TabResize (stb, 0)
        stb:SetScript ("OnClick", function (this)
          local tnum = this:GetID ()
          this:GetParent():GetParent():SetTab (this.pbuttonid, tnum)
        end)
        subtab.tbutton = stb
        stb.SetShown = BC.SetShown
        srtp = "TOPRIGHT"
        srf = stb
        srx = 0
        sry = 0
      end
      PanelTemplates_SetNumTabs (thistab.frame, snt)
      PanelTemplates_SetTab (thistab.frame, 1)
    end
  end

  frame.tabs[1].frame:Show ()
  PanelTemplates_SetNumTabs (frame, nt)
  PanelTemplates_SetTab (frame, 1)

  frame.SetTitleText = function (this, text)
    this.titletext = text or ""
    this.title:SetText (this.titletext)
  end

  frame.SetTab = td_SetTab

  frame:SetTab (1,1)

  return frame
end

--
-- Please note that this element type completely fills the parent frame,
-- and that the width and height config elements are ignored. If you require
-- a specific size, ensure that the parent specified is of the correct size.
--

--
-- This function is used to set the current item in a list. It is called
-- from several places. First, when a list is being updated with new items
-- it is called with a nil offset to disable any current selection. This
-- is because the current selection may no longer be valid after the list
-- is updated. Thus it is the caller's responsibility to remember any
-- current position if restoring the current selection is important.
-- Second, it is called when a list item is clicked. It is not called
-- directly, but through the containing list's :SetSelected() method. The
-- default helper functions do this correctly but if the code implements
-- its own newitem method, it must set the OnClick handler to call the
-- :SetSelected() method itself.
-- When a new offset is selected, this code ensures that the previously
-- selected entry has its highlight removed and its deselection routine run.
-- It then highlights the new entry, and runs its selection method. Thus all
-- of the logic for dealing with the selection is here in this function.
--
local function sl_setsel (objp, offset, force)
  local i
  local nslot = nil
  local nbtn = nil
  local ro

  if (offset and (offset > objp.itemcount or offset <= 0)) then
    offset = nil
  end

  if (objp.selecteditem) then
    -- We have a currently selected item. If the new offset is not the same
    -- as the current selection, we need to remove the highlight, and run
    -- the current selected items deselection function.
    local cslot = nil
    local cbtn = nil
    for i = 1, objp.visibleslots do
      ro = i + objp.offset
      if (ro == objp.selecteditem) then
        cslot = i
        cbtn = objp.slots[i]
      end
      if (offset and ro == ofset) then
        nslot = i
        nbtn = objp.slots[i]
      end
    end
    if (objp.selecteditem ~= offset) then
      -- The new offset is not the same as the current. If the current one
      -- is being displayed at the moment, remove its highlight.
      if (cslot) then
        objp:highlightitem (objp.selecteditem, cslot, cbtn, false)
      end
      -- And run its deselection function
      objp:selectitem (objp.selecteditem, cslot, cbtn, false)
    else
      if (force) then
        objp:selectitem (objp.selecteditem, cslot, cbtn, true)
      end
      return
    end
  end

  if (offset and not nslot) then
    for i = 1, objp.visibleslots do
      ro = i + objp.offset
      if (ro == offset) then
        nslot = i
        nbtn = objp.slots[i]
        break
      end
    end
  end

  objp.selecteditem = offset
  if (offset) then
    -- If we have a new offset and it would be visible, turn on its highlight
    -- and run its selection function. If it wouldnt be visible just run the
    -- selection function.
    if (nbtn) then
      objp:highlightitem (offset, nslot, nbtn, true)
    end
    objp:selectitem (offset, nslot, nbtn, true)
  else
    -- No offset, we're setting the offset to nil. No need to deal with any
    -- highlights here, just call the selection function appropriately.
    objp:selectitem (nil, nil, nil, nil)
  end
end

local function sl_setrem_highlight (objp, onoff)
  local onoff = onoff or false
  if (not objp.selecteditem) then
    return
  end
  local i, ro
  local sel = objp.selecteditem
  for i = 1, objp.visibleslots do
    ro = i + objp.offset
    if (ro == sel) then
      objp:highlightitem (ro, i, objp.slots[i], onoff)
      return
    end
  end
end

local function sl_vertscroll (objp, offset)
  sl_setrem_highlight (objp, false)
  local sb = objp.scrollbar
  local sel = objp.selecteditem
  objp.visibleslots = floor (objp:GetHeight () / objp.itemheight)
  local maxoffs = (objp.itemcount - objp.visibleslots) * objp.itemheight
  maxoffs = max (maxoffs, 0)

  if (offset ~= nil) then
    if (offset < 0) then
      offset = 0
    elseif (offset > maxoffs) then
      offset = maxoffs
    end
    sb:SetValue (offset)
    objp.offset = floor((offset / objp.itemheight) + 0.5)
  end

  if (objp.itemcount <= objp.visibleslots) then
    objp.offset = 0
    sb:SetValue (0)
  end

  for i = 1, objp.visibleslots do
    local ro = i + objp.offset

    if (ro > objp.itemcount) then
      objp.slots[i]:Hide ()
    else
      objp.slots[i]:Show ()
      objp.slots[i]:SetID (ro)
      objp:setitem (ro, i, objp.slots[i])
    end
  end

  if (objp:IsShown ()) then
    local upb = _G[sb:GetName () .. "ScrollUpButton"]
    local dnb = _G[sb:GetName () .. "ScrollDownButton"]
    local sch = 0

    if (objp.itemcount > 0) then
      objp.content:Show()
      sch = objp.itemcount * objp.itemheight
    else
      objp.content:Hide ()
    end

    sb:SetMinMaxValues (0, maxoffs)
    sb:SetValueStep (objp.itemheight)
    objp.content:SetHeight (sch)

    if (objp.offset > maxoffs) then
      objp.offset = maxoffs
      sb:SetValue (maxoffs)
    end

    if (sb:GetValue () == 0) then
      upb:Disable ()
    else
      upb:Enable ()
    end
    if (sb:GetValue () - maxoffs == 0) then
      dnb:Disable ()
    else
      dnb:Enable ()
    end
  end
  sl_setrem_highlight (objp, true)
end

local function sl_updatevals (objp)
  sl_setrem_highlight (objp, false)
  local dispheight = objp:GetHeight ()
  local fullheight = objp.content:GetHeight ()
  local numvisible = floor (dispheight / objp.itemheight)
  local desiredheight = objp.itemcount * objp.itemheight
  local rslot = nil
  local rbtn = nil

  if (numvisible > objp.numslots) then
    for i = objp.numslots+1, numvisible do
      objp.slots[i] = objp.newitem (objp, i)
      if (i == 1) then
        objp.slots[i]:SetPoint ("TOPLEFT", objp, "TOPLEFT", 0, 0)
      else
        objp.slots[i]:SetPoint ("TOPLEFT", objp.slots[i-1], "BOTTOMLEFT", 0, 0)
      end
      objp.slots[i]:Hide ()
    end
    objp.numslots = numvisible
  end

  for i = 1, numvisible do
    local ro = i + objp.offset
    if (ro <= objp.itemcount) then
      objp.slots[i]:Show ()
      objp.slots[i]:SetID (ro)
      objp:setitem (ro, i, objp.slots[i])
      if (ro == objp.selecteditem) then
        rslot = i
        rbtn = objp.slots[i]
      end
    end
  end

  for i = numvisible+1, objp.numslots do
    objp.slots[i]:Hide ()
  end

  objp.content:SetHeight (desiredheight)
  objp.visibleslots = numvisible
  if (numvisible < objp.itemcount) then
    objp.scrollbar:Show ()
    objp.scrollbar:SetValue (objp.scrollbar:GetValue() or 0)
  else
    objp.scrollbar:Hide ()
  end

  sl_setrem_highlight (objp, true)
  return rslot, rbtn
end

function KUI:CreateScrollList (cfg, kparent)
  local x = self:GetWidgetNum ("scrolllist")
  local fname = cfg.name or ("KUIScrollList" .. x)
  local frame, parent, width, height = newobj(cfg, kparent, 0, 0, fname, "ScrollFrame","BackdropTemplate")
  local sname = "KUIScrollBar" .. self:GetWidgetNum ("scrollbar")
  local scrollbar = MakeFrame ("Slider", sname, frame, "UIPanelScrollBarTemplateLightBorder")
  local content = MakeFrame ("Frame", nil,frame)

  assert (cfg.newitem)
  assert (cfg.setitem)
  assert (cfg.selectitem)
  assert (cfg.highlightitem)

  local scrollbg = scrollbar:CreateTexture (nil, "BACKGROUND")
  scrollbg:SetAllPoints (scrollbar)
  scrollbg:SetColorTexture (0, 0, 0, 0.4)

  frame.scrollbar = scrollbar
  frame.offset = 0
  frame.content = content

  frame:ClearAllPoints ()
  frame:SetPoint ("TOPLEFT", parent, "TOPLEFT", 0, 0)
  frame:SetPoint ("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 0)
  frame:SetScrollChild (content)
  frame:EnableMouseWheel (true)
  scrollbar:EnableMouseWheel (true)

  --
  -- itemheight is the height of each individual item in the list.
  -- newitem is a function that is called to create a new item slot when the
  -- window size changes and the code needs a new item to display a list
  -- entry. This code will only ever create more item slots, it will never
  -- reduce them, so the maximum number of slots is always the largest the
  -- window has ever been. If the window is shrunk, there will be excess
  -- item slots that simply go unused.
  -- setitem is called to set an individual item in the list. It is passed
  -- the real index (from list item 1) as well as the slot index and the
  -- return value from newitem() for that slot.
  --
  frame.itemheight = cfg.itemheight
  frame.newitem = cfg.newitem
  frame.setitem = cfg.setitem
  frame.selectitem = cfg.selectitem
  frame.highlightitem = cfg.highlightitem
  frame.slots = {}
  frame.numslots = 0
  frame.visibleslots = 0
  frame.itemcount = 0

  frame:HookScript ("OnMouseWheel", function (self, delta)
    local sb = self.scrollbar
    if (delta > 0) then
      sb:SetValue (sb:GetValue () - (sb:GetHeight () / 2))
    else
      sb:SetValue (sb:GetValue () + (sb:GetHeight () / 2))
    end
  end)

  scrollbar:HookScript ("OnMouseWheel", function (self, delta)
    if (delta > 0) then
      self:SetValue (self:GetValue () - (self:GetHeight () / 2))
    else
      self:SetValue (self:GetValue () + (self:GetHeight () / 2))
    end
  end)

  frame:HookScript ("OnSizeChanged", function (this, w, h)
    sl_updatevals (this)
    sl_vertscroll (this, nil)
  end)

  frame:HookScript ("OnVerticalScroll", function (this, offset)
    sl_vertscroll (this, offset)
  end)

  content:ClearAllPoints ()
  content:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 0)
  content:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  scrollbar:ClearAllPoints ()
  scrollbar:SetPoint ("TOPLEFT", frame, "TOPRIGHT", 4, -20)
  scrollbar:SetPoint ("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 20)

  frame.UpdateList = function (this)
    this.selecteditem = nil
    for i = 1, this.visibleslots do
      this.highlightitem (this, nil, 1, this.slots[i], false)
    end
    sl_setsel (this, nil, false)
    sl_updatevals (this)
    sl_vertscroll (this, nil)
  end

  frame.SetSelected = function (this, offset, display, force)
    sl_setsel (this, offset, force)
    if (display and offset) then
      sl_vertscroll (this, (offset - 1) * this.itemheight)
    end
  end

  frame.GetSelected = function (this)
    return this.selecteditem
  end

  sl_updatevals (frame)
  return frame
end

--
-- These functions are helper functions for dealing with scroll lists.
-- Most often, scroll lists are lists of text items that need to have
-- something happen when they are selected, deselected and clicked.
-- Most of the code can be shared, and these helper functions do most of
-- the common stuff. They provide opportunities for the caller to
-- provide custom functions for various tasks.
--
function KUI.NewItemHelper (objp, num, name, w, h, stf, och, ocs, pch)
  local bname = name .. tostring(num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (w or 160)
  rf:SetHeight (h or 16)
  rf:SetHighlightTexture (htn, "ADD")

  local text = rf:CreateFontString (nil, "ARTWORK", nfn)
  text:ClearAllPoints ()
  text:SetPoint ("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint ("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -8, 2)
  text:SetJustifyH ("LEFT")
  text:SetJustifyV ("TOP")
  rf.text = text

  rf.SetText = stf or function (self, txt)
    self.text:SetText (txt)
  end

  rf:SetScript ("OnClick", och or function (this, button)
    local idx = this:GetID ()
    if (ocs) then
      if (ocs(this, idx)) then
        return
      end
    end
    this:GetParent():GetParent():SetSelected (idx, false)
  end)

  if (pch) then
    pch (rf, objp, num)
  end

  return rf
end

function KUI.SetItemHelper (objp, btn, idx, tfn)
  local ts = tfn (objp, idx)
  btn:SetText (ts)
end

function KUI.SelectItemHelper (objp, idx, slot, btn, onoff, cfn, onfn, offfn, nilfn)
  if (onoff) then
    if (cfn) then
      local rv = cfn ()
      if (rv == nil) then return end
      if (rv == false) then
        error ("Severe logic bug! Please report to cruciformer@gmail.com", 1)
        return
      end
    end

    if (onfn) then
      return onfn (objp, idx, slot, btn, true)
    end
  elseif (onoff == false) then
    if (offfn) then
      return offfn (objp, idx, slot, btn, onoff)
    end
  elseif (onoff == nil) then
    if (nilfn) then
      return nilfn (objp, idx, slot, btn, nil)
    end
    if (offfn) then
      return offfn (objp, idx, slot, btn, nil)
    end
  end
end

function KUI.HighlightItemHelper (objp, idx, slot, btn, onoff, onfn, offfn)
  if (onoff) then
    local ntn = "Interface/AuctionFrame/UI-AuctionFrame-FilterBg"
    btn:SetNormalTexture (ntn)
    local nt = btn:GetNormalTexture()
    nt:SetTexCoord (0, 0.53125, 0, 0.625)

    if (onfn) then
      return onfn (objp, idx, slot, btn, true)
    end
    return
  else
    btn:SetNormalTexture (nil)
    if (offfn) then
      return offfn (objp, idx, slot, btn, false)
    end
  end
end

KUI.ddframes = KUI.ddframes or {}

local function ddmi_tooltip (this)
  if (this.spacer) then
    return
  end
  do_tooltip_onenter (this, this.enabled and (not this.title))
end

local function stop_countdown (this)
  this:SetScript ("OnUpdate", nil)
end

local function cd_OnUpdate (this)
  local now = GetTime ()
  if ((now - this.timeout_start) > this.timeout) then
    this:SetScript ("OnUpdate", nil)
    if (this.dropdown) then
      this.dropdown:Close ()
    else
      this:Close ()
    end
    this.timeout_start = 0
    this.lastpos = {}
  end
end

local function start_countdown (this)
  this.timeout_start = GetTime ()
  this:SetScript ("OnUpdate", cd_OnUpdate)
end

local function tl_OnShow (this)
  this.toplevel:StartTimeoutCounter ()
  this.toplevel.screenw = GetScreenWidth ()
  this.toplevel.screenh = GetScreenHeight ()
  this.toplevel.scale = UIParent:GetEffectiveScale ()
end

local function tl_OnHide (this)
  this.toplevel:StopTimeoutCounter ()
  if (this.toplevel.subopen) then
    this.toplevel.subopen:Close ()
    this.toplevel.subopen = nil
  end
end

local function tl_OnEnter (this)
  this.toplevel:StopTimeoutCounter ()
  do_tooltip_onenter (this, this.enabled or false)
end

local function tl_OnLeave (this)
  this.toplevel:StartTimeoutCounter ()
  GameTooltip:Hide ()
end

local function dd_OnEnter (this)
  this.toplevel:StopTimeoutCounter ()
  do_tooltip_onenter (this.toplevel, this.toplevel.enabled or false)
end

local function dd_OnLeave (this)
  this.toplevel:StartTimeoutCounter ()
  GameTooltip:Hide ()
end

local function parent_OnEnter (this)
  this:GetParent().toplevel:StopTimeoutCounter ()
end

local function parent_OnLeave (this)
  this:GetParent().toplevel:StartTimeoutCounter ()
end

local function dd_Close (self)
  if (self.subopen) then
    self.subopen:Close ()
    self.subopen = nil
  end
  self:Hide ()
  tremove (self.toplevel.lastpos)
end

local function nfr_OnEnter (this)
  this.toplevel:StopTimeoutCounter ()
  if (this.parent.subopen) then
    this.parent.subopen:Close ()
    this.parent.subopen = nil
  end
  if (this.menuframe and this.enabled) then
    local os = this.toplevel.offset
    local ls = this.parent.hasvscroll
    local nl = #this.toplevel.lastpos
    local lasth = nl > 0 and this.toplevel.lastpos[nl][1] or nil
    local lastv = nl > 0 and this.toplevel.lastpos[nl][2] or nil
    local sw = this.toplevel.screenw
    local sh = this.toplevel.screenh
    this.menuframe:Show ()
    this.parent.subopen = this.menuframe
    local rpos = KUI.GetFramePos (this, true)
    this.menuframe:ClearAllPoints ()
    this.menuframe:SetPoint ("TOPLEFT", this, "TOPRIGHT", 0, os)
    local mpos = KUI.GetFramePos (this.menuframe, true)
    this.menuframe:ClearAllPoints ()
    if (mpos.r > sw) then
      lasth = "LEFT"
    elseif ((rpos.l - mpos.w) < 0) then
      lasth = "RIGHT"
    elseif (not lasth) then
      if (mpos.l < (sw / 2)) then
        lasth = "RIGHT"
      else
        lasth = "LEFT"
      end
    end
    if (mpos.b < 0) then
      lastv = "UP"
    elseif (mpos.t > sh) then
      lastv = "DOWN"
    elseif (not lastv) then
      if (mpos.t < (sh / 2)) then
        lastv = "UP"
      else
        lastv = "DOWN"
      end
    end

    if (lastv == "UP") then
      if (lasth == "LEFT") then
        this.menuframe:SetPoint ("BOTTOMRIGHT", this, "BOTTOMLEFT", -ls, -os)
      else
        this.menuframe:SetPoint ("BOTTOMLEFT", this, "BOTTOMRIGHT", 0, -os)
      end
    else
      if (lasth == "LEFT") then
        this.menuframe:SetPoint ("TOPRIGHT", this, "TOPLEFT", -ls, os)
      else
        this.menuframe:SetPoint ("TOPLEFT", this, "TOPRIGHT", 0, os)
      end
    end
    tinsert (this.toplevel.lastpos, { lasth, lastv })
  end
  ddmi_tooltip (this)
end

local function nfr_OnLeave (this)
  this.toplevel:StartTimeoutCounter ()
  GameTooltip:Hide ()
end

--
-- If this is an item for a dropdown and it is in either SINGLE or COMPACT
-- mode, we do not uncheck it if it is already checked, or if there is already
-- anothe value checked, we uncheck that one and check this one. For MULTI
-- mode dropdowns or for popup menus, this becomes a simple toggle.
--
local function run_funcs (this, iscreate)
  if (this.func) then
    this.func (this, iscreate)
  end
  if (this.parent.func and this.parent.func ~= this.func) then
    this.parent.func (this, iscreate)
  end
  if (this.toplevel.func and this.toplevel.func ~= this.parent.func and this.toplevel.func ~= this.func) then
    this.toplevel.func (this, iscreate)
  end
end

local function real_nfr_OnClick (this, isset)
  local tlf = this.toplevel

  if (not tlf.mode or (tlf.mode == 3)) then
    if (this.checked) then
      if (this.checkmark) then
        this.checkmark:Hide ()
      end
    else
      if (this.checkmark) then
        this.checkmark:Show ()
      end
    end
    this.checked = not this.checked
    this.toplevel:Throw ("OnItemChecked", this, this.checked)
    if (tlf.mode == 3 and not this.keep) then
      tlf.dropdown:Close ()
    end
  else
    local changed = false
    if (tlf.current) then
      if (tlf.current == this) then
        if (isset) then
          return
        end
        if (not this.keep) then
          tlf.dropdown:Close ()
        end
        return
      else
        changed = true
        tlf.current.checked = false
        if (tlf.current.checkmark) then
          tlf.current.checkmark:Hide ()
        end
        tlf:Throw ("OnItemChecked", tlf.current, false)
        run_funcs (tlf.current, false)
      end
    end
    tlf.current = this
    if (this.checked == false) then
      changed = true
    end
    this.checked = true
    if (this.checkmark) then
      this.checkmark:Show ()
    end
    if (not this.keep) then
      if (not isset) then
        tlf.dropdown:Close ()
      end
    end
    if (this.text) then
      tlf.text:SetText (this.text:GetText ())
      local r,g,b,a = this.text:GetTextColor ()
      local d = tlf.enabled and 1 or 2
      tlf.text:SetTextColor (r/d, g/d, b/d, a)
    end
    tlf:Throw ("OnItemChecked", this, true)
    if (changed) then
      tlf:Throw ("OnValueChanged", this.value, true)
    end
  end

  run_funcs (this, false)
end

local function nfr_OnClick (this)
  if ((not this.clickable) or (not this.enabled)) then
    return
  end
  real_nfr_OnClick (this)
end

local function nfr_OnHide (this)
  if (this.subopen) then
    this.subopen:Close ()
    this.subopen = nil
  end
end

local function dd_SetJustification (this, just)
  local tf = this.text
  if (just == "RIGHT") then
    tf:SetJustifyH (just)
  elseif (just == "CENTER") then
    tf:SetJustifyH (just)
  else
    just = "LEFT"
    tf:SetJustifyH (just)
  end
end

local global_dd_shown

local function dd_OnClick (this, ...)
  local pdf = this:GetParent().dropdown
  if (pdf:IsShown ()) then
    pdf:Close ()
    if (global_dd_shown == pdf) then
      global_dd_shown = nil
    end
  else
    if (global_dd_shown) then
      global_dd_shown:Close ()
      global_dd_shown = nil
    end
    if (pdf.itemcount < 1) then
      return
    end
    pdf:Show ()
    global_dd_shown = pdf
  end
  this:GetParent():Throw ("OnClick", ...)
end

local function dd_OnMouseWheel (this, value)
  local sbf = this:GetParent().scrollbar
  local sv = floor(sbf:GetValueStep()) or 0
  local cv = sbf:GetValue() or 0
  local _, my = sbf:GetMinMaxValues ()
  if (value > 0) then
    cv = cv - sv
  elseif (value < 0) then
    cv = cv + sv
  end
  if (cv < 0 or cv < sv) then
    cv = 0
  end
  if (cv > my) then
    cv = my
  end
  cv = (floor(cv/sv) * sv)
  sbf:SetValue (cv)
end

local function dd_OnValueChanged (this, val)
  local sf = this:GetParent().sframe
  sf:SetVerticalScroll (val)
  sf:UpdateScrollChildRect ()
end

local function dd_OnScrollRangeChanged (this, x, y)
  local fr = this:GetParent ()
  local sb = fr.scrollbar
  local cv = sb:GetValue () or 0
  local _, my = sb:GetMinMaxValues ()
  local sheight = (this:GetHeight () - (2 * fr.offset) - fr.headeroffset - fr.footeroffset) / 2

  if (my ~= y) then
    sb:SetMinMaxValues (0, y)
  end
  if (cv > y) then
    cv = y
  end

  if (sheight > y) then
    sheight = y
  end
  sb:SetValueStep (sheight)
  sb:SetValue (cv)
end

local function tl_OnEvent (this, event)
  if (event == "PLAYER_REGEN_ENABLED") then
    this.incombat = false
    this:Throw ("OnLeaveCombat")
  elseif (event == "PLAYER_REGEN_DISABLED") then
    this.incombat = true
    this:Throw ("OnEnterCombat")
  end
end

local function dd_create_cframe (fr, cfname, ftype)
  local nfr
  if (not ftype and fr.kframes[cfname]) then
    nfr = fr.kframes[cfname]
    nfr:SetParent (fr.cframe)
  else
    nfr = MakeFrame (ftype or "Button", ftype == nil and cfname or nil, fr.cframe)
    if (not ftype) then
      fr.kframes[cfname] = nfr
    end
  end
  nfr:SetFrameStrata (fr.cframe:GetFrameStrata ())
  nfr:SetFrameLevel (fr.cframe:GetFrameLevel () + 1)
  nfr.toplevel = fr.toplevel or fr
  nfr.parent = fr
  nfr.rparent = fr.cframe
  nfr:SetScript ("OnEnter", nfr_OnEnter)
  nfr:SetScript ("OnLeave", nfr_OnLeave)
  if (not ftype) then
    nfr:SetScript ("OnClick", nfr_OnClick)
  end
  nfr:SetScript ("OnHide", nfr_OnHide)
  nfr.tiptitle = nil
  nfr.tiptext = nil
  nfr.tipfunc = nil
  return nfr
end

local create_dd_sa

local function dd_refresh_frame (fr, tlfr, ilist, nilist)
  if (tlfr == fr) then
    -- If this is the top level frame, set it to nil
    tlfr = nil
  end
  fr.itemcount = nilist
  fr.items = ilist
  fr.iheight = 0
  fr.iframes = {}
  local cf = fr.cframe

  --
  -- Set up the actual list item buttons. As we go through the list we
  -- calculate the widest button and whether or not any buttons have
  -- check marks, icons or submenu marks. We set the text for each
  -- button (with any color specified) and other button options.
  --
  local relframe = fr.cframe
  local rtopleft = "TOPLEFT"
  local rbotright = "TOPRIGHT"
  local widest = 0
  local hassub = 0
  local hasicons = 0
  local hascheck = 0

  for k,v in ipairs (fr.items) do
    local tbf, txt, w, h = nil, nil, nil, nil

    local cfname = cf:GetName() .. "Button" .. k
    tbf = dd_create_cframe (fr, cfname, v.frame and "Frame" or nil)
    tinsert (fr.iframes, tbf)

    tbf.text = nil
    tbf.frame = nil
    tbf.spacer = nil
    tbf.height = nil
    tbf.width = nil
    tbf.iinfo = v
    tbf.idx = k
    tbf.arg = v.arg
    tbf.name = v.name
    tbf.func = v.func
    tbf.value = v.value
    tbf.menuname = fr:GetName ()
    tbf.menuarg = fr.arg
    if (v.tooltip) then
      tbf.tiptitle = v.tooltip.title
      tbf.tiptext = v.tooltip.text
      tbf.tipfunc = v.tooltip.func
    end
    if (tlfr) then
      tbf.toplevel = tlfr
      tbf.tlarg = tlfr.arg
      tbf.tlname = tlfr:GetName ()
    else
      tbf.toplevel = fr
      tbf.tlarg = fr.arg
      tbf.tlname = fr:GetName ()
    end

    if (v.color) then
      if (type (v.color) == "table") then
        tbf.color = {r = v.color.r or 1, g = v.color.g or 1, b = v.color.b or 1, a = v.color.a or 1 }
      elseif (type (v.color) == "function") then
        local fc = v.color (tbf)
        assert (type (fc) == "table", "return color must be an RGB table")
        tbf.color = {r = fc.r or 1, g = fc.g or 1, b = fc.b or 1, a = fc.a or 1 }
      else
        assert (false, "color must be a table or function")
      end
    else
      tbf.color = nil
    end

    -- See if it is a title element or not
    tbf.title = false
    if (v.title ~= nil) then
      if (type (v.title) == "boolean") then
        tbf.title = v.title
      elseif (type (v.title) == "function") then
        tbf.title = v.title (tbf)
      else
        assert (false, "title must be a boolean or a function")
      end
    end

    -- See if it is disabled or not
    tbf.enabled = true
    if (v.enabled ~= nil) then
      if (type (v.enabled) == "boolean") then
        tbf.enabled = v.enabled
      elseif (type (v.enabled) == "function") then
        tbf.enabled = v.enabled (tbf)
      else
        assert (false, "enabled must be a boolean or a function")
      end
    end

    -- Determine if it is checked or not
    tbf.checked = false
    if (v.checked ~= nil) then
      if (type (v.checked) == "boolean") then
        tbf.checked = v.checked
      elseif (type (v.checked) == "function") then
        tbf.checked = v.checked (tbf)
      else
        assert (false, "checked must be a boolean or a function")
      end
    end

    -- Determine if we should keep the window open on click or not
    if (fr.mode == 1 or fr.mode == 2) then
      tbf.keep = false
    else
      tbf.keep = true
    end
    if (v.keep ~= nil) then
      if (type (v.keep) == "boolean") then
        tbf.keep = v.keep
      elseif (type (v.keep) == "function") then
        tbf.keep = v.keep (tbf)
      else
        assert (false, "keep must be a boolean or a function")
      end
    end

    -- Determine the item text
    tbf.spacer = nil
    if (v.text) then
      if (type (v.text) == "string") then
        txt = v.text
      elseif (type (v.text) == "function") then
        txt = v.text (tbf)
      else
        assert (false, "text must be a string or a function")
      end
      assert (txt)
      if (txt == "-") then
        -- This is a spacer
        if (not tbf.p_spacer) then
          local st = tbf:CreateTexture (nil, "ARTWORK")
          st:SetColorTexture (0.75, 0.75, 0.75, 1)
          st:Hide ()
          tbf.p_spacer = st
        end
        tbf.spacer = tbf.p_spacer
        txt = nil
      else
        if (tbf.p_spacer) then
          tbf.p_spacer:Hide ()
        end
      end
    end

    -- Determine if the item is clickable or not
    tbf.clickable = true
    if (v.notclickable ~= nil) then
      if (type (v.notclickable) == "boolean") then
        tbf.clickable = not v.notclickable
      elseif (type (v.notclickable) == "function") then
        tbf.clickable = not v.notclickable (tbf)
      else
        assert (false, "notclickable must be a boolean or a function")
      end
    end

    -- Determine if the item is checkable or not
    tbf.checkable = true
    if (v.notcheckable ~= nil) then
      if (type (v.notcheckable) == "boolean") then
        tbf.checkable = not v.notcheckable
      elseif (type (v.notcheckable) == "function") then
        tbf.checkable = not v.notcheckable (tbf)
      else
        assert (false, "notcheckable must be a boolean or a function")
      end
    end

    -- Set values that depend on the type
    if (tbf.title or tbf.spacer) then
      tbf.checked = false
      tbf.clickable = false
      tbf.checkable = false
    end

    if (not tbf.enabled) then
      tbf.clickable = false
      if (not tbf.frame) then
        tbf:SetScript ("OnClick", nil)
      end
    end

    -- In COMPACT mode all items are not checkable
    if (fr.mode == 2) then
      tbf.checkable = false
    end

    -- Adjust for submenus, icons and check marks
    if (v.submenu) then
      tbf.checkable = false
      hassub = 16
      if (not tbf.p_subarrow) then
        local sm = tbf:CreateTexture (nil, "ARTWORK")
        sm:SetTexture ("Interface/ChatFrame/ChatFrameExpandArrow")
        sm:SetWidth (16)
        sm:SetHeight (16)
        sm:SetPoint ("LEFT", tbf, "RIGHT", -16, 0)
        sm:Show ()
        tbf.p_subarrow = sm
      end
      tbf.subarrow = tbf.p_subarrow
      if (tbf.enabled) then
        SetDesaturation (tbf.subarrow, false)
        tbf.menuframe = create_dd_sa (v.submenu, fr, fr.toplevel, nil)
      else
        SetDesaturation (tbf.subarrow, true)
        tbf.menuframe = nil
      end
    else
      if (tbf.p_subarrow) then
        tbf.p_subarrow:Hide ()
      end
      tbf.subarrow = nil
      tbf.menuframe = nil
    end

    if (v.icon) then
      hasicons = 16
      if (not tbf.p_icon) then
        local it = tbf:CreateTexture (nil, "ARTWORK")
        if (type (v.icon) == "string") then
          it:SetTexture (v.icon)
        elseif (type (v.icon) == "function") then
          it:SetTexture (v.icon (tbf))
        else
          assert (false, "icon must be a string or a function")
        end
        it:SetWidth (16)
        it:SetHeight (16)
        it:ClearAllPoints ()
        tbf.p_icon = it
      end
      tbf.icon = tbf.p_icon
      tbf.icon:SetTexture (v.icon)
      if (v.iconcoord) then
        tbf.icon:SetTexCoord (v.iconcoord.left or 0, v.iconcoord.right or 1, v.iconcoord.top or 0, v.iconcoord.bottom or 1)
      else
        tbf.icon:SetTexCoord (0, 1, 0, 1)
      end
    else
      if (tbf.p_icon) then
        tbf.p_icon:Hide ()
      end
      tbf.icon = nil
    end

    local fontnm = "GameFontHighlightSmallLeft"
    if (tbf.title) then
      fontnm = "GameFontNormalSmallLeft"
    end
    tbf.font = fontnm
    if (v.font) then
      if (type (v.font) == "string") then
        tbf.font = v.font
      elseif (type (v.font) == "function") then
        tbf.font = v.font (tbf)
      else
        assert (false, "font must be a string or a function")
      end
    end

    -- See if this is the widest item yet
    if (txt) then
      w = ceil (KUI.MeasureStrWidth (txt, tbf.font) + 8)
    elseif (not tbf.spacer) then
      if (type (v.frame) == "table") then
        tbf.frame = v.frame
      elseif (type (v.frame) == "function") then
        tbf.frame = v.frame (tbf)
      elseif (v.frame == true) then
        tbf.frame = KUI.ItemWidget (tbf)
      else
        assert (false, "frame must be a table, a function or true")
      end
      tbf.frame:SetParent (cf)
      tbf.frame:SetFrameLevel (tbf:GetFrameLevel () + 1)

      w = tbf.width or floor (tbf.frame:GetWidth () + 0.5)
    end

    if (fr.itemheight) then
      h = fr.itemheight
    else
      assert (v.height, "item must specify height if global itemheight not set")
    end
    if (v.height) then
      h = v.height
    end
    if ((not w or w == 0) and v.width) then
      w = v.width
    end

    --
    -- In case one of the functions called forced a width and height, set it
    -- to any preset values now.
    --
    if (tbf.width) then
      w = tbf.width
    end
    if (tbf.height) then
      h = tbf.height
    end

    if (tbf.checkable) then
      hascheck = 16
      if (not tbf.p_checkmark) then
        local cm = tbf:CreateTexture (nil, "ARTWORK")
        cm:SetTexture ("Interface/Buttons/UI-CheckBox-Check")
        cm:SetWidth (16)
        cm:SetHeight (16)
        cm:ClearAllPoints ()
        cm:SetPoint ("LEFT", tbf, "LEFT", 0, 0)
        cm:Hide ()
        tbf.p_checkmark = cm
      end
      tbf.checkmark = tbf.p_checkmark
      if (not tbf.enabled) then
        SetDesaturation (tbf.checkmark, true)
      else
        SetDesaturation (tbf.checkmark, false)
      end
      tbf.checkmark:Hide ()
    else
      if (tbf.p_checkmark) then
        tbf.p_checkmark:Hide ()
      end
      tbf.checkmark = nil
      tbf.checked = false
    end

    if (w and w > widest) then
      widest = w
    end
    fr.iheight = fr.iheight + h

    -- Position the item frame within the scrolling child frame
    tbf:ClearAllPoints ()
    tbf.height = h
    tbf:SetPoint ("TOPLEFT", relframe, rtopleft, 0, 0)
    tbf:SetPoint ("BOTTOMRIGHT", relframe, rbotright, 0, -tbf.height)
    relframe = tbf
    rtopleft = "BOTTOMLEFT"
    rbotright = "BOTTOMRIGHT"

    -- If it was a text item create the string and set its value
    if (txt) then
      if (not tbf.p_text) then
        tbf.p_text = tbf:CreateFontString (nil, "OVERLAY", tbf.font)
      end
      local text = tbf.p_text
      text:SetFontObject (tbf.font)
      text:ClearAllPoints ()
      text:SetJustifyH (v.justifyh or "LEFT")
      text:SetJustifyV (v.justifyv or "MIDDLE")
      text:SetText (txt)
      check_tooltip_title (tbf, v, txt)
      if (tbf.color) then
        text:SetTextColor (tbf.color.r, tbf.color.g, tbf.color.b, tbf.color.a)
      else
        text:SetTextColor (KUI.GetFontColor (tbf.font))
      end
      tbf.text = text
    else
      if (tbf.p_text) then
        tbf.p_text:Hide ()
      end
      tbf.text = nil
    end

    --
    -- If the item isn't disabled in any way (not a title, not explicitly
    -- disabled), set the button highlight texture. Otherwise clear it in
    -- case we are reusing a frame from a previous call to create this
    -- menu.
    --
    if (not tbf.frame) then
      if ((not tbf.enabled) or (not tbf.clickable)) then
        tbf:SetHighlightTexture (nil)
      else
        tbf:SetHighlightTexture ("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
      end
    end

    if (tbf.text and (not tbf.enabled)) then
      local r, g, b, a = tbf.text:GetTextColor ()
      tbf.text:SetTextColor (r/2, g/2, b/2, a)
    end
  end -- Of loop through all of the items

  local wwidth = widest
  if (fr.width and fr.width > 0) then
    if (fr.width > widest) then
      widest = fr.width
    end
    wwidth = fr.width
  end

  local wheight = fr.height
  if (not wheight or wheight <= 0) then
    wheight = fr.iheight
    if (wheight > 300) then
      wheight = 300
    end
  end
  local iwheight = wheight

  -- See if we need a vertical scroll bar or not
  local hasvscroll = 0
  if (fr.iheight > wheight) then
    hasvscroll = 12
  end
  if (fr.maxheight and fr.iheight > fr.maxheight) then
    hasvscroll = 12
  end
  if (fr.minheight and fr.iheight > fr.minheight) then
    hasvscroll = 12
  end

  --
  -- Now adjust the width for possible submenu marks, scroll bars and for
  -- the checkmark. Then, size the frame and draw its borders, background
  -- etc.
  --
  local xtra = hasvscroll + hasicons + hassub + hascheck
  -- Add in the width/height of the border
  wheight = wheight + (fr.offset * 2) + fr.headeroffset + fr.footeroffset
  wwidth = wwidth + xtra + (fr.offset * 2)

  fr.hasvscroll = hasvscroll
  fr.hasicons = hasicons
  fr.hassub = hassub
  fr.hascheck = hascheck

  local maxwidth = widest + xtra + (fr.offset * 2)
  local maxheight = fr.iheight + (fr.offset * 2) + fr.headeroffset + fr.footeroffset

  fr:SetWidth (wwidth)
  fr:SetHeight (wheight)
  fr.widest = widest
  fr.extrawidth = xtra

  fr:SetMinResize (fr.minwidth or wwidth, fr.minheight or wheight)
  fr:SetMaxResize (fr.maxwidth or maxwidth, fr.maxheight or maxheight)

  --
  -- Now we need to loop through all of the item frames one last time and
  -- do the final positioning of all elements now that we know which
  -- extra elements will be displayed.
  --
  for k,v in ipairs (fr.iframes) do
    if (v.spacer) then
      v.spacer:ClearAllPoints ()
      local vpos = floor (v.height / 2) - 1
      v.spacer:SetPoint ("TOPLEFT", v, "TOPLEFT", 0, -vpos)
      v.spacer:SetPoint ("TOPRIGHT", v, "TOPRIGHT", fr.hassub * -1, -vpos)
      v.spacer:SetHeight (1)
      v.spacer:Show ()
    elseif (v.text) then
      v.text:ClearAllPoints ()
      v.text:SetPoint ("TOPLEFT", v, "TOPLEFT", fr.hascheck + fr.hasicons, 0)
      v.text:SetPoint ("BOTTOMRIGHT", v, "BOTTOMRIGHT", fr.hassub * -1, 0)
      v.text:Show ()
    elseif (v.frame) then
      v.frame:Show ()
    end

    if (v.icon) then
      v.icon:SetPoint ("LEFT", v, "LEFT", fr.hascheck, 0)
      v.icon:Show ()
    end

    if (v.checked and v.checkmark) then
      --
      -- We can't just blindly show the check mark. If this is a SINGLE or
      -- COMPACT dropdown menu, only 1 item at a time can ever be checked.
      -- So, we look to see if we already have an entry checked, and if so,
      -- we uncheck it and mark this one as the current checked value.
      --
      if (v.toplevel.mode) then
        if (v.toplevel.mode < 3) then
          if (v.toplevel.current) then
            v.toplevel.current.checked = false
            if (v.toplevel.current.checkmark) then
              v.toplevel.current.checkmark:Hide ()
            end
          end
          v.toplevel.current = v
        end
        v.checkmark:Show ()
      else
        v.checkmark:Show ()
      end
    elseif (v.checked and v.clickable) then
      if (v.toplevel.mode < 3) then
        if (v.toplevel.current) then
          v.toplevel.current.checked = false
          if (v.toplevel.current.checkmark) then
            v.toplevel.current.checkmark:Hide ()
          end
        end
        v.toplevel.current = v
      end
    end

    if (v.subarrow) then
      v.subarrow:Show ()
    end

    run_funcs (v, true)
  end

  --
  -- And last but not least, position the scrollbar and scroll frame
  -- within the main frame.
  --
  fr.sframe:SetPoint ("TOPLEFT", fr, "TOPLEFT", fr.offset + fr.hasvscroll, -(fr.offset + fr.headeroffset))
  fr.sframe:SetPoint ("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -fr.offset, fr.offset + fr.footeroffset)
  cf:SetHeight (fr.iheight)
  cf:SetWidth (fr.widest + fr.extrawidth - fr.hasvscroll)
  fr.sframe:UpdateScrollChildRect ()
  if (fr.hasvscroll > 0) then
    fr.scrollbar:Show ()
    fr.scrollbar:SetValue (0)
    local mxs = fr.minheight
    if (not fr.minheight) then
      mxs = iwheight
    end
    fr.scrollbar:SetMinMaxValues (0, fr.iheight - mxs)
  else
    fr.scrollbar:Hide ()
  end

  --
  -- Check to see if the window is currently larger than the min/maximum. This
  -- can happen when items are refreshed and the maximum size changes.
  --
  local mxwidth, mxheight = fr:GetMaxResize ()
  local mnwidth, mnheight = fr:GetMinResize ()
  local cw, ch = fr:GetWidth (), fr:GetHeight ()
  local sbx, sby = fr.scrollbar:GetMinMaxValues ()
  if (cw < mnwidth) then
    fr:SetWidth (mnwidth)
    cw = mnwidth
  end
  if (ch < mnheight) then
    fr:SetHeight (mnheight)
    ch = mnheight
  end
  --
  -- By ordering things this way we catch the case where the maximum is
  -- actually less than the minimum.
  --
  if (cw > mxwidth) then
    fr:SetWidth (mxwidth)
  end
  if (ch > mxheight) then
    fr:SetHeight (mxheight)
  end
end

--
-- Only the top-level frame gets this function
--

local function dd_UpdateItems (this, newitems)
  assert (newitems, "dropdown items must be provided")
  local ic = 0
  for k,v in pairs(newitems) do
    ic = ic + 1
    assert (v.text or v.frame, "must provide text or a custom frame")
  end

  if (this.subopen) then
    this.subopen:Close ()
    this.subopen = nil
  end
  if (this.dropdown) then
    local oldv
    if (this.current) then
      oldv = this.current.value
      if (this.current.checkmark) then
        this.current.checkmark:Hide ()
      end
      this.current.checked = false
      this.current = nil
    end
    this.dropdown:Close ()
    dd_refresh_frame (this.dropdown, this.toplevel, newitems, ic)
    if (this.text) then
      if (this.mode == 3 and this.titletext) then
        this.text:SetText (this.titletext)
      else
        this.text:SetText ("")
      end
    end
    if (oldv) then
      this:SetValue (oldv, true)
    end
  else
    this.current = nil
    dd_refresh_frame (this, this.toplevel, newitems, ic)
  end
end

local function dd_SetText (this, text)
  if (not this.dropdown or not this.text) then
    return
  end
  this.text:SetText (text)
end

local function dd_GetValue (this)
  local tl = this.toplevel
  if (not tl.current) then
    return nil
  end
  return tl.current.value
end

local function dd_SetValue (this, value, nothrow)
  local tl = this.toplevel
  if (tl.current and tl.current.value == value) then
    return true
  end

  local function recursive_set (tlf, frs, val)
    for k,v in ipairs (frs.iframes) do
      if (v.value == val and v.clickable) then
        if (tlf.current) then
          tlf.current.checked = false
          if (tlf.current.checkmark) then
            tlf.current.checkmark:Hide ()
          end
          tlf.current = nil
        end
        tlf.current = v
        v.checked = true
        if (v.checkmark) then
          v.checkmark:Show ()
        end
        return true
      end
      if (v.menuframe) then
        local done = recursive_set (tlf, v.menuframe, val)
        if (done) then
          return true
        end
      end
    end
    return false
  end

  local ret = recursive_set (tl, this.dropdown, value)
  if (tl.current and tl.current.text) then
    local tt = tl.current.text
    local r,g,b,a = tt:GetTextColor ()
    local d = this.enabled and 1 or 2
    this.text:SetText (tt:GetText ())
    this.text:SetTextColor (r/d,g/d, b/d, a)
  elseif (tl.current and tl.current.frame) then
    this.text:SetText ("")
  elseif (not tl.current) then
    this.text:SetText ("")
  end

  if (ret) then
    if (not nothrow) then
      tl:Throw ("OnValueChanged", value, false)
    end
  end
  return ret
end

local function dd_OnEnable (this, event, onoff)
  local onoff = onoff or false

  this.enabled = onoff

  local button = this.button

  if (onoff) then
    button:Enable ()
  else
    button:Disable ()
    if (this.dropdown) then
      this.dropdown:Close ()
    else
      if (this.subopen) then
        this.subopen:Close ()
        this.subopen = nil
      end
    end
  end
  local d = onoff and 1 or 2
  if (this.label) then
    this.label:SetTextColor (this.labelcolor.r/d, this.labelcolor.g/d, this.labelcolor.b/d, this.labelcolor.a)
  end
  if (this.dropdown) then
    if (this.mode == 3) then
      if (this.trgb) then
        this.text:SetTextColor (this.trgb.r/d, this.trgb.g/d, this.trgb.b/d, this.trgb.a)
      end
    else
      if (this.current and this.current.text) then
        local tt = this.current.text
        local r,g,b,a = tt:GetTextColor ()
        this.text:SetTextColor (r/d,g/d, b/d, a)
      end
    end
  end
end

--
-- This is the workhorse function that creates the functional part of a
-- dropdown menu or a popup menu. This is the bit that contains the actual
-- items. It can call itself recursively if any of the items have submenus.
-- If this is the top-level menu, it is what is returned to the caller and
-- has two functions which each child must call when the cursor is over
-- the child: StopTimeoutCounter() when the cursor moves into a child frame
-- and StartTimeoutCounter() when it leaves.
--

create_dd_sa = function (cfg, parent, toplevel, ispopup)
  assert (cfg, "dropdown config must be provided")
  assert (cfg.name, "you must provide a frame name")
  assert (cfg.items, "dropdown items must be provided ("..cfg.name..")")
  if (toplevel) then
    assert (toplevel.StopTimeoutCounter, "toplevel specified incorrectly")
    assert (toplevel.StartTimeoutCounter, "toplevel specified incorrectly")
  end

  local nitems = 0
  for k,v in ipairs(cfg.items) do
    nitems = nitems + 1
    assert (v.text or v.frame, "must provide text or a custom frame")
  end
  assert (nitems > 0, "must provide at least 1 item")

  local frame
  if (not toplevel and not ispopup) then
    assert (cfg.dwidth, "must provide dropdown width (dwidth)")
    --
    -- This is a "dropdown" style frame. This has a controlling UI element
    -- that does not change, and then the actual dropped down portion which
    -- might. This is where we create the controlling UI element which will
    -- "house" the countdown timers and other events. The actual dropped
    -- down portion that will be displayed when the downarrow button is
    -- pressed is created by a recursive call to this function below.
    --
    local tn = "Interface/Glues/CharacterCreate/CharacterCreate-LabelFrame"
    local ppf
    frame, ppf = newobj (cfg, parent, 100, 32, cfg.name .. "DDContainer")
    frame:SetWidth (cfg.dwidth)
    frame:SetHeight (32)

    local lt = frame:CreateTexture (frame:GetName() .. "Left", "ARTWORK")
    lt:SetTexture (tn)
    lt:SetTexCoord (0.125, 0.2109375, 0.25, 0.75)
    lt:SetWidth (12)
    lt:SetHeight (32)
    lt:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local rt = frame:CreateTexture (frame:GetName() .. "Right", "ARTWORK")
    rt:SetTexture (tn)
    rt:SetTexCoord (0.78128, 0.875, 0.25, 0.75)
    rt:SetWidth (12)
    rt:SetHeight (32)
    rt:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local mt = frame:CreateTexture (frame:GetName() .. "Middle", "ARTWORK")
    mt:SetTexture (tn)
    mt:SetTexCoord (0.2109375, 0.78128, 0.25, 0.75)
    mt:SetWidth (78)
    mt:SetHeight (32)
    mt:SetPoint ("LEFT", lt, "RIGHT", 0, 0)
    mt:SetPoint ("RIGHT", rt, "LEFT", 0, 0)

    local text = frame:CreateFontString (frame:GetName() .. "Text", "ARTWORK")
    frame.text = text
    text:SetFontObject ("GameFontHighlightSmall")
    text:ClearAllPoints ()
    text:SetPoint ("TOPLEFT", frame, "TOPLEFT", 12, -6)
    text:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 8)

    local button = MakeFrame ("Button", frame:GetName() .. "Button", frame)
    frame.button = button
    button.toplevel = frame
    button:SetWidth (24)
    button:SetHeight (24)
    button:ClearAllPoints ()
    button:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 0, -3)

    local bnt = button:CreateTexture (button:GetName() .. "NormalTexture")
    bnt:SetTexture ("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Up")
    bnt:SetWidth (24)
    bnt:SetHeight (24)
    bnt:ClearAllPoints ()
    bnt:SetPoint ("RIGHT", button)

    local bpt = button:CreateTexture (button:GetName() .. "PushedTexture")
    bpt:SetTexture ("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Down")
    bpt:SetWidth (24)
    bpt:SetHeight (24)
    bpt:ClearAllPoints ()
    bpt:SetPoint ("RIGHT", button)

    local bdt = button:CreateTexture (button:GetName() .. "DisabledTexture")
    bdt:SetTexture ("Interface/ChatFrame/UI-ChatIcon-ScrollDown-Disabled")
    bdt:SetWidth (24)
    bdt:SetHeight (24)
    bdt:ClearAllPoints ()
    bdt:SetPoint ("RIGHT", button)

    local bht = button:CreateTexture (button:GetName() .. "HighlightTexture")
    bht:SetTexture ("Interface/Buttons/UI-Common-MouseHilight")
    bht:SetWidth (24)
    bht:SetHeight (24)
    bht:ClearAllPoints ()
    bht:SetPoint ("RIGHT", button)
    bht:SetBlendMode ("ADD")

    button:SetNormalTexture (bnt)
    button:SetPushedTexture (bpt)
    button:SetDisabledTexture (bdt)
    button:SetHighlightTexture (bht)

    frame.OnEnable = dd_OnEnable
    frame.SetJustification = dd_SetJustification
    frame.UpdateItems = dd_UpdateItems
    frame.GetValue = dd_GetValue
    frame.SetValue = dd_SetValue

    button:SetScript ("OnEnter", dd_OnEnter)
    button:SetScript ("OnLeave", dd_OnLeave)
    button:SetScript ("OnClick", dd_OnClick)

    frame:SetJustification (cfg.justifyh or "LEFT")

    --
    -- Dropdowns can also have a label. Deal with that now.
    --
    if (cfg.label) then
      local lfont = cfg.label.font or "GameFontNormal"
      local lwidth = KUI.MeasureStrWidth (cfg.label.text, lfont) + 4
      local label = frame:CreateFontString(nil, "ARTWORK", lfont)
      frame.label = label
      frame.labelcolor = KUI.GetFontColor (lfont, true)
      if (cfg.label.color) then
        frame.labelcolor.r = cfg.label.color.r
        frame.labelcolor.g = cfg.label.color.g
        frame.labelcolor.b = cfg.label.color.b
        frame.labelcolor.a = cfg.label.color.a or 1
      end
      label:SetHeight (16)
      label:SetWidth (lwidth)
      label:SetJustifyH (cfg.label.justifyh or "LEFT")
      label:SetJustifyV (cfg.label.justifyv or "MIDDLE")
      label:SetText (cfg.label.text or "")
      check_tooltip_title (frame, cfg, cfg.label.text)

      if (cfg.label.pos == "LEFT") then
        label:SetPoint ("TOPRIGHT", frame, "TOPLEFT", -4, -6)
        if (cfg.x) then
          if (cfg.x == "CENTER") then
            frame:SetPoint ("CENTER", ppf, "CENTER", (lwidth/2)*-1, 0)
          else
            frame:SetPoint ("LEFT", ppf, "LEFT", cfg.x + lwidth + 4, 0)
          end
        end
      elseif (cfg.label.pos == "RIGHT") then
        label:SetPoint ("TOPLEFT", frame, "TOPRIGHT", 4, -6)
        if (cfg.x and cfg.x == "CENTER") then
          frame:SetPoint ("CENTER", ppf, "CENTER", (lwidth/2)*-1, 0)
        end
      elseif (cfg.label.pos == "BOTTOM") then
        label:SetPoint ("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
      else -- Assume TOP
        label:SetPoint ("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
        if (cfg.y) then
          if (cfg.y == "MIDDLE") then
            frame:SetPoint ("MIDDLE", ppf, "MIDDLE", 0, -8)
          else
            frame:SetPoint ("TOP", ppf, "TOP", 0, cfg.y - 16)
          end
        end
      end
    end
  else
    if (not toplevel) then
      frame = newobj (cfg, parent, 100, 100, cfg.name)
    else
      if (KUI.ddframes[cfg.name]) then
        frame = KUI.ddframes[cfg.name]
        frame:SetParent (parent or UIParent)
      else
        frame = MakeFrame ("Frame", cfg.name, parent or UIParent,"BackdropTemplate")
        frame.SetEnabled = BC.SetEnabled
        frame.SetShown = BC.SetShown
        KUI.ddframes[cfg.name] = frame
      end
    end
  end
  frame:Show ()

  if (frame.subopen) then
    frame.subopen:Close ()
    frame.subopen = nil
  end

  frame.toplevel = toplevel or frame
  frame.height = cfg.height
  frame.width = cfg.width

  if (toplevel) then
    frame.border = toplevel.border
    frame.mode = toplevel.mode
  else
    frame:SetFrameLevel (frame:GetFrameLevel () + 8 + (ispopup and 8 or 0))
    if (frame.SetTopLevel) then
      frame:SetTopLevel (true)
    end
    if (cfg.escclose or not ispopup) then
      add_escclose (cfg.name)
    else
      remove_escclose (cfg.name)
    end

    frame.timeout = cfg.timeout or 3
    if (cfg.border == "THIN") then
      frame.border = 1
    elseif (cfg.border == "THICK") then
      frame.border = 2
    else
      if (ispopup) then
        frame.border = 1
      else
        frame.border = 2
      end
    end
    frame.lastpos = {}
    if (ispopup) then
      frame.mode = nil
      frame.SetEnabled = nil
      frame.OnStopMoving = function (this, evt)
        this.lastpos = {}
      end
    else
      if (cfg.mode == "MULTI") then
        frame.mode = 3
      elseif (cfg.mode == "COMPACT") then
        frame.mode = 2
      elseif (cfg.mode == "SINGLE") then
        frame.mode = 1
      else
        frame.mode = 1
      end
    end
  end

  frame.arg = cfg.arg
  frame.func = cfg.func
  frame.itemheight = cfg.itemheight or frame.toplevel.itemheight
  frame.items = cfg.items
  frame.minheight = cfg.minheight or frame.toplevel.minheight
  frame.minwidth = cfg.minwidth or frame.toplevel.minwidth
  frame.maxheight = cfg.maxheight or frame.toplevel.maxheight
  frame.maxwidth = cfg.maxwidth or frame.toplevel.maxwidth

  if (not toplevel) then
    frame.StopTimeoutCounter = stop_countdown
    frame.StartTimeoutCounter = start_countdown
    frame:UnregisterAllEvents ()
    if (ispopup) then
      frame:SetFrameStrata (cfg.strata or "FULLSCREEN_DIALOG")
      frame:RegisterEvent ("PLAYER_REGEN_ENABLED")
      frame:RegisterEvent ("PLAYER_REGEN_DISABLED")
      frame:HookScript ("OnEvent", tl_OnEvent)
    end
    frame:HookScript ("OnShow", tl_OnShow)
    frame:HookScript ("OnHide", tl_OnHide)
  else
    frame.StopTimeoutCounter = nil
    frame.StartTimeoutCounter = nil
    frame:SetFrameStrata (toplevel:GetFrameStrata ())
  end

  frame.Close = dd_Close
  frame:EnableMouse (true)
  frame:HookScript ("OnEnter", tl_OnEnter)
  frame:HookScript ("OnLeave", tl_OnLeave)

  if (not toplevel and not ispopup) then
    --
    -- DropDown menu. Create the actual portion that is dropped down when
    -- the button is pressed. Simply create the dropdown frame and return
    -- the container.
    --
    frame.dropdown = create_dd_sa (cfg, frame, frame, false)
    frame.dropdown:SetFrameLevel (frame.dropdown:GetFrameLevel() + 4)
    frame.dropdown:ClearAllPoints ()
    frame.dropdown:SetPoint ("TOPLEFT", frame, "BOTTOMLEFT", -10, 6)
    if (frame.mode == 3) then
      if (cfg.title) then
        local tfont = cfg.title.font or "GameFontNormalSmallLeft"
        frame.text:SetFontObject (tfont)
        frame.text:SetText (cfg.title.text)
        frame.titletext = cfg.title.text
        frame.trgb = KUI.GetFontColor (tfont, true)
        if (cfg.title.color) then
          frame.trgb.r = cfg.title.color.r
          frame.trgb.g = cfg.title.color.g
          frame.trgb.b = cfg.title.color.b
          frame.trgb.a = cfg.title.color.a or 1
        end
        check_tooltip_title (frame, cfg, cfg.title.text)
      else
        if (frame.dropdown.iframes[1].title) then
          local tfont = frame.dropdown.iframes[1].font
          frame.text:SetFontObject (tfont)
          frame.text:SetText (frame.dropdown.iframes[1].text:GetText ())
          check_tooltip_title (frame, cfg, frame.text:GetText ())
          frame.trgb = KUI.GetFontColor (tfont, true)
        else
          frame.trgb = KUI.GetFontColor ("GameFontNormalSmallLeft", true)
        end
      end
    else
      if (frame.current) then
        if (frame.current.text) then
          frame.text:SetText (frame.current.text:GetText ())
        else
          frame.text:Settext ("")
        end
      end
    end
    if (cfg.initialvalue ~= nil) then
      frame:SetValue (cfg.initialvalue)
    end
    frame:SetEnabled (cfg.enabled)
    return frame
  end

  frame.offset = borders[frame.border].offset
  frame:SetBackdrop ( { bgFile = borders[frame.border].bgFile,
    edgeFile = borders[frame.border].edgeFile,
    tile = true,
    tileSize = borders[frame.border].tileSize,
    edgeSize = borders[frame.border].edgeSize,
    insets = borders[frame.border].insets, })
  frame:SetBackdropColor (0, 0, 0, 1)

  --
  -- Now we create the scrollframe and fit it just inside the borders of
  -- the container frame. If this is a popup menu we allow the user to reserve
  -- space at the top and bottom of the frame for a header and a footer.
  --
  local sframe = frame.sframe
  local cframe = frame.cframe
  local hframe = frame.header
  local fframe = frame.footer
  if (not frame.sframe) then
    sframe = MakeFrame ("ScrollFrame", nil, frame,"BackdropTemplate")
    frame.sframe = sframe
    sframe.toplevel = frame.toplevel
    sframe:HookScript ("OnEnter", tl_OnEnter)
    sframe:HookScript ("OnLeave", tl_OnLeave)
    local bdrop = {
      bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
      tile = true,
      tileSize = 32,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
    sframe:SetBackdrop (bdrop)
  end

  if (not frame.cframe) then
    cframe = MakeFrame ("Frame", frame:GetName() .. "Child", sframe)
    frame.cframe = cframe
    cframe.toplevel = frame.toplevel
    cframe:HookScript ("OnEnter", tl_OnEnter)
    cframe:HookScript ("OnLeave", tl_OnLeave)
  end

  frame.headeroffset = 0
  frame.footeroffset = 0
  if (ispopup) then
    if (cfg.header) then
      frame.headeroffset = cfg.header
      if (not frame.header) then
        hframe = MakeFrame ("Frame", frame:GetName() .. "Header", frame)
        frame.header = hframe
        hframe.toplevel = frame.toplevel
        hframe:HookScript ("OnEnter", tl_OnEnter)
        hframe:HookScript ("OnLeave", tl_OnLeave)
      end
      hframe:ClearAllPoints ()
      hframe:SetPoint ("TOPLEFT", frame, "TOPLEFT", frame.offset, -frame.offset)
      hframe:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", -frame.offset, -frame.offset)
      hframe:SetHeight (cfg.header)
    end
    if (cfg.footer) then
      frame.footeroffset = cfg.footer
      if (not frame.footer) then
        fframe = MakeFrame ("Frame", frame:GetName() .. "Footer", frame)
        frame.footer = fframe
        fframe.toplevel = frame.toplevel
        fframe:HookScript ("OnEnter", tl_OnEnter)
        fframe:HookScript ("OnLeave", tl_OnLeave)
      end
      fframe:ClearAllPoints ()
      fframe:SetPoint ("BOTTOMLEFT", frame, "BOTTOMLEFT", frame.offset, frame.offset)
      fframe:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -frame.offset, frame.offset)
      fframe:SetHeight (cfg.footer)
    end
  end

  sframe:SetScrollChild (cframe)
  sframe:ClearAllPoints ()
  sframe:SetPoint ("TOPLEFT", frame, "TOPLEFT", frame.offset, -(frame.offset + frame.headeroffset))
  sframe:SetPoint ("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -frame.offset, frame.offset + frame.footeroffset)
  sframe:EnableMouse (true)
  sframe:EnableMouseWheel (true)
  cframe:EnableMouse (true)

  local sbar = frame.scrollbar
  if (not frame.scrollbar) then
    sbar = MakeFrame ("Slider", nil, frame)
    frame.scrollbar = sbar
  end
  sbar:SetOrientation ("VERTICAL")
  sbar:ClearAllPoints ()
  sbar:SetPoint ("TOPLEFT", sframe, "TOPLEFT", -12, 0)
  sbar:SetPoint ("BOTTOMRIGHT", sframe, "BOTTOMLEFT", -4, 0)
  sbar:EnableMouse (true)
  sbar:EnableMouseWheel (true)
  sbar:SetThumbTexture ("Interface\\Buttons\\UI-ScrollBar-Knob")

  local sbt = sbar:GetThumbTexture ()
  sbt:SetTexCoord (0.15625, 0.78128, 0.1875, 0.75)
  sbt:SetWidth (8)
  sbt:SetHeight (16)
  sbar:Hide ()

  sbar:HookScript ("OnMouseWheel", dd_OnMouseWheel)
  sbar:HookScript ("OnValueChanged", dd_OnValueChanged)
  sbar:HookScript ("OnEnter", parent_OnEnter)
  sbar:HookScript ("OnLeave", parent_OnLeave)

  sframe:HookScript ("OnMouseWheel", dd_OnMouseWheel)
  sframe:HookScript ("OnScrollRangeChanged", dd_OnScrollRangeChanged)

  if (not toplevel and cfg.canmove and ispopup) then
    --
    -- If we want a moveable frame, we can only do so by click-dragging on the
    -- very top of the frame, along its border. We want to set up a target
    -- zone for registering those clicks which means we need to create yet
    -- another frame.
    --
    frame:SetMovable (true)
    local mframe = frame.mframe
    if (not frame.mframe) then
      mframe = MakeFrame ("Frame", nil, frame)
      frame.mframe = mframe
    end
    mframe:ClearAllPoints ()
    mframe:SetPoint ("TOPLEFT", frame, "TOPLEFT", 0, 0)
    mframe:SetPoint ("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    mframe:SetHeight (frame.offset)
    mframe:EnableMouse (true)
    mframe:SetScript ("OnMouseDown", parent_StartMoving)
    mframe:SetScript ("OnMouseUp", parent_StopMoving)
    mframe:SetScript ("OnEnter", parent_OnEnter)
    mframe:SetScript ("OnLeave", parent_OnLeave)
    mframe:Show ()
  else
    frame:SetMovable (false)
    if (frame.mframe) then
      frame.mframe:ClearAllPoints ()
      frame.mframe:Hide ()
    end
  end

  local swframe, seframe, soframe = make_resizeable (frame, frame.offset + 10,
    cfg.canresize, frame.swframe, frame.seframe, frame.soframe)

  if (swframe) then
    frame.swframe = swframe
    swframe:SetScript ("OnEnter", parent_OnEnter)
    swframe:SetScript ("OnLeave", parent_OnLeave)
  end

  if (seframe) then
    frame.seframe = seframe
    seframe:SetScript ("OnEnter", parent_OnEnter)
    seframe:SetScript ("OnLeave", parent_OnLeave)
  end

  if (soframe) then
    frame.soframe = soframe
    soframe:SetScript ("OnEnter", parent_OnEnter)
    soframe:SetScript ("OnLeave", parent_OnLeave)
  end

  if (not frame:IsResizable ()) then
    frame:SetScript ("OnSizeChanged", nil)
    if (frame.seframe) then
      frame.seframe:Hide ()
      frame.seframe:ClearAllPoints ()
    end
    if (frame.swframe) then
      frame.swframe:Hide ()
      frame.swframe:ClearAllPoints ()
    end
    if (frame.soframe) then
      frame.soframe:Hide ()
      frame.soframe:ClearAllPoints ()
    end
  end

  --
  -- kframes is used to store the names of the various child frames we have
  -- created. Since every line element in a menu is actually a frame, and
  -- we can change the appearance or values of each of those frames at any
  -- time, we do not want to create more frames than we need, so we keep
  -- track of the child frames we create. Note that this table tracks only
  -- the item entry frames, it does not store the frame pointers for
  -- submenu frames (see below for those).
  --
  frame.kframes = {}

  dd_refresh_frame (frame, toplevel, cfg.items, nitems)
  frame:Hide ()

  if (toplevel) then
    return frame
  end

  frame.UpdateItems = dd_UpdateItems
  return frame
end

function KUI:CreateDropDown (cfg, parent)
  return create_dd_sa (cfg, parent, nil, false)
end

function KUI:CreatePopupMenu (cfg, parent)
  return create_dd_sa (cfg, parent, nil, true)
end

--
-- Helper function for creating custom frames as popup item widgets.
--
local function get_radiowidget (this)
  return this.frame or this
end

function KUI.ItemWidget (tbf)
  local ti = tbf.iinfo
  local cfg = {}
  local ret

  cfg.checked = tbf.checked
  cfg.enabled = tbf.enabled
  cfg.x = ti.x or 0
  cfg.y = ti.y or 0
  cfg.width = ti.width
  cfg.height = ti.height
  cfg.initialvalue = ti.initialvalue
  if (ti.label) then
    cfg.label = { text = ti.label, color = tbf.color, font = tbf.font }
  end

  if (ti.widget == "radio") then
    assert (ti.group, "must provide group name for radio items")
    cfg.group = ti.group
    cfg.value = ti.value
    cfg.groupparent = tbf.rparent
    cfg.getbutton = get_radiowidget
    tbf.checkable = false
    cfg.checked = tbf.checked
    ret = KUI:CreateRadioButton (cfg, tbf)
  elseif (ti.widget == "slider") then
    local dw, dh, xw, xh
    cfg.orientation = ti.orientation or "VERTICAL"
    if (cfg.orientation == "VERTICAL") then
      dw = 16
      dh = 100
      xw = 50
      xh = 0
    else
      dw = 100
      dh = 16
      xw = 0
      xh = 16
    end
    cfg.editfont = ti.editfont
    cfg.editcolor = ti.editcolor or {r = 1, g = 1, b = 0 }
    cfg.minmaxfont = ti.minmaxfont
    cfg.minmaxcolor = ti.minmaxcolor or {r = 0, g = 1, b = 0 }
    cfg.minval = ti.minval
    cfg.maxval = ti.maxval
    cfg.step = ti.step
    cfg.width = ti.width or dw
    cfg.height = ti.height or dh
    tbf.height = cfg.height + xh
    tbf.width = cfg.width + xw
    tbf.checkable = false
    ret = KUI:CreateSlider (cfg, tbf)
    ret.editbox.toplevel = tbf.toplevel
    ret.editbox:HookScript ("OnEnter", tl_OnEnter)
    ret.editbox:HookScript ("OnLeave", tl_OnLeave)
  elseif (ti.widget == "editbox") then
    cfg.len = ti.len
    cfg.numeric = ti.numeric
    cfg.font = ti.font and tbf.font or nil
    cfg.color = tbf.color
    cfg.label = nil
    cfg.width = ti.width or 100
    cfg.height = ti.height or 24
    tbf.height = cfg.height
    tbf.width = cfg.width
    tbf.checkable = false
    ret = KUI:CreateEditBox (cfg, tbf)
    ret:SetTextInsets (0, 0, 5, 1)
  elseif (ti.widget == "button") then
    cfg.text = ti.label
    cfg.width = ti.width or 100
    cfg.height = ti.height or 24
    cfg.template = ti.template
    tbf.height = cfg.height
    tbf.width = cfg.width
    tbf.checkable = false
    ret = KUI:CreateButton (cfg, tbf)
  else
    assert (false, "unknown or missing widget type")
  end

  ret.toplevel = tbf.toplevel
  ret.parent = tbf.parent
  ret:HookScript ("OnEnter", tl_OnEnter)
  ret:HookScript ("OnLeave", tl_OnLeave)
  return ret
end

--
-- This is a mixture of a popup menu and a scroll list, but wrapped in a dialog
-- frame. It is meant for popping up long lists of names. It uses the more
-- space efficient ScrollList rather than using a popup menu which is unsuited
-- to arbitrarily long lists of names.
--
local function ksl_settext (self, txt)
  self.text:SetText (txt)
end

local function ksl_onclick (this)
  local idx = this:GetID()
  local tlf = this.toplevel

  tlf.slist:SetSelected (idx, false)
  if (tlf.func) then
    tlf.func (tlf.selectionlist, idx, tlf.arg)
  end
  tlf:Hide ()
end

local function ksl_onshow (this)
  this.toplevel:StartTimeoutCounter ()
end

local function ksl_onhide (this)
  this.toplevel:StopTimeoutCounter ()
end

local ksl_onenter = ksl_onhide
local ksl_onleave = ksl_onshow

local function ksl_newitem (objp, num)
  local nm = objp:GetName() .. "Button"
  local tlf = objp.toplevel
  local rf = KUI.NewItemHelper (objp, num, nm, tlf.itemwidth, tlf.itemheight, ksl_settext, ksl_onclick, nil, nil)
  rf.toplevel = tlf
  rf:HookScript ("OnEnter", ksl_onenter)
  rf:HookScript ("OnLeave", ksl_onleave)
  return rf
end

local function ksl_setitem (objp, idx, slot, btn)
  local tlf = objp.toplevel

  if (tlf.textfunc) then
    btn:SetText (tlf.textfunc (tlf.selectionlist, idx, tlf.arg))
  else
    local tbl = tlf.selectionlist
    if (type (tbl[idx]) == "string") then
      btn:SetText (tbl[idx])
    elseif (type (tbl[idx]) == "table") then
      btn:SetText (tbl[idx].text)
    else
      assert (false)
    end
  end
end

local function ksl_selectitem (objp, idx, slot, btn, onoff)
end

local function ksl_highlightitem (objp, idx, slot, btn, onoff)
  return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff, nil, nil)
end

local function ksl_onupdate (this)
  local now = GetTime ()
  if ((now - this.timeout_start) > this.timeout) then
    this:SetScript ("OnUpdate", nil)
    this.timeout_start = 0
    this:Hide ()
  end
end

local function ksl_startcountdown (this)
  this.timeout_start = GetTime ()
  this:SetScript ("OnUpdate", ksl_onupdate)
end

local function ksl_stopcountdown (this)
  this:SetScript ("OnUpdate", nil)
end

local function ksl_updatelist (this, nlist)
  this.selectionlist = nlist
  local x
  if (not nlist) then
    x = 0
  else
   x = #nlist
  end
  local ga = this.headerspace + this.footerspace + (2 * this.borderoffset)
  local mh = ((x + 1) * this.itemheight) + ga
  local h = min(mh, this.uheight)
  local mnw, _ = this:GetMinResize ()
  local mxw, _ = this:GetMaxResize ()
  this.height = h
  this:SetMinResize (mnw, (2 * this.itemheight) + ga + 48)
  this:SetMaxResize (mxw, mh)
  this:SetHeight (h)
  this.slist.itemcount = x
  this.slist:UpdateList ()
end

local function ksl_hook (fr)
  fr:HookScript ("OnShow", ksl_onshow)
  fr:HookScript ("OnHide", ksl_onhide)
  fr:HookScript ("OnEnter", ksl_onenter)
  fr:HookScript ("OnLeave", ksl_onleave)
end

function KUI:CreatePopupList (cfg, parent)
  assert (cfg.name)

  local arg = {
    x = cfg.x,
    y = cfg.y,
    name = cfg.name,
    border = cfg.border,
    width = cfg.width,
    height = cfg.height,
    title = cfg.title,
    titlewidth = cfg.titlewidth,
    minwidth = cfg.minwidth,
    maxwidth = cfg.maxwidth,
    minheight = cfg.minheight,
    maxheight = cfg.maxheight,
    titleheight = cfg.titleheight,
    canmove = cfg.canmove,
    canresize = cfg.canresize,
    escclose = cfg.escclose,
    blackbg = cfg.blackbg,
    xbutton = cfg.xbutton,
    level = cfg.level or 24,
  }
  local ret = KUI:CreateDialogFrame (arg, cfg.parent or parent)
  ret.toplevel = ret
  ret.content.toplevel = ret
  local c = ret.content
  local tlf = c
  local brf = c
  local tlp = "TOPLEFT"
  local brp = "BOTTOMRIGHT"

  ksl_hook (ret)
  ksl_hook (ret.content)
  if (ret.title) then
    ret.title.toplevel = ret
    ksl_hook (ret.title)
  end
  if (ret.mframe) then
    ret.mframe.toplevel = ret
    ksl_hook (ret.mframe)
  end

  ret.headerspace = 0
  ret.footerspace = 0
  if (cfg.header) then
    ret.headerspace = cfg.header
    ret.header = MakeFrame ("Frame", nil, c)
    ret.header.toplevel = ret
    ret.header:ClearAllPoints ()
    ret.header:SetPoint ("TOPLEFT", c, "TOPLEFT", 0, 0)
    ret.header:SetPoint ("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    ret.header:SetHeight (cfg.header)
    tlf = ret.header
    tlp = "BOTTOMLEFT"
    ksl_hook (ret.header)
  end

  if (cfg.footer) then
    ret.footerspace = cfg.footer
    ret.footer = MakeFrame ("Frame", nil, c)
    ret.footer.toplevel = ret
    ret.footer:ClearAllPoints ()
    ret.footer:SetPoint ("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    ret.footer:SetPoint ("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    ret.footer:SetHeight (cfg.footer)
    brf = ret.footer
    brp = "TOPRIGHT"
    ksl_hook (ret.footer)
  end

  if (ret.header or ret.footer) then
    ret.cframe = MakeFrame ("Frame", nil, c)
    ret.cframe:ClearAllPoints ()
    ret.cframe:SetPoint ("TOPLEFT", tlf, tlp, 0, 0)
    ret.cframe:SetPoint ("BOTTOMRIGHT", brf, brp, 0, 0)
  else
    ret.cframe = ret.content
  end

  ret.arg = cfg.arg
  ret.textfunc = cfg.textfunc
  ret.func = cfg.func
  ret.timeout = cfg.timeout or 3
  ret.itemheight = cfg.itemheight or 16
  ret.itemwidth = cfg.itemwidth or 160
  ret.uheight = cfg.height

  arg = {
    name = cfg.name .. "ScrollList",
    itemheight = ret.itemheight,
    newitem = ksl_newitem,
    setitem = ksl_setitem,
    selectitem = ksl_selectitem,
    highlightitem = ksl_highlightitem,
    __noh__ = ret,
    newobjhook = function (fr,cf,pr,wd,ht)
      fr.toplevel = cf.__noh__
    end,
  }
  ret.StopTimeoutCounter = ksl_stopcountdown
  ret.StartTimeoutCounter = ksl_startcountdown
  ret.cframe.toplevel = ret
  ret.slist = KUI:CreateScrollList (arg, ret.cframe)
  ret.slist.toplevel = ret
  ksl_hook (ret.slist)
  ret.slist.scrollbar.toplevel = ret
  ksl_hook (ret.slist.scrollbar)
  ret.UpdateList = ksl_updatelist
  ret:Hide ()

  return ret
end
