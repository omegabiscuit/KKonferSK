--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     Git: https://github.com/kahluamods/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com

   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2018 James Kean Johnston. All rights reserved.

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

local K = LibStub:GetLibrary("KKore")

if (not K) then
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
end

local ksk = K:GetAddon ("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local KRP = ksk.KRP
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tsort = table.sort
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strgsub = string.gsub
local strlen = string.len
local strfind = string.find
local strsplit = string.split
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local strlower = string.lower
local printf = K.printf

local ucolor = K.ucolor
local ecolor = K.ecolor
local icolor = K.icolor
local debug = ksk.debug
local info = ksk.info
local err = ksk.err
local white = ksk.white
local class = ksk.class
local shortclass = ksk.shortclass
local aclass = ksk.aclass
local shortaclass = ksk.shortaclass

local members = nil
local current_list = nil
local current_listid = nil
local current_memberid = nil
local current_members = nil
local current_member = nil
local newlistdlg = nil
local implistdlg = nil
local explistdlg = nil
local addmissingdlg = nil

local linfo = {}
local qf = {}

--
-- This file contains all of the UI handling code for the lists panel,
-- as well as all list manipulation functions.
--

local function hide_popup ()
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end
end

local function changed (res)
  local res = res or false
  if (not current_listid) then
    res = true
  end
  qf.listupdbtn:SetEnabled (not res)
end

--
-- linfo is needed because we don't save changes to the data immediately, we
-- wait for teh user to be done and then press the "Update" button. If we made
-- the changes directly in each onclick handler we wouldn't need this, but
-- then we would need to send out a change event for every change. This way we
-- batch up all changes into one event.
--
local function setup_linfo ()
  if (not current_list) then
    return
  end

  linfo = {}
  linfo.sortorder = current_list.sortorder
  linfo.def_rank = current_list.def_rank
  linfo.strictcfilter = current_list.strictcfilter
  linfo.strictrfilter = current_list.strictrfilter
  linfo.extralist = current_list.extralist
end

--
-- Refresh the local members list used in this panel. This just refreshes
-- the user interface used here. If the members list changes (users are
-- added, deleted or moved) then this is only one of the functions that needs
-- to be called. The item editor and the loot rolling stuff also need to be
-- refreshed but it is the responsibility of the functions that actually
-- change the data to call those, we don't do that here. This is only for
-- refreshing the data that THIS code is responsible for. The function below
-- (RefreshAllMemberLists) refreshes everything (and calls this).
--
-- This updates current_members, current_member and members.
local function refresh_member_list (listid)
  local oldmember = current_memberid or nil
  local oldidx = nil

  if (listid and current_listid and listid ~= current_listid) then
    return
  end

  current_members = nil
  current_memberid = nil
  current_member = nil
  members = nil

  if (not ksk.currentid) then
    current_listid = nil
    current_list = nil
  end

  if (current_listid) then
    current_members = current_list.users

    if (current_list.nusers > 0) then
      members = {}
      for k,v in ipairs(current_members) do
        local ti = {id = v, idx = k }
        tinsert (members, ti)
      end

      if (ksk.cfg.tethered) then
        for i = #members, 1, -1 do
          local usr = ksk.users[members[i].id]
          if (usr.alts) then
            for j = 1, #usr.alts do
              local ti = { id = usr.alts[j], isalt = true,
                main = members[i].id, idx = members[i].idx }
              tinsert (members, i+j, ti)
            end
          end
        end
      end

      for k,v in ipairs (members) do
        if (v.id == oldmember) then
          oldidx = k
        end
      end
    end
  end

  if (members) then
    qf.memberlist.itemcount = #members
  else
    qf.memberlist.itemcount = 0
  end
  qf.memberlist:UpdateList ()

  -- This will update current_memberid and current_member.
  qf.memberlist:SetSelected (oldidx, true, true)

  local en = true
  if (not ksk.csd.is_admin or qf.lists.itemcount < 1) then
    en = false
  end

  if ((qf.memberlist.itemcount < 1) or not current_memberid) then
    en = false
  end
  qf.delete:SetEnabled (en)
  qf.resunres:SetEnabled (en)
end

--
-- Handling the members list is a bit tricky if the configuration has
-- tethered alts. Without tethered alts, the display is a direct 1-1
-- mapping from the members list to what is displayed. However, if there
-- are tethered alts, it is more useful to display the alts of the user
-- underneath their main, and have things like "Move Up" and "Move Down"
-- move all those users as a block. This is purely a visual thing, as in
-- the actual member list database there is only one entry, for the user's
-- main character. The easiest way to deal with this is to do all manipulations
-- such as suiciding, moving users up and down etc on the raw members list
-- data, and then to create a for-display array that is refreshed from that
-- raw data each time a change is made.
--

local function rlist_setenabled (onoff)
  local onoff = onoff or false

  if (not qf.listconf) then
    return
  end

  qf.listconf.sortorder:SetEnabled (onoff)
  qf.listconf.defrank:SetEnabled (onoff)
  qf.listconf.cfilter:SetEnabled (onoff)
  qf.listconf.rfilter:SetEnabled (onoff)
  qf.listconf.slistdd:SetEnabled (onoff)
  qf.insert:SetEnabled (onoff)

  if (ksk.cfg.cfgtype == ksk.CFGTYPE_PUG) then
    qf.listconf.defrank:SetEnabled (false)
  end
end

local function rlist_selectitem (objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  hide_popup ()
  rlist_setenabled (onoff and ksk.csd.is_admin)

  if (onoff) then
    current_listid = ksk.sortedlists[idx].id
    current_list = ksk.lists[current_listid]
    setup_linfo ()
    qf.listconf.sortorder:SetValue (current_list.sortorder)
    qf.listconf.defrank:SetValue (current_list.def_rank)
    qf.listconf.cfilter:SetChecked (current_list.strictcfilter)
    qf.listconf.rfilter:SetChecked (current_list.strictrfilter)
    qf.listconf.slistdd:SetValue (current_list.extralist)
    qf.listctl.announcebutton:SetEnabled (ksk.csd.is_admin and ksk.raid ~= nil)
  else
    current_listid = nil
    current_list = nil
    qf.listctl.announcebutton:SetEnabled (false)
  end

  -- Updates current_members, current_member, current_memberid, members
  refresh_member_list (current_listid)

  changed (true)
end

local function mlist_newitem (objp, num)
  local bname = "KSKMListButton" .. tostring (num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (225)
  rf:SetHeight (16)
  rf:SetHighlightTexture (htn, "ADD")

  local text = rf:CreateFontString (nil, "ARTWORK", nfn)
  text:ClearAllPoints ()
  text:SetPoint ("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint ("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -48, 2)
  text:SetJustifyH ("LEFT")
  text:SetJustifyV ("TOP")
  rf.text = text

  local si = rf:CreateFontString (nil, "ARTWORK", "GameFontNormalSmall")
  si:ClearAllPoints ()
  si:SetPoint ("TOPLEFT", text, "TOPRIGHT", 0, 0)
  si:SetPoint ("BOTTOMRIGHT", text, "BOTTOMRIGHT", 40, 0)
  si:SetJustifyH ("RIGHT")
  si:SetJustifyV ("TOP")
  rf.indicators = si

  rf.SetText = function (self, txt, ench, frozen, res)
    self.text:SetText (txt)
    local st = ""
    local et = ""
    local is = ""
    if (ench) then
      is = L["USER_ENCHANTER"]
    end
    if (frozen) then
      is = is .. L["USER_FROZEN"]
    end
    if (res) then
      is = is .. L["USER_RESERVED"]
    end
    if (is ~= "") then
      st = "["
      et = "]"
    end
    self.indicators:SetText (st .. is .. et)
  end

  rf:SetScript ("OnClick", function (this)
    if (not ksk.csd.is_admin) then
      return
    end
    local idx = this:GetID ()
    this:GetParent():GetParent():SetSelected (idx)
    qf.findmember:SetText ("")
    qf.findmember:ClearFocus ()
  end)

  return rf
end

local function mlist_setitem (objp, idx, slot, btn)
  local uid = members[idx].id
  local ench, frozen, res
  local uc = uid
  local at = strfmt ("%d: ", members[idx].idx)
  local bm = true

  --
  -- If we are tethered, we only care about the main character being frozen
  -- or reserved, but we do care about any of the alts being enchanters.
  -- Also, if we are tethered, then members points to a different array that
  -- has different info we care about.
  --
  if (ksk.cfg.tethered) then
    if (members[idx].isalt) then
      uc = members[idx].main
      at = "    - "
      bm = false
    else
      at = strfmt ("%d: ", members[idx].idx)
    end
  end

  ench = ksk.UserIsEnchanter (uid)
  frozen = ksk.UserIsFrozen (uc) and bm
  res = ksk.UserIsReserved (uc) and bm

  btn:SetText (at .. shortclass (ksk.users[uid]), ench, frozen, res)
  btn:SetID (idx)
  btn:Show ()
end

local function mlist_selectitem (objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  hide_popup ()

  if (onoff) then
    current_memberid = members[idx].id
    local ridx = idx
    if (ksk.cfg.tethered) then
      ridx = members[idx].idx
      if (members[idx].isalt) then
        current_memberid = members[idx].main
      end
    end
    current_member = current_members[current_memberid]

    local ee = (ridx > 1 and ksk.csd.is_admin)
    local ef = (ridx < #current_list.users and ksk.csd.is_admin)
    qf.king:SetEnabled (ee)
    qf.moveup:SetEnabled (ee)
    qf.movedown:SetEnabled (ef)
    qf.suicide:SetEnabled (ef)
    qf.resunres:SetText (L["Reserve"])
    if (ksk.csd.is_admin and ksk.UserIsReserved (current_memberid)) then
      qf.resunres:SetText (L["Unreserve"])
    end
    qf.resunres:SetEnabled (ksk.csd.is_admin)
    qf.delete:SetEnabled (ksk.csd.is_admin)
  else
    qf.king:SetEnabled (false)
    qf.moveup:SetEnabled (false)
    qf.movedown:SetEnabled (false)
    qf.suicide:SetEnabled (false)
    qf.resunres:SetEnabled (false)
    qf.delete:SetEnabled (false)
    qf.resunres:SetText (L["Reserve"])
    current_memberid = nil
    current_member = nil
  end
end

local function create_list_button ()
  local box

  if (not newlistdlg) then
    newlistdlg, box = ksk.SingleStringInputDialog ("KSKSetupNewList",
      L["Create Roll List"], L["NEWLIST"], 400, 175)

    local function verify_with_create (objp, val)
      if (strlen (val) < 1) then
        err (L["invalid roll list name. Please try again."])
        objp:Show ()
        objp.ebox:SetFocus ()
        return true
      end
      ksk.CreateNewList (val)
      newlistdlg:Hide ()
      ksk.mainwin:Show ()
      return false
    end

    newlistdlg:Catch ("OnAccept", function (this, evt)
      return verify_with_create (this:GetParent(), this.ebox:GetText ())
    end)

    newlistdlg:Catch ("OnCancel", function (this, evt)
      newlistdlg:Hide ()
      ksk.mainwin:Show ()
      return false
    end)

    box:Catch ("OnEnterPressed", function (this, evt, val)
      return verify_with_create (this:GetParent(), val)
    end)
  else
    box = newlistdlg.ebox
  end

  box:SetText ("")
  ksk.mainwin:Hide ()
  newlistdlg:Show ()
  box:SetFocus ()
end

local function delete_list_button (lid)
  ksk.DeleteListCmd (lid)
end

local function rename_list_button (lid)
  hide_popup ()

  local function rename_helper (newname, old)
    local found = false
    local lname = strlower (newname)

    for k,v in pairs (ksk.lists) do
      if (strlower(ksk.lists[k].name) == lname) then
        found = true
      end
    end

    if (found) then
      err (L["roll list %q already exists. Try again."], white (newname))
      return true
    end

    local rv = ksk.RenameList (old, newname)
    if (rv) then
      return true
    end

    return false
  end

  ksk.RenameDialog (L["Rename Roll List"], L["Old Name"],
    ksk.lists[lid].name, L["New Name"], 32, rename_helper,
    lid, true)
end

local function copy_list_button (lid)
  hide_popup ()

  local function copy_helper (newname, old)
    local found = false
    local lname = strlower (newname)

    for k,v in pairs (ksk.lists) do
      if (strlower(ksk.lists[k].name) == lname) then
        found = true
      end
    end

    if (found) then
      err (L["roll list %q already exists. Try again."], white (newname))
      return true
    end

    local rv = ksk.CopyList (old, newname)
    if (rv) then
      return true
    end

    return false
  end

  ksk.RenameDialog (L["Copy Roll List"], L["Source List"],
    ksk.lists[lid].name, L["Destination List"], 32, copy_helper,
    lid, true)
end

local insert_popup = nil
local random_insert = false

local function insert_member (btn)
  local ulist = {}
  local pdef = nil

  hide_popup ()

  for k,v in pairs (ksk.users) do
    if (not ksk.UserInList (k)) then
      local doit = false
      local ti = nil
      if (ksk.cfg.tethered) then
        if (not ksk.UserIsAlt (k, v.flags)) then
          doit = true
        end
      else
        doit = true
      end
      if (doit) then
        ti = { value = k, text = class (v.name, v.class), }
        tinsert (ulist, ti)
      end
    end
  end

  tsort (ulist, function (a,b)
    -- Sort so that if we are in a raid, that current raid members appear first
    -- and then all of the offline members. Makes it a lot easier to find a
    -- user if you need to add them in the middle of a raid.
    local anm = ksk.users[a.value].name
    local bnm = ksk.users[b.value].name

    if (KRP.in_raid) then
      local air = KRP.players[anm] and true or false
      local bir = KRP.players[bnm] and true or false
      if (air and not bir) then
        return true
      end
      if (bir and not air) then
        return false
      end
    end
    return strlower (anm) < strlower (bnm)
  end)

  if (ksk.cfg.tethered) then
    for i = #ulist, 1, -1 do
      if (ksk.users[ulist[i].value].alts) then
        for k,v in pairs (ksk.users[ulist[i].value].alts) do
          local usr = ksk.users[v]
          local ti = { value = ulist[i].value, text = "  - "..class (usr) }
          tinsert (ulist, i+1, ti)
        end
      end
    end
  end

  local function pop_func (puid)
    if (ksk.cfg.tethered) then
      if (ksk.UserIsAlt (puid)) then
        id = ksk.users[puid].main
      end
    end

    hide_popup ()

    --
    -- If we've been asked to insert this at a random position, pick the
    -- position now. Otherwise, just insert at the bottom.
    --
    local rlist = ksk.lists[current_listid]
    local pos = rlist.nusers + 1
    if (random_insert) then
      pos = math.random (pos)
    end
    ksk.InsertMember (puid, current_listid, pos)
    info (L["added %s to list %q at position %s."],
      shortaclass (ksk.users[puid]), white(rlist.name), white(tostring(pos)))
  end

  if (not insert_popup) then
    insert_popup = ksk.PopupSelectionList ("KSKInsertMemberPopup",
      ulist, nil, 205, 300, ksk.mainwin.tabs[ksk.LISTS_TAB].content, 16,
      pop_func, 20, 20)
    local arg = {
      x = 0, y = 2, width = 150, parent = insert_popup.header,
      initialvalue = false, label = { text = L["Insert Randomly"] },
    }
    insert_popup.randpos = KUI:CreateCheckBox (arg, insert_popup.header)
    insert_popup.randpos.toplevel = insert_popup
    insert_popup.randpos:HookScript ("OnEnter", function (this)
      this.toplevel:StopTimeoutCounter ()
    end)
    insert_popup.randpos:HookScript ("OnLeave", function (this)
      this.toplevel:StartTimeoutCounter ()
    end)
    insert_popup.randpos:SetFrameLevel (insert_popup.header:GetFrameLevel () + 1)
    insert_popup.randpos:Catch ("OnValueChanged", function (this, evt, val)
      random_insert = val
    end)

    arg = {
      x = 0, y = 2, len = 16, font = "ChatFontSmall", width = 170,
      tooltip = { title = L["User Search"], text = L["TIP099"] },
      parent = insert_popup.footer,
    }
    insert_popup.usearch = KUI:CreateEditBox (arg, insert_popup.footer)
    insert_popup.usearch.toplevel = insert_popup
    qf.inssearch = insert_popup.usearch
    insert_popup.usearch:Catch ("OnEnterPressed", function (this)
      this:SetText ("")
    end)
    insert_popup.usearch:HookScript ("OnEnter", function (this)
      this.toplevel:StopTimeoutCounter ()
    end)
    insert_popup.usearch:HookScript ("OnLeave", function (this)
      this.toplevel:StartTimeoutCounter ()
    end)
    insert_popup.usearch:Catch ("OnValueChanged", function (this, evt, newv, user)
      if (not ksk.users or not this.toplevel.selectionlist or this.toplevel.slist.itemcount < 1) then
        return
      end
      if (user and newv and newv ~= "") then
        local lnv = strlower (newv)
        local tln
        for k,v in pairs (this.toplevel.selectionlist) do
          tln = strlower (ksk.users[v.value].name)
          if (strfind (tln, lnv, 1, true)) then
            this.toplevel.slist:SetSelected (k, true)
            return
          end
        end
      end
    end)
  else
    insert_popup:UpdateList (ulist)
  end

  insert_popup:ClearAllPoints ()
  insert_popup:SetPoint ("TOPLEFT", btn, "TOPRIGHT", 0, 0)
  insert_popup:Show ()
  ksk.popupwindow = insert_popup
end

local function move_member (btn, dir)
  hide_popup ()

  local c = qf.memberlist:GetSelected ()
  if (not c) then
    return
  end

  local uid = members[c].id
  if (ksk.cfg.tethered and members[c].isalt) then
    uid = members[c].main
  end

  --
  -- We need to check if the "direction" is suicide, and if we are in a
  -- raid, issue a propper suicide command. This is because 99 times out
  -- of a hundred, when you manually adjust a member while in a raid it
  -- is to deal with a miss-loot of an item, and the user would have been
  -- suicided normally if there was no mistake. Doing repairs to the list
  -- outside of the raid, however, we can assume that pressing suicide
  -- wants to send the user to the extreme bottom of the list, and we use
  -- the MoveMember function.
  --
  if (dir == 0 and ksk.raid) then
    local sulist = ksk.CreateRaidList (current_listid)
    ksk.SuicideUser (current_listid, sulist, uid, ksk.currentid)
  else
    local es = strfmt ("%s:%s:%d", uid, current_listid, dir)
    ksk.AddEvent (ksk.currentid, "MMLST", es, true)
    ksk.MoveMember (uid, current_listid, dir, ksk.currentid)
  end
end

local function resunres_member (btn)
  hide_popup ()

  local ir = ksk.UserIsReserved (current_memberid) or false
  ksk.ReserveUser (current_memberid, not ir)
end

local function insert_list_member (uid, listid, pos, cfg, nocmd)
  local cfg = cfg or ksk.currentid
  local listid = listid or current_listid

  if (not ksk.configs[cfg] or not ksk.configs[cfg].lists[listid]) then
    return true
  end

  if (ksk.UserInList (uid, listid, cfg)) then
    return true
  end

  local rl = ksk.configs[cfg].lists[listid]

  rl.nusers = rl.nusers + 1
  pos = pos or rl.nusers
  if (pos > rl.nusers) then
    pos = rl.nusers
  end
  tinsert (rl.users, pos, uid)

  if (not nocmd) then
    local es = strfmt ("%s:%s:%d", uid, listid, pos)
    ksk.AddEvent (cfg, "IMLST", es, true)
  end

  return false
end

local function delete_member (btn)
  hide_popup ()

  local c = qf.memberlist:GetSelected ()
  if (not c) then
    return
  end

  local uid = members[c].id
  if (ksk.cfg.tethered and members[c].isalt) then
    uid = members[c].main
  end

  ksk.DeleteMember (uid, current_listid, ksk.currentid)
end

local function import_list_button ()
  local osklist = ""
  local insrand = true
  local imprank = 0
  local csvstr = ""
  local csvopt = 1

  if (not implistdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKImportListDialog",
      title = L["Import List Members"],
      border = true,
      width = 400,
      height = 280,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = "CENTER", y = ypos, width = 200, border = true, autosize = false,
      justifyh = "CENTER",
    }
    ret.curlist = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 32

    arg = {
      x = 0, y = ypos, dwidth = 175, mode = "SINGLE", itemheight = 16,
      items = KUI.emptydropdown, name = "KSKListImpRanks",
      label = { text = L["Guild Rank to Import"], pos = "LEFT" },
    }
    ret.grank = KUI:CreateDropDown (arg, ret)
    ret.grank:Catch ("OnValueChanged", function (this, evt, newv)
      implistdlg.insrand:SetEnabled (newv ~= 0)
      implistdlg.csvimp:SetEnabled (newv == 0)
      imprank = tonumber (newv)
    end)
    ypos = ypos - 24
    arg = {}

    arg = {
      x = 20, y = ypos, checked = true,
      label = { text = L["Insert Randomly"] },
    }
    ret.insrand = KUI:CreateCheckBox (arg, ret)
    ret.insrand:Catch ("OnValueChanged", function (this, evt, val)
      insrand = val
    end)
    arg = {}
    ypos = ypos - 24

    arg = {
      x = 0, y = ypos, len = 9999,
      label = { text = L["CSV Import"], pos = "LEFT" },
    }
    ret.csvimp = KUI:CreateEditBox (arg, ret)
    ret.csvimp:Catch ("OnValueChanged", function (this, evt, newv)
      implistdlg.grank:SetEnabled (newv == "" and K.player.is_guilded)
      implistdlg.insrand:SetEnabled (newv == "" and imprank ~= 0 and K.player.is_guilded)
      implistdlg.csvopts:SetEnabled (newv ~= "" and imprank == 0)
      csvstr = newv
    end)
    ypos = ypos - 30
    arg = {}

    arg = {
      x = 16, y = ypos, dwidth = 250, mode = "SINGLE", items = {
        { text = L["Set List to Imported Values"], value = 1 },
        { text = L["Add to Existing Members"], value = 2 },
        { text = L["Randomly Add to Existing Members"], value = 3 },
      }, name = "KSKCSVImpOpts", enabled = false, initialvalue = 1,
      itemheight = 16,
    }
    ret.csvopts = KUI:CreateDropDown (arg, ret)
    ret.csvopts:Catch ("OnValueChanged", function (this, evt, newv)
      csvopt = newv
    end)

    ret.OnAccept = function (this)
      if (imprank ~= 0) then
        -- Import a guild rank (possibly randomly)
        local rusers = {}
        local ngm = K.guild.numroster
        for i = 1, ngm do
          local nm = K.guild.roster.id[i].name
          local ri = K.guild.roster.id[i].rank
          local cl = K.guild.roster.id[i].class
          if (ri == imprank) then
            local uid = ksk.FindUser (nm)
            if (not uid) then
              uid = ksk.CreateNewUser (nm, cl, nil, false, true)
            end
            tinsert (rusers, uid)
          end
        end

        ksk.RefreshUsers ()

        for k,v in pairs (rusers) do
          local pos = nil
          if (not ksk.UserInList (v)) then
            if (insrand) then
              pos = math.random (current_list.nusers + 1)
            end
            insert_list_member (v, current_listid, pos)
          end
        end
      elseif (csvstr ~= "") then
        --
        -- Import from a CSV string. First thing we do is remove any spaces,
        -- and then split the string on the comma delimiter. We then have
        -- to search the user list for each user, to ensure the string is
        -- valid. If any user is missing, report it and bail.
        --
        local wstr = strgsub (csvstr, " ", "")
        local utbl = { strsplit (",", wstr) }
        local musr = {}
        local ilist = {}
        for k,v in pairs (utbl) do
          v = K.CapitaliseName (v)
          local uid = ksk.FindUser (v)
          if (not uid) then
            tinsert (musr, v)
          else
            tinsert (ilist, uid)
          end
        end
        if (#musr > 0) then
          err (L["The following users are missing from the user list: %s"], tconcat (musr, ", "))
          err (L["Import from the CSV string cannot continue until these users are added."])
          return
        end
        if (csvopt == 1) then
          ksk.SetMemberList (tconcat (ilist, ""))
        else
          for k,v in pairs (ilist) do
            local pos = nil
            if (not ksk.UserInList (v)) then
              if (csvopt == 3) then
                pos = math.random (current_list.nusers + 1)
              end
              insert_list_member (v, current_listid, pos)
            end
          end
        end
      end
      implistdlg:Hide ()
      ksk.RefreshAllMemberLists (current_listid)
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      implistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    implistdlg = ret
  end

  local gitems = {}
  tinsert (gitems, { text = L["None"], value = 0 })
  if (K.player.is_guilded) then
    implistdlg.grank:SetEnabled (true)
    for i = 1, K.guild.numranks do
      local iv = { text = K.guild.ranks[i], value = i }
      tinsert (gitems, iv)
    end
  else
    implistdlg.grank:SetEnabled (false)
    implistdlg.insrand:SetEnabled (false)
  end
  implistdlg.grank:UpdateItems (gitems)
  implistdlg.grank:SetValue (0)

  ksk.mainwin:Hide ()
  implistdlg.csvimp:SetText ("")
  implistdlg.csvopts:SetValue (csvopt)
  implistdlg.curlist:SetText (ksk.lists[current_listid].name)
  implistdlg:Show ()
end

local function export_list_button ()
  local selwhat = nil
  local thestring = ""
  local lststring = ""
  local uu = {}
  local uv = {}

  if (not explistdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKExportListDialog",
      title = L["Export List Members"],
      border = true,
      width = 400,
      height = 175,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)

    arg = {
      x = 0, y = ypos, width = 300, font = "GameFontNormal",
      text = "",
    }
    ret.clistmsg = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24

    arg = {
      label = { text = L["Select"], pos = "LEFT" },
      name = "KSKWhatToExport", mode = "SINGLE",
      x = 0, y = ypos, dwidth = 250, items = {
        { text = L["Nothing"], value = 0 },
        { text = L["Export current list as CSV"], value = 1 },
        { text = L["Export current list as XML"], value = 2 },
        { text = L["Export current list as BBcode"], value = 3 },
        { text = L["Export all lists as XML"], value = 4 },
        { text = L["Export all lists as BBcode"], value = 5 },
      }, initialvalue = 0, itemheight = 16,
    }
    ret.what = KUI:CreateDropDown (arg, ret)
    ret.what:Catch ("OnValueChanged", function (this, evt, newv)
      selwhat = newv
      local function do_xml_list (listid)
        lststring = lststring .. strfmt ("<list id=%q n=%q>", listid, ksk.lists[listid].name)
        local ll = ksk.lists[listid]
        local lul = {}
        for k,v in ipairs (ll.users) do
          local up=ksk.users[v]
          if (not uu[v]) then
            uu[v] = true
            tinsert (uv, strfmt ("<u id=%q n=%q c=%q/>", v, up.name, up.class))
          end
          tinsert (lul, strfmt ("<u id=%q/>", tostring(v)))
        end
        lststring = lststring .. tconcat (lul, "") .. "</list>"
      end

      local function do_bbcode_list (listid)
        lststring = lststring .. strfmt ("[center][b]List: %q[/b][/center]\n[list]", ksk.lists[listid].name)
        local ll = ksk.lists[listid]
        local lul = {}
        for k,v in ipairs (ll.users) do
          local up=ksk.users[v]
          tinsert (lul, strfmt ("[*][color=#%s]%s[/color]\n", K.ClassColorsHex[up.class], up.name))
        end
        lststring = lststring .. tconcat (lul, "") .. "[/list]\n"
      end

      local function final_xml_string ()
        local _, mo, dy, yr =  C_DateAndTime.GetCurrentCalendarTime()
        local hh, mm = GetGameTime ()
        local dstr = strfmt ("%04d-%02d-%02d", yr, mo, dy)
        local tstr = strfmt ("%02d:%02d", hh, mm)
        local cs = ""
        for k,v in pairs (K.IndexClass) do
          if (v.u) then
            cs = cs .. strfmt ("<c id=%q v=%q/>", tostring (k), strlower (tostring(v.u)))
          end
        end
        thestring = strfmt ("<ksk date=%q time=%q><classes>%s</classes><users>%s</users><lists>%s</lists></ksk>", dstr, tstr, cs, tconcat (uv, ""), lststring)
      end

      local function final_bbcode_string ()
        local _, mo, dy, yr =  C_DateAndTime.GetCurrentCalendarTime()
        local hh, mm = GetGameTime ()
        local dstr = strfmt ("%04d-%02d-%02d", yr, mo, dy)
        local tstr = strfmt ("%02d:%02d", hh, mm)
        thestring = strfmt ("[center][b]KSK Lists as of %s %s[/b][/center]\n", dstr, tstr) .. lststring
      end

      if (selwhat == 1 and current_listid) then
        local tt = {}
        for k,v in ipairs (current_list.users) do
          tinsert (tt, ksk.users[v].name)
        end
        thestring = tconcat (tt, ",")
      elseif (selwhat == 2 and current_listid) then
        uu = {}
        uv = {}
        lststring = ""
        do_xml_list (current_listid)
        final_xml_string ()
        lststring = ""
      elseif (selwhat == 3 and current_listid) then
        uu = {}
        uv = {}
        lststring = ""
        do_bbcode_list (current_listid)
        final_bbcode_string ()
        lststring = ""
      elseif (selwhat == 4) then
        uu = {}
        uv = {}
        lststring = ""
        for k,v in ipairs (ksk.sortedlists) do
          do_xml_list (v.id)
        end
        final_xml_string ()
      elseif (selwhat == 5) then
        uu = {}
        uv = {}
        lststring = ""
        for k,v in ipairs (ksk.sortedlists) do
          do_bbcode_list (v.id)
        end
        final_bbcode_string ()
      else
        thestring = ""
      end
      explistdlg.expstr:SetText (thestring)
    end)
    ypos = ypos - 32

    arg = {
      x = 0, y = ypos, len = 99999,
      label = { text = L["Export string"], pos = "LEFT" },
    }
    ret.expstr = KUI:CreateEditBox (arg, ret)
    ret.expstr:Catch ("OnValueChanged", function (this, evt, newv, user)
      this:HighlightText ()
      this:SetCursorPosition (0)
      if (newv ~= "") then
        this:SetFocus ()
        explistdlg.copymsg:Show ()
      else
        this:ClearFocus ()
        explistdlg.copymsg:Hide ()
      end
    end)
    ypos = ypos - 24

    arg = {
      x = 16, y = ypos, width = 300,
      text = L["Press Ctrl+C to copy the export string"],
    }
    ret.copymsg = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24

    ret.OnAccept = function (this)
      explistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      explistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    explistdlg = ret
  end

  explistdlg.what:SetValue (selwhat)
  explistdlg.expstr:SetText ("")
  explistdlg.clistmsg:SetText (strfmt (L["Current list: %s"], white (current_list.name)))

  ksk.mainwin:Hide ()
  explistdlg:Show ()
end

local function add_missing_button ()
  local insrandom
  local whatv

  if (not addmissingdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKAddMissingDialog",
      title = L["Add Missing Members"],
      border = true,
      width = 400,
      height = 175,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = 0, y = ypos, width = 300, font = "GameFontNormal",
      text = "",
    }
    ret.clistmsg = KUI:CreateStringLabel (arg, ret)
    arg = {}
    ypos = ypos - 24

    arg = {
      label = { text = L["Select"], pos = "LEFT" },
      name = "KSKWhoMissingToAdd", mode = "SINGLE",
      x = 4, y = ypos, dwidth = 250, items = {
        { text = L["Add Missing Raid Members"], value = 1 },
        { text = L["Add All Missing Members"], value = 2 },
      }, initialvalue = 1, itemheight = 16,
    }
    ret.what = KUI:CreateDropDown (arg, ret)
    ret.what:Catch ("OnValueChanged", function (this, evt, newv)
      whatv = tonumber (newv)
    end)
    ypos = ypos - 32
    arg = {}

    arg = {
      x = 0, y = ypos, label = { text = L["Insert Randomly"] },
    }
    ret.insrandom = KUI:CreateCheckBox (arg, ret)
    ret.insrandom:Catch ("OnValueChanged", function (this, evt, val)
      insrandom = val
    end)
    arg = {}
    ypos = ypos - 24

    ret.OnAccept = function (this)
      if (whatv == 1 and ksk.raid and ksk.raid.users) then
        for k,v in pairs (ksk.raid.users) do
          local uid = k
          if (ksk.cfg.tethered) then
            if (ksk.UserIsAlt (uid)) then
              uid = ksk.users[uid].main
            end
          end

          if (not ksk.UserInList (uid)) then
            local pos = ksk.lists[current_listid].nusers + 1
            if (insrandom) then
              pos = math.random (pos)
            end
            insert_list_member (uid, current_listid, pos)
            info (L["added %s to list %q at position %s."],
              shortaclass (ksk.users[uid]),
              white (ksk.lists[current_listid].name),
              white (tostring (pos)))
          end
        end
      elseif (whatv == 2) then
        for k,v in pairs (ksk.users) do
          local doit = false
          if (ksk.cfg.tethered) then
            if (not ksk.UserIsAlt (k, v.flags)) then
              doit = true
            end
          else
            doit = true
          end
          if (doit) then
            if (not ksk.UserInList (k)) then
              local pos = ksk.lists[current_listid].nusers + 1
              if (insrandom) then
                pos = math.random (pos)
              end
              insert_list_member (k, current_listid, pos)
              info (L["added %s to list %q at position %s."], shortaclass (v),
                white (ksk.lists[current_listid].name), white (tostring (pos)))
            end
          end
        end
      end
      addmissingdlg:Hide ()
      ksk.RefreshAllMemberLists (current_listid)
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      addmissingdlg:Hide ()
      ksk.mainwin:Show ()
    end

    addmissingdlg = ret
  end

  insrandom = false
  whatv = 1
  addmissingdlg.what:SetValue (whatv)
  addmissingdlg.insrandom:SetChecked (insrandom)
  print(current_list)
  addmissingdlg.clistmsg:SetText (strfmt (L["Current list: %s"], white (current_list.name)))

  ksk.mainwin:Hide ()
  addmissingdlg:Show ()
end

local function announce_list_button (isall, shifted)
  if (not current_list or not members or (not shifted and not ksk.raid)) then
    return
  end

  local ts = strfmt (L["%s: relative positions of all currrent raiders for the %q list (ordered highest to lowest): "], L["MODTITLE"], current_list.name)

  if (isall) then
    ts = strfmt (L["%s: members of the %q list (ordered highest to lowest): "], L["MODTITLE"], current_list.name)
  end

  local sendfn = ksk.SendRaidMsg

  if (shifted and K.player.is_guilded) then
    sendfn = ksk.SendGuildMsg
  end

  local uid, as, al
  local np = 0
  local len = strlen (ts)

  for i = 1, #members do
    uid = members[i].id
    as = nil
    if (not isall and ksk.raid.users[uid]) then
      np = np + 1
      as = strfmt ("%s(%d) ", K.ShortName (ksk.users[uid].name), members[i].idx)
    elseif (isall) then
      np = np + 1
      as = K.ShortName (ksk.users[uid].name) .. " "
    end
    if (as) then
      al = strlen (as)
      if (len + al > 240) then
        sendfn (ts)
        ts = strfmt ("%s: ", L["MODTITLE"])
        len = strlen (ts)
      end
      ts = ts .. as
      len = len + al
    end
  end
  if (np > 0) then
    sendfn (ts)
  end
end

function ksk.InitialiseListsUI ()
  local arg
  local kmt = ksk.mainwin.tabs[ksk.LISTS_TAB]

  kmt.onclick = function (main, sub)
    local en

    if (main == 1 and sub == 1 and ksk.csd.is_admin) then
      en = true
    else
      en = false
    end
    qf.memberctl:SetShown (en)
    qf.findmember:SetShown (en)
    qf.listctl:SetShown (en)
  end

  -- First set up the quick access frames we will be using.
  qf.members = kmt.tabs[ksk.LISTS_MEMBERS_PAGE].content
  qf.cfgopts = kmt.tabs[ksk.LISTS_CONFIG_PAGE].content

  local cf = kmt.content
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  --
  -- The left-hand side panel remains invariant regardless of which top tab
  -- is selected. It contains the list of lists, and the buttons for the member
  -- selected in the right panel, if any. To make better use of the screen
  -- space since there are likely to be many users but few lists, the right
  -- hand column now just contains the members and we split the left side
  -- horizontally and have the member control buttons there instead of along
  -- the right side of the member scroll list. So that it doesn't cause any
  -- confusion when the config tab is selected at the top, this left middle
  -- panel with the member control buttons is hidden when the list config
  -- screen is active, and shown when the actual members list is active.
  --
  arg = {
    inset = 0, height = 50,
    rightsplit = true, name = "KSKListsLHHSplit",
  }
  ls.hsplit = KUI:CreateHSplit (arg, ls)
  arg = {}
  local tl = ls.hsplit.topframe
  local bl = ls.hsplit.bottomframe
  qf.listctl = bl

  local ypos = 0
  arg = {
    x = "CENTER", y = ypos, width = 165, height = 24, text = L["Announce"],
    tooltip = { title = "$$", text = L["TIP029"], },
  }
  bl.announcebutton = KUI:CreateButton (arg, bl)
  bl.announcebutton:Catch ("OnClick", function (this, evt)
    announce_list_button (false, IsShiftKeyDown ())
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = "CENTER", y = ypos, width = 165, height = 24, text = L["Announce All"],
    tooltip = { title = "$$", text = L["TIP094"], },
  }
  bl.announceallbutton = KUI:CreateButton (arg, bl)
  bl.announceallbutton:Catch ("OnClick", function (this, evt)
    announce_list_button (true, IsShiftKeyDown ())
  end)
  arg = {}
  ypos = ypos - 24

  --
  -- Split the top let panel into two, to make space for the member control
  -- buttons.
  --
  arg = {
    inset = 0, height = 98, rightsplit = true, bottomanchor = true,
    name = "KSKListsTLHSplit",
  }
  tl.hsplit = KUI:CreateHSplit (arg, tl)
  arg = {}
  local tlt = tl.hsplit.topframe
  local blt = tl.hsplit.bottomframe

  cf.cframe = MakeFrame ("Frame", nil, blt)
  cf.cframe:ClearAllPoints ()
  cf.cframe:SetPoint ("TOPLEFT", blt, "TOPLEFT", 0, 0)
  cf.cframe:SetPoint ("BOTTOMRIGHT", blt, "BOTTOMRIGHT", 0, 0)
  qf.memberctl = cf.cframe

  local mcf = cf.cframe

  --
  -- Create the member modification buttons in the left middle frame.
  --
  ypos = 0
  arg = { x = 0, y = ypos, width = 98, height = 24,
    text = L["Insert"],
    tooltip = { title = "$$", text = L["TIP030"], },
  }
  mcf.insertbutton = KUI:CreateButton (arg, mcf)
  mcf.insertbutton:Catch ("OnClick", function (this, evt)
    insert_member (this)
  end)
  qf.insert = mcf.insertbutton
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Delete"]
  arg.tooltip = { title = "$$", text = L["TIP031"], }
  mcf.deletebutton = KUI:CreateButton (arg, mcf)
  mcf.deletebutton:Catch ("OnClick", function (this, evt)
    delete_member (this)
  end)
  qf.delete = mcf.deletebutton
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Reserve"]
  arg.tooltip = { title = "$$", text = L["TIP036"], }
  mcf.reservebutton = KUI:CreateButton (arg, mcf)
  mcf.reservebutton:Catch ("OnClick", function (this, evt)
    resunres_member (this)
  end)
  qf.resunres = mcf.reservebutton

  ypos = 0
  arg.x = 100
  arg.y = ypos
  arg.text = L["King"]
  arg.tooltip = { title = "$$", text = L["TIP032"], }
  mcf.kingbutton = KUI:CreateButton (arg, mcf)
  mcf.kingbutton:Catch ("OnClick", function (this, evt)
    move_member (this, 3)
  end)
  qf.king = mcf.kingbutton
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Move Up"]
  arg.tooltip = { title = "$$", text = L["TIP033"], }
  mcf.upbutton = KUI:CreateButton (arg, mcf)
  mcf.upbutton:Catch ("OnClick", function (this, evt)
    move_member (this, 2)
  end)
  qf.moveup = mcf.upbutton
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Move Down"]
  arg.tooltip = { title = "$$", text = L["TIP034"], }
  mcf.downbutton = KUI:CreateButton (arg, mcf)
  mcf.downbutton:Catch ("OnClick", function (this, evt)
    move_member (this, 1)
  end)
  qf.movedown = mcf.downbutton
  ypos = ypos - 24

  arg.y = ypos
  arg.x = "CENTER"
  arg.text = L["Suicide"]
  arg.tooltip = { title = "$$", text = L["TIP035"], }
  mcf.suicidebutton = KUI:CreateButton (arg, mcf)
  mcf.suicidebutton:Catch ("OnClick", function (this, evt)
    move_member (this, 0)
  end)
  qf.suicide = mcf.suicidebutton
  ypos = ypos - 24

  arg = {}

  -- Now for the actual scroll list of roll lists in the left top frame.
  local function rlist_och (this)
    local idx = this:GetID ()
    if (qf.memberlist) then
      qf.memberlist.itemcount = 0
      qf.memberlist:UpdateList ()
    end
    this:GetParent():GetParent():SetSelected (idx, false, true)
    return true
  end

  arg = {
    name = "KSKRollListScrollList",
    itemheight = 16,
    newitem = function (objp, num)
      return KUI.NewItemHelper (objp, num, "KSKRListButton", 170, 16,
        nil, rlist_och, nil, nil)
      end,
    setitem = function (objp, idx, slot, btn)
      return KUI.SetItemHelper (objp, btn, idx,
        function (op, ix)
          return ksk.lists[ksk.sortedlists[ix].id].name
        end)
      end,
    selectitem = rlist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tlt.slist = KUI:CreateScrollList (arg, tlt)
  arg = {}
  qf.lists = tlt.slist

  local bdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tlt.slist:SetBackdrop (bdrop)

  --
  -- Lists panel, Members tab
  --

  local cf = qf.members

  --
  -- We need to create a frame anchored to the left side of the split, that
  -- will contain the scrolling list of users. The buttons appear to the
  -- right of the list. The scrolling list code requires a complete frame
  -- to take over so we create that first.
  --
  cf.sframe = MakeFrame ("Frame", nil, cf)
  cf.sframe:ClearAllPoints ()
  cf.sframe:SetPoint ("TOPLEFT", cf, "TOPLEFT", 0, 0)
  cf.sframe:SetPoint ("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 25)

  arg = {
    x = 0, y = 2, len = 16, font = "ChatFontSmall",
    width = 190, tooltip = { title = L["User Search"], text = L["TIP099"] },
  }
  cf.searchbox = KUI:CreateEditBox (arg, cf)
  cf.searchbox:ClearAllPoints ()
  cf.searchbox:SetPoint ("BOTTOMLEFT", cf, "BOTTOMLEFT", 8, 0)
  cf.searchbox:SetWidth (225)
  cf.searchbox:SetHeight (20)
  qf.findmember = cf.searchbox
  cf.searchbox:Catch ("OnEnterPressed", function (this, evt, newv, user)
    this:SetText ("")
  end)
  cf.searchbox:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (not members) then
      return
    end
    if (user and newv and newv ~= "") then
      local lnv = strlower (newv)
      for k,v in pairs (members) do
        local tln = strlower (ksk.users[v.id].name)
        if (strfind (tln, lnv, 1, true)) then
          local its = v.id
          if (v.isalt) then
            its = v.main
          end
          for kk,vv in ipairs (members) do
            if (vv.id == its) then
              qf.memberlist:SetSelected (kk, true)
              break
            end
          end
          return
        end
      end
    end
  end)

  arg = {
    name = "KSKMembersScrollList",
    itemheight = 16,
    newitem = mlist_newitem,
    setitem = mlist_setitem,
    selectitem = mlist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  cf.slist = KUI:CreateScrollList (arg, cf.sframe)
  arg = {}
  qf.memberlist = cf.slist
  cf.slist:SetBackdrop (bdrop)

  --
  -- Lists panel, Config tab
  --

  --
  -- Create the horizontal split at the bottom for the buttons
  --

  local cf = qf.cfgopts

  arg = {
    inset = 2, height = 75, leftsplit = true, name = "KSKListCfgRSplit",
  }
  cf.hsplit = KUI:CreateHSplit (arg, cf)
  local tr = cf.hsplit.topframe
  local br = cf.hsplit.bottomframe

  qf.listconf = tr
  qf.listcfgbuttons = br

  ypos = 0
  arg = {
    x = 0, y = ypos, label = { text = L["Sort Order"] },
    width = 200, minval = 1, maxval = 64,
    tooltip = { title = "$$", text = L["TIP037"] },
  }
  tr.sortorder = KUI:CreateSlider (arg, tr)
  tr.sortorder:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (user) then
      changed ()
    end
    linfo.sortorder = tonumber (newv)
  end)
  arg = {}
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, name = "KSKDefRankDropdown", itemheight = 16,
    dwidth = 175, items = KUI.emptydropdown, mode = "SINGLE",
    label = { text = L["Initial Guild Rank Filter"], },
    tooltip = { title = "$$", text = L["TIP038"] },
  }
  tr.defrank = KUI:CreateDropDown (arg, tr)
  -- Must remain visible in ksk.qf so it can be changed from main.
  ksk.qf.defrankdd = tr.defrank
  tr.defrank:Catch ("OnValueChanged", function (this, evt, nv, user)
    if (user) then
      changed ()
    end
    linfo.def_rank = tonumber (nv)
  end)
  arg = {}
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, label = { text = L["Strict Class Armor Filtering"] },
    tooltip = { title = "$$", text = L["TIP039"] },
  }
  tr.cfilter = KUI:CreateCheckBox (arg, tr)
  tr.cfilter:Catch ("OnValueChanged", function (this, evt, val, user)
    if (user) then
      changed ()
    end
    linfo.strictcfilter = val
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Strict Role Filtering"] },
    tooltip = { title = "$$", text = L["TIP040"] },
  }
  tr.rfilter = KUI:CreateCheckBox (arg, tr)
  tr.rfilter:Catch ("OnValueChanged", function (this, evt, val, user)
    if (user) then
      changed ()
    end
    linfo.strictrfilter = val
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, name = "KSKAdditionalSuicideDD", itemheight = 16,
    dwidth = 175, mode = "SINGLE", items = KUI.emptydropdown,
    label = { text = L["Suicide on Additional List"] },
    tooltip = { title = "$$", text = L["TIP041"] },
  }
  tr.slistdd = KUI:CreateDropDown (arg, tr)
  qf.extralist = tr.slistdd
  tr.slistdd:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (user) then
      changed ()
    end
    linfo.extralist = newv
  end)
  arg = {}
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, text = L["Update"], enabled = false,
    tooltip = { title = "$$", text = L["TIP042"] },
  }
  tr.updatebtn = KUI:CreateButton (arg, tr)
  qf.listupdbtn = tr.updatebtn
  tr.updatebtn:Catch ("OnClick", function (this, evt, ...)
    K.CopyTable (linfo, current_list)
    ksk.RefreshAllLists ()
    tr.updatebtn:SetEnabled (false)
    -- If this changes MUST change CHLST is KSK-Config.lua
    local es = strfmt ("%s:%d:%d:%s:%s:%s", current_listid,
      linfo.sortorder, linfo.def_rank, linfo.strictcfilter and "Y" or "N",
      linfo.strictrfilter and "Y" or "N", linfo.extralist)
    ksk.AddEvent (ksk.currentid, "CHLST", es)
  end)

  --
  -- List control buttons at the bottom right
  --
  ypos = 0
  arg = {
    x = 0, y = ypos, width = 90, height = 24, text = L["Create"],
    tooltip = { title = "$$", text = L["TIP043"] },
  }
  br.createbutton = KUI:CreateButton (arg, br)
  br.createbutton:Catch ("OnClick", function (this, evt)
    create_list_button ()
  end)
  arg = {}

  arg = {
    x = 90, y = ypos, width = 90, height = 24, text = L["Delete"],
    tooltip = { title = "$$", text = L["TIP044"] },
  }
  br.deletebutton = KUI:CreateButton (arg, br)
  br.deletebutton:Catch ("OnClick", function (this, evt)
    delete_list_button (current_listid)
  end)
  arg = {}

  arg = {
    x = 180, y = ypos, width = 90, height = 24, text = L["Rename"],
    tooltip = { title = "$$", text = L["TIP045"] },
  }
  br.renamebutton = KUI:CreateButton (arg, br)
  br.renamebutton:Catch ("OnClick", function (this, evt)
    rename_list_button (current_listid)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, width = 90, height = 24, text = L["Copy"],
    tooltip = { title = "$$", text = L["TIP046"] },
  }
  br.copybutton = KUI:CreateButton (arg, br)
  br.copybutton:Catch ("OnClick", function (this, evt)
    copy_list_button (current_listid)
  end)
  arg = {}

  arg = {
    x = 90, y = ypos, width = 90, height = 24, text = L["Import"],
    tooltip = { title = "$$", text = L["TIP047"] },
  }
  br.importbutton = KUI:CreateButton (arg, br)
  br.importbutton:Catch ("OnClick", function (this, evt)
    import_list_button ()
  end)
  arg = {}

  arg = {
    x = 180, y = ypos, width = 90, height = 24, text = L["Export"],
    tooltip = { title = "$$", text = L["TIP048"] },
  }
  br.exportbutton = KUI:CreateButton (arg, br)
  br.exportbutton:Catch ("OnClick", function (this, evt)
    export_list_button ()
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 75, y = ypos, width = 120, height = 24, text = L["Add Missing"],
    tooltip = { title = "$$", text = L["TIP049"] },
  }
  br.addmissingbutton = KUI:CreateButton (arg, br)
  br.addmissingbutton:Catch ("OnClick", function (this, evt)
    add_missing_button ()
  end)
  arg = {}
end

--
-- Update the various dropdown lists that need to contain the list of list
-- names. There are several user interface elements that may need to be
-- changed. The list configuration panel has a "Next List" drop down and a
-- "suicide on additional lists" option. The main configuration also has a
-- "Default List" option and a "Try Final List" option that all need to be
-- updated to the new list of lists. Some of these lists (such as the list
-- config panel's Next List setting) have additional options over and above the
-- list of lists. However, all of them share the actual basic lists of lists,
-- which we will calculate first before inserting additional members for other
-- UI elements.
--
function ksk.RefreshAllLists ()
  local llist = {}
  local ti
  local dlfound = false
  local oldlist = current_listid or nil
  local oldidx = nil

  ksk.sortedlists = {}
  current_listid = nil

  for k,v in pairs (ksk.lists) do
    --
    -- Since we're going through the list anyway, check to make sure that our
    -- next and additional suicide lists are still valid. Set them to 0 if
    -- not.
    --
    if (v.extralist ~= "0" and not ksk.lists[v.extralist]) then
      ksk.lists[k].extralist = "0"
    end
    local ent = { id = k }
    tinsert (ksk.sortedlists, ent)
  end

  tsort (ksk.sortedlists, function (a,b)
    if (ksk.lists[a.id].sortorder < ksk.lists[b.id].sortorder) then
      return true
    end
    if (ksk.lists[a.id].sortorder == ksk.lists[b.id].sortorder) then
      return strlower(ksk.lists[a.id].name) < strlower(ksk.lists[b.id].name)
    end
    return false
  end)

  for k,v in ipairs (ksk.sortedlists) do
    if (v.id ==  oldlist) then
      oldidx = k
      break
    end
  end

  qf.lists.itemcount = #ksk.sortedlists
  qf.lists:UpdateList ()

  --
  -- This has side-effects. Since we force the setting, it will always run
  -- the selection callback (rlist_selectitem). This will set current_listid
  -- and current_list. It also calls refresh_member_list() so we don't need to
  -- call that explicitly ourselves.
  --
  qf.lists:SetSelected (oldidx, true, true)

  ti = { text = L["None"], value = "0", }
  tinsert (llist, ti)
  for k,v in pairs (ksk.sortedlists) do
    ti = { text = ksk.lists[v.id].name, value = v.id, }
    if (ksk.settings.def_list == v.id) then
      dlfound = true
    end
    tinsert (llist, ti)
  end

  if (not dlfound) then
    ksk.settings.def_list = "0"
  end

  qf.extralist:UpdateItems (llist)
  if (current_list) then
    qf.extralist:SetValue (current_list.extralist or "0")
  else
    qf.extralist:SetValue ("0")
  end

  --
  -- Update any lists in the config UI.
  --
  ksk.RefreshConfigLists (llist)

  --
  -- Update any lists in the loot / items UI.
  --
  ksk.RefreshLootLists (llist)

  --
  -- Update any lists in the users UI.
  --
  ksk.RefreshUsersLists (llist)
end

function ksk.RefreshListsUIForRaid (inraid)
  local en = true

  if (not current_listid or not ksk.csd.is_admin or not inraid) then
    en = false
  end
  qf.listctl.announcebutton:SetEnabled (en)

  en = true
  if (qf.lists.itemcount < 1 or not ksk.csd.is_admin or not inraid) then
    en = false
  end
  qf.listctl.announceallbutton:SetEnabled (en)
end

function ksk.RefreshListsUI (reset)
  if (not ksk.currentid) then
    ksk.sortedlists = nil
    current_listid = nil
    current_memberid = nil
    qf.lists.itemcount = 0
    qf.lists.UpdateList ()
    qf.lists.SetSelected (nil, false, true)
    qf.memberlist.itemcount = 0
    qf.memberlist:UpdateList ()
    qf.memberlist.SetSelected (nil, false, true)
    return
  end

  if (reset) then
    current_listid = nil
  end

  ksk.RefreshAllLists ()
  ksk.RefreshListsUIForRaid (ksk.raid ~= nil)
  ksk.RefreshAllMemberLists (current_listid, true)
end

function ksk.FindList (name, cfg)
  local cfg = cfg or ksk.currentid
  local lowname = strlower(name)

  for k,v in pairs(ksk.configs[cfg].lists) do
    if (strlower(v.name) == lowname) then
      return k
    end
  end
  return nil
end

function ksk.CreateNewList (name, cfg, myid, nocmd)
  local cfg = cfg or ksk.currentid

  if (strfind (name, ":")) then
    err (L["invalid list name. Please try again."])
    return true
  end

  local cid = ksk.FindList (name, cfg)
  if (cid) then
    if (not nocmd) then
      err (L["roll list %q already exists. Try again."], white (name))
    end
    return true
  end

  local newkey = myid or ksk.CreateNewID (name)
  ksk.configs[cfg].lists[newkey] = {}
  local rl = ksk.configs[cfg].lists[newkey]

  rl.name = name
  rl.sortorder = 1
  rl.def_rank = 0
  rl.strictcfilter = false
  rl.strictrfilter = false
  rl.extralist = "0"
  rl.users = {}
  rl.nusers = 0

  ksk.configs[cfg].nlists = ksk.configs[cfg].nlists + 1

  if (not myid and not nocmd) then
    info (L["roll list %q created."], white(name))
  end

  if (not nocmd) then
    local es = strfmt ("%s:%s", newkey, name)
    ksk.AddEvent (cfg, "MKLST", es, true)
  end

  if (cfg == ksk.currentid) then
    ksk.lists = ksk.configs[cfg].lists
    ksk.RefreshAllLists ()
  end

  return false, newkey
end

function ksk.DeleteList (listid, cfgid, nocmd)
  local cfg = cfgid or ksk.currentid

  if (ksk.configs[cfg].lists[listid]) then
    local name = ksk.configs[cfg].lists[listid].name
    ksk.configs[cfg].lists[listid] = nil
    ksk.configs[cfg].nlists = ksk.configs[cfg].nlists - 1
    if (not nocmd) then
      info (L["roll list %q deleted."], white (name))
    end
  end

  if (ksk.configs[cfg].settings.def_list == listid) then
    ksk.configs[cfg].settings.def_list = "0"
  end

  if (ksk.configs[cfg].settings.final_list == listid) then
    ksk.configs[cfg].settings.final_list = "0"
  end

  for k,v in pairs(ksk.configs[cfg].lists) do
    if (v.extralist == listid) then
      ksk.configs[cfg].lists[k].extralist = "0"
    end
  end

  for k,v in pairs (ksk.items) do
    if (v.nextdrop and v.nextdrop.suicide == listid) then
      ksk.items[k].nextdrop.suicide = nil
    end
    if (v.list and v.list == listid) then
      ksk.items[k].list = nil
    end
    if (v.suicide and v.suicide == listid) then
      ksk.items[k].suicide = nil
    end
  end

  if (current_listid == listid) then
    current_listid = nil
  end

  if (not nocmd) then
    ksk.AddEvent (cfg, "RMLST", listid, true)
  end

  if (cfg == ksk.currentid) then
    ksk.RefreshAllLists ()
  end
end

local function real_delete_list (arg)
  local cfg = arg.cfg or ksk.currentid
  local listid = arg.listid

  ksk.DeleteList (listid, cfg, false)
end

function ksk.DeleteListCmd (listid, show, cfg)
  local cfg = cfg or ksk.currentid

  local isshown = show or ksk.mainwin:IsShown ()
  ksk.mainwin:Hide ()

  ksk.ConfirmationDialog (L["Delete Roll List"], L["DELLIST"],
    ksk.configs[cfg].lists[listid].name, real_delete_list,
    { cfg=cfg, listid=listid}, isshown, 190)

  return false
end

function ksk.RenameList (listid, newname, cfg, nocmd)
  local cfg = cfg or ksk.currentid

  local cid = ksk.FindList (newname, cfg)
  if (cid) then
    if (not nocmd) then
      err (L["roll list %q already exists. Try again."], white (name))
    end
    return true
  end

  local oldname = ksk.configs[cfg].lists[listid].name
  if (not nocmd) then
    info (L["NOTICE: roll list %q renamed to %q."], white (oldname), white (newname))
  end
  ksk.configs[cfg].lists[listid].name = newname

  if (not nocmd) then
    local es = strfmt ("%s:%s", listid, newname)
    ksk.AddEvent (cfg, "MVLST", es, true)
  end

  if (cfg == ksk.currentid) then
    ksk.RefreshAllLists ()
  end

  return false
end

function ksk.CopyList (listid, newname, cfg, myid, nocmd)
  local cfg = cfg or ksk.currentid

  local cid = ksk.FindList (newname, cfg)
  if (cid) then
    if (not nocmd) then
      err (L["roll list %q already exists. Try again."], white (name))
    end
    return true
  end

  local rv
  rv, cid = ksk.CreateNewList (newname, cfg, myid, nocmd)
  if (rv) then
    return true
  end

  local src = ksk.lists[listid]
  local dst = ksk.lists[cid]

  dst.sortorder = src.sortorder
  dst.def_rank = src.def_rank
  dst.strictcfilter = src.strictcfilter
  dst.strictrfilter = src.strictrfilter
  dst.extralist = src.extralist
  dst.nusers = src.nusers
  K.CopyTable (src.users, dst.users)

  if (not nocmd) then
    local es = strfmt ("%s:%s:%s", listid, cid, newname)
    ksk.AddEvent (cfg, "CPLST", es, true)
  end

  if (cfg == ksk.currentid) then
    ksk.RefreshAllLists ()
  end

  return false
end

function ksk.SelectList (listid)
  for k,v in ipairs (ksk.sortedlists) do
    if (v.id == listid) then
      qf.lists:SetSelected (k, true, true)
      return false
    end
  end
  return true
end

function ksk.SelectListByIdx (idx)
  qf.lists:SetSelected (idx, true, true)
end

--
-- JKJ FIXME - should we take alts into account here? If we're using tethered
-- alts, they may be checking an alt's uid, but that won't appear directly in
-- the user lists, only the main ID will.
--
function ksk.UserInList (uid, listid, cfg)
  local cfg = cfg or ksk.currentid
  local listid = listid or current_listid

  if (not ksk.configs[cfg] or not ksk.configs[cfg].lists[listid]) then
    return nil
  end

  local rlist = ksk.configs[cfg].lists[listid]
  if (rlist.nusers < 1) then
    return false
  end
  for k,v in ipairs (rlist.users) do
    if (uid == v) then
      return true, k
    end
  end
  return false
end

function ksk.InsertMember (uid, listid, pos, cfg, nocmd)
  local cfg = cfg or ksk.currentid
  local listid = listid or current_listid
  local rv = insert_list_member (uid, listid, pos, cfg, nocmd)

  if (not rv and cfg == ksk.currentid) then
    ksk.RefreshAllMemberLists (listid)
  end

  return rv
end

--
-- Sets the member list to exactly the ulist string, which is a concatenated
-- list of user IDs, all of which are assumed to already exist. This is
-- only actually used by the CSV import functionality.
--
function ksk.SetMemberList (ulist, listid, cfg, nocmd)
  local cfg = cfg or ksk.currentid
  local listid = listid or current_listid

  if (not ksk.configs[cfg] or not ksk.configs[cfg].lists[listid]) then
    return true
  end

  local ll = ksk.configs[cfg].lists[listid]
  ll.users = ksk.SplitRaidList (ulist)
  ll.nusers = #ll.users

  if (not nocmd) then
    ksk.AddEvent (cfg, "SMLST", strfmt ("%s:%s", listid, ulist), true)
  end

  if (cfg == ksk.currentid) then
    ksk.RefreshAllMemberLists (listid)
  end

  return false
end

--
-- This can be called from either the user interface or from the sync code.
-- Unlike a normal loot suicide which needs to know which raid members were
-- present in order to move around offline users, moving a user up and down
-- always acts on the full raw list, and it can always move over frozen
-- users, so we don't need to worry about them either. Please note that this
-- is the code that actually implements the moves, it will not record a move
-- event for the sync log. That is handled above in the actual button press
-- handler (which in turn ends up calling this function).
-- The dir parameter is 1 to move them down 1 slot, 2 to move them up 1
-- slot, 0 to suicide them to the extreme bottom of the list or 3 to king
-- them and move them to the extreme top of the list.
--
function ksk.MoveMember (uid, listid, dir, cfg)
  local cfg = cfg or ksk.currentid
  local listid = listid or current_listid

  if (not ksk.configs[cfg] or not ksk.configs[cfg].lists[listid]) then
    return true
  end

  local rl = ksk.configs[cfg].lists[listid]
  local ul = rl.users
  local up = nil

  for k,v in ipairs (ul) do
    if (v == uid) then
      up = k
      break
    end
  end

  if (up == nil) then
    return true
  end

  local m = tremove (ul, up)
  if (dir == 0) then
    tinsert (ul, m)
  elseif (dir == 3) then
    tinsert (ul, 1, m)
  elseif (dir == 1) then
    if (up ~= #ul+1) then
      tinsert (ul, up+1, m)
    else
      tinsert (ul, up, m)
    end
  elseif (dir == 2) then
    if (up ~= 1) then
      tinsert (ul, up-1, m)
    else
      tinsert (ul, up, m)
    end
  end

  if (cfg == ksk.currentid) then
    ksk.RefreshAllMemberLists (listid)
  end

  return false
end

function ksk.DeleteMember (uid, listid, cfg, nocmd)
  local cfg = cfg or ksk.currentid
  local listid = listid or current_listid

  if (not ksk.configs[cfg] or not ksk.configs[cfg].lists[listid]) then
    return true
  end

  local rl = ksk.configs[cfg].lists[listid]
  local ul = rl.users
  local up = nil

  for k,v in ipairs (ul) do
    if (v == uid) then
      up = k
      break
    end
  end

  if (up == nil) then
    return true
  end

  tremove (ul, up)
  rl.nusers = rl.nusers - 1
  if (not nocmd) then
    local es = strfmt ("%s:%s", uid, listid)
    ksk.AddEvent (cfg, "DMLST", es, true)
  end

  if (cfg == ksk.currentid) then
    ksk.RefreshAllMemberLists (listid)
  end

  return false
end

--
-- Whenever we change a user's Alt status, or whenever a config space has
-- its "tethered alts" setting changed, we may need to fix up entries in all
-- of the lists. Say for example UserB is an alt of UserA. They are both
-- members in List1. Now the owner decides she wants to enable tethered alts.
-- This means that UserB needs to be removed from List1, because that user
-- will now appear "underneath" UserA in the list. The same situation can
-- occur if tethered alts were already enabled but a user was not correctly
-- marked as an alt. When that is corrected, we need to make sure that the
-- alt is removed from all lists, as it will now be tethered to the main.
-- So we simply need to go through all lists in the configuration and remove
-- any alts. However, if only the alt is in the list, we need to replace that
-- slot position with the main, as it will now be replaced by the main.
--
function ksk.FixupLists (cfg, rec)
  local cfg = cfg or ksk.currentid

  if (not ksk.configs[cfg] or not ksk.configs[cfg].tethered) then
    return false
  end

  local changed = false

  for k,v in pairs (ksk.configs[cfg].lists) do
    local il = 1
    while (il <= #v.users) do
      local inc = 1
      local vv = v.users[il]
      local ia, mid = ksk.UserIsAlt (vv, nil, cfg)

      if (ia) then
        assert (mid)
        if (not ksk.UserInList (mid, k, cfg)) then
          --
          -- The user is marked as an alt but their main isn't in the list.
          -- This means we have to replace this alt (in the same position)
          -- with the alt's main.
          --
          v.users[il] = mid
          changed = true
        else
          --
          -- The alt's main is already in the list, so we can now safely
          -- remove this alt from the roll list.
          --
          tremove (v.users, il)
          v.nusers = v.nusers - 1
          changed = true
          inc = 0
        end
      end
      il = il + inc
    end
  end

  if (changed) then
    ksk.FixupLists (cfg, true)
  end

  if (not rec and cfg == ksk.currentid) then
    ksk.RefreshAllLists ()
    ksk.RefreshAllMemberLists (nil)
  end

  return false
end

function ksk.RefreshAllMemberLists (listid, notus)
  if (not notus) then
    -- Refresh the list panel's member list (that's us).
    refresh_member_list (listid)
  end

  -- Refresh the loot distribution's member list.
  ksk.RefreshLootMembers (listid)
end

