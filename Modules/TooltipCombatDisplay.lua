-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, PT = ...;
local module = PT:NewModule("TooltipCombatDisplay", "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);
local AceTimer = LibStub("AceTimer-3.0"); -- we don't embed it since its just used by the config window...

local _G = _G;

LibStub("iLib"):EmbedTooltipFunctions(module, module.name);

----------------------
-- Variables
----------------------

module.order = 2;
module.displayName = function() return (module:IsEnabled() and "|cff00ff00%s|r" or "|cffff0000%s|r"):format(L["Display: Tooltip"]) end
module.desc = L["LibQTip based combat display for Pet Battles and the old way of displaying things.. Disable it if you want to use the frame based combat display."];
module.noEnableButton = true;

local COLOR_RED = "|cffff0000%s|r";
local COLOR_GOLD = "|cfffed100%s|r";

local icon_size = 22;

-------------------------
-- Module Handling
-------------------------

function module:OnInitialize()
	self.db = PT.db:RegisterNamespace("TooltipCombatDisplay", {
		profile = {
			pos_x = 0,
			pos_y = 300,
			scale = 1,
		},
	});

	if( PT.db.profile.activeBattleDisplay ~= 2 ) then
		self:SetEnabledState(false);
	end
end

function module:OnEnable()
	self:RegisterEvent("PET_BATTLE_OPENING_START", "PetBattleStart");
	self:RegisterEvent("PET_BATTLE_OVER", "PetBattleStop");
	self:RegisterEvent("PET_BATTLE_CLOSE", "PetBattleStop");
	self:RegisterEvent("PET_BATTLE_PET_CHANGED", "PetBattleChanged");
	self:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE", "PetBattleChanged");
	--self:RegisterEvent("PET_BATTLE_HEALTH_CHANGED", "PetBattleChanged");
	--self:RegisterEvent("PET_BATTLE_MAX_HEALTH_CHANGED", "PetBattleChanged");
end

function module:OnDisable()
	self:UnregisterEvent("PET_BATTLE_OPENING_START");
	self:UnregisterEvent("PET_BATTLE_OVER");
	self:UnregisterEvent("PET_BATTLE_CLOSE");
	self:UnregisterEvent("PET_BATTLE_PET_CHANGED");
	self:UnregisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE");
	--self:UnregisterEvent("PET_BATTLE_HEALTH_CHANGED");
	--self:UnregisterEvent("PET_BATTLE_MAX_HEALTH_CHANGED");
end

-------------------------
-- Event callbacks
-------------------------

do
	local function update_player(tip) module:UpdateTooltip(tip, Enum.BattlePetOwner.Ally, PT.PlayerInfo, PT.EnemyInfo)  end
	local function update_enemy(tip)  module:UpdateTooltip(tip, Enum.BattlePetOwner.Enemy,  PT.EnemyInfo,  PT.PlayerInfo) end
	
	function module:PetBattleStart(event)
		if( event ~= "NOSCAN" ) then -- developer stuff
			PT:ScanPets();
		end -- dev stuff
		
		local tip;
		
		tip = self:GetTooltip("Player", update_player);
		tip:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", self.db.profile.pos_x, -self.db.profile.pos_y);
		tip:SetFrameStrata("LOW");
		tip:SetScale(self.db.profile.scale);
		tip:Show();
		
		tip = self:GetTooltip("Enemy", update_enemy);
		tip:SetPoint("TOPRIGHT", _G.UIParent, "TOPRIGHT", -self.db.profile.pos_x, -self.db.profile.pos_y);
		tip:SetFrameStrata("LOW");
		tip:SetScale(self.db.profile.scale);
		tip:Show();
	end
end

function module:PetBattleStop()
	if( self:IsTooltip("Player") ) then
		self:GetTooltip("Player"):Release();
	end
	if( self:IsTooltip("Enemy") ) then
		self:GetTooltip("Enemy"):Release();
	end
end

function module:PetBattleChanged()
	PT:RoundUpPets();
	self:CheckTooltips("Player", "Enemy");
end

--------------------------
-- Helper functions
--------------------------

local function helper_pettype_icon(pet)
	return "|T"..PT:GetTypeIcon(pet.type)..":"..icon_size..":"..icon_size..":0:0:128:256:62:102:128:169|t";
end

local function helper_pet_quality(pet)
	local color = _G.ITEM_QUALITY_COLORS[pet.quality or 0];
	return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, pet.name);
end

local function helper_pet_level(pet, enemy)
	local r, g, b = PT:GetDifficultyColor(enemy, pet);
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, pet.level);
end

local function helper_ability_cd(side, pet, ab, abName)
	local available, cdleft = PT:GetAbilityCooldown(side, pet, ab);
	
	if( not available ) then
		return (COLOR_RED):format(abName..(cdleft > 0 and " ("..cdleft..")" or ""));
	else
		return (COLOR_GOLD):format(abName);
	end
end

-------------------------------
-- Speed icon qtip cells
-------------------------------

local cell_provider, cell_prototype = LibStub("LibQTip-1.0"):CreateCellProvider();

function cell_prototype:InitializeCell()
	local bg = self:CreateTexture(nil, "BACKGROUND", "PTTextureBonusTemplate");
	self.bg = bg;
	bg:SetAllPoints(self);
	
	local icon = self:CreateTexture(nil, "OVERLAY", "PTTextureSpeedTemplate");
	self.icon = icon;
	icon:ClearAllPoints(); -- there are preset points cause of set in xml :D
	icon:SetPoint("LEFT", 5, 0);
	icon:SetPoint("RIGHT", -5, 0);
	icon:SetPoint("TOP", 0, -5);
	icon:SetPoint("BOTTOM", 0, 5);
end

function cell_prototype:SetupCell(tooltip, speed, justification, font, r, g, b)
	if( speed == PT.BONUS_SPEED_FASTER ) then
		self.icon:SetVertexColor(1, 1, 1, 1);
	elseif( speed == PT.BONUS_SPEED_EQUAL ) then
		self.icon:SetVertexColor(0.6, 0.6, 0.6, 1);
	elseif( speed == PT.BONUS_SPEED_SLOWER ) then
		self.icon:SetVertexColor(0.1, 0.1, 0.1, 1);
	else
		self.icon:SetVertexColor(1, 0, 0, 1);
	end
			
	return icon_size, icon_size;
end

-----------------------------------
-- Ability tooltip functions
-----------------------------------

local function tooltip_ability_show(anchor, t)
	local side, pet, ab = unpack(t);
	
	_G.PetBattleAbilityTooltip_SetAbility(side, pet, ab);
	
	if( side == Enum.BattlePetOwner.Ally ) then
		_G.PetBattleAbilityTooltip_Show("TOPLEFT", anchor, "RIGHT", 10, 4);
	else
		_G.PetBattleAbilityTooltip_Show("TOPRIGHT", anchor, "LEFT", -10, 4);
	end
end	

local function tooltip_ability_hide()
	_G.PetBattlePrimaryAbilityTooltip:Hide();
end

-----------------------
-- UpdateTooltip
-----------------------

function module:UpdateTooltip(tip, side, player, enemy)
	tip:Clear();
	tip:SetColumnLayout(2 + enemy.numPets, "LEFT", "LEFT", "CENTER", "CENTER", "CENTER");
	
	local line;
	
	-- adding enemy pet icons
	line = tip:AddLine("");
	for pet = 1, enemy.numPets do
		tip:SetCell(line, 2 + pet, "|T"..enemy[pet].icon..":"..icon_size..":"..icon_size.."|t");
		
		if( pet == enemy.activePet ) then
			if( side == Enum.BattlePetOwner.Ally ) then
				tip:SetColumnColor(2 + pet, 1, 0, 0, 0.5);
			else
				tip:SetColumnColor(2 + pet, 0, 1, 0, 0.5);
			end
		else
			tip:SetColumnColor(2 + pet, 0, 0, 0, 0);
		end
	end
	
	-- adding pets one after another
	local speed, flying;
	local abID, abName, abIcon, abMaxCD, abDesc, abNumTurns, abType, noStrongWeak;
	
	for pet = 1, player.numPets do
		if( pet > 1 ) then
			tip:AddSeparator();
		end
		
		line = tip:AddLine(
			helper_pettype_icon(player[pet]),
			helper_pet_quality(player[pet]).."  "..helper_pet_level(player[pet], enemy[enemy.activePet])
		);
		
		for enemPet = 1, enemy.numPets do
			speed, flying = PT:GetSpeedBonus( player[pet], enemy[enemPet] );
			tip:SetCell(line, 2 + enemPet, flying and -1 or speed, cell_provider);
		end
		
		-- coloring active pet
		if( pet == player.activePet ) then
			if( side == Enum.BattlePetOwner.Ally ) then
				tip:SetLineColor(line, 0, 1, 0, 0.5);
			else
				tip:SetLineColor(line, 1, 0, 0, 0.5);
			end
		end
		
		-- adding the abilities and their bonuses
		for ab = 1, player[pet].numAbilities do
			abID, abName, abIcon, abMaxCD, abDesc, abNumTurns, abType, noStrongWeak = _G.C_PetBattles.GetAbilityInfoByID( player[pet]["ab"..ab] );
			line = tip:AddLine("|T"..abIcon..":"..icon_size..":"..icon_size.."|t", helper_ability_cd(side, pet, ab, abName));
			
			for enemPet = 1, enemy.numPets do
				tip:SetCell(line, 2 + enemPet, "|T"..PT:GetTypeBonusIcon(abType, enemy[enemPet].type, noStrongWeak)..":"..icon_size..":"..icon_size.."|t" );
			end
			
			tip:SetLineScript(line, "OnEnter", tooltip_ability_show, {side, pet, ab}); -- creates 18 tables (=2 sides, 3 pets, 3 abilities)
			tip:SetLineScript(line, "OnLeave", tooltip_ability_hide);
		end
	end	
	
end

----------------------
-- Option Table
----------------------

local timer;
local function dummy_tooltip_hide()
	module:PetBattleStop();
	timer = nil;
end

local function dummy_tooltip_show()
	PT:ScanDummyPets();
	module:PetBattleStart("NOSCAN");
	
	if( _G.C_PetBattles.IsInBattle() ) then
		return;
	end
	
	if( timer ) then
		AceTimer.CancelTimer(module, timer);
	end
	timer = AceTimer.ScheduleTimer(module, dummy_tooltip_hide, 5);
end

function module:GetOptions()	
	return {
		scale = {
			type = "range",
			name = L["Frame scale"],
			order = 1,
			min = 0.5,
			max = 2,
			step = 0.05,
			get = function()
				return module.db.profile.scale;
			end,
			set = function(_, value)
				module.db.profile.scale = value;
				dummy_tooltip_show();
			end,
		},
		spacer = { type = "description", name = "", order = 1.1 },
		pos_x = {
			type = "range",
			name = L["Horizontal position"],
			order = 2,
			min = 1, 
			max = math.floor((_G.GetScreenWidth() * _G.UIParent:GetScale() / module.db.profile.scale) / 2),
			step = 1,
			get = function()
				return module.db.profile.pos_x;
			end,
			set = function(_, value)
				module.db.profile.pos_x = value;
				dummy_tooltip_show();
			end,
		},
		pos_y = {
			type = "range",
			name = L["Vertical position"],
			order = 3,
			min = 1,
			max = math.floor(_G.GetScreenHeight() * _G.UIParent:GetScale() / module.db.profile.scale),
			step = 1,
			get = function()
				return module.db.profile.pos_y;
			end,
			set = function(_, value)
				module.db.profile.pos_y = value;
				dummy_tooltip_show();
			end,
		},
	};
end