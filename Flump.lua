local Flump = CreateFrame("frame")

local ENABLE_IN_RAID     = true      -- enable in raid
local ENABLE_IN_DUNGEONS = true      -- enable in dungeons
local MIN_TANK_HP        = 55000     -- How much health must a player have to be considered a tank?
local MIN_HEALER_MANA    = 20000     -- How much mana must a player have to be considered a healer?
local DIVINE_PLEA        = false     -- Announce when (holy) Paladins cast Divine Plea? (-50% healing)

-- Chat Parameters
local maxMessagesSent             = 3   -- Max messages that can be send at once before getting muted by the server
local gracePeriodForSendMessages  = 1.3   -- Assuming that we can send at most 'maxMessagesSent' every 'gracePeriodForSendMessages' seconds
-- Chat Variables
local timeMessagesSent            = {}
local queuedMessages
local MAX_PRIORITY = 1000000
local playersUnableToSpeak        = {}

local debug  = false
local status = "|cff39d7e5Flump: %s|r"

local bot    = "%s%s used a %s!"
local used   = "%s%s used %s!"
local sw     = "%s faded from %s%s!"
local cast   = "%s%s cast %s on %s%s!"
local castnt = "%s%s cast %s!"  -- Cast no target
local fade   = "%s%s's %s faded from %s%s!"
local feast  = "%s%s prepares a %s!"
local gs     = "%s%s's %s consumed: %d heal!"
local ad     = "%s%s's %s consumed!"
local res    = "%s%s's %s resurrected %s%s!"
local portal = "%s%s opened a %s!"
local create = "%s%s is creating a %s!"
local dispel = "%s%s's %s failed to dispel %s%s's %s!"
local ss     = "%s died with a %s!"

local sacrifice   = {}
local soulstones  = {}
local ad_heal     = false
local topPriority = true

local HEROISM       = UnitFactionGroup("player") == "Horde" and 2825 or 32182   -- Horde = "Bloodlust" / Alliance = "Heroism"
local MISDIRECTION  = 34477                                                     -- "MD"           34477
local TRICKS        = 57934                                                     -- "Tricks"       57934
local RAISE_ALLY    = 61999                                                     -- "Raise Ally"
local HOLY_WRATH    = 48817                                                     -- "Holy Wrath"
local METAMORPHOSIS = 47241                                                     -- "Metamorphosis"
local REBIRTH       = GetSpellInfo(20484)                                       -- "Rebirth"
local HOP           = GetSpellInfo(1022)                                        -- "Hand of Protection"
local SOULSTONE     = GetSpellInfo(20707)                                       -- "Soulstone Resurrection"
local CABLES        = GetSpellInfo(54732)                                       -- "Defibrillate"

local raid = {}
local raidOrdered = {}

-- Upvalues
local UnitInBattleground, UnitInRaid, UnitInParty, UnitAffectingCombat, UnitName, UnitClass = UnitInBattleground, UnitInRaid, UnitInParty, UnitAffectingCombat, UnitName, UnitClass
local UnitHealthMax, UnitManaMax, GetSpellLink, GetTime, GetRaidTargetIndex, wipe, format = UnitHealthMax, UnitManaMax, GetSpellLink, GetTime, GetRaidTargetIndex, wipe, string.format
local SendChatMessage, SendAddonMessage, IsInInstance, GetRealNumRaidMembers, GetRealNumPartyMembers = SendChatMessage, SendAddonMessage, IsInInstance, GetRealNumRaidMembers, GetRealNumPartyMembers
local UnitIsFeignDeath, UnitIsConnected, GetNumRaidMembers, GetNumPartyMembers, GetRaidRosterInfo = UnitIsFeignDeath, UnitIsConnected, GetNumRaidMembers, GetNumPartyMembers, GetRaidRosterInfo

local debugSpell = {
   -- Paladin
   [20271] = true, -- Judgement of Light
   [53408] = true, -- Judgement of Wisdom
   [48785] = false, -- Flash Heal (for debug)
   -- Hunter (debug only)
   [53209] = false, -- Chimera Shot
   [49050] = false, -- Aimed Shot
   [49052] = false, -- Steady Shot
   [49001] = false, -- Serpent Sting
}

-- http://www.wowhead.com/?search=portal#abilities
local port = {
   -- Mage
   [53142] = true, -- Portal: Dalaran        (Alliance/Horde)
   [11419] = true, -- Portal: Darnassus      (Alliance)
   [32266] = true, -- Portal: Exodar         (Alliance)
   [11416] = true, -- Portal: Ironforge      (Alliance)
   [11417] = true, -- Portal: Orgrimmar      (Horde)
   [33691] = true, -- Portal: Shattrath      (Alliance)
   [35717] = true, -- Portal: Shattrath      (Horde)
   [32267] = true, -- Portal: Silvermoon     (Horde)
   [49361] = true, -- Portal: Stonard        (Horde)
   [10059] = true, -- Portal: Stormwind      (Alliance)
   [49360] = true, -- Portal: Theramore      (Alliance)
   [11420] = true, -- Portal: Thunder Bluff  (Horde)
   [11418] = true, -- Portal: Undercity      (Horde)
}

local rituals = {
   -- Mage
   [58659] = true,  -- Ritual of Refreshment
   -- Warlock
   [58887] = false, -- Ritual of Souls
   [698]   = true,  -- Ritual of Summoning
}

-- Combat only announce, require target
local spells = {
   -- Death Knight
   [49016] = false, -- Hysteria
   -- Paladin
   [6940]  = false, -- Hand of Sacrifice
   [20233] = false, -- Lay on Hands (Rank 1) [Fade]
   [20236] = false, -- Lay on Hands (Rank 2) [Fade]
   -- Priest
   [47788] = true,  -- Guardian Spirit
   [33206] = true,  -- Pain Suppression
}

local use = {
   -- Death Knight
   [48707] = false, -- Anti-Magic Shell
   [48792] = false, -- Icebound Fortitude
   [55233] = false, -- Vampiric Blood
   -- Druid
   [22812] = false, -- Barkskin
   [22842] = false, -- Frenzied Regeneration
   [61336] = false, -- Survival Instincts
   -- Paladin
   [498]   = true,  -- Divine Protection
   -- Warrior
   [12975] = false, -- Last Stand [Gain]
   [12976] = false, -- Last Stand [Fade]
   [871]   = true,  -- Shield Wall
}

local bots = {
   -- Engineering
   [22700] = true,  -- Field Repair Bot 74A
   [44389] = true,  -- Field Repair Bot 110G
   [67826] = true,  -- Jeeves
   [54710] = true,  -- MOLL-E
   [54711] = true,  -- Scrapbot
}

local bonus = {
   -- Death Knight
   [70654] = false, -- Blood Armor [4P T10]
   -- Druid
   [70725] = false, -- Enraged Defense [4P T10]
}

local feasts = {
   [57426] = true,  -- Fish Feast
   [57301] = false, -- Great Feast
   [66476] = false, -- Bountiful Feast
}
-- Combat only announce, spells that doesn't require target
local special = {
   -- Paladin
   [31821] = false, -- Aura Mastery
   -- Priest
   [64843] = false, -- Divine Hymn
   [64901] = false, -- Hymn of Hope
   -- Shaman
   [16190] = true,  -- Mana Tide Totem
}

local toys = {
   [61031] = true,  -- Toy Train Set
}

local fails = {
    -- Shambling Horror
   ["Enrage"]          = "Shambling Horror",
   -- The Lich King
   ["Necrotic Plague"] = false,
}

Flump:SetScript("OnEvent", function(self, event, ...)
   self[event](self, ...)
end)

local function send(msg)
   if(msg~=nil) then print("|cff39d7e5Flump:|r " .. msg) end
end

local function GetPartyType()
   if UnitInBattleground("player") then
      return "BATTLEGROUND"
   elseif UnitInRaid("player") then
      return "RAID"
   elseif UnitInParty("player") then
      return "PARTY"
   else
      return nil
   end
end

local function say(msg)
   if(msg~=nil) then SendChatMessage(msg, GetPartyType()) end
end

local function tableHasThisEntry(table, entry)
   assert(table~=nil, "bad argument #1: 'table' cannot be nil")
   assert(type(table) == "table", "bad argument #1: 'table' needs to be a table; instead what came was " .. tostring(type(table)))
   assert(entry~=nil, "bad argument #2: 'entry' cannot be nil")

   for _, value in ipairs(table) do
      if value == entry then
         return true
      end
   end
   return false
end

local function getTableLength(table)
   table = table or {}
   assert(type(table) == "table", "bad argument #1: 'table' needs to be a table; instead what came was " .. tostring(type(table)))
   local count = 0
   for _ in pairs(table) do count = count + 1 end
   return count
end

-- automatically sends an addon message to the appropriate channel (BATTLEGROUND, RAID or PARTY)
local function sendSync(prefix, msg)
   assert(prefix~=nil, "bad argument #1: 'prefix' cannot be nil")
   assert(type(prefix) == "string", "bad argument #1: 'prefix' needs to be a string; instead what came was " .. tostring(type(prefix)))
   local zoneType = select(2, IsInInstance())
   if zoneType == "pvp" or zoneType == "arena" then
      SendAddonMessage(prefix, msg, "BATTLEGROUND")
   elseif GetRealNumRaidMembers() > 0 then
      SendAddonMessage(prefix, msg, "RAID")
   elseif GetRealNumPartyMembers() > 0 then
      SendAddonMessage(prefix, msg, "PARTY")
   end
end

-- Addon is going to check how many messages got sent in the last 'gracePeriodForSendMessages', and if its equal or maxMessageSent then this function will return true, indicating that player cannot send more messages for now
local function isSendMessageGoingToMute()
   local now = GetTime()
   local count = 0

   for index, string in pairs(timeMessagesSent) do
      if (now <= (tonumber(string) + gracePeriodForSendMessages)) then
         count = count + 1
      else
         table.remove(timeMessagesSent,index)
      end
   end
   if count >= maxMessagesSent then return true
   else return false end
end

-- Frame update handler
local function onUpdate(this)
   if not Flump.db.enabled then return end
   if not queuedMessages then
      this:SetScript("OnUpdate", nil)
      return
   end
   if isSendMessageGoingToMute() then return end

   table.insert(timeMessagesSent, GetTime())
   say(queuedMessages[1])
   table.remove(queuedMessages,1)
   if getTableLength(queuedMessages)==0 then queuedMessages = nil end
end

local function queueMsg(msg)
   if(msg~=nil) then
      queuedMessages = queuedMessages or {}
      table.insert(queuedMessages,msg)
      Flump:SetScript("OnUpdate", onUpdate)
   end
end

function Flump:CHAT_MSG_WHISPER(_, srcName)
   if srcName == UnitName("player") then table.insert(timeMessagesSent, GetTime()) end
end

function Flump:CHAT_MSG_SAY(_, srcName)
   if srcName == UnitName("player") then table.insert(timeMessagesSent, GetTime()) end
end

function Flump:CHAT_MSG_PARTY(_, srcName)
   if srcName == UnitName("player") then table.insert(timeMessagesSent, GetTime()) end
end

function Flump:CHAT_MSG_RAID(_, srcName)
   if srcName == UnitName("player") then table.insert(timeMessagesSent, GetTime()) end
end

function Flump:CHAT_MSG_RAID_LEADER(_, srcName)
   if srcName == UnitName("player") then table.insert(timeMessagesSent, GetTime()) end
end

function Flump:CHAT_MSG_RAID_WARNING(_, srcName)
   if srcName == UnitName("player") then table.insert(timeMessagesSent, GetTime()) end
end

-- Remove spaces on start and end of string
local function trim(s)
   if s==nil then return "" end
   assert(type(s) == "string", "bad argument #1: 's' needs to be a string; instead what came was " .. tostring(type(s)))
   return string.match(s,'^()%s*$') and '' or string.match(s,'^%s*(.*%S)')
end

local function removeWords(myString, howMany)
   if (myString~=nil and howMany~=nil) then
      assert(type(myString) == "string", "bad argument #1: 'myString' needs to be a string; instead what came was " .. tostring(type(myString)))
      assert(type(howMany) == "number", "bad argument #2: 'howMany' needs to be a number; instead what came was " .. tostring(type(howMany)))
      assert(math.floor(howMany) == howMany, "bad argument #2: 'howMany' needs to be an integer")

      for i=1, howMany do
         myString = string.gsub(myString,"^(%s*%a+)","",1)
      end
      return trim(myString)
   end
   return ""
end
-- end of [string utils]

do
   local holyWrathCasts = {}

   local function icon(name)
      local n = GetRaidTargetIndex(name)
      return n and format("{rt%d}", n) or ""
   end

   local function canHolyWrathBeAnnounced(srcName, destName)
      if not srcName or destName~="Val'kyr Shadowguard" then return false end

      -- [Name] = Time
      for i, v in pairs(holyWrathCasts) do
         if(i == srcName) then
            if holyWrathCasts[i]~=nil and tonumber(holyWrathCasts[i]) and GetTime() < (tonumber(holyWrathCasts[i]) + 2) then
               return false
            end
         end
      end
      holyWrathCasts[srcName] = GetTime()
      return true
   end

   function Flump:COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, srcGUID, srcName, srcFlags, destGUID, destName, destFlags, spellID, spellName, school, ...)
      if not Flump:IsInRaid(srcName) then return end -- If the caster or player isn't in the group
      --if not UnitInRaid(srcName) then return end -- If the caster isn't in the group

      -- Track Demon Form and prevent player from trying to speak if transformed, temporarily assigning his role to somebody else
      if event == "SPELL_CAST_SUCCESS" or event == "SPELL_AURA_APPLIED" then
         if spellID == METAMORPHOSIS then
            if not tableHasThisEntry(playersUnableToSpeak,srcName) then table.insert(playersUnableToSpeak, srcName) end
            if srcName == UnitName("player") then
               if debug and event == "SPELL_AURA_APPLIED" then send("Meta cast") end
            else
               topPriority = false
               for i,name in ipairs(raidOrdered) do
                  if name and raid[name].priority and not tableHasThisEntry(playersUnableToSpeak, name) then
                     if debug and name == UnitName("player") then send(srcName .. " cast meta and you are the top priority after him, changing the prio to you temporarily.") end
                     topPriority = name==UnitName("player")
                     break
                  end
               end
            end
         end
      elseif event == "SPELL_AURA_REMOVED" then
         if spellID == METAMORPHOSIS then
            for i,v in ipairs(playersUnableToSpeak) do
               if v==srcName then table.remove(playersUnableToSpeak, i) end
            end
            if srcName == UnitName("player") then
               if debug then send("Meta fade") end
            else
               topPriority = false
               for i,name in ipairs(raidOrdered) do
                  if name and raid[name].priority and not tableHasThisEntry(playersUnableToSpeak, name) then
                     if debug then
                        if name==UnitName("player") then send("You are the top priority again!")
                        else send(send(srcName .. " meta faded, so he can speak again, reassigning priorities back to him.")) end
                     end
                     topPriority = name==UnitName("player")
                     break
                  end
               end
            end
         end
      end
      if not topPriority or tableHasThisEntry(playersUnableToSpeak, UnitName("player")) then return end

      if Flump:IsInRaid(destName) then -- If the target is in the raid group
         if spellName == SOULSTONE and event == "SPELL_AURA_REMOVED" then
            if not soulstones[destName] then soulstones[destName] = {} end
            soulstones[destName].time = GetTime()
         elseif spellID == 27827 and event == "SPELL_AURA_APPLIED" then
            soulstones[destName] = {}
            soulstones[destName].SoR = true -- Workaround for Spirit of Redemption issue
         elseif event == "UNIT_DIED" and soulstones[destName] and not UnitIsFeignDeath(destName) then
            if not soulstones[destName].SoR and (GetTime() - soulstones[destName].time) < 2 then
               -- [X] died with a Soulstone!
               queueMsg(ss:format(destName, GetSpellLink(6203)))
               SendChatMessage(ss:format(destName, GetSpellLink(6203)), "RAID_WARNING")
            end
            soulstones[destName] = nil
         end
      end

      if debug and debugSpell[spellID] and event == "SPELL_CAST_SUCCESS" then
         --send("spell " .. GetSpellLink(spellID) .. " was casted by " .. srcName)
         if destName~=nil then queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
         else queueMsg(castnt:format(icon(srcName), srcName, GetSpellLink(spellID))) end
         return
      end

      if UnitAffectingCombat(srcName) then -- If the caster is in combat
         if event == "SPELL_CAST_SUCCESS" then
            if spells[spellID] then
               queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] cast [Y] on [Z]
            elseif spellID == 19752 then -- Don't want to announce when it fades, so
               queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- Divine Intervention
            elseif use[spellID] and UnitHealthMax(srcName) >= MIN_TANK_HP then
               queueMsg(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used [Y]
               --elseif spellID == 64205 then  -- Workaround for Divine Sacrifice issue
               --   queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used Divine Sacrifice
               --   sacrifice[srcGUID] = true
            elseif special[spellID] then -- Workaround for spells which aren't tanking spells
               queueMsg(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used Aura Mastery
            elseif DIVINE_PLEA and spellID == 54428 and UnitManaMax(srcName) >= MIN_HEALER_MANA then
               queueMsg(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used Divine Plea
            end

         elseif event == "SPELL_AURA_APPLIED" then -- [X] cast [Y] on [Z]
            if spellID == 20233 or spellID == 20236 then -- Improved Lay on Hands (Rank 1/Rank 2)
               queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
            elseif bonus[spellID] then
               queueMsg(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used [Z] (bonus)
            elseif spellID == 66233 then
               if not ad_heal then -- If the Ardent Defender heal message hasn't been sent already
                  queueMsg(ad:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X]'s [Y] consumed
               end
               ad_heal = false
            elseif spellName == HOP and UnitHealthMax(destName) >= MIN_TANK_HP then
               queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] cast Hand of Protection on [Z]
            end

         elseif event == "SPELL_HEAL" then
            if spellID == 48153 or spellID == 66235 then -- Guardian Spirit / Ardent Defender
               local amount = ...
               ad_heal = true
               queueMsg(gs:format(icon(srcName), srcName, GetSpellLink(spellID), amount)) -- [X]'s [Y] consumed: [Z] heal
            end

         elseif event == "SPELL_AURA_REMOVED" then
            if spells[spellID] or (spellName == HOP and UnitHealthMax(destName) >= MIN_TANK_HP) then
               queueMsg(fade:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X]'s [Y] faded from [Z]
            elseif use[spellID] and UnitHealthMax(srcName) >= MIN_TANK_HP then
               queueMsg(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- [X] faded from [Y]
            elseif bonus[spellID] then
               queueMsg(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- [X] faded from [Y] (bonus)
               --elseif spellID == 64205 and sacrifice[destGUID] then
               --   queueSend(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- Divine Sacrifice faded from [Y]
               --   sacrifice[destGUID] = nil
            elseif special[spellID] then -- Workaround for spells which aren't tanking spells
               queueMsg(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- Aura Mastery faded from [X]
            elseif DIVINE_PLEA and spellID == 54428 and UnitManaMax(srcName) >= MIN_HEALER_MANA then
               queueMsg(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- Divine Plea faded from [X]
            end
         end
      end

      if event == "SPELL_CAST_SUCCESS" then
         if spellID == HEROISM then
            queueMsg(used:format(icon(srcName), srcName, GetSpellLink(spellID)))  -- [X] used [Y] -- Heroism/Bloodlust
         elseif spellID == MISDIRECTION or spellID == TRICKS then
            queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] used Misdirection on [Z]
         elseif spellID == RAISE_ALLY then
            queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] used Raise Ally on [Z]
         elseif bots[spellID] then
            queueMsg(bot:format(icon(srcName), srcName, GetSpellLink(spellID)))   -- [X] used a [Y] -- Bots
         elseif rituals[spellID] then
            queueMsg(create:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] is creating a [Z] -- Rituals
         end

      elseif event == "SPELL_DAMAGE" then
         if spellID == HOLY_WRATH and destName~=nil and canHolyWrathBeAnnounced(srcName, destName) then
            queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
         end

      elseif event == "SPELL_AURA_APPLIED" then -- Check name instead of ID to save checking all ranks
         -- Hand of Sacrifice
         --if spells[spellID] and spellID == 6940 then
         --  end(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
         --else
         if spellName == SOULSTONE then
            local _, class = UnitClass(srcName)
            if class == "WARLOCK" then -- Workaround for Spirit of Redemption issue
               queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(6203), icon(destName), destName)) -- [X] cast [Y] on [Z] -- Soulstone
            end
         end

      elseif event == "SPELL_CREATE" then
         if port[spellID] then
            queueMsg(portal:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] opened a [Z] -- Portals
         elseif toys[spellID] then
            queueMsg(bot:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used a [Z]
         end

      elseif event == "SPELL_CAST_START" then
         if feasts[spellID] then
            queueMsg(feast:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] prepares a [Z] -- Feasts
         end

      elseif event == "SPELL_RESURRECT" then
         if spellName == REBIRTH then -- Check name instead of ID to save checking all ranks
            queueMsg(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] cast [Y] on [Z] -- Rebirth
         elseif spellName == CABLES then
            queueMsg(res:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
         end

      elseif event == "SPELL_DISPEL_FAILED" then
         local extraID, extraName = ...
         local target = fails[extraName]
         if target or destName == target then
            queueMsg(dispel:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName, GetSpellLink(extraID))) -- [W]'s [X] failed to dispel [Y]'s [Z]
         end
      end
   end
end

local function splitVersion(version, delimiter)
   if delimiter == nil then
      delimiter = "%s"
   end
   local t={}
   for str in string.gmatch(version, "([^"..delimiter.."]+)") do
      table.insert(t, tonumber(str or 0))
   end
   return t
end

-----------------------------
--  Ordering Raid Members  --
-----------------------------
do
   local function compareVersions(v1,v2)
      if not v1 then return false end
      if not v2 then return true end

      local a = splitVersion(v1,".")
      local b = splitVersion(v2,".")

      local max = math.max(getTableLength(a), getTableLength(b), 1)
      for i=1, max do
         if not a[i] or not b[i] then return a[i]~=nil end
         if a[i]~=b[i] then return a[i] > b[i] end
      end
      return true
   end
   local function comparePriorities(a1,b2)
      local a = raid[a1]
      local b = raid[b2]

      if not a then return false end
      if not b then return true end
      if not a.name then return false end
      if not b.name then return true end
      if not UnitIsConnected(a.name) then return false end
      if not UnitIsConnected(b.name) then return true end

      if a.priority and b.priority then
         if a.version and b.version and a.version~=b.version then return compareVersions(a.version,b.version) end
         if a.rank and b.rank and a.rank~=b.rank then return a.rank > b.rank end
         if a.priority and b.priority and a.priority~=b.priority then return a.priority > b.priority end
         if a.id and b.id and a.id~=b.id then return a.id > b.id end
      end
      return a.priority~=nil
   end
   function Flump:ReorderPriorities()
      if not raid then return end
      raidOrdered = {}

      for k,v in pairs(raid) do
         if v~=nil and v.id then table.insert(raidOrdered,k) end
      end
      local length = getTableLength(raidOrdered)
      if length == 0 then return end
      if length > 1 then table.sort(raidOrdered,comparePriorities) end

      if debug then
         send("Table of priorities")
         for i,n in ipairs(raidOrdered) do send(format("%s. %s (%s - %s)",i,n,(raid[n].priority or 0),(raid[n].version or 0))) end
      end

      if raidOrdered[1] == UnitName("player") then
         topPriority = true
      else
         topPriority = false
      end
   end
end

-----------------------------
--  Handle Incoming Syncs  --
-----------------------------
do
   local syncHandlers = {}

   syncHandlers["Flump-Prio"] = function(msg, channel, sender)
      if msg == "Hi!" and Flump.db.enabled and Flump:IsPlayerInsideValidInstance() then
         sendSync("Flump-Prio", Flump.Priority)
      elseif msg ~= "Hi!" then
         local priority = tonumber(msg)
         if sender and sender~="" and (priority==nil or type(priority) == "number") then
            --if debug then send(format("%s sent you his priority (%s)",sender,(priority or 0))) end
            raid[sender] = raid[sender] or {}
            raid[sender].priority = priority
            if sender~=UnitName("player") and priority == Flump.Priority then
               Flump.Priority = math.random(MAX_PRIORITY)
               if Flump.db.enabled then sendSync("Flump-Prio", Flump.Priority) end
            end
            Flump:ReorderPriorities()
         end
      end
   end

   syncHandlers["Flump-Ver"] = function(msg, channel, sender)
      if msg == "Hi!" then
         sendSync("Flump-Ver", Flump.Version)
      elseif msg ~= "Hi!" then
         if msg and msg~="" and sender and sender~="" and raid and raid[sender] then
            raid[sender].version = msg
         end
      end
   end

   function Flump:CHAT_MSG_ADDON(prefix, msg, channel, sender)
      if msg and channel ~= "WHISPER" and channel ~= "GUILD" then
         local handler = syncHandlers[prefix]
         if handler then handler(msg, channel, sender) end
      --elseif msg and channel == "WHISPER" and self:GetRaidUnitId(sender) ~= "none" then
      --   local handler = whisperSyncHandlers[prefix]
      --   if handler then handler(msg, channel, sender) end
      end
   end
end

---------------------------
--  Raid/Party Handling  --
---------------------------
do
   local inRaid = false

   function Flump:RAID_ROSTER_UPDATE()
      if GetNumRaidMembers() >= 1 then
         if not inRaid then
            inRaid = true
            sendSync("Flump-Ver", "Hi!")
            sendSync("Flump-Prio", "Hi!")
         end
         for i = 1, GetNumRaidMembers() do
            local name, rank, subgroup, _, _, fileName,_,online = GetRaidRosterInfo(i)
            if name and inRaid then
               raid[name] = raid[name] or {}
               raid[name].name = name
               raid[name].rank = rank
               raid[name].subgroup = subgroup
               raid[name].class = fileName
               raid[name].id = "raid"..i
               if raid[name].priority~=nil and not online then raid[name].priority=nil end
               raid[name].updated = true
            end
         end
         -- removing players that left pt
         for i, v in pairs(raid) do
            if not v.updated then
               raid[i] = nil
            else
               v.updated = nil
            end
         end
         Flump:ReorderPriorities()
      else
         inRaid = false
         topPriority = true
         for i,_ in pairs(raid) do raid[i] = nil end
         raid = {}
      end
   end

   function Flump:PARTY_MEMBERS_CHANGED()
      if GetNumRaidMembers() > 0 then return end
      if GetNumPartyMembers() >= 1 then
         if not inRaid then
            inRaid = true
            sendSync("Flump-Ver", "Hi!")
            sendSync("Flump-Prio", "Hi!")
         end
         for i = 0, GetNumPartyMembers() do
            local id
            if (i == 0) then
               id = "player"
            else
               id = "party"..i
            end
            local name, server = UnitName(id)
            local rank, _, fileName = UnitIsPartyLeader(id), UnitClass(id)
            if server and server ~= ""  then
               name = name.."-"..server
            end
            local online = UnitIsConnected(name) and true or false
            raid[name] = raid[name] or {}
            raid[name].name = name
            if rank then
               raid[name].rank = 2
            else
               raid[name].rank = 0
            end
            raid[name].class = fileName
            raid[name].id = id
            if raid[name].priority~=nil and not online then raid[name].priority=nil end
            raid[name].updated = true
         end
         -- removing players that left pt
         for i, v in pairs(raid) do
            if not v.updated then
               raid[i] = nil
            else
               v.updated = nil
            end
         end
         Flump:ReorderPriorities()
      else
         inRaid = false
         topPriority = true
         for i,_ in pairs(raid) do raid[i] = nil end
         raid = {}
      end
   end

   function Flump:IsInRaid(name)
      return name==UnitName("player") and inRaid or (raid[name] and raid[name].id~=nil)
   end

   function Flump:GetRaidRank(name)
      name = name or UnitName("player")
      return (raid[name] and raid[name].rank) or 0
   end

   function Flump:GetRaidSubgroup(name)
      name = name or UnitName("player")
      return (raid[name] and raid[name].subgroup) or 0
   end

   function Flump:GetRaidClass(name)
      name = name or UnitName("player")
      return (raid[name] and raid[name].class) or "UNKNOWN"
   end

   function Flump:GetRaidUnitId(name)
      name = name or UnitName("player")
      return (raid[name] and raid[name].id) or "none"
   end

   function Flump:ResetRaid()
      for i, v in pairs(raid) do
         raid[i] = nil
      end
      raid = {}
      inRaid = false
   end
end

function Flump:PLAYER_REGEN_ENABLED()
   wipe(playersUnableToSpeak)
   wipe(timeMessagesSent)
end

function Flump:IsPlayerInsideValidInstance()
   local _, instance = IsInInstance()
   if (instance == "raid" and ENABLE_IN_RAID) or (instance == "party" and ENABLE_IN_DUNGEONS) then
      return true
   end
   return false
end

function Flump:RegisterAddonEvents()
   if debug then send("Registering \"only if inside instance\" addon events") end
   self:RegisterEvents(
      "COMBAT_LOG_EVENT_UNFILTERED",
      "CHAT_MSG_WHISPER",
      "CHAT_MSG_SAY",
      "CHAT_MSG_PARTY",
      "CHAT_MSG_RAID",
      "CHAT_MSG_RAID_LEADER",
      "CHAT_MSG_RAID_WARNING"
   )
   -- Reinforming people about your priority if it got modified when you unregistered it or some other reason
   if not debug then
      if(raid and raid[UnitName("player")] and Flump.Priority ~= raid[UnitName("player")].priority and UnitHealth("player") > 1) then
         if debug then send("Reinforming people about your priority if you nulled it when your events got unregistered") end
         sendSync("Flump-Prio", Flump.Priority)
      end
   -- But if you have debug on, this function will be called regardless of whenever you are inside the instance or not, so this prevents dead players with debug on from stealing place of those who can actually speak
   elseif UnitHealth("player") <= 1 then
      sendSync("Flump-Prio", nil)
   end
end

function Flump:UnregisterAddonEvents()
   if debug then send("Unregistering \"only if inside instance\" addon events") end
   self:UnregisterEvents(
      "COMBAT_LOG_EVENT_UNFILTERED",
      "CHAT_MSG_WHISPER",
      "CHAT_MSG_SAY",
      "CHAT_MSG_PARTY",
      "CHAT_MSG_RAID",
      "CHAT_MSG_RAID_LEADER",
      "CHAT_MSG_RAID_WARNING"
   )
   -- If the player debug mode is off, or if he is dead/ghost, then send nil as priority when unregistering the events to tell other people that this player cannot speak
   if not debug or UnitHealth("player") <= 1 then sendSync("Flump-Prio", nil) end
   wipe(timeMessagesSent)
end

function Flump:CheckEnable()
   if self.db.enabled and (self:IsPlayerInsideValidInstance() or debug) then
      self:RegisterAddonEvents()
   else
      self:UnregisterAddonEvents()
   end
end

function Flump:PLAYER_ENTERING_WORLD()
   self:CheckEnable()
end

do
   local function sortVersion(v1, v2)
      if not v1 then return false end
      if not v2 then return true end
      if not v1.version then return false end
      if not v2.version then return true end
      if not v1.priority then return false end
	  if not v2.priority then return true end

      local a = splitVersion(v1.version,".")
      local b = splitVersion(v2.version,".")

      local max = math.max(getTableLength(a), getTableLength(b), 1)
      for i=1, max do
         if not a[i] or not b[i] then return a[i]~=nil end
         if a[i]~=b[i] then return a[i] > b[i] end
      end
      return false
   end

   function Flump:ShowVersions()
      local sortedTable = {}
      for i, v in pairs(raid) do
         if v~=nil then table.insert(sortedTable, v) end
      end
      print("|cff2d61e3<|r|cff4da6ebFlump|r|cff2d61e3>|r |cff39d7e5Flump - Versions|r")
      if getTableLength(sortedTable) > 1 then table.sort(sortedTable, sortVersion) end
      if getTableLength(sortedTable) == 0 then
         if Flump.Version and Flump.db.enabled then
            print(format("|cff2d61e3<|r|cff4da6ebFlump|r|cff2d61e3>|r |cff39d7e5%s|r: %s", UnitName("player"), Flump.Version))
         else
            print(format("|cff2d61e3<|r|cff4da6ebFlump|r|cff2d61e3>|r |cff39d7e5%s|r: %s (disabled)", UnitName("player"), Flump.Version))
         end
      else
         for i, v in ipairs(sortedTable) do
            local msg
            if v.version then
               msg = format("|cff2d61e3<|r|cff4da6ebFlump|r|cff2d61e3>|r |cff39d7e5%s|r: %s", v.name, v.version)
               if not v.priority and UnitIsConnected(v.name) then
                  msg = msg .. " (disabled or outside instance)"
               elseif not UnitIsConnected(v.name) then
                  msg = msg .. " (offline)"
               end
            else
               msg = format("|cff2d61e3<|r|cff4da6ebFlump|r|cff2d61e3>|r |cff39d7e5%s|r: Flump not installed", v.name)
            end
            print(msg)
         end
         for i = #sortedTable, 1, -1 do
            if not sortedTable[i].version then
               table.remove(sortedTable, i)
            end
         end
      end
     print(format("|cff2d61e3<|r|cff4da6ebFlump|r|cff2d61e3>|r |cff39d7e5Found|r |cfff0a71f%s|r |cff39d7e5player%s with Flump|r",(#sortedTable > 1 and #sortedTable or 1),(#sortedTable > 1 and "s" or "")))
      for i = #sortedTable, 1, -1 do
         sortedTable[i] = nil
      end
   end
end

----------------------
--  Slash Commands  --
----------------------
do
   local function showHelp()
      send("Please use one of the following: on, off, toggle, version.")
   end

   local function toggleAddon(state)
      if state==nil then state = not Flump.db.enabled end
      if state then
         Flump.db.enabled = true
         topPriority = true
         Flump:RegisterEvents(
            "PLAYER_ENTERING_WORLD",
            "PLAYER_REGEN_ENABLED"
         )
         Flump:ResetRaid()
         Flump:RAID_ROSTER_UPDATE()
         Flump:PARTY_MEMBERS_CHANGED()
         Flump:CheckEnable()
         send("|cff00ff00on|r")
      else
         Flump.db.enabled = false
         Flump:UnregisterAddonEvents()
         Flump:UnregisterEvents(
            "PLAYER_ENTERING_WORLD",
            "PLAYER_REGEN_ENABLED"
         )
         Flump:CheckEnable()
         sendSync("Flump-Prio", nil)
         send("|cffff0000off|r")
      end
   end

   local function toggleDebug()
      debug = not debug
      Flump.db.debug = debug
      Flump:CheckEnable()
      send("debug mode turned " .. (debug and "|cff00ff00on|r" or "|cffff0000off|r"))
   end

   local function showPriority()
      if debug then send("My priority is " .. Flump.Priority) end
   end

   local function setPriority(extra)
      if debug and extra~=nil and tonumber(extra)~=nil then
         Flump.Priority = tonumber(extra)
         send("priority set to " .. extra)
         sendSync("Flump-Prio", Flump.Priority)
      end
   end

   local function listPriorities()
      if not debug then return end
      send("Table of priorities (TP)")
      for i,n in ipairs(raidOrdered) do send(format("%s. %s (%s - %s)",i,n,(raid[n].priority or 0),(raid[n].version or 0))) end
   end

   function Flump:SlashCommand(typed)
      local cmd = string.match(typed,"^(%w+)") -- Gets the first word the user has typed
      if cmd~=nil then cmd = cmd:lower() end   -- And makes it lower case
      local extra = removeWords(typed, 1)
      if extra~=nil then extra = extra:lower() end

      if(cmd=="help" or cmd=="?" or cmd=="" or cmd==nil) then showHelp()
      elseif (cmd=="toggle") then toggleAddon()
      elseif (cmd=="on" or cmd=="enable") then toggleAddon(true)
      elseif (cmd=="off" or cmd=="disable") then toggleAddon(false)
      elseif (cmd=="prio" or cmd=="priority" or cmd=="p") then showPriority()
      elseif (cmd=="setprio" or cmd=="setpriority" or cmd=="sp") then setPriority(extra)
      elseif (cmd=="priotable" or cmd=="pt" or cmd=="tp") then listPriorities()
      elseif (cmd=="ver" or cmd=="version") then Flump:ShowVersions()
      elseif (cmd=="debug") then toggleDebug()
      end
   end
end

--------------
--  OnLoad  --
--------------

function Flump:RegisterEvents(...)
   for i = 1, select("#", ...) do
      local ev = select(i, ...)
      Flump:RegisterEvent(ev)
   end
end

function Flump:UnregisterEvents(...)
   for i = 1, select("#", ...) do
      local ev = select(i, ...)
      Flump:UnregisterEvent(ev)
   end
end

function Flump:ADDON_LOADED(addon)
   if addon ~= "Flump" then return end
   Flump.Priority = math.random(MAX_PRIORITY)

   FlumpDB = FlumpDB or { enabled = true }
   self.db = FlumpDB
   debug = self.db.debug or debug
   Flump.Version = GetAddOnMetadata("Flump", "Version")

   SLASH_FLUMP1 = "/flump"
   SlashCmdList.FLUMP = function(cmd) self:SlashCommand(cmd) end
   if debug then send("remember that debug mode is |cff00ff00ON|r.") end

   self:RegisterEvents(
      "RAID_ROSTER_UPDATE",
      "PARTY_MEMBERS_CHANGED",
      "CHAT_MSG_ADDON"
   )
   if Flump.db.enabled then
      self:RegisterEvents(
         "PLAYER_ENTERING_WORLD",
         "PLAYER_REGEN_ENABLED"
      )
   end
   self:RAID_ROSTER_UPDATE()
   self:PARTY_MEMBERS_CHANGED()
end

Flump:RegisterEvent("ADDON_LOADED")