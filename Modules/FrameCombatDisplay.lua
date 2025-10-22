-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, PT = ...;
local module = PT:NewModule("FrameCombatDisplay", "AceHook-3.0", "AceEvent-3.0", "AceBucket-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);
local AceTimer = LibStub("AceTimer-3.0"); -- we don't embed it since its just used by some hooks

local _G = _G;
local ipairs, pairs, table = _G.ipairs, _G.pairs, _G.table;

----------------------
-- Variables
----------------------

module.order = 1;
module.displayName = function() return (module:IsEnabled() and "|cff00ff00%s|r" or "|cffff0000%s|r"):format(L["Display: Frames"]) end
module.desc = L["True frame based combat display for Pet Battles and the next generation of Pokemon Trainer. Disable it if you want to use the tooltip based combat display."];
module.noEnableButton = true;

local BattleFrames = {}; -- if a battle frame is loaded, it adds itself into this table (simply for iterating over battle frames)

-- xml values
local FRAME_PLAYER = "PTPlayer";
local FRAME_ENEMY  = "PTEnemy";

local FRAME_BUTTON_WIDTH = 22;
local FRAME_LINE_HEIGHT = 22;
local SPACE_PETS = 5;
local SPACE_ABILITIES = 2;
local SPACE_HORIZONTAL = 3;

local FONT_LEVEL_DEFAULT = 13;
local FONT_LEVEL_ADJUST = 8;

-- Little Helpers

-- get enemy frame by frame reference
local function get_enemy(self)
	return self:GetName() == FRAME_PLAYER and _G[FRAME_ENEMY] or _G[FRAME_PLAYER];
end

-- get frame reference by side ID
local function get_frame(side)
	return side == Enum.BattlePetOwner.Ally and _G[FRAME_PLAYER] or _G[FRAME_ENEMY];
end

-------------------------
-- Module Handling
-------------------------

function module:OnInitialize()
	self.db = PT.db:RegisterNamespace("FrameCombatDisplay", {
		profile = {
			PTPlayer_icon = "TOPLEFT",
			PTPlayer_x = 200,
			PTPlayer_y = 200,
			PTEnemy_icon = "TOPRIGHT",
			PTEnemy_x = ((_G.GetScreenWidth() * _G.UIParent:GetScale()) - 298),
			PTEnemy_y = 200,
			scale = 1,
			resize = true,
			highlight_active = true,
			animate_active = true,
			highlight_active_r = 0.99,
			highlight_active_g = 0.82,
			highlight_active_b = 0,
			active_enemy_border = true,
			bg = false,
			bg_r = 0.30,
			bg_g = 0.30,
			bg_b = 0.30,
			bg_a = 0.48,
			breeds = 3,
			model3d = true,
			reorganize_use = true,
			reorganize_ani = true,
			nactivealpha_use = false,
			nactivealpha = 0.5,
			cd_text = true,
			cd_text_r = 1,
			cd_text_g = 1,
			cd_text_b = 1,
			cd_text_a = 1,
			cd_highlight = true,
			cd_highlight_r = 0,
			cd_highlight_g = 0,
			cd_highlight_b = 0,
			cd_highlight_a = 0.8,
			ability_zoom = false,
			ability_highlight = true,
			ability_highlight_blizzard = true,
			ability_ramping = true,
		},
	});

	if( PT.db.profile.activeBattleDisplay ~= 1 ) then
		self:SetEnabledState(false);
	end

	-- This is a small "positioning" window which is shown when repositioning the battle frames
	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName.."_"..self:GetName(), self.GetPositionOptions);
	LibStub("AceConfigDialog-3.0"):SetDefaultSize(AddonName.."_"..self:GetName(), 420, 370);
end

function module:OnEnable()
	-- normal event registering
	self:RegisterEvent("PET_BATTLE_OPENING_START", "OnEvent");
	self:RegisterEvent("PET_BATTLE_OVER", "OnEvent");
	self:RegisterEvent("PET_BATTLE_CLOSE", "OnEvent");
	--self:RegisterEvent("PET_BATTLE_TURN_STARTED", "OnEvent");
	self:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE", "OnEvent");
	self:RegisterEvent("PET_BATTLE_PET_CHANGED", "OnEvent");
	self:RegisterEvent("PET_BATTLE_HEALTH_CHANGED", "OnEvent");
	self:RegisterEvent("PET_BATTLE_MAX_HEALTH_CHANGED", "OnEvent");
	self:RegisterEvent("CHAT_MSG_PET_BATTLE_COMBAT_LOG", "OnEvent");

	-- registering aura events into a bucket to throttle PetAura update calls
	self:RegisterBucketEvent({"PET_BATTLE_AURA_APPLIED", "PET_BATTLE_AURA_CHANGED", "PET_BATTLE_AURA_CANCELED"}, 2, "OnAuraBucket");

	-- ability buttons handle cooldown highlightning events by themselves
	for _,frame in ipairs(BattleFrames) do
		for pet = PT.PET_INDEX, #frame.petFrames do
			for ab = 1, PT.MAX_PET_ABILITY do
				-- for every ability button
				_G[frame.petFrames[pet]:GetName()]["Ability"..ab]:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE");
			end
		end

		-- reanchor when module loads
		self.BattleFrame_Reanchor(frame, true);
	end

	-- setup hooks
	self:SecureHookScript(_G.PetBattleFrame.BottomFrame.PetSelectionFrame, "OnShow", "Hook_PetSelection_Show");
	self:SecureHookScript(_G.PetBattleFrame.BottomFrame.PetSelectionFrame, "OnHide", "Hook_PetSelection_Hide");
	for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
		self:SecureHookScript(_G.PetBattleFrame.BottomFrame.PetSelectionFrame["Pet"..pet], "OnEnter", "Hook_PetSelection_Pet_Enter");
		self:SecureHookScript(_G.PetBattleFrame.BottomFrame.PetSelectionFrame["Pet"..pet], "OnLeave", "Hook_PetSelection_Pet_Leave");
		self:SecureHookScript(_G.PetBattleFrame.BottomFrame.PetSelectionFrame["Pet"..pet], "OnClick", "Hook_PetSelection_Hide");
	end
end

function module:OnDisable()
	self:UnregisterAllEvents();
	self:UnregisterAllBuckets();

	for _,frame in ipairs(BattleFrames) do
		for pet = PT.PET_INDEX, #frame.petFrames do
			for ab = 1, PT.MAX_PET_ABILITY do
				-- for every ability button
				_G[frame.petFrames[pet]:GetName()]["Ability"..ab]:UnregisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE");
			end
		end
	end

	-- unhook hooks
	self:UnhookAll();
end

function module:OnEvent(event, ...)
	-- a pet battle recently started - completely set up the frames
	if( event == "PET_BATTLE_OPENING_START" ) then
		PT:ScanPets();
		for _,frame in ipairs(BattleFrames) do
			frame:FadeIn();
			PT:ScanPetAuras(frame.player);
			self.BattleFrame_UpdateAbilityHighlights(frame);
		end
	-- battle is over (beginning camera zoom)
	elseif( event == "PET_BATTLE_OVER" ) then
		_G[FRAME_PLAYER]:FadeOut();
		_G[FRAME_ENEMY]:FadeOut();
	-- battle is over or got interrupted (by lfg warp etc.), we must hide the frames if no _OVER event was fired
	elseif( event == "PET_BATTLE_CLOSE" ) then
		for _,frame in ipairs(BattleFrames) do
			if( frame:IsVisible() and not frame.animHide:IsPlaying() ) then
				frame:Hide();
			end
		end
	-- fires before a new round begins
	elseif( event == "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE" ) then
		PT:RoundUpPets();
		self.BattleFrame_UpdateSpeedButtons(_G[FRAME_PLAYER]);
		self.BattleFrame_UpdateSpeedButtons(_G[FRAME_ENEMY]);
		--PT.BattleFrame_UpdateActivePetHighlight(self);
	-- fires when either player or enemy changed their active pet
	elseif( event == "PET_BATTLE_PET_CHANGED" ) then
		local side = ...;
		local frame = get_frame(side);
		local enemy = get_enemy(frame);

		--self.glowing_hideall(frame);

		PT:RoundUpPets(side);
		PT:ScanPetAuras(frame.player);

		self.BattleFrame_SetActiveEnemy(enemy);
		self.BattleFrame_UpdateActivePetHighlight(frame);

		if( frame.firstRound or not self.db.profile.reorganize_use ) then
			frame.firstRound = nil;
			self.BattleFrame_UpdateAbilityHighlights(frame);
			self.BattleFrame_UpdateAbilityHighlights(enemy); -- enemy needs update, too!
		else
			-- update ability highlight is called by Reorganize_Show_Finished too, after reorganizing is done.
			self.BattleFrame_Pets_Reorganize_Init(frame);
		end
	-- fired whenever a pet got damaged, healed or buffed itself more HP
	elseif( event == "PET_BATTLE_HEALTH_CHANGED" or event == "PET_BATTLE_MAX_HEALTH_CHANGED" ) then
		local side, pet = ...;
		local frame = get_frame(side);

		if( pet == frame.player.activePet ) then
			PT:RoundUpPets(side);
			self.BattleFrame_UpdateHealthState(frame);
		end
	elseif( event == "CHAT_MSG_PET_BATTLE_COMBAT_LOG") then
		if( not PT:IsPVPBattle() ) then return end

		local check, _, abID, maxHealth, power, speed = string.find(..., "HbattlePetAbil:([%d]+):([%d]+):([%d]+):([%d]+).*");
		if( not check ) then return end

		abID, power, speed = tonumber(abID), tonumber(power), tonumber(speed);

		local pet = PT.EnemyInfo[PT.EnemyInfo.activePet];

		if( pet.power == power and pet.speed == speed ) then
			local changed = false;

			for ab = 1, pet.numAbilities do
				if( not pet["ab"..ab.."ok"] ) then
					if( pet.tableAbilities[ab] == abID or pet.tableAbilities[ab + 3] == abID ) then
						pet["ab"..ab] = abID;
						pet["ab"..ab.."ok"] = true;
						changed = true;
					end
				end
			end

			if( changed ) then
				module.BattleFrame_SetupAbilityButtons(_G.PTEnemy, PT.EnemyInfo.activePet);
			end
		end
	--@do-not-package@
	else
		print("Uncatched event:", event, ...);
		--@end-do-not-package@
	end
end

function module:OnAuraBucket(side)
	local player = get_frame(Enum.BattlePetOwner.Ally);
	local enemy  = get_frame(Enum.BattlePetOwner.Enemy);

	if( side[Enum.BattlePetOwner.Weather] or side[Enum.BattlePetOwner.Ally] ) then
		PT:ScanPetAuras(player.player);
	end

	if( side[Enum.BattlePetOwner.Weather] or side[Enum.BattlePetOwner.Enemy] ) then
		PT:ScanPetAuras(enemy.player);
	end

	self.BattleFrame_UpdateAbilityHighlights(player);
	self.BattleFrame_UpdateAbilityHighlights(enemy);
end

---------------
-- Hooks
---------------

-- This chunk of hooks makes PT interacting with the default PetBattle UI Pet Selection Frame
do
	local pet_selected = false; -- when clicked a pet, this becomes true to prevent re-loading the default selecting highlights

	-- Sets all player levels to default size excepting the current pet
	local function adjust_player_fonts(current_pet)
		current_pet = pet_selected and -1 or current_pet;

		local font, size, outline;
		local fs;

		-- Safety check: ensure numPets is a valid number
		local numPets = PT.PlayerInfo.numPets or 0;
		if type(numPets) ~= "number" then
			numPets = 0;
		end

		for pet = PT.PET_INDEX, numPets do
			-- fs = _G[FRAME_PLAYER.."Pet"..pet].Button.Level; MODEL
			fs = _G[FRAME_PLAYER.."Pet"..pet].Level;
			font, size, outline = fs:GetFont();
			fs:SetFont(font, FONT_LEVEL_DEFAULT + (pet == current_pet and FONT_LEVEL_ADJUST or 0), outline);
		end
	end

	-- Sets all enemy levels to either default size or adjusted size
	local function adjust_enemy_fonts(bigger)
		local font, size, outline;
		local fs;

		-- Safety check: ensure numPets is a valid number for PvP battles
		local numPets = PT.EnemyInfo.numPets or 0;
		if type(numPets) ~= "number" then
			numPets = 0;
		end

		for pet = PT.PET_INDEX, numPets do
			-- fs = _G[FRAME_ENEMY.."Pet"..pet].Button.Level; MODEL
			fs = _G[FRAME_ENEMY.."Pet"..pet].Level;
			font, size, outline = fs:GetFont();
			fs:SetFont(font, FONT_LEVEL_DEFAULT + (bigger and FONT_LEVEL_ADJUST or 0), outline);
		end
	end

	-- colorizes all enemy levels based on the given level (= hovered player pet level)
	local function adjust_color(level)
		local r, g, b;

		-- Safety check: ensure numPets is a valid number for PvP battles
		local numPets = PT.EnemyInfo.numPets or 0;
		if type(numPets) ~= "number" then
			numPets = 0;
		end

		for pet = PT.PET_INDEX, numPets do
			r, g, b = PT:GetDifficultyColor(level, PT.EnemyInfo[pet].level);
			-- _G[FRAME_ENEMY.."Pet"..pet].Button.Level:SetTextColor(r, g, b, 1); MODEL
			_G[FRAME_ENEMY.."Pet"..pet].Level:SetTextColor(r, g, b, 1);
		end
	end

	-- called when PetSelection is shown
	function module:Hook_PetSelection_Show(frame)
		pet_selected = false;
		adjust_enemy_fonts(true);
		adjust_player_fonts(PT.PlayerInfo.activePet);
	end

	-- called when PetSelection is hidden
	function module:Hook_PetSelection_Hide(frame, button)
		-- we set pet_selected to true because we clicked it (which results in frame closing)
		if( button and button == "LeftButton" ) then
			pet_selected = true;
		end

		adjust_enemy_fonts(false);
		adjust_player_fonts(-1); -- fake pet index to get all fonts smaller :D
	end

	local timer;

	-- called when a pet is hovered on the PetSelection frame
	function module:Hook_PetSelection_Pet_Enter(frame)
		local pet = frame.petIndex;
		adjust_color(PT.PlayerInfo[pet].level);
		adjust_player_fonts(frame.petIndex);

		if( timer ) then
			AceTimer.CancelTimer(module, timer);
		end
	end

	-- called when the timer hits null
	local function real_leave()
		local pet = PT.PlayerInfo.activePet;
		adjust_color(PT.PlayerInfo[pet].level);
		adjust_player_fonts(pet);
		timer = nil;
	end

	-- called when a pet is not hovered anymore on the PetSelection frame
	-- the reason for the timer is a delayed reset to defaults
	function module:Hook_PetSelection_Pet_Leave(frame)
		if( not pet_selected ) then -- if pet_selected, we do not need the timer which sets everything to default
			timer = AceTimer.ScheduleTimer(module, real_leave, 0.2);
		end
	end
end

----------------------------
-- Frame Functions
----------------------------

-- function to resize a battle frame
function module.BattleFrame_Resize(self)
	-- resizing may be disabled
	if( not module.db.profile.resize ) then
		return;
	end

	local frame_name = self:GetName();

	local pet_y;
	local y = FRAME_LINE_HEIGHT; -- header frame

	local x = 1 + (self.enemy.numPets + 1) * (FRAME_BUTTON_WIDTH + SPACE_HORIZONTAL) - SPACE_HORIZONTAL;

	for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
  	if( not(pet > self.player.numPets) ) then
    	pet_y = FRAME_LINE_HEIGHT; -- type and speed icons

			for ab = 1, (module.db.profile.model3d and PT.MAX_PET_ABILITY or self.player[pet].numAbilities) do
      	pet_y = pet_y + FRAME_LINE_HEIGHT + SPACE_ABILITIES;
			end

			y = y + pet_y + SPACE_PETS;
			_G[frame_name.."Pet"..pet]:SetWidth(x);
			_G[frame_name.."Pet"..pet]:SetHeight(pet_y);
		end
	end

	self:SetWidth(x);
	self:SetHeight(y);
end

-- function to move the "active enemy" border
function module.BattleFrame_SetActiveEnemy(self)
	self.EnemyActive:ClearAllPoints();
	self.EnemyActive:SetPoint("TOP", _G[self:GetName().."Header"]["Enemy"..self.enemy.activePet], 0, -21);
	self.EnemyActive:SetPoint("BOTTOM", 0, -6);
end

-- returns true if on the left side of the screen, false otherwise
-- called by xml for displaying tooltips
function module.GetTooltipPosition()
	return _G.GetCursorPosition() < (_G.GetScreenWidth() * _G.UIParent:GetEffectiveScale() / 2);
end

-------------------------------
-- On Loading and Events
-------------------------------

do
	-- we keep calling frame:FadeIn and frame:FadeOut instead of frame:Show and frame:Hide
	local function FadeIn(self)
		self:SetAlpha(0);
		self:Show();
		self.animShow:Play();
	end

	local function FadeOut(self)
		self.animHide:Play();
	end

	-- called by xml
	function module.BattleFrame_OnLoad(self)
		local frame_name = self:GetName();

		-- we store the table ID's for further use and set the backdrop border colors, which need to be set once
		if( self:GetID() == Enum.BattlePetOwner.Ally ) then
			self.player = PT.PlayerInfo;
			self.enemy  = PT.EnemyInfo;
			self.EnemyActive:SetBackdropBorderColor(1, 0, 0, 1);
		else
			self.player = PT.EnemyInfo;
			self.enemy  = PT.PlayerInfo;
			self.EnemyActive:SetBackdropBorderColor(0, 1, 0, 1);
		end

		-- add self to BattleFrames
		table.insert(BattleFrames, self);

		-- animations
		self.petFrames = {
			_G[frame_name.."Pet1"],
			_G[frame_name.."Pet2"],
			_G[frame_name.."Pet3"],
		};

		-- add our Fade functions to the frame objects
		self.FadeIn = FadeIn;
		self.FadeOut = FadeOut;
	end
end

--------------------------
-- Frame Visibility
--------------------------

local function BattleFrame_SetColumnVisibility(f, column, visible)
	-- we just need the frame name here
	f = f:GetName();

	if( visible ) then
		_G[f.."Header"]["Enemy"..column]:Show();
		for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
			_G[f.."Pet"..pet].Type["Speed"..column]:Show();
			_G[f.."Pet"..pet].Type["SpeedBG"..column]:Show();
			_G[f.."Pet"..pet]["Ability1"]["Bonus"..column]:Show();
			_G[f.."Pet"..pet]["Ability2"]["Bonus"..column]:Show();
			_G[f.."Pet"..pet]["Ability3"]["Bonus"..column]:Show();
		end
	else
		_G[f.."Header"]["Enemy"..column]:Hide();
		for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
			_G[f.."Pet"..pet].Type["Speed"..column]:Hide();
			_G[f.."Pet"..pet].Type["SpeedBG"..column]:Hide();
			_G[f.."Pet"..pet]["Ability1"]["Bonus"..column]:Hide();
			_G[f.."Pet"..pet]["Ability2"]["Bonus"..column]:Hide();
			_G[f.."Pet"..pet]["Ability3"]["Bonus"..column]:Hide();
		end
	end
end

local function BattleFrame_SetRowVisibility(self, pet, ab, visible)
	local f = self:GetName();

	if( visible ) then
		_G[f.."Pet"..pet]["Ability"..ab]:Show();
	else
		_G[f.."Pet"..pet]["Ability"..ab]:Hide();
	end
end

----------------------------------
-- Battle Frame: Initialize
----------------------------------

-- called by xml whenever a battle frame is shown
function module.BattleFrame_Initialize(self)
	local enemy = get_enemy(self);
	local color;

	local frame_name = self:GetName();
	local breed, show1, show2;

	for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
		if( pet <= self.player.numPets ) then
			-- setting up pet icons
			_G[frame_name.."Pet"..pet].Button.Icon:SetTexture(self.player[pet].icon);
			_G[frame_name.."Pet"..pet].Type.Icon:SetTexture(PT:GetTypeIcon(self.player[pet].type));
			_G[enemy:GetName().."Header"]["Enemy"..pet].Icon:SetTexture(self.player[pet].icon);

			-- encolor pet icon borders
			color = _G.ITEM_QUALITY_COLORS[self.player[pet].quality or 0];
			_G[frame_name.."Pet"..pet].Button.Border:SetVertexColor(color.r, color.g, color.b, 1);
			_G[enemy:GetName().."Header"]["Enemy"..pet].Border:SetVertexColor(color.r, color.g, color.b, 1);

			-- set level strings
			-- _G[frame_name.."Pet"..pet].Button.Level:SetText( self.player[pet].level ); MODEL
			_G[frame_name.."Pet"..pet].Level:SetText( self.player[pet].level );

			-- display pet column on enemy frame
			BattleFrame_SetColumnVisibility(enemy, pet, true);

			-- setup ability buttons
			module.BattleFrame_SetupAbilityButtons(self, pet);

			-- prepare breed info
			breed = self.player[pet].breed;
			show1, show2 = false, false;

			if( breed and module.db.profile.breeds > 0 ) then
				-- the breeds option has to be treated as an ORed value
				if( bit.band(module.db.profile.breeds, 1) > 0 ) then
					-- _G[frame_name.."Pet"..pet].Button.BreedText:SetText(breed); MODEL
					_G[frame_name.."Pet"..pet].BreedText:SetText(breed);
					show1 = true;
				end

				-- the breeds option has to be treated as an ORed value
				if( bit.band(module.db.profile.breeds, 2) > 0 ) then
					breed = breed:sub(1, 1); -- we don't need breed anymore, so we get the first letter for displaying icons
					show2 = true;

					if( breed == "P" ) then
						-- _G[frame_name.."Pet"..pet].Button.BreedTexture:SetTexCoord(0, 0.5, 0, 0.5); MODEL
						_G[frame_name.."Pet"..pet].BreedTexture:SetTexCoord(0, 0.5, 0, 0.5);
					elseif( breed == "S" ) then
						-- _G[frame_name.."Pet"..pet].Button.BreedTexture:SetTexCoord(0, 0.5, 0.5, 1); MODEL
						_G[frame_name.."Pet"..pet].BreedTexture:SetTexCoord(0, 0.5, 0.5, 1);
					elseif( breed == "H" ) then
						-- _G[frame_name.."Pet"..pet].Button.BreedTexture:SetTexCoord(0.5, 1, 0.5, 1); MODEL
						_G[frame_name.."Pet"..pet].BreedTexture:SetTexCoord(0.5, 1, 0.5, 1);
					else
						-- balanced means no special stuff, so no icon
						show2 = false;
					end
				end
			end
			-- if( show1 ) then _G[frame_name.."Pet"..pet].Button.BreedText:Show() else _G[frame_name.."Pet"..pet].Button.BreedText:Hide() end MODEL
			-- if( show2 ) then _G[frame_name.."Pet"..pet].Button.BreedTexture:Show() else _G[frame_name.."Pet"..pet].Button.BreedTexture:Hide() end MODEL
			if( show1 ) then _G[frame_name.."Pet"..pet].BreedText:Show() else _G[frame_name.."Pet"..pet].BreedText:Hide() end
			if( show2 ) then _G[frame_name.."Pet"..pet].BreedTexture:Show() else _G[frame_name.."Pet"..pet].BreedTexture:Hide() end

			-- display pet frame
			_G[frame_name.."Pet"..pet]:Show();
		else
			-- hide pet ability frame
			_G[frame_name.."Pet"..pet]:Hide();

			-- hide pet column on enemy frame
			BattleFrame_SetColumnVisibility(enemy, pet, false);
		end
	end

	-- set health state
	module.BattleFrame_UpdateHealthState(self);

	-- set active enemy
	module.BattleFrame_SetActiveEnemy(self);
end

---------------------------------------------
-- Battle Frame: Setup Ability Buttons
---------------------------------------------

do
	local heap = {}; -- stores unused ramping frames
	local rampnum = 0;

	-- Crayon is used for coloring the ramping state
	local LibCrayon = LibStub("LibCrayon-3.0");

	-- Either generates a new ramping frame from template or uses an unused one
	local function ramping_show(self, side, pet, ability, ramping)
		if( not self.rampFrame ) then
			local ramp = table.remove(heap);
			if( not ramp ) then
				rampnum = rampnum + 1;
				ramp = _G.CreateFrame("Frame", "PTRampingFrame"..rampnum, _G.UIParent, "PTFrameRampingTemplate");
			end

			ramp.side		 = side;
			ramp.pet		 = pet;
			ramp.ability = ability;
			ramp.rampMax = ramping;

			ramp:SetParent(self);
			ramp:ClearAllPoints();
			ramp:SetSize(8, 8);
			ramp:SetPoint("TOPLEFT", -1, 1);

			ramp.tex:ClearAllPoints();
			ramp.tex:SetPoint("CENTER", ramp.bg);
			ramp.tex:SetVertexColor(1, 0, 0, 1);

			ramp:Show();
			self.rampFrame = ramp;
		end
	end

	-- Updates a ramping frame, if it exists
	local function ramping_update(self)
		if( self.rampFrame ) then
			local ramp = self.rampFrame;
			local r, g, b =  LibCrayon:GetThresholdColor(PT:GetAbilityRampingState(ramp.side, ramp.pet, ramp.ability), ramp.rampMax);

			ramp.tex:SetVertexColor(r, g, b, 1);
		end
	end

	-- Hides an existing ramping frame and puts it to the heap
	local function ramping_blast(self)
		if( self.rampFrame ) then
			self.rampFrame:Hide();
			table.insert(heap, self.rampFrame);
			self.rampFrame = nil;
		end
	end

	-- Setup ability buttons, initializing their ability icons and visibility
	function module.BattleFrame_SetupAbilityButtons(self, pet)
		local abID, abName, abIcon, abMaxCD, abDesc, abNumTurns, abType, noStrongWeak;
		local abilityButton, script;

		for ab = 1, PT.MAX_PET_ABILITY do
			script = true;
			abilityButton = _G[self:GetName().."Pet"..pet]["Ability"..ab];

			if( self:GetID() == Enum.BattlePetOwner.Enemy and PT:IsPVPBattle() ) then
				if( self.player[pet]["ab"..ab.."ok"] ) then
					abilityButton.Approved:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready");
				else
					abilityButton.Approved:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady");
				end
			end

			-- during the battle opening scene, buttons glow red until the player can actually use them - if highlights are enabled
			abilityButton.Cooldown:SetText("");

			if( module.db.profile.cd_highlight ) then
				abilityButton.CooldownBG:SetColorTexture(module.db.profile.cd_highlight_r, module.db.profile.cd_highlight_g, module.db.profile.cd_highlight_b, module.db.profile.cd_highlight_a);
				abilityButton.CooldownBG:Show();
			else
				abilityButton.CooldownBG:Hide();
			end

			if( ab <= self.player[pet].numAbilities ) then
				abID, abName, abIcon, abMaxCD, abDesc, abNumTurns, abType, noStrongWeak = _G.C_PetBattles.GetAbilityInfoByID( self.player[pet]["ab"..ab] );

				-- set ability icon
				abilityButton.bg:SetTexture(abIcon);

				-- check for ability ramping
				if( module.db.profile.ability_ramping ) then
					local ramping = PT:GetAbilityRamping(abID);

					if( ramping ) then
						ramping_show(abilityButton, self:GetID(), pet, abID, ramping);
					end
				else
					ramping_blast(abilityButton);
				end

				-- show ability row on self
				BattleFrame_SetRowVisibility(self, pet, ab, true);

				-- setup vulnerability bonus buttons
				for enemPet = PT.PET_INDEX, self.enemy.numPets do
					abilityButton["Bonus"..enemPet]:SetTexture( PT:GetTypeBonusIcon(abType, self.enemy[enemPet].type, noStrongWeak) );
				end
			else
				-- hide ability row on self and don't attach a script
				script = false;
				BattleFrame_SetRowVisibility(self, pet, ab, false);
			end

			-- when not engaging another pet, we don't need to set the event script
			if( not _G.C_PetBattles.IsInBattle() ) then
				script = false;
			end

			-- we do not need to listen for events, when the button is unused.
			if( script ) then
				abilityButton:SetScript("OnEvent", module.BattleFrame_UpdateAbilityCooldowns);
			else
				abilityButton:SetScript("OnEvent", nil);
			end
		end
	end

	-- called by xml
	function module.BattleFrame_AbilityButton_Hide(self)
		ramping_blast(self);
		self:SetScript("OnEvent", nil);
	end

	-- Updates ability cooldown highlights and cooldown round number
	function module.BattleFrame_UpdateAbilityCooldowns(self, event)
		ramping_update(self);

		local available, cdleft = PT:GetAbilityCooldown(self:GetParent():GetParent():GetID(), self:GetParent():GetID(), self:GetID());

		if( available ) then
			self.Cooldown:SetText("");
			self.CooldownBG:Hide();
		else
			if( module.db.profile.cd_text ) then
				self.Cooldown:SetTextColor(module.db.profile.cd_text_r, module.db.profile.cd_text_g, module.db.profile.cd_text_b, module.db.profile.cd_text_a);
				self.Cooldown:SetText(cdleft > 0 and cdleft or "");
			end
			if( module.db.profile.cd_highlight ) then
				self.CooldownBG:SetColorTexture(module.db.profile.cd_highlight_r, module.db.profile.cd_highlight_g, module.db.profile.cd_highlight_b, module.db.profile.cd_highlight_a);
				self.CooldownBG:Show();
			else
				self.CooldownBG:Hide();
			end
		end
	end
end

---------------------------------------------
-- Battle Frame: Misc Update functions
---------------------------------------------

function module.BattleFrame_UpdateSpeedButtons(self)
	local speed, flying;
	local frame_name = self:GetName();

	for pet = PT.PET_INDEX, self.player.numPets do
		-- iterate through enemy pets and (re-)calculate speed bonuses
		for enemPet = PT.PET_INDEX, self.enemy.numPets do
			-- update speed buttons
			speed, flying = PT:GetSpeedBonus( self.player[pet], self.enemy[enemPet] );

			if( speed == PT.BONUS_SPEED_FASTER ) then -- faster
				_G[frame_name.."Pet"..pet].Type["Speed"..enemPet]:SetVertexColor(1, 1, 1, 1);
			elseif( speed == PT.BONUS_SPEED_EQUAL ) then -- equal
				_G[frame_name.."Pet"..pet].Type["Speed"..enemPet]:SetVertexColor(0.6, 0.6, 0.6, 1);
			elseif( speed == PT.BONUS_SPEED_SLOWER ) then -- slower
				if( flying ) then -- would be faster with active flying bonus
					_G[frame_name.."Pet"..pet].Type["Speed"..enemPet]:SetVertexColor(1, 0, 0, 1);
				else
					_G[frame_name.."Pet"..pet].Type["Speed"..enemPet]:SetVertexColor(0.1, 0.1, 0.1, 1);
				end
			end
		end -- end for enemPet
	end -- end for pet
end

function module.BattleFrame_UpdateHealthState(self)
	local enemy = get_enemy(self);

	local frame_name = self:GetName();
	local enemy_name = enemy:GetName();

	for pet = PT.PET_INDEX, self.player.numPets do
		if( self.player[pet].dead ) then
			_G[frame_name.."Pet"..pet].Button.Dead:Show();
			_G[frame_name.."Pet"..pet].Button.Border:Hide();
			_G[enemy_name.."Header"]["Enemy"..pet].Dead:Show();
			_G[enemy_name.."Header"]["Enemy"..pet].Border:Hide();
		else
			_G[frame_name.."Pet"..pet].Button.Dead:Hide();
			_G[frame_name.."Pet"..pet].Button.Border:Show();
			_G[enemy_name.."Header"]["Enemy"..pet].Dead:Hide();
			_G[enemy_name.."Header"]["Enemy"..pet].Border:Show();
		end

		module.BattleFrame_UpdateModel(_G[frame_name.."Pet"..pet].Model);
		module.BattleFrame_UpdateModel(_G[enemy_name.."Pet"..pet].Model);
	end
end

---------------------------------------------
-- Battle Frame: Update 3D Model Functions
---------------------------------------------

function module.BattleFrame_UpdateModel(self)
	if( not module.db.profile.model3d ) then
		return;
	end

	local parent = self:GetParent();
	local master = parent:GetParent();
	local pet;

	if( parent:GetID() > master.player.numPets ) then
		return;
	else
		pet = master.player[parent:GetID()];
	end

	self:SetDisplayInfo( pet.displayID );
	self:SetRotation(master:GetName() == FRAME_PLAYER and 0.5 or -0.5);
	self:SetDoBlend(true);

	-- choose right animation: pet standing or pet dead
	self:SetAnimation( (pet.dead and 6 or 742), 0);

	-- pet quality fog color
	local color = _G.ITEM_QUALITY_COLORS[pet.quality or 0];
	self.Border:SetVertexColor(color.r, color.g, color.b, 1);
end

----------------------------
-- Ability Highlights
----------------------------

do
	-- Our own implementation of glowing frames in a separate scope
	-- Using Blizzards implementation (defined in FrameXML/ActionButton.lua) could eventually taint all action buttons
	-- because unused glow frames are stored in a secure table and get reused by Blizzards UI elements
	local heap = {}; -- stores unused glow frames
	local glownum = 0;

	-- "blasts" glowing frames: instantly hides them out, removes them from the parent object and puts them into the heap
	local function glowing_blast(self)
		--if( not self ) then return end;
		--
		--local glow = self:GetParent();
		--local frame = glow:GetParent();
		--
		--glow:Hide();
		--
		--table.insert(heap, glow);
		--frame.glowFrame = nil;
	end

	-- glowing frame script OnHide replacement, the original one calls Blizzards glow frame script
	local function glowing_OnHide(self)
		--if( self.animOut:IsPlaying() ) then
		--	self.animOut:Stop();
		--	glowing_blast(self.animOut);
		--end
	end

	-- re-defined this function because it needs to set finished = true
	local function glowing_OnFinished(self)
		--local frame = self:GetParent();
		--local frameWidth, frameHeight = frame:GetSize();
		--frame.spark:SetAlpha(0);
		--frame.innerGlow:SetAlpha(0);
		--frame.innerGlow:SetSize(frameWidth, frameHeight);
		--frame.innerGlowOver:SetAlpha(0.0);
		--frame.outerGlow:SetSize(frameWidth, frameHeight);
		--frame.outerGlowOver:SetAlpha(0.0);
		--frame.outerGlowOver:SetSize(frameWidth, frameHeight);
		--frame.ants:SetAlpha(1.0);
		--
    	--frame.finished = true;
	end

	-- OnUpdate script as used by Blizzard, too
	local function glowing_OnUpdate(self, elapsed)
		--_G.AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, 0.01);
	end

	-- This function is needed because sometimes the animation isn't playing
	-- Sometimes the OnFinish script didn't apply the new alphas, so this function
	-- waits until OnFinished is called, then checks for correct alphas and replaces itself in the OnUpdate handler
	-- when everything works allright
	local function glowing_OnUpdate_Bugfix(self, elapsed)
		--glowing_OnUpdate(self, elapsed);
		--
		--self.elapsed = self.elapsed + elapsed;
		--if( self.elapsed > 0.25 ) then
		--	if( self.finished ) then
		--		if( self.spark:GetAlpha() == 0 and self.innerGlow:GetAlpha() == 0 and self.innerGlowOver:GetAlpha() == 0
		--			and self.outerGlowOver:GetAlpha() == 0 and self.ants:GetAlpha() == 1 ) then
		--			self:SetScript("OnUpdate", nil);
		--			self:SetScript("OnUpdate", glowing_OnUpdate);
		--		else
		--			self.spark:SetAlpha(0);
		--			self.innerGlow:SetAlpha(0);
		--			self.innerGlowOver:SetAlpha(0);
		--			self.outerGlowOver:SetAlpha(0);
		--			self.ants:SetAlpha(1);
		--		end
		--	end
		--	self.elapsed = 0;
		--end
	end

	-- retrieves a glowing frame from the heap or, if there are no unused frames, creates a new
	local function glowing_get()
		--local glow = table.remove(heap);
		--if( not glow ) then
		--	glownum = glownum + 1;
		--	glow = _G.CreateFrame("Frame", "PTGlowFrame"..glownum, _G.UIParent, "ActionBarButtonSpellActivationAlert");
		--
		--	glow.animOut:SetScript("OnFinished", glowing_blast);
		--	glow.animIn:SetScript("OnFinished", glowing_OnFinished);
		--	glow:SetScript("OnHide", glowing_OnHide);
		--end
		--
		--glow.elapsed = 0;
		--glow.finished = false;
		--glow:SetScript("OnUpdate", glowing_OnUpdate_Bugfix);
		--
		--return glow;
	end

	-- show glowing frame: displays a glowing frame and anchors it to its parent
	local function glowing_show(self)
		--if( self.glowFrame ) then
		--	if( self.glowFrame.animOut:IsPlaying() ) then
		--		self.glowFrame.animOut:Stop();
		--		self.glowFrame.animIn:Play();
		--	end
		--else
		--	local glow = glowing_get();
		--	local width, height = self:GetSize();
		--
		--	glow:SetParent(self);
		--	glow:ClearAllPoints();
		--	glow:SetSize(width * 1.6, height * 1.6);
		--	glow:SetPoint("CENTER");
		--	glow.animIn:Play();
		--
		--	self.glowFrame = glow;
		--end
	end

	-- hide glowing frame: hides a glowing frame either with animation or not
	local function glowing_hide(self)
		--local glow = self.glowFrame;
		--
		--if( glow ) then
		--	if( glow.animIn:IsPlaying() ) then
		--		glow.animIn:Stop();
		--	end
		--	if( self:IsVisible() ) then
		--		glow.animOut:Play();
		--	else
		--		glowing_blast(self, glow);
		--	end
		--end
	end

	-- update glowing frame: it depends on status to either show or hide the glowing
	local function glowing_update(self, status)
		--if( status ) then
		--	glowing_show(self);
		--else
		--	glowing_hide(self);
		--end
	end

	-- hides all currently displayed glowing frames on the active frame
	-- module-public function because its needed by the event handler, too
	function module.glowing_hideall(self)
		--local frame_name = self:GetName();
		--local glow;
		--
		--for ab = 1, self.player[self.player.activePet].numAbilities do
		--	glow = _G[frame_name.."Pet"..self.player.activePet]["Ability"..ab].glowFrame;
		--	if( glow ) then
		--		glowing_blast(glow.animOut);
		--	end
		--end
		--
		---- player also may have glowing ability buttons
		--if( self:GetID() == Enum.BattlePetOwner.Ally ) then
		--	for ab = 1, PT.MAX_PET_ABILITY do
		--		glow = _G.PetBattleFrame.BottomFrame.abilityButtons[ab]; -- bitching glow variable
		--		if( glow and glow.glowFrame ) then
		--			glowing_blast(glow.glowFrame.animOut);
		--		end
		--	end
		--end
	end

	-- Updates ability button highlights, retrieves state bonuses from the core and either shows or hides glowing frames
	function module.BattleFrame_UpdateAbilityHighlights(self)
		--if( not _G.C_PetBattles.IsInBattle() ) then
		--	return;
		--end
		--local petFrame = _G[self:GetName().."Pet"..self.player.activePet];
		--
		--if( module.db.profile.ability_highlight ) then
		--	local glow1, glow2, glow3 = PT:GetAbilityStateBonuses(self.player, self.enemy);
		--
		--	glowing_update(petFrame.Ability1, glow1);
		--	glowing_update(petFrame.Ability2, glow2);
		--	glowing_update(petFrame.Ability3, glow3);
		--
		--	-- Applies glowing to players ability buttons in the original UI
		--	if( self:GetID() == Enum.BattlePetOwner.Ally ) then
		--		petFrame = _G.PetBattleFrame.BottomFrame.abilityButtons; -- reusing the petFrame variable. :D
		--
		--		if( module.db.profile.ability_highlight_blizzard ) then
		--			glowing_update(petFrame[1], glow1);
		--			glowing_update(petFrame[2], glow2);
		--			glowing_update(petFrame[3], glow3);
		--		else
		--			glowing_hide(petFrame[1]);
		--			glowing_hide(petFrame[2]);
		--			glowing_hide(petFrame[3]);
		--		end
		--	end
		--else
		--	glowing_hide(petFrame.Ability1);
		--	glowing_hide(petFrame.Ability2);
		--	glowing_hide(petFrame.Ability3);
		--end
	end
end

---------------------------------------------------------
-- Highlighting, Reorganizing, Animation Functions
---------------------------------------------------------

function module.BattleFrame_UpdateActivePetHighlight(self)
	local frame_name = self:GetName();
	local r, g, b, petFrame;

	for pet = PT.PET_INDEX, self.player.numPets do
		-- sets the level color in relation to the active enemy pet
		-- UPDATE NOTICE: there must be an option to reverse the coloring since it may be confusing
		r, g, b = PT:GetDifficultyColor(self.enemy[self.enemy.activePet], self.player[pet]);

		petFrame = _G[frame_name.."Pet"..pet];
		--petFrame.Button.Level:SetTextColor(r, g, b, 1); MODEL
		petFrame.Level:SetTextColor(r, g, b, 1);

		-- set alpha
		if( module.db.profile.nactivealpha_use ) then
			if( pet == self.player.activePet ) then
				petFrame:SetAlpha(1);
			else
				petFrame:SetAlpha(module.db.profile.nactivealpha);
			end
		else
			petFrame:SetAlpha(1);
		end

		if( pet == self.player.activePet and module.db.profile.highlight_active ) then
			petFrame.activeBG:SetAlpha(1);

			if( module.db.profile.animate_active ) then
				petFrame.activeBG.animActive:Play();
			else
				petFrame.activeBG.animActive:Stop();
				petFrame.activeBG:SetAlpha(1);
			end
		else
			petFrame.activeBG.animActive:Stop();
			petFrame.activeBG:SetAlpha(0);
		end

	end
end

function module.BattleFrame_Pets_Reorganize_Exec(self, animate) -- self is PT master frame
	animate = type(animate) == "nil" and true or false;
	animate = animate and module.db.profile.reorganize_ani and true or false;

	local frame_name = self:GetName();

	for i,f in ipairs(self.petFrames) do
		f:ClearAllPoints();

		if( i == 1 ) then
			f:SetPoint("TOPLEFT", frame_name.."Header", "BOTTOMLEFT", 0, -6);
		else
			f:SetPoint("TOPLEFT", self.petFrames[i - 1], "BOTTOMLEFT", 0, -SPACE_PETS);
		end

		if( animate ) then
			f.animShow:Play();
		else
			module.BattleFrame_Pet_ShowFinished(f.animShow); -- dummy
		end
	end
end

-- little sort function which sorts the pet frames, dead pets are displayed last
local function pets_sort(pet1, pet2)
	local master = pet1:GetParent();

	-- if pet frame > numPets, put it last
	local numPets = master.player.numPets;
	if( pet1:GetID() > numPets ) then
		return false;
	elseif( pet2:GetID() > numPets ) then
		return true;
	end

	-- check for active pet
	if( master.player.activePet == pet1:GetID() ) then
		return true;
	elseif( master.player.activePet == pet2:GetID() ) then
		return false;
	end

	-- check for a dead pet
	local dead1 = master.player[pet1:GetID()].dead;
	local dead2 = master.player[pet2:GetID()].dead;
	if( dead1 and not dead2 ) then
		return false;
	elseif( dead2 and not dead1 ) then
		return true;
	end

	-- fall back to pet ID (1, 2, 3) (no pets dead, numPets == MAX_PETS)
	return pet1:GetID() < pet2:GetID();
end

function module.BattleFrame_Pets_Reorganize_Init(self, animate) -- self is PT master frame
	animate = (type(animate) == "nil" or animate == true) and true or false; -- nil/true = animate, false = do not animate

	-- animation can be toggled in configuration
	if( animate and not module.db.profile.reorganize_ani ) then
		animate = false;
	end

	if( animate ) then
		for i,f in ipairs(self.petFrames) do
			f.animHide:Play();
		end
	end

	table.sort(self.petFrames, pets_sort);

	if( not animate ) then
		module.BattleFrame_Pets_Reorganize_Exec(self, animate);
	end
end

-- called by xml
function module.BattleFrame_Pet_HideFinished(self) -- self is animation frame
	local parent = self:GetParent(); -- pet frame
	local master = parent:GetParent(); -- master frame

	master.animDone = master.animDone + 1;
	parent:SetAlpha(0);

	-- if all frames are hidden, the reorganizing shall begin
	if( master.animDone == master.player.numPets ) then
		master.animDone = 0;
		module.BattleFrame_Pets_Reorganize_Exec(master);
	end
end

-- called by xml
function module.BattleFrame_Pet_ShowFinished(self) -- self is animation frame
	local parent = self:GetParent(); -- pet frame
	local alpha = module.db.profile.nactivealpha_use and module.db.profile.nactivealpha or 1;
	parent:SetAlpha( parent:GetID() == parent:GetParent().player.activePet and 1 or alpha );

	-- the reorganization process is finished now, so we can update ability highlights
	-- parent of parent is master
	parent = parent:GetParent();
	module.BattleFrame_UpdateAbilityHighlights(parent);
	module.BattleFrame_UpdateAbilityHighlights(get_enemy(parent)); -- enemy needs update, too!
end

-- called by xml
function module.BattleFrame_Pet_WhilePlaying(self) -- self is animation frame
	local parent = self:GetParent();
	if( module.db.profile.nactivealpha_use and parent:GetID() ~= parent:GetParent().player.activePet ) then
		if( module.db.profile.nactivealpha <= parent:GetAlpha() ) then
			self:Stop();
		end
	end
end

-------------------------------------------------------
-- Misc option setting apply functions and stuff
-------------------------------------------------------

-- also used by drag&drop
local mirrors = {
	TOPLEFT = "TOPRIGHT",
	TOPRIGHT = "TOPLEFT",
	LEFT = "RIGHT",
	RIGHT = "LEFT",
	BOTTOMLEFT = "BOTTOMRIGHT",
	BOTTOMRIGHT = "BOTTOMLEFT",
	CENTER = "CENTER",
	TOP = "TOP",
	BOTTOM = "BOTTOM",
};

-- called by xml and configuration window
function module.BattleFrame_Options_Apply(self)
	local frame_name = self:GetName();

	local value = module.db.profile[frame_name.."_icon"];

	for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
		local petFrame = _G[frame_name.."Pet"..pet];

		-- reanchor level and breed infos
		petFrame.Level:ClearAllPoints();
		petFrame.BreedText:ClearAllPoints();
		petFrame.BreedTexture:ClearAllPoints();

		-- display either 3d models for pets or not and reanchor level and breed strings
		if( module.db.profile.model3d ) then
			-- anchor model, level string
			petFrame.Model:ClearAllPoints();

			if( value == "TOPLEFT" ) then
				petFrame.Model:SetPoint("TOPRIGHT", petFrame.Model:GetParent(), "TOPLEFT", 0, 13);
				petFrame.Level:SetPoint("BOTTOMRIGHT", petFrame.Model.Border, "BOTTOMRIGHT", 0, 0);

				if( module.db.profile.breeds == 1 ) then -- only text
					petFrame.BreedText:SetPoint("BOTTOMLEFT", petFrame.Model.Border, "BOTTOMLEFT", 0, 2);
				elseif( module.db.profile.breeds == 2 ) then -- only icon
					petFrame.BreedTexture:SetPoint("BOTTOMLEFT", petFrame.Model.Border, "BOTTOMLEFT", 0, 0);
				elseif( module.db.profile.breeds == 3 ) then -- both
					petFrame.BreedTexture:SetPoint("BOTTOMLEFT", petFrame.Model.Border, "BOTTOMLEFT", 0, 0);
					petFrame.BreedText:SetPoint("LEFT", petFrame.BreedTexture, "RIGHT", 2, 0);
				end
			else
				petFrame.Model:SetPoint("TOPLEFT", petFrame.Model:GetParent(), "TOPRIGHT", -2, 13);
				petFrame.Level:SetPoint("BOTTOMLEFT", petFrame.Model.Border, "BOTTOMLEFT", 0, 0);

				if( module.db.profile.breeds == 1 ) then -- only text
					petFrame.BreedText:SetPoint("BOTTOMRIGHT", petFrame.Model.Border, "BOTTOMRIGHT", 0, 2);
				elseif( module.db.profile.breeds == 2 ) then -- only icon
					petFrame.BreedTexture:SetPoint("BOTTOMRIGHT", petFrame.Model.Border, "BOTTOMRIGHT", 0, 0);
				elseif( module.db.profile.breeds == 3 ) then -- both
					petFrame.BreedTexture:SetPoint("BOTTOMRIGHT", petFrame.Model.Border, "BOTTOMRIGHT", 0, 0);
					petFrame.BreedText:SetPoint("RIGHT", petFrame.BreedTexture, "LEFT", -1, 0);
				end
			end

			petFrame.Model:Show();

			-- hide pet icon
			petFrame.Button:Hide();
		else
			-- adjust pet icon anchors
			petFrame.Button:ClearAllPoints();
			petFrame.Button:SetPoint(mirrors[value], petFrame.Button:GetParent(), value, (value == "TOPLEFT" and -6 or 4), 0);
			petFrame.Button:Show();

			-- hide 3d model
			petFrame.Model:Hide();

			-- anchor breed infos to icon
			if( value == "TOPLEFT" ) then
				petFrame.BreedText:SetPoint("BOTTOMRIGHT", petFrame.Button, "BOTTOMRIGHT", 1, 2);
				petFrame.BreedTexture:SetPoint("BOTTOMLEFT", petFrame.Button, "BOTTOMLEFT", -4, -2);
			else
				petFrame.BreedText:SetPoint("BOTTOMLEFT", petFrame.Button, "BOTTOMLEFT", 0, 2);
				petFrame.BreedTexture:SetPoint("BOTTOMRIGHT", petFrame.Button, "BOTTOMRIGHT", 4, -2);
			end

			-- anchor level string   <Anchor point="TOP" relativePoint="BOTTOM" x="0" y="-2" />
			petFrame.Level:SetPoint("TOP", petFrame.Button, "BOTTOM", 0, -2);
		end

		-- adjust active highlight colors
		petFrame.activeBG:SetColorTexture(
			module.db.profile.highlight_active_r,
			module.db.profile.highlight_active_g,
			module.db.profile.highlight_active_b,
			0.2 -- the alpha is not adjustable
		);

		-- cut off ability icon borders, or not
		if( module.db.profile.ability_zoom ) then
			for ab = 1, PT.MAX_PET_ABILITY do
				petFrame["Ability"..ab].bg:SetTexCoord(0.078125, 0.921875, 0.078125, 0.921875);
			end
		else
			for ab = 1, PT.MAX_PET_ABILITY do
				petFrame["Ability"..ab].bg:SetTexCoord(0, 1, 0, 1);
			end
		end
	end

	-- adjust frame background colors
	if( module.db.profile.bg ) then
		self.bg:SetColorTexture(module.db.profile.bg_r, module.db.profile.bg_g, module.db.profile.bg_b, module.db.profile.bg_a);
	else
		self.bg:SetColorTexture(0, 0, 0, 0.4);
	end

	-- adjust frame scale
	self:SetScale(module.db.profile.scale);

	-- show or hide the active enemy border
	if( module.db.profile.active_enemy_border ) then
		self.EnemyActive:Show();
	else
		self.EnemyActive:Hide();
	end
end

-----------------------------------
-- Drag&Drop and Positioning
-----------------------------------

-- Well, this Drag&Drop code is coded a little bit nooby, but it is really worth it.
-- I'm currently too lazy to code my own position frame etc., so I used a dirty self-implementation of AceGUI instead.
-- Blame me at wow-addons@grdn.eu or by PM :)

-- enemy frame mirrors the positions of the dragged frame
local mirror = true;
local function do_mirror(self, elapsed)
	-- throttle onUpdate calls
	self.dragElapsed = self.dragElapsed + elapsed;
	if( self.dragElapsed < 0.0417 ) then -- 24 times a second, should be almost fluent
		return;
	end
	self.dragElapsed = 0;

	local point, relativeTo, relativePoint, x, y = self:GetPoint();

	-- re-position the enemy frame
	local enemy = get_enemy(self);

	-- we need to correct x since there is always an inaccuracy of appros 2 pixels
	x = x - 2;

	enemy:ClearAllPoints();
	enemy:SetPoint(mirrors[point], relativeTo, mirrors[point], -x, y);
end

-- called by xml
function module.BattleFrame_StartDrag(self) -- self is master frame
	self:StartMoving();

	if( mirror ) then
		self:SetScript("OnUpdate", do_mirror);
	end
end

-- after dragging stopped, we reanchor both frames to TOPLEFT points instead of LEFT, CENTER, etc.
-- also called from :OnEnable()
function module.BattleFrame_Reanchor(self, from_config)
	local left, top;
	local frame_name = self:GetName();

	if( from_config ) then
		left, top = module.db.profile[frame_name.."_x"], module.db.profile[frame_name.."_y"];
	else
		left, top = self:GetLeft(), self:GetTop();

		-- we must adjust top by both UI and frame scale
		top = ((_G.GetScreenHeight() * _G.UIParent:GetScale() / module.db.profile.scale) - top);

		module.db.profile[frame_name.."_x"] = left;
		module.db.profile[frame_name.."_y"] = top;
	end

	self:ClearAllPoints();
	self:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", left, -top);
end

-- called by xml
function module.BattleFrame_StopDrag(self) -- self is master frame
	self:StopMovingOrSizing();

	if( mirror ) then
		self:SetScript("OnUpdate", nil);
		do_mirror(self, 0);
	end

	local enemy = get_enemy(self);
	module.BattleFrame_Reanchor(self);
	module.BattleFrame_Reanchor(enemy);

	-- set to true so the UI saves and restores their positions automatically
	self:SetUserPlaced(false);
	enemy:SetUserPlaced(false);
end

-- fake AceGUI widget with custom close callback, which acts as our container
-- we also must adjust little things so the container fit our needs.
local container = LibStub("AceGUI-3.0"):Create("Frame");
container:Hide(); -- damn auto show -.-
container:EnableResize(false); -- resizing is not allowed!

-- called when closing the little window
container:SetCallback("OnClose", function(widget, event)
	local appName = widget:GetUserData("appName");
	LibStub("AceConfigDialog-3.0").OpenFrames[appName] = nil;
	widget:Hide();

	-- unregister dragging mouse buttons
	_G[FRAME_PLAYER]:RegisterForDrag();
	_G[FRAME_ENEMY]:RegisterForDrag();

	-- hiding the frames during a battle is sort of annoying
	if( not _G.C_PetBattles.IsInBattle() ) then
		_G[FRAME_PLAYER]:Hide();
		_G[FRAME_ENEMY]:Hide();

		-- when not in a battle, call /pt to re-open the options frame
		pcall(_G.SlashCmdList["PT"]);
	end
end);

-- called by the "edit positions" button in the config window
local function OpenPositioning()
	LibStub("AceConfigDialog-3.0"):Open("PokemonTrainer_FrameCombatDisplay", container); -- container == our custom AceGUI container

	if( not _G.C_PetBattles.IsInBattle() ) then
		PT:ScanDummyPets();
	end

	for _,frame in ipairs(BattleFrames) do
		frame:Show();
		frame:RegisterForDrag("LeftButton");
	end
end

-- called by :OnInitialize
local function get_pet_icon(info)
	return module.db.profile[info.arg.."_icon"];
end

local function set_pet_icon(info, value)
	module.db.profile[info.arg.."_icon"] = value;
	module.BattleFrame_Options_Apply(_G[info.arg]);
end

function module:GetPositionOptions()
	local options = {
		name = L["More settings"],
		type = "group",
		args = {
			info = {
				type = "description",
				name = L["You can now move the frames by dragging them around."],
				order = 1,
			},
			spacer1 = { type = "description", name = "", order = 1.1 },
			mirror = {
				type = "toggle",
				name = L["Mirror frames"],
				desc = L["When moving a battle frame, the enemy frame gets mirrored to the opposite side of the screen."],
				order = 2,
				get = function()
					return mirror;
				end,
				set = function(_, value)
					mirror = value;
				end,
			},
			scale = {
				type = "range",
				name = L["Frame scale"],
				min = 0.5,
				max = 2.0,
				step = 0.05,
				order = 2.1,
				get = function()
					return module.db.profile.scale;
				end,
				set = function(_, value)
					module.db.profile.scale = value;
					module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
					module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
					do_mirror(_G[FRAME_ENEMY], 1); -- for styling purposes, scaling smells
				end,
			},
			spacer2 = { type = "description", name = "", order = 2.2 },
			bg = {
				type = "toggle",
				name = L["Override color"],
				desc = L["Battle frames are usually colored black. Enable to set your own color."],
				order = 3,
				get = function()
					return module.db.profile.bg;
				end,
				set = function(_, value)
					module.db.profile.bg = value;
					module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
					module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
				end,
			},
			bg_color = {
				type = "color",
				name = _G.COLOR,
				order = 4,
				hasAlpha = true,
				get = function()
					return module.db.profile.bg_r, module.db.profile.bg_g, module.db.profile.bg_b, module.db.profile.bg_a;
				end,
				set = function(_, r, g, b, a)
					module.db.profile.bg_r = r;
					module.db.profile.bg_g = g;
					module.db.profile.bg_b = b;
					module.db.profile.bg_a = a;
					module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
					module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
				end,
			},
			spacer3 = { type = "description", name = "", order = 4.1 },
			model3d = {
				type = "toggle",
				name = "|TInterface\\OptionsFrame\\UI-OptionsFrame-NewFeatureIcon:0:0:0:0|t".."Use 3D Models",
				desc = "Display either 3D models for pets or not.",
				order = 4.4,
				get = function()
					return module.db.profile.model3d;
				end,
				set = function(_, value)
					module.db.profile.model3d = value;
					module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
					module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
				end,
			},
			breeds = {
				type = "select",
				name = L["Display breeds"],
				desc = L["Perhaps, you heard of battle pet breeds before. Any pet has an assigned breed ID which defines which stats will grow larger than others while leveling up. Stats are health, power and speed. When this option is enabled, you can actually see pet breeds in during battles."],
				order = 4.5,
				get = function()
					return module.db.profile.breeds;
				end,
				set = function(_, value)
					module.db.profile.breeds = value;
					module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
					module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
				end,
				values = {
					[0] = _G.NONE,
					[1] = L["As text"],
					[2] = L["As image"],
					[3] = L["Both"],
				},
			},
			hint1 = {
				type = "description",
				name = L["You need to re-open this window when changing breed settings."],
				order = 4.9,
			},
			spacer4 = { type = "description", name = "", order = 4.9 },
			peticon1 = {
				type = "select",
				name = L["Player: pet icons"],
				order = 5,
				get = get_pet_icon,
				set = set_pet_icon,
				values = {
					["TOPLEFT"] = L["Left"],
					["TOPRIGHT"] = L["Right"],
				},
				arg = FRAME_PLAYER,
			},
			peticon2 = {
				type = "select",
				name = L["Enemy: pet icons"],
				order = 6,
				get = get_pet_icon,
				set = set_pet_icon,
				values = {
					["TOPLEFT"] = L["Left"],
					["TOPRIGHT"] = L["Right"],
				},
				arg = FRAME_ENEMY,
			},
			activepets = {
				name = L["Pet highlightning"],
				type = "group",
				inline = true,
				order = 7,
				args = {
					active = {
						type = "toggle",
						name = L["Highlight active pets"],
						desc = L["Currently active pets will have a background color, if this option is activated."],
						order = 1,
						width = "full",
						get = function()
							return module.db.profile.highlight_active;
						end,
						set = function(_, value)
							module.db.profile.highlight_active = value;
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_PLAYER]);
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_ENEMY]);
						end,
					},
					active_animate = {
						type = "toggle",
						name = L["With animation"],
						desc = L["In addition, the background of active pets gets animated with a smooth effect."],
						order = 1.1,
						get = function()
							return module.db.profile.animate_active;
						end,
						set = function(_, value)
							module.db.profile.animate_active = value;
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_PLAYER]);
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_ENEMY]);
						end,
					},
					active_color = {
						type = "color",
						name = _G.COLOR,
						order = 1.2,
						get = function()
							return module.db.profile.highlight_active_r, module.db.profile.highlight_active_g, module.db.profile.highlight_active_b;
						end,
						set = function(_, r, g, b, a)
							module.db.profile.highlight_active_r = r;
							module.db.profile.highlight_active_g = g;
							module.db.profile.highlight_active_b = b;
							module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
							module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
						end,
					},
					active_enemy_border = {
						type = "toggle",
						name = L["Display active enemy borders"],
						desc = L["Draws a border around the column of currently active enemys, so it is easier to detect the active pet on your frame for comparing bonuses."],
						order = 1.3,
						width = "full",
						get = function()
							return module.db.profile.active_enemy_border;
						end,
						set = function(_, value)
							module.db.profile.active_enemy_border = value;
							module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
							module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
						end,
					},
					nactivealpha_use = {
						type = "toggle",
						name = L["Inactive pet alpha"],
						desc = L["Enable if you want to override the alpha of inactive pets. Set the new value on the right."],
						order = 2,
						get = function()
							return module.db.profile.nactivealpha_use;
						end,
						set = function(_, value)
							module.db.profile.nactivealpha_use = value;
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_PLAYER]);
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_ENEMY]);
						end,
					},
					nactivealpha = {
						type = "range",
						name = L["Value"],
						min = 0.05,
						max = 0.95,
						step = 0.05,
						order = 3,
						get = function()
							return module.db.profile.nactivealpha;
						end,
						set = function(_, value)
							module.db.profile.nactivealpha = value;
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_PLAYER]);
							module.BattleFrame_UpdateActivePetHighlight(_G[FRAME_ENEMY]);
						end,
						disabled = is_disabled,
					},
				},
			},
		},
	};

	module.GetPositionOptions = nil;
	return options;
end

----------------------
-- Option Table
----------------------

local function is_disabled(info)
	return not module:IsEnabled() and true or not module.db.profile[info[#info].."_use"];
end

local function is_highlight_disabled(info)
	return not module:IsEnabled() and true or not module.db.profile.ability_highlight;
end

function module:GetOptions()
	return {
		frame = {
			name = L["Frame-related options"],
			type = "group",
			inline = true,
			order = 2,
			args = {
				resize = {
					type = "toggle",
					name = L["Auto-resize"],
					desc = L["Battle frames are getting resized when players have less than three pets."],
					order = 1,
					get = function()
						return self.db.profile.resize;
					end,
					set = function(_, value)
						self.db.profile.resize = value;
					end,
				},
				drag = {
					type = "execute",
					name = L["More settings"],
					order = 2,
					func = OpenPositioning,
				},
			},
		},
		reorganize = {
			name = L["Reorganize pets by activity"],
			type = "group",
			inline = true,
			order = 3,
			args = {
				use = {
					type = "toggle",
					name = L["Enable"],
					desc = L["If enabled, active pets are displayed first."],
					order = 1,
					get = function()
						return self.db.profile.reorganize_use;
					end,
					set = function(_, value)
						self.db.profile.reorganize_use = value;
					end,
				},
				reorganize = {
					type = "toggle",
					name = L["Animate reorganizing"],
					desc = L["Reorganizing will take place with a cool animation."],
					order = 2,
					get = function()
						return self.db.profile.reorganize_ani;
					end,
					set = function(_, value)
						self.db.profile.reorganize_ani = value;
					end,
					disabled = is_disabled,
				},
			},
		},
		ability = {
			name = L["General ability settings"],
			type = "group",
			inline = true,
			order = 5,
			args = {
				ability_zoom = {
					type = "toggle",
					name = L["Cut off ability icon borders"],
					desc = L["Removes the borders from any ability icon displayed by PT. Only for styling purposes."],
					order = 1,
					width = "full",
					get = function()
						return self.db.profile.ability_zoom;
					end,
					set = function(_, value)
						self.db.profile.ability_zoom = value;
						module.BattleFrame_Options_Apply(_G[FRAME_PLAYER]);
						module.BattleFrame_Options_Apply(_G[FRAME_ENEMY]);
					end,
				},
				ability_ramping = {
					type = "toggle",
					name = L["Display ability amplifying state"],
					desc = L["Some abilities get stronger on each usage. If this option is enabled, you will see a red dot which gets more green the more you are using these abilities."],
					order = 2,
					width = "full",
					get = function()
						return self.db.profile.ability_ramping;
					end,
					set = function(_, value)
						self.db.profile.ability_ramping = value;
					end,
					disabled = _G.C_PetBattles.IsInBattle,
				},
			},
		},
		cooldowns = {
			name = L["Pet ability cooldowns"],
			type = "group",
			inline = true,
			order = 6,
			args = {
				text = {
					type = "toggle",
					name = L["Display rounds"],
					desc = L["Whether to show the cooldown of abilities on the buttons or not."],
					order = 1,
					get = function()
						return self.db.profile.cd_text;
					end,
					set = function(_, value)
						self.db.profile.cd_text = value;
					end,
				},
				text_color = {
					type = "color",
					name = _G.COLOR,
					order = 2,
					hasAlpha = true,
					get = function()
						return self.db.profile.cd_text_r, self.db.profile.cd_text_g, self.db.profile.cd_text_b, self.db.profile.cd_text_a;
					end,
					set = function(_, r, g, b, a)
						self.db.profile.cd_text_r = r;
						self.db.profile.cd_text_g = g;
						self.db.profile.cd_text_b = b;
						self.db.profile.cd_text_a = a;
					end,
				},
				highlight = {
					type = "toggle",
					name = L["Highlight"],
					desc = L["Highlights ability buttons with a color when they are on cooldown."],
					order = 3,
					get = function()
						return self.db.profile.cd_highlight;
					end,
					set = function(_, value)
						self.db.profile.cd_highlight = value;
					end,
				},
				highlight_color = {
					type = "color",
					name = _G.COLOR,
					order = 4,
					hasAlpha = true,
					get = function()
						return self.db.profile.cd_highlight_r, self.db.profile.cd_highlight_g, self.db.profile.cd_highlight_b, self.db.profile.cd_highlight_a;
					end,
					set = function(_, r, g, b, a)
						self.db.profile.cd_highlight_r = r;
						self.db.profile.cd_highlight_g = g;
						self.db.profile.cd_highlight_b = b;
						self.db.profile.cd_highlight_a = a;
					end,
				},
			},
		},
		broken = {
			name = "Currently broken",
			type = "group",
			inline = true,
			order = 7,
			args = {
				ability_highlight = {
					type = "toggle",
					name = L["Highlight buffed abilities"],
					desc = L["Whenever your abilities are doing more damage based on buffs or weather, they will glow."],
					order = 1,
					get = function()
						return false -- disabled until a workaround for the Blizzard rewrite is found.
						--return self.db.profile.ability_highlight;
					end,
					set = function(_, value)
						--self.db.profile.ability_highlight = value;
					end,
					disabled = true -- disabled until a workaround for the Blizzard rewrite is found.
				},
				ability_highlight_blizzard = {
					type = "toggle",
					name = L["...on Blizzard Bar"],
					desc = L["Applys ability glowing states on Blizzards Pet Action Buttons, too."],
					order = 2,
					get = function()
						return false -- disabled until a workaround for the Blizzard rewrite is found.
						--return self.db.profile.ability_highlight_blizzard;
					end,
					set = function(_, value)
						--self.db.profile.ability_highlight_blizzard = value;
					end,
					--disabled = is_highlight_disabled,
					disabled = true -- disabled until a workaround for the Blizzard rewrite is found.
				},
			},
		},

	};
end