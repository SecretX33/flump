local Flump = CreateFrame("frame")

local OUTPUT          = "RAID"
local RAID_OUTPUT     = "RAID"    -- Which channel should the announcements be sent to if the player is in a raid group?
local PARTY_OUTPUT    = "PARTY"   -- Which channel should the announcements be sent to if the player is in a party group?
local MIN_TANK_HP     = 55000     -- How much health must a player have to be considered a tank?
local MIN_HEALER_MANA = 20000     -- How much mana must a player have to be considered a healer?
local DIVINE_PLEA     = false     -- Announce when (holy) Paladins cast Divine Plea? (-50% healing)

-- Chat Parameters
local maxMessagesSent             = 4   -- Max messages that can be send at once before getting muted by the server
local gracePeriodForSendMessages  = 1.2   -- Assuming that we can send at most 'maxMessagesSent' every 'gracePeriodForSendMessages' seconds
-- Chat Variables
local timeMessagesSent            = {}
local queuedMessages

local debug    = false
local alwayson = false
local status   = "|cff39d7e5Flump: %s|r"

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
local instanceType
local priority
local lastSentPriority
local topPriority = true
local playerIsUnderMetamorphosis = false

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

local addonVersion

-- Upvalues
local UnitInBattleground, UnitInRaid, UnitAffectingCombat = UnitInBattleground, UnitInRaid, UnitAffectingCombat
local UnitHealthMax, UnitManaMax, GetSpellLink, format = UnitHealthMax, UnitManaMax, GetSpellLink, string.format

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

local bots = {
   -- Engineering
   [22700] = true,  -- Field Repair Bot 74A
   [44389] = true,  -- Field Repair Bot 110G
   [67826] = true,  -- Jeeves
   [54710] = true,  -- MOLL-E
   [54711] = true,  -- Scrapbot
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

local function say(msg)
   if(msg~=nil) then SendChatMessage(msg, OUTPUT) end
end

local function getTableLength(table)
   local count = 0
   for _ in pairs(table) do count = count + 1 end
   return count
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

local function queueSend(msg)
   if(msg~=nil) then
      queuedMessages = queuedMessages or {}
      table.insert(queuedMessages,msg)
      Flump:SetScript("OnUpdate", onUpdate)
   end
end

-- Remove spaces on start and end of string
local is_int = function(n)
   return (type(n) == "number") and (math.floor(n) == n)
end

local function trim(s)
   return string.match(s,'^()%s*$') and '' or string.match(s,'^%s*(.*%S)')
end

local function removeWords(myString, numberOfWords)
   if (myString~=nil and numberOfWords~=nil) then
      if is_int(numberOfWords) then
         for i=1, numberOfWords do
            myString = string.gsub(myString,"^(%s*%a+)","",1)
         end
         return trim(myString)
      else send("numberOfWords arg came, it's not nil BUT it's also NOT an integer, report this, type = " .. tostring(type(numberOfWords))) end
   end
   return ""
end
-- end of [string utils]

local function icon(name)
   local n = GetRaidTargetIndex(name)
   return n and format("{rt%d}", n) or ""
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

local function sendAddonMessage()
   local channel = GetPartyType()
   if not channel then return end
   local prio
   -- Player needs to have the addon on and to be inside the raid to be able to send messages
   if (alwayson and not playerIsUnderMetamorphosis) or (Flump.db.enabled and instanceType=="raid" and not playerIsUnderMetamorphosis) then
      prio = tostring(priority)
   else
      prio = "0"
   end
   if(prio~="0" or lastSentPriority~=0) then
      SendAddonMessage("Flump", prio, channel)
      lastSentPriority = tonumber(prio)
   end
end

local function checkIfAddonShouldBeEnabled()
   local playerIsInRaidGroup = (not UnitInBattleground("player") and UnitInRaid("player"))
   local state = false
   local reason = "addonOff"

   if debug and Flump.db.enabled then
      if not topPriority then send("You are not the top priority. :(")
      elseif playerIsUnderMetamorphosis then send("You are top priority but you are transformed so your top priority status is temporarily revogated.")
      else send("You are the top priority! ;)") end
   end

   if not Flump.db.enabled or (not playerIsInRaidGroup and not alwayson) then
      if not playerIsInRaidGroup then
         reason = "notInRaidGroup"
      end
      Flump:UnregisterEvent("CHAT_MSG_ADDON")
      Flump:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
      Flump:UnregisterEvent("PLAYER_REGEN_DISABLED")
      Flump:UnregisterEvent("RAID_ROSTER_UPDATE")
   else
      if playerIsInRaidGroup then Flump:RegisterEvent("RAID_ROSTER_UPDATE")
      else Flump:UnregisterEvent("RAID_ROSTER_UPDATE") end

      if (instanceType == "raid" and topPriority) or (alwayson and topPriority) then
         if (instanceType == "raid" and topPriority) then reason = "topPriority"
         elseif (alwayson and topPriority) then reason = "alwaysOnAndTopPriority" end
         --if debug then send("Addon is on because debug mode is on") end
         Flump:RegisterEvent("CHAT_MSG_ADDON")
         Flump:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
         Flump:RegisterEvent("PLAYER_REGEN_DISABLED")
         -- player is not top priority or is not inside the raid
      elseif not topPriority or not instanceType == "raid" then
         if not instanceType == "raid" then
            reason = "notInsideInstance"
         elseif not topPriority then
            reason = "notTopPriority"
         end
         Flump:RegisterEvent("CHAT_MSG_ADDON")
         if not playerIsUnderMetamorphosis then Flump:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end
         Flump:RegisterEvent("PLAYER_REGEN_DISABLED")
      end
   end

   return state, reason
end

function Flump:COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, srcGUID, srcName, srcFlags, destGUID, destName, destFlags, spellID, spellName, school, ...)
   if not UnitInRaid(srcName) then return end -- If the caster isn't in the raid group

   -- Track Demon Form and prevent player from trying to speak if transformed, temporarily assigning his role to somebody else
   if event == "SPELL_CAST_SUCCESS" or event == "SPELL_AURA_APPLIED" then
      if spellID == METAMORPHOSIS and srcName == UnitName("player") then
         playerIsUnderMetamorphosis = true
         sendAddonMessage()
         if debug and event == "SPELL_AURA_APPLIED" then send("Meta cast") end
      end
   elseif event == "SPELL_AURA_REMOVED" then
      if spellID == METAMORPHOSIS and srcName == UnitName("player") then
         playerIsUnderMetamorphosis = false
         sendAddonMessage()
         if debug then send("Meta fade") end
      end
   end
   if playerIsUnderMetamorphosis then return end

   --getOutput(srcName, destName)
   --if not OUTPUT return end
   -- [X] died with a Soulstone!
   if UnitInRaid(destName) then -- If the target isn't in the raid group
      if spellName == SOULSTONE and event == "SPELL_AURA_REMOVED" then
         if not soulstones[destName] then soulstones[destName] = {} end
         soulstones[destName].time = GetTime()
      elseif spellID == 27827 and event == "SPELL_AURA_APPLIED" then
         soulstones[destName] = {}
         soulstones[destName].SoR = true -- Workaround for Spirit of Redemption issue
      elseif event == "UNIT_DIED" and soulstones[destName] and not UnitIsFeignDeath(destName) then
         if not soulstones[destName].SoR and (GetTime() - soulstones[destName].time) < 2 then
            queueSend(ss:format(destName, GetSpellLink(6203)))
            SendChatMessage(ss:format(destName, GetSpellLink(6203)), "RAID_WARNING")
         end
         soulstones[destName] = nil
      end
   end

   if debug and debugSpell[spellID] then
      send("spell " .. GetSpellLink(spellID) .. " was casted by " .. srcName)
      if destName~=nil then queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
      else queueSend(castnt:format(icon(srcName), srcName, GetSpellLink(spellID))) end
      return
   end

   if UnitAffectingCombat(srcName) then -- If the caster is in combat
      if event == "SPELL_CAST_SUCCESS" then
         if spellID == HOLY_WRATH then
            queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID)))
         elseif spells[spellID] then
            queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] cast [Y] on [Z]
         elseif spellID == 19752 then -- Don't want to announce when it fades, so
            queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- Divine Intervention
         elseif use[spellID] and UnitHealthMax(srcName) >= MIN_TANK_HP then
            queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used [Y]
         --elseif spellID == 64205 then  -- Workaround for Divine Sacrifice issue
         --   queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used Divine Sacrifice
         --   sacrifice[srcGUID] = true
         elseif special[spellID] then -- Workaround for spells which aren't tanking spells
            queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used Aura Mastery
         elseif DIVINE_PLEA and spellID == 54428 and UnitManaMax(srcName) >= MIN_HEALER_MANA then
            queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used Divine Plea
         end
         
      elseif event == "SPELL_AURA_APPLIED" then -- [X] cast [Y] on [Z]
         if spellID == 20233 or spellID == 20236 then -- Improved Lay on Hands (Rank 1/Rank 2)
            queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
         elseif bonus[spellID] then
            queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used [Z] (bonus)
         elseif spellID == 66233 then
             if not ad_heal then -- If the Ardent Defender heal message hasn't been sent already
            queueSend(ad:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X]'s [Y] consumed
             end
             ad_heal = false
         elseif spellName == HOP and UnitHealthMax(destName) >= MIN_TANK_HP then
            queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] cast Hand of Protection on [Z]
         end
      
      elseif event == "SPELL_HEAL" then
         if spellID == 48153 or spellID == 66235 then -- Guardian Spirit / Ardent Defender
            local amount = ...
            ad_heal = true
            queueSend(gs:format(icon(srcName), srcName, GetSpellLink(spellID), amount)) -- [X]'s [Y] consumed: [Z] heal
         end
         
      elseif event == "SPELL_AURA_REMOVED" then
         if spells[spellID] or (spellName == HOP and UnitHealthMax(destName) >= MIN_TANK_HP) then
            queueSend(fade:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X]'s [Y] faded from [Z]
         elseif use[spellID] and UnitHealthMax(srcName) >= MIN_TANK_HP then
            queueSend(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- [X] faded from [Y]
         elseif bonus[spellID] then
            queueSend(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- [X] faded from [Y] (bonus)
         --elseif spellID == 64205 and sacrifice[destGUID] then
         --   queueSend(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- Divine Sacrifice faded from [Y]
         --   sacrifice[destGUID] = nil
         elseif special[spellID] then -- Workaround for spells which aren't tanking spells
            queueSend(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- Aura Mastery faded from [X]
         elseif DIVINE_PLEA and spellID == 54428 and UnitManaMax(srcName) >= MIN_HEALER_MANA then
            queueSend(sw:format(GetSpellLink(spellID), icon(srcName), srcName)) -- Divine Plea faded from [X]
         end
      end
   end
   
   if event == "SPELL_CAST_SUCCESS" then
      if spellID == HEROISM then
         queueSend(used:format(icon(srcName), srcName, GetSpellLink(spellID)))  -- [X] used [Y] -- Heroism/Bloodlust
      elseif spellID == MISDIRECTION or spellID == TRICKS then
         queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] used Misdirection on [Z]
      elseif spellID == RAISE_ALLY then
         queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] used Raise Ally on [Z]
      elseif bots[spellID] then
         queueSend(bot:format(icon(srcName), srcName, GetSpellLink(spellID)))   -- [X] used a [Y] -- Bots
      elseif rituals[spellID] then
         queueSend(create:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] is creating a [Z] -- Rituals
      end
      
   elseif event == "SPELL_AURA_APPLIED" then -- Check name instead of ID to save checking all ranks
      -- Hand of Sacrifice
      --if spells[spellID] and spellID == 6940 then
      --  end(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
      --else
      if spellName == SOULSTONE then
         local _, class = UnitClass(srcName)
         if class == "WARLOCK" then -- Workaround for Spirit of Redemption issue
            queueSend(cast:format(icon(srcName), srcName, GetSpellLink(6203), icon(destName), destName)) -- [X] cast [Y] on [Z] -- Soulstone
         end
      end

   elseif event == "SPELL_CREATE" then
      if port[spellID] then
         queueSend(portal:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] opened a [Z] -- Portals
      elseif toys[spellID] then
         queueSend(bot:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] used a [Z]
      end
      
   elseif event == "SPELL_CAST_START" then
      if feasts[spellID] then
         queueSend(feast:format(icon(srcName), srcName, GetSpellLink(spellID))) -- [X] prepares a [Z] -- Feasts
      end
      
   elseif event == "SPELL_RESURRECT" then
      if spellName == REBIRTH then -- Check name instead of ID to save checking all ranks
         queueSend(cast:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName)) -- [X] cast [Y] on [Z] -- Rebirth
      elseif spellName == CABLES then
         queueSend(res:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName))
      end   
      
   elseif event == "SPELL_DISPEL_FAILED" then
      local extraID, extraName = ...
      local target = fails[extraName]
      if target or destName == target then
         queueSend(dispel:format(icon(srcName), srcName, GetSpellLink(spellID), icon(destName), destName, GetSpellLink(extraID))) -- [W]'s [X] failed to dispel [Y]'s [Z]
      end
   end
end

function Flump:CHAT_MSG_ADDON(addon, msg, _, sender)
   if addon ~= "Flump" or sender == UnitName("player") then return end

   if lastSentPriority==0 and playerIsUnderMetamorphosis then return end -- Prevent loop where player is transformed and keeps telling everyone that he is 0 but thinks he is 'priority'
   local friendPriority = tonumber(msg)
   if debug then send((sender or "") .. " sent you his priority, your are " .. priority .. " and his is " .. friendPriority) end

   if priority > friendPriority then
      topPriority = true
      checkIfAddonShouldBeEnabled()
      sendAddonMessage()
   elseif friendPriority > priority then
      topPriority = false
      checkIfAddonShouldBeEnabled()
   elseif friendPriority~=0 then
      priority = math.random(1000000)
      sendAddonMessage()
   end
end

function Flump:PLAYER_REGEN_DISABLED()
   sendAddonMessage()
end

function Flump:RAID_ROSTER_UPDATE()
   if debug then send("raid roaster updated.") end
   topPriority = true
   checkIfAddonShouldBeEnabled()
   sendAddonMessage()
end

function Flump:PLAYER_ENTERING_WORLD()
   instanceType = select(2,IsInInstance())
   checkIfAddonShouldBeEnabled()
   if (not UnitInBattleground("player") and UnitInRaid("player")) then sendAddonMessage() end
end

local function slashCommand(typed)
   local cmd = string.match(typed,"^(%w+)") -- Gets the first word the user has typed
   if cmd~=nil then cmd = cmd:lower() end   -- And makes it lower case
   local extra = removeWords(typed,1)
   if(cmd=="debug") then
      debug = not debug
      Flump.db.debug = debug
      send("debug mode turned " .. (debug and "|cff00ff00on|r" or "|cffff0000off|r"))
      topPriority = true
      sendAddonMessage()
      checkIfAddonShouldBeEnabled()
   elseif (cmd=="alwayson") then
      alwayson = not alwayson
      Flump.db.alwayson = alwayson
      send("alwayson mode turned " .. (alwayson and "|cff00ff00on|r" or "|cffff0000off|r"))
      topPriority = true
      sendAddonMessage()
      checkIfAddonShouldBeEnabled()
   elseif (cmd=="prio" or cmd=="priority") then
      send("my priority is " .. priority)
   elseif (cmd=="setprio" or cmd=="setpriority") then
      if not debug then return end
      if extra~=nil and (is_int(tonumber(extra))) then
         priority = tonumber(extra)
         send("priority set to " .. extra)
         topPriority = true
         sendAddonMessage()
         checkIfAddonShouldBeEnabled()
      end
   elseif (cmd=="ver" or cmd=="version") then
      if addonVersion~=nil then send("version " .. addonVersion) end
   elseif Flump.db.enabled then
      Flump.db.enabled = false
      checkIfAddonShouldBeEnabled()
      sendAddonMessage()
      print(status:format("|cffff0000off|r"))
   else
      Flump.db.enabled = true
      topPriority = true
      sendAddonMessage()
      checkIfAddonShouldBeEnabled()
      print(status:format("|cff00ff00on|r"))
   end
end

function Flump:ADDON_LOADED(addon)
   if addon ~= "Flump" then return end
   priority = math.random(1000000)

   FlumpDB = FlumpDB or { enabled = true }
   self.db = FlumpDB
   debug = self.db.debug or debug
   alwayson = self.db.alwayson or alwayson
   if debug then spells[48785] = true end
   addonVersion = GetAddOnMetadata("Flump", "Version")

   SLASH_FLUMP1 = "/flump"
   SlashCmdList.FLUMP = function(cmd) slashCommand(cmd) end
   if debug then send("remember that debug mode is |cff00ff00ON|r.") end
   if alwayson then send("remember that alwayson mode is |cff00ff00ON|r.") end
   self:RegisterEvent("PLAYER_ENTERING_WORLD")
end

Flump:RegisterEvent("ADDON_LOADED")