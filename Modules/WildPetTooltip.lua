-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, PT = ...;
local module = PT:NewModule("WildPetTooltip", "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local _G = _G;

----------------------
-- Variables
----------------------

module.displayName = L["Battle Pet Tooltip"];
module.desc = L["Add battle-specific informations to battle pet tooltips."];

-------------------------
-- Module Handling
-------------------------

function module:OnInitialize()
	self.db = PT.db:RegisterNamespace("WildPetTooltip", {
		profile = {
			enabled = true,
			battlelevel = true,
			battlelevelonlydiff = true,
			consolidated = false,
			onlywildpets = false,
		},
	});

	if( not self.db.profile.enabled ) then
		self:SetEnabledState(false);
	end
end

function module:OnEnable()
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "ProcessTooltip");
end

function module:OnDisable()
	self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT");
end

------------------------
-- Change Tooltip
------------------------

local function get_ability_infos(petLevel, slot, ab, enemyType)
	if( slot > (petLevel >= 4 and 3 or petLevel >= 2 and 2 or 1) ) then
		return;
	end
	local _, abName, abIcon, _, _, _, abType, noStrongWeak = _G.C_PetBattles.GetAbilityInfoByID(ab);

	return PT:GetTypeBonus(abType, enemyType, noStrongWeak), abName, abIcon;
end

local function isStrongWeak(strong, weak, modifier)
	if( modifier > 1 ) then
		strong = true;
	elseif( modifier < 1 ) then
		weak = true;
	end

	return strong, weak;
end

function module:ProcessTooltip()
	local name, unit = _G.GameTooltip:GetUnit();

	local func = self.db.profile.onlywildpets and _G.UnitIsWildBattlePet or _G.UnitIsBattlePet;
	if( not unit or not func(unit) ) then
		return;
	end

	local numLines = _G.GameTooltip:NumLines();
	local battleLevelText = L["Battle Level"];

	for i = 1, numLines do
		local line = _G["GameTooltipTextLeft" .. i];
		if line and line:GetText() and line:GetText():find(battleLevelText) then
			-- Already processed, don't add again
			return;
		end
	end

	local enemyType, enemyLevel = _G.UnitBattlePetType(unit), _G.UnitBattlePetLevel(unit)

	local petID, ab1, ab2, ab3, slotLocked;
	local _, customName, petLevel, petName, petType;
	local r, g, b;
	local modifier, abName, abIcon;
	local strong, weak;

	if( self.db.profile.battlelevel and not(self.db.profile.battlelevelonlydiff and enemyLevel == _G.UnitLevel(unit)) ) then
		_G.GameTooltip:AddDoubleLine("|cffffffff"..L["Battle Level"].."|r  "..enemyLevel);
	end

	_G.GameTooltip:AddLine(" ");

	for pet = PT.PET_INDEX, PT.MAX_COMBAT_PETS do
		petID, ab1, ab2, ab3, slotLocked = _G.C_PetJournal.GetPetLoadOutInfo(pet);

		if( not slotLocked and petID ) then
			_, customName, petLevel, _, _, _, _, petName, _, petType = _G.C_PetJournal.GetPetInfoByPetID(petID);
			petName = customName and customName.." (|cffffffff"..petName.."|r)" or petName;

			r, g, b = PT:GetDifficultyColor(petLevel, enemyLevel);

			if( self.db.profile.consolidated ) then
				strong, weak = false, false;

				-- Ability 1
				modifier = get_ability_infos(petLevel, 1, ab1, enemyType);
				if( modifier ) then
					strong, weak = isStrongWeak(strong, weak, modifier);
				end

				-- Ability 2
				modifier = get_ability_infos(petLevel, 2, ab2, enemyType);
				if( modifier ) then
					strong, weak = isStrongWeak(strong, weak, modifier);
				end

				-- Ability 3
				modifier = get_ability_infos(petLevel, 3, ab3, enemyType);
				if( modifier ) then
					strong, weak = isStrongWeak(strong, weak, modifier);
				end

				_G.GameTooltip:AddDoubleLine(
					petName.."  "..("|cff%02x%02x%02x%s|r"):format(r *255, g *255, b *255, petLevel),
					(strong and "|T"..PT:GetTypeBonusIcon(1.5)..":14:14|t" or "")..
					(weak and "|T"..PT:GetTypeBonusIcon(0.5)..":14:14|t" or "")..
					(not strong and not weak and "|T"..PT:GetTypeBonusIcon(1)..":14:14|t" or "")
				);
			else
				if( pet > 1 ) then
					_G.GameTooltip:AddLine(" ");
				end

				-- Pet Type
				_G.GameTooltip:AddDoubleLine(
					petName.."  "..("|cff%02x%02x%02x%s|r"):format(r *255, g *255, b *255, petLevel),
					"|T"..PT:GetTypeIcon(petType)..":14:14:0:0:128:256:62:102:128:169|t"
				);

				-- Ability 1
				modifier, abName, abIcon = get_ability_infos(petLevel, 1, ab1, enemyType);
				if( modifier ) then
					_G.GameTooltip:AddDoubleLine(
						" |T"..abIcon..":14:14|t |cffffffff"..abName.."|r",
						"|T"..PT:GetTypeBonusIcon(modifier)..":14:14|t"
					);
				end

				-- Ability 2
				modifier, abName, abIcon = get_ability_infos(petLevel, 2, ab2, enemyType);
				if( modifier ) then
					_G.GameTooltip:AddDoubleLine(
						" |T"..abIcon..":14:14|t |cffffffff"..abName.."|r",
						"|T"..PT:GetTypeBonusIcon(modifier)..":14:14|t"
					);
				end

				-- Ability 3
				modifier, abName, abIcon = get_ability_infos(petLevel, 3, ab3, enemyType);
				if( modifier ) then
					_G.GameTooltip:AddDoubleLine(
						" |T"..abIcon..":14:14|t |cffffffff"..abName.."|r",
						"|T"..PT:GetTypeBonusIcon(modifier)..":14:14|t"
					);
				end
			end
		end
	end

	_G.GameTooltip:Show();
end

----------------------
-- Option Table
----------------------

do
	local function is_disabled()
		return not(module:IsEnabled() and module.db.profile.battlelevel);
	end

	function module:GetOptions()
		return {
			battlelevel = {
				type = "toggle",
				name = L["Display battle pet level"],
				desc = L["Sometimes the actual battle pet level differs from the NPC pet level."],
				get = function()
					return self.db.profile.battlelevel;
				end,
				set = function(_, value)
					self.db.profile.battlelevel = value;
				end,
				order = 1,
				width = "full",
			},
			battlelevelonlydiff = {
				type = "toggle",
				name = L["...only on different levels"],
				get = function()
					return self.db.profile.battlelevelonlydiff;
				end,
				set = function(_, value)
					self.db.profile.battlelevelonlydiff = value;
				end,
				order = 2,
				width = "full",
				disabled = is_disabled,
			},
			spacer = { type = "description", name = " ", order = 3 },
			consolidated = {
				type = "toggle",
				name = L["Consolidated battle infos"],
				desc = L["Display your battle pet team without their abilities and if they have at least one bonus or weakness."],
				get = function()
					return self.db.profile.consolidated;
				end,
				set = function(_, value)
					self.db.profile.consolidated = value;
				end,
				order = 4,
				width = "full",
			},
			onlywildpets = {
				type = "toggle",
				name = L["Display battle infos only on wild pets"],
				desc = L["If this is not set, battle infos are also displayed on NPC and player pets."],
				get = function()
					return self.db.profile.onlywildpets;
				end,
				set = function(_, value)
					self.db.profile.onlywildpets = value;
				end,
				order = 5,
				width = "full",
			},
		};
	end
end