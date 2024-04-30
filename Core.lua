-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------
-- "|TInterface\\OptionsFrame\\UI-OptionsFrame-NewFeatureIcon:0:0:0:0|t"

local AddonName = ...;
local PT = LibStub("AceAddon-3.0"):NewAddon(select(2, ...), AddonName, "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);
local AceTimer = LibStub("AceTimer-3.0"); -- no need for embedding it
local LibBreed = LibStub("LibPetBreedInfo-1.0");

local _G = _G;
local ipairs, pairs = _G.ipairs, _G.pairs;

_G.PT = PT;

-------------------------------
-- Registering with iLib
-------------------------------

LibStub("iLib"):Register(AddonName);

----------------------
-- Variables
----------------------

PT.PlayerInfo = {};
PT.EnemyInfo  = {};

PT.PAD_INDEX = _G.PET_BATTLE_PAD_INDEX;
PT.PET_INDEX = 1;

PT.MAX_COMBAT_PETS = 3;
PT.MAX_PET_ABILITY = _G.NUM_BATTLE_PET_ABILITIES;

PT.BONUS_SPEED_FASTER = 2;
PT.BONUS_SPEED_EQUAL  = 1;
PT.BONUS_SPEED_SLOWER = 0;

PT.alpha = false; -- is this an alpha package?
--@alpha@
PT.alpha = true;
--@end-alpha@

--@do-not-package@
PT.developer = true;
--@end-do-not-package@

------------------
-- Boot
------------------

function PT:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("PokemonTrainerDB", { profile = { activeBattleDisplay = 1, version = "", alpha = false } }, "Default");
	
	-- hook pet battle queue frame to bring sounds back
	-- not implemented with Ace3 Hook because this is very little code and isn't worth using Ace3
	--hooksecurefunc(_G.PetBattleQueueReadyFrame, "Show", function() _G.PlaySound("ReadyCheck") end);
	--_G.PetBattleQueueReadyFrame.DeclineButton:HookScript("OnClick", function() _G.PlaySound("LFG_Denied") end);
end

function PT:OnEnable()
	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, PT.OpenOptions);
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName);

	print("|cff00aaff"..AddonName.."|r: loaded.");
	
	_G.SlashCmdList["PT"] = function() Settings.OpenToCategory(AddonName); end
	_G["SLASH_PT1"] = "/pt";
	
	-- version check and reminder that the user may want to check the options
	local msg;
	local version = tostring(_G.GetAddOnMetadata(AddonName, "Version"));
	if( self.db.profile.version ~= version ) then
		if( self.db.profile.version == "" ) then
			msg = "|cff00aaff"..AddonName.."|r: "..L["First run, you may wanna check /pt for options."];
		else
			msg = "|cff00aaff"..AddonName.."|r: "..L["Recently updated to version"].." "..version;
		end
		self.db.profile.alpha = true;
	end
	if( self.db.profile.alpha and PT.alpha and not PT.developer ) then
		self.db.profile.alpha = false;
		msg = "|cff00aaff"..AddonName.."|r: Running Alpha Package without being a developer, it could be unstable or erroneous. Feedback is appreciated. Please install at least a Beta Package if you do not want that at all.";
	end
	if( msg ) then
		self.db.profile.version = version;
		AceTimer.ScheduleTimer(self, function() print(msg) end, 15);
	end
	
	-- Thanks to esiemiat on CurseForge
	--
	-- *************************************************************************************
	-- **** Addresses a Blizzard issue in C_PetJournal when the UI is loading. Sometimes there is a lag
	-- **** between C_PetJournal.GetPetInfoByIndex producing valid values and C_PetJournal.GetPetStats
	-- **** producing valid values. This leads to the following:
	-- ****      Error Message: ...e\AddOns\Blizzard_PetJournal\Blizzard_PetJournal.lua line 771:
	-- ****      attempt to perform arithmetic on local 'rarity' (a nil value)
	-- *************************************************************************************
	local LibPetJournal = LibStub("LibPetJournal-2.0")
	LibPetJournal.RegisterCallback(self, "PostPetListUpdated", function()
		if not _G.IsAddOnLoaded("Blizzard_Collections") then _G.LoadAddOn("Blizzard_Collections") end
		LibPetJournal.UnregisterCallback(self, "PostPetListUpdated")
	end)
end

-------------------------
-- Event Callbacks
-------------------------

-- Both hooks only apply for the FrameCombatDisplay
-- When hiding the UI, PT's frames are hidden as well
_G.UIParent:HookScript("OnShow", function()
	if( _G.C_PetBattles.IsInBattle() and PT.db.profile.activeBattleDisplay == 1 ) then
		_G.PTPlayer:Show();
		_G.PTEnemy:Show();
	end
end);

_G.UIParent:HookScript("OnHide", function()
	if( _G.C_PetBattles.IsInBattle() and PT.db.profile.activeBattleDisplay == 1 ) then
		_G.PTPlayer:Hide();
		_G.PTEnemy:Hide();
	end
end);

---------------------------
-- Compare Functions
---------------------------

-- RETURN
-- Whether it is a PvP match or not
function PT:IsPVPBattle()
	return _G.C_PetBattles.IsInBattle() and not _G.C_PetBattles.IsWildBattle() and not _G.C_PetBattles.IsPlayerNPC(2);
end

-- RETURN
-- float number which acts as a percentage
function PT:GetTypeBonus(petType, enemyType, noStrongWeak)
	if( not petType or not enemyType or noStrongWeak ) then
		return 1; -- in this case 0 bonuses
	end
	
	assert(type(petType) == "number");
	assert(type(enemyType) == "number");
	
	return _G.C_PetBattles.GetAttackModifier(petType, enemyType) or 1;
end

-- RETURN
-- Texture Path
function PT:GetTypeBonusIcon(petType, enemyType, noStrongWeak)
	local modifier = petType; -- if the second arg is nil, this method treats petType as the modifier to prevent double calling :GetTypeBonus
	
	if( enemyType ) then
		modifier = self:GetTypeBonus(petType, enemyType, noStrongWeak);
	end
	
	assert(type(modifier) == "number");
	
	if( modifier > 1 ) then
		return "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong";
	elseif( modifier < 1 ) then
		return "Interface\\PetBattles\\BattleBar-AbilityBadge-Weak";
	else
		return "Interface\\PetBattles\\BattleBar-AbilityBadge-Neutral";
	end
end

-- RETURN
-- Texture path
function PT:GetTypeIcon(petType)
	assert(type(petType) == "number");
	return _G.GetPetTypeTexture(petType);
end

-- RETURN
-- result:		number which is matching to one PT.BONUS_SPEED_... constants
-- better_with_flying: bool		if the pet is flying and no active speed bonus, would it be faster than pet2 if the bonus was active?
function PT:GetSpeedBonus(pet1, pet2)
	local better_with_flying = false;
	
	assert(type(pet1) == "table");
	assert(type(pet2) == "table");
	
	-- Flying pets get a speed bonus, if their HP is above 50%
	if( _G.PET_TYPE_SUFFIX[pet1.type] == "Flying" ) then
		better_with_flying = not(pet1.hpP >= 0.5) and ((pet1.speed * 1.5) >= pet2.speed) or false;
	end
	
	local result = (pet1.speed > pet2.speed) and PT.BONUS_SPEED_FASTER or (pet2.speed > pet1.speed) and PT.BONUS_SPEED_SLOWER or PT.BONUS_SPEED_EQUAL;
	
	return result, better_with_flying;
end

-- COLORTABLE (comparision our level against enemy level)
-- Our table differs from the blizzard pet level zone coloring (WorldMapFrame.lua)
-- The reason is that we must play safe, that means Blizzards color table is weird while displaying pet battles.
-- If the enemys level would be 2 higher than yours, it said the enemy has normal difficulty while you have hard difficulty.
-- In my opinion, that is not right. My concept: normal<->normal, hard<->easy, easy<->hard, trivial<->very hard, very hard<->trivial
--					we								|		blizzard
-------------------------------------------------------------
--	> 9												|		trivial (grey)
--  > 4			trivial (grey)		|		
--	> 3												|		easy (green)
--	> 2			easy (green)			|		
--	> 1												|		normal (yellow)
--	==			normal (yellow)		|		
--	< 1												|		hard (orange)
--	< 2			hard (orange)			|		
--	< 3												|		very hard (red)
--	< 4			very hard (red)		|		
-------------------------------------------------------------
-- RETURN
-- r, g, b:		self-explaining
function PT:GetDifficultyColor(pet1, pet2)
	if( type(pet1) == "table" ) then
		pet1 = pet1.level;
	end
	if( type(pet2) == "table" ) then
		pet2 = pet2.level;
	end

	assert(type(pet1) == "number");
	assert(type(pet2) == "number");
	
	if( (pet2 - pet1) <= -4 ) then
		pet2 = pet2 - 4; -- leaps over the big range of green difficulties and colors it trivial
	end
	
	local color;
	if( pet1 < pet2 ) then
		color = _G.GetRelativeDifficultyColor(pet1, pet2 + 1);
	elseif( pet1 > pet2 ) then
		color = _G.GetRelativeDifficultyColor(pet1 + 1, pet2);
	else
		color = _G.QuestDifficultyColors["difficult"];
	end
	
	return color.r, color.g, color.b;
end

-- RETURN
-- available:	bool
-- cdleft:		number
function PT:GetAbilityCooldown(side, pet, ab)
	assert(type(side) == "number");
	assert(type(pet)  == "number");
	assert(type(ab)   == "number");

	local available, cdleft = _G.C_PetBattles.GetAbilityState(side, pet, ab);
	
	-- the API returns available = true/false and cdleft = 0/>0, but we want to make sure that this will actually happen
	
	-- Curse comment #105
	-- overrides the state when a pet is currently sleeping, repairing etc. and cannot use abilities
	-- so we disable that way of handling CDs
	--  available = not(cdleft and cdleft > 0);
	--  cdleft = available and 0 or cdleft;
	
	-- back to the roots
	available = available == true;
	
	if( cdleft and cdleft > 0 ) then
		available = false;
	else
		cdleft = 0;
	end
	
	return available, cdleft;
end

----------------------------------
-- Scanning Pets for Combat
----------------------------------

local scan_pets, scan_dummys, roundup_pets;
do
	-- wipes all keys/values and subtable keys/values, but not the subtables themselves
	local function wipe_pets(t)
		for k,v in pairs(t) do
			if( type(v) == 'table' ) then
				for i = 1, #v do
					v[i] = nil
				end
				v[''] = 1
				v[''] = nil
			else
				t[k] = nil
			end
		end
		t[''] = 1
		t[''] = nil
	end
	
	-- Checks how many abilities a pet actually has
	local function get_num_abilities(side, pet)
		local num = 0;
		
		for i = 1, PT.MAX_PET_ABILITY do
			if( (_G.C_PetBattles.GetAbilityInfo(side, pet, i)) ) then
				num = num + 1;
			end
		end
		
		return num;
	end
	
	-- enables new table keys whose data isn't directly saved in the table
	local mt = {
		__index = function(t, k)
			if( k == "dead" ) then
				return t.hp <= 0;
			elseif( k == "hpP" ) then
				return t.hp / t.hpM;
			end
		end,
	};
	
	scan_pets = function(side, t)
		wipe_pets(t);
		
		local numPets = _G.C_PetBattles.GetNumPets(side);
		local activePet = _G.C_PetBattles.GetActivePet(side);
		
		local species, speciesName, petIcon, petType;
		local petLevel, petName, petPower, petSpeed, petQuality, petHP, petMaxHP;
		local numAbilities, displayID;
		
		t.side = side;
		t.numPets = numPets;
		t.activePet = activePet;
		t.aurastates = t.aurastates or {}; -- won't get deleted by wipe_pets() and we don't want to redeclare thousands of tables
		t.scanned = true;
		
		for pet = 1, numPets do
			species = _G.C_PetBattles.GetPetSpeciesID(side, pet);
			speciesName, petIcon, petType = _G.C_PetJournal.GetPetInfoBySpeciesID(species);
			
			petLevel = _G.C_PetBattles.GetLevel(side, pet);
			petName = _G.C_PetBattles.GetName(side, pet);
			petPower = _G.C_PetBattles.GetPower(side, pet);
			petSpeed = _G.C_PetBattles.GetSpeed(side, pet);
			petQuality = _G.C_PetBattles.GetBreedQuality(side, pet);
			
			petHP = _G.C_PetBattles.GetHealth(side, pet);
			petMaxHP = _G.C_PetBattles.GetMaxHealth(side, pet);
			
			--numAbilities = petLevel >= 4 and 3 or petLevel >= 2 and 2 or 1;
			numAbilities = get_num_abilities(side, pet); -- Apparently some trainers ignore the above rule :/
			
			displayID = _G.C_PetBattles.GetDisplayID(side, pet);
			
			-- the t[pet] tables will be reused even after wipe_pets() got executed, the garbagecollector doesn't get something to eat *sob*
			if( not t[pet] or not(type(t[pet]) == "table") ) then
				t[pet] = {};
				setmetatable(t[pet], mt);
			end
			
			--t[pet].side = side;
			--t[pet].pet = pet;
			t[pet].name = petName;
			t[pet].level = petLevel;
			t[pet].species = species;
			t[pet].type = petType;
			t[pet].power = petPower;
			t[pet].speed = petSpeed;
			t[pet].icon = petIcon;
			t[pet].quality = petQuality - 1; -- little hack, the API returns (actual_pet_quality + 1) -.-
			t[pet].hp = petHP;
			t[pet].hpM = petMaxHP;
			t[pet].numAbilities = numAbilities;
			t[pet].displayID = displayID;
			t[pet].breed = LibBreed:GetBreedName( LibBreed:GetBreedByPetBattleSlot(side, pet) or 0 );
			
			if( side == Enum.BattlePetOwner.Enemy and PT:IsPVPBattle() ) then -- the ability scanner is only required during PvP battles
				local t1, t2 = {}, {};
				_G.C_PetJournal.GetPetAbilityList(species, t1, t2);
				
				t[pet].tableAbilities = t1;
				t[pet].tableAbilityLevels = t2;
				
				numAbilities = 0;
				for i = 1, 3 do
					if( petLevel >= t2[i] ) then
						numAbilities = numAbilities + 1;
					end
					
					t[pet]["ab"..i] = t1[i]; -- ability id
				end
				t[pet].numAbilities = numAbilities;
				
				for i = 4, 6 do
					t[pet]["ab"..(i - 3).."ok"] = not t2[i] and true or petLevel < t2[i];
				end
			else
			
				for ab = 1, numAbilities do
					t[pet]["ab"..ab] = _G.C_PetBattles.GetAbilityInfo(side, pet, ab); -- ability id
				end
			
			end
		end
	end
	
	local random = math.random;
	scan_dummys = function(side, t)
		-- if there is scanned data, we can return :)
		if( t.scanned ) then return; end
		
		local numPets = 3;
		local activePet = random(1, numPets);
		
		t.side = side;
		t.numPets = numPets;
		t.activePet = activePet;
		t.aurastates = t.aurastates or {};
		t.scanned = true;
		
		local abID; -- for random ability creation
		
		for pet = 1, numPets do
			-- the t[pet] tables will be reused even after wipe_pets() got executed, the garbagecollector doesn't get something to eat *sob*
			if( not t[pet] or not(type(t[pet]) == "table") ) then
				t[pet] = {};
				setmetatable(t[pet], mt);
			end
			
			--t[pet].side = side;
			--t[pet].pet = pet;
			t[pet].name = "Dummy "..pet;
			t[pet].level = random(1, 25);
			t[pet].species = species;
			t[pet].type = random(1, 10);
			t[pet].power = t[pet].level * random(2, 20);
			t[pet].speed = t[pet].level * random(7, 15);
			t[pet].icon = "INTERFACE\\ICONS\\INV_CRATE_02";
			t[pet].quality = pet + ((side - 1) * 3) - 1;
			t[pet].hp = random(0, 10);
			t[pet].hpM = 10;
			t[pet].numAbilities = random(1, 3);
			t[pet].displayID = 7511;
			t[pet].breed = LibBreed:GetBreedName( random(1, 10) );
			
			for ab = 1, t[pet].numAbilities do
				while( not abID ) do
					abID = _G.C_PetBattles.GetAbilityInfoByID(random(200, 800));
				end
				t[pet]["ab"..ab] = abID;
				abID = nil;
			end
		end
	end
	
	-- I decided to create a roundup function to get rid off too many scan_pets() calls
	-- For each battle round there is little updated data: speed and current hp (excepting buffs/debuffs)
	roundup_pets = function(side, t)
		local numPets = _G.C_PetBattles.GetNumPets(side);
		local activePet = _G.C_PetBattles.GetActivePet(side);
		
		local petSpeed, petHP, petMaxHP;
		
		t.numPets = numPets; -- weird, usually the number of pets shouldn't change during battles. :D
		t.activePet = activePet;
		
		for pet = 1, numPets do
			petSpeed = _G.C_PetBattles.GetSpeed(side, pet);
			petHP = _G.C_PetBattles.GetHealth(side, pet);
			
			t[pet].speed = petSpeed;
			t[pet].hp = petHP;
		end
	end
end

-- initially scans both player and enemy pets and initializes all important data
function PT:ScanPets()
	scan_pets(Enum.BattlePetOwner.Ally, self.PlayerInfo);
	scan_pets(Enum.BattlePetOwner.Enemy , self.EnemyInfo );
end

-- when no pets were scanned before, fill the tables with dummy data
function PT:ScanDummyPets()
	scan_dummys(Enum.BattlePetOwner.Ally, self.PlayerInfo);
	scan_dummys(Enum.BattlePetOwner.Enemy , self.EnemyInfo );
end

-- rounds up the pet data (speed, hp)
function PT:RoundUpPets(side)
	if( not side or side == Enum.BattlePetOwner.Ally ) then
		roundup_pets(Enum.BattlePetOwner.Ally, self.PlayerInfo);
	end
	if( not side or side == Enum.BattlePetOwner.Enemy ) then
		roundup_pets(Enum.BattlePetOwner.Enemy , self.EnemyInfo );
	end
end

-- this chunk is our aura and state scanner
do
	-- retrieve aurastates from Data for given aura ID and add them to players .aurastates
	local function add_aura_states(player, aura)
		local states = PT.Data.aurastates[aura];
		
		if( type(states) == "number" ) then
			player.aurastates[states] = true;
		elseif( type(states) == "table" ) then
			for _,stateID in ipairs(states) do
				player.aurastates[stateID] = true;
			end
		end
	end
	
	-- Loops thru all pet auras and scans for buff and debuff states
	-- all states are stored in the .auratable and have to be treated as table indexes (simple lookup)
	-- called by the event handler
	function PT:ScanPetAuras(player)		
		_G.wipe(player.aurastates); -- wipe old aurastate data
		
		local slot;
		
		-- there are three types of auras
		--  1. Weather (applies on both player and enemy)
		--  2. Player-wide (applies on all pets of a player)
		--  3. Pet-only (applies on one pet)
		
		-- get weather states
		add_aura_states(player, (_G.C_PetBattles.GetAuraInfo(Enum.BattlePetOwner.Weather, PT.PAD_INDEX, 1)) );
		
		-- get player-wide states
		slot = _G.C_PetBattles.GetNumAuras(player.side, PT.PAD_INDEX) or 0; -- apparently can be nil
		for slot = 1, slot do
			add_aura_states(player, (_G.C_PetBattles.GetAuraInfo(player.side, PT.PAD_INDEX, slot)) );
		end
		
		-- get pet-only states
		slot = _G.C_PetBattles.GetNumAuras(player.side, player.activePet) or 0; -- apparently can be nil
		for slot = 1, slot do
			add_aura_states(player, (_G.C_PetBattles.GetAuraInfo(player.side, player.activePet, slot)) );
		end
	end

	local get = {}; -- an ability-effect-retrieve-function storage
	
	local effects = {"points"};
	--@do-not-package@
	-- As a developer, we have access to all existing effects since the "normal" addon user only needs some effects
	effects = {_G.C_PetBattles.GetAllEffectNames()};
	--@end-do-not-package@
	
	-- loop all effects and create retrieve functions
	for i, effect in ipairs(effects) do
		get[effect] = function(abilityID, turnIndex, event)
			return _G.C_PetBattles.GetAbilityEffectInfo(abilityID, turnIndex, event, effects[i]) or 0;
		end;
	end

	-- table of event IDs used by the pet battle system. also called procs by Blizzard
	local events = {
		On_Apply				= _G.PET_BATTLE_EVENT_ON_APPLY,
		On_Damage_Taken	= _G.PET_BATTLE_EVENT_ON_DAMAGE_TAKEN,
		On_Damage_Dealt	= _G.PET_BATTLE_EVENT_ON_DAMAGE_DEALT,
		On_Heal_Taken		= _G.PET_BATTLE_EVENT_ON_HEAL_TAKEN,
		On_Heal_Dealt		= _G.PET_BATTLE_EVENT_ON_HEAL_DEALT,
		On_Aura_Removed	= _G.PET_BATTLE_EVENT_ON_AURA_REMOVED,
		On_Round_Start	= _G.PET_BATTLE_EVENT_ON_ROUND_START,
		On_Round_End		= _G.PET_BATTLE_EVENT_ON_ROUND_END,
		On_Turn					= _G.PET_BATTLE_EVENT_ON_TURN,
		On_Ability			= _G.PET_BATTLE_EVENT_ON_ABILITY,
		On_Swap_In			= _G.PET_BATTLE_EVENT_ON_SWAP_IN,
		On_Swap_Out			= _G.PET_BATTLE_EVENT_ON_SWAP_OUT,
	};
	
	-- table of states, which can be modifiers, debuffs, weathers, stats, everything
	-- the normal user wouldn't need all of these, but I don't want to procude more code to prevent fetching all states
	local states = {};
	for stateName, stateID in pairs(_G.C_PetBattles.GetAllStates()) do
		stateName = stateName:sub(7, -1); -- cuts off, regex ^STATE_(.*)$ replace $1
		states[stateName] = stateID;
	end
	
	--@do-not-package@
	-- I need that for developing stuff since Developer.lua uses this tables as well. Normal users don't have direct access to this tables
	PT.effects, PT.states, PT.events, PT.get = effects, states, events, get;
	--@end-do-not-package@
	
	-- checks whether or not a state is currently active on the given player
	local function lookup_aurastate(player, state)
		if( state and player.aurastates[state] ) then
			return true;
		end
		return false;
	end
	-- same check but involves weather / elemental bonus (Elementals ignore ALL weather effects, thus they receive no bonus from them, too!)
	local function lookup_aurastate_weather(player, petType, state)
		if( _G.PET_TYPE_SUFFIX[petType] == "Elemental" ) then
			return false;
		end
		return lookup_aurastate(player, state);
	end
	
	-- checks whether or not an ability actually does damage
	local function does_damage(ability)
		return get.points(ability, 1, events.On_Damage_Taken) > 0; -- 1 is turn index
	end
	
	-- static table which stores glowing informations, each index is an ability index
	local glow = {};
	
	-- called by combat displays to get info about whether or not an ability button shall glow
	function PT:GetAbilityStateBonuses(player, enemy)		
		local playerPet = player[player.activePet];
		
		glow[1], glow[2], glow[3] = false, false, false;
		
		-- Check if we are currently buffed with a damage modifier
		-- if yes, returns since the other checks aren't necessary anymore
		if( lookup_aurastate(player, states.Mod_DamageDealtPercent ) ) then
			for ab = 1, playerPet.numAbilities do
				glow[ab] = does_damage(playerPet["ab"..ab]);
			end
			return unpack(glow);
		end
		
		-- Check if the enemy currently has a debuff which boosts our ability power
		-- if yes, returns since the other checks aren't necessary anymore
		if( lookup_aurastate(enemy, states.Mod_DamageTakenPercent ) ) then
			for ab = 1, playerPet.numAbilities do
				glow[ab] = does_damage(playerPet["ab"..ab]);
			end
			return unpack(glow);
		end
		
		-- Looping thru our abilities and check for enemy debuffs and weather modificators
		local mods;
		for ab = 1, playerPet.numAbilities do
			mods = PT.Data.abilitymods[playerPet["ab"..ab]];
			
			if( type(mods) == "number" ) then
				glow[ab] = lookup_aurastate_weather(player, playerPet.type, mods);
			elseif( type(mods) == "table" ) then
				if(	lookup_aurastate(enemy,  mods[2]) or				-- check for enemy debuff which empowers our ability
						lookup_aurastate_weather(player, playerPet.type, mods[1]) or				-- check for weather which empowers our ability
						lookup_aurastate_weather(player, playerPet.type, mods[3]) ) then		-- check for weather state2 which empowers our ability
					glow[ab] = true;
				end				
			end
		end
		
		return unpack(glow);
	end
	
	-- Checks whether or not ramping is available for that ability ID
	-- and returns the max ramping value (how much stacks apply additional power)
	function PT:GetAbilityRamping(ability)
		if( type(self.Data.abilitymods[ability]) ~= "table" ) then
			return;
		end
		return self.Data.abilitymods[ability][4];
	end
	
	-- Checks the current ramping state of abilityID
	-- Returns either 0 if it fails or the actual value (which can be also 0)
	function PT:GetAbilityRampingState(side, pet, ability)
		if( _G.C_PetBattles.GetStateValue(side, pet, states.Ramping_DamageID) ~= ability ) then
			return 0;
		else
			return _G.C_PetBattles.GetStateValue(side, pet, states.Ramping_DamageUses);
		end
	end
end

-----------------------------
-- Configuration stuff
-----------------------------

local options;
function PT:OpenOptions()
	options = {
		name = L["Pokemon Trainer Options"]..(PT.alpha and " |cffff0000Alpha Package|r" or ""),
		type = "group",
		args = {
			display = {
				type = "select",
				name = L["Preferred combat display"],
				desc = L["Choose between the new (Frames) or the old (Tooltip) way of displaying combat data during pet battles."],
				order = 1,
				style = "radio",
				get = function()
					return PT.db.profile.activeBattleDisplay;
				end,
				set = function(_, value)
					if( value == 2 ) then
						PT:GetModule("FrameCombatDisplay"):Disable();
						PT:GetModule("TooltipCombatDisplay"):Enable();
					else
						PT:GetModule("FrameCombatDisplay"):Enable();
						PT:GetModule("TooltipCombatDisplay"):Disable();
					end
					PT.db.profile.activeBattleDisplay = value;
				end,
				values = {
					[1] = L["Display: Frames"],
					[2] = L["Display: Tooltip"],
				},
				hidden = _G.C_PetBattles.IsInBattle,
			},
			combatnotice = {
				type = "description",
				name = "|cffff0000"..L["Switching the combat display doesn't work during pet battles."].."|r",
				order = 1.1,
				hidden = function() return not _G.C_PetBattles.IsInBattle() end,
			},
			spacer = { type = "description", name = " ", order = 50 },
		},
	};
	
	-- Parts of this code snippet have been written by ckknight and the Chinchilla team
	-- They are great and fit our needs, so we do not re-invent the wheel over and over again.
	local t;
	for key, module in PT:IterateModules() do
		if( key:sub(1, 1) ~= "_" ) then -- no data modules
			t = module.GetOptions and module:GetOptions() or {};
			
			for option, args in pairs(t) do
				if( type(args.disabled) == "nil" ) then
					args.disabled = function() return not module:IsEnabled(); end
				end
			end
			
			t.descr = { type = "description", name = module.desc, order = 0.1 };
			t._spacer1 = { type = "description", name = " ", order = 0.2 };
			
			if( not module.noEnableButton ) then
				t.enabled = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Enable this module."],
					get = function()
						return module:IsEnabled();
					end,
					set = function(_, value)
						module.db.profile.enabled = not not value; -- to ensure a boolean
						
						if value then
							return module:Enable();
						else
							return module:Disable();
						end
					end,
					order = 0.3,
					width = "full",
				};
				t._spacer2 = { type = "description", name = " ", order = 0.4 }; -- spacer between the Enable toggle button and the acual options
			end
			
			options.args[key] = { type = "group", name = module.displayName, desc = module.desc, handler = module, order = module.order or -1, args = t }
		end
	end
	
	PT.OpenOptions = nil; -- this function is needed once and gets deleted
	return options;
end