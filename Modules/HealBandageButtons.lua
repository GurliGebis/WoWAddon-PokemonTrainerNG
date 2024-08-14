-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, PT = ...;
local module = PT:NewModule("HealBandageButtons", "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local _G = _G;

----------------------
-- Variables
----------------------

module.displayName = L["Heal Pet Buttons"];
module.desc = L["When pet tracking is enabled, this module displays two buttons on a separate and draggable frame. One for healing your battle pets with the spellcast, another for healing with pet bandages. Clicking these buttons is allowed when not in combat."];

module.petHealSpell = 125439; -- Blizzard_PetJournal.lua
module.petBandage = 86143; -- item id

-------------------------
-- Module Handling
-------------------------

function module:OnInitialize()
	self.db = PT.db:RegisterNamespace("HealBandageButtons", {
		profile = {
			enabled = false,
			scale = 1,
			draggable = true,
			mousebutton = "type1",
			modifier = "alt-",
		},
	});

	if( not self.db.profile.enabled ) then
		self:SetEnabledState(false);
	end
	
	-- set options
	_G.PTHealBandageFrame:SetScale(module.db.profile.scale);
	self:SetDraggable();
	self:SetBindings(false, false);
end

function module:OnEnable()	
	self:RegisterEvent("MINIMAP_UPDATE_TRACKING", "CheckMinimapTracking");
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "CombatEvent", true);
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "CombatEvent", false);
	
	self:CheckMinimapTracking();
end

function module:OnDisable()
	self:UnregisterEvent("MINIMAP_UPDATE_TRACKING");
	self:UnregisterEvent("PLAYER_REGEN_DISABLED");
	self:UnregisterEvent("PLAYER_REGEN_ENABLED");
	
	_G.PTHealBandageFrame:Hide();
end

------------------------
-- Event Handlers
------------------------

function module:CombatEvent(in_combat)
	if( in_combat ) then
		self.prevdisplayed = _G.PTHealBandageFrame:IsVisible();
		_G.PTHealBandageFrame:Hide();
	else
		if( self.prevdisplayed ) then
			_G.PTHealBandageFrame:Show();
		end
	end	
end

function module:CheckMinimapTracking()
	local name, icon, active;
	
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		name, icon, active = C_Minimap.GetTrackingInfo(i);
		
		if( icon == "Interface\\Icons\\tracking_wildpet" ) then			
			break;
		end
	end
	
	if( active ) then
		_G.PTHealBandageFrame:Show();
	else
		_G.PTHealBandageFrame:Hide();
	end
end

-----------------------
-- Frame related
-----------------------

function module:SetDraggable(draggable)
	if( type(draggable) == "nil" ) then
		draggable = module.db.profile.draggable;
	end
	draggable = draggable and "LeftButton" or nil;
	
	_G.PTHealBandageFrame:RegisterForDrag(draggable);
	_G.PTHealBandageFrameHealButton:RegisterForDrag(draggable);
	_G.PTHealBandageFrameBandageButton:RegisterForDrag(draggable);
end

function module:SetBindings(button, modifier, value)
	local old_button, old_modifier = self.db.profile.mousebutton, self.db.profile.modifier;
	button = button and value or old_button;
	modifier = modifier and value or old_modifier;
	
	_G.PTHealBandageFrameHealButton:SetAttribute(old_modifier..old_button, nil);
	_G.PTHealBandageFrameHealButton:SetAttribute(modifier..button, "spell");
	
	_G.PTHealBandageFrameBandageButton:SetAttribute(old_modifier..old_button, nil);
	_G.PTHealBandageFrameBandageButton:SetAttribute(modifier..button, "item");
end

-----------------------------
-- Both Button related
-----------------------------

function module.Button_UpdateCooldown(self)
	local start, duration, enable;
	
	if( self:GetID() == 1 ) then
		start, duration, enable = C_Spell.GetSpellCooldown(module.petHealSpell);
	else
		start, duration, enable = C_Item.GetItemCooldown(module.petBandage);		
	end
	
	_G.CooldownFrame_SetTimer(self.cooldown, start, duration, enable);
end

function module.Button_UpdateUsability(self)
	if( _G.C_PetBattles.IsInBattle() ) then
		self:SetButtonState("NORMAL", true);
		self.icon:SetDesaturated(true);
	else
		self:SetButtonState("NORMAL", false);
		self.icon:SetDesaturated(false);
	end
		
	if( self:GetID() == 1 ) then		
		if( self:IsEventRegistered("SPELLS_CHANGED") ) then
			self:UnregisterEvent("SPELLS_CHANGED");
		end
	else
		if( self:IsEventRegistered("BAG_UPDATE_DELAYED") ) then
			self:UnregisterEvent("BAG_UPDATE_DELAYED");
		end
		
		local id = module.petBandage;
		local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id);				
		local count = C_Item.GetItemCount(id);
		
		self.icon:SetTexture(icon);
		_G[self:GetName().."Count"]:SetText(count);
		
		if( count > 0 ) then
			self.icon:SetVertexColor(1, 1, 1, 1);
		else
			self.icon:SetVertexColor(0.3, 0.3, 0.3, 1);
		end
	end
end

----------------------
-- Option Table
----------------------

do
	local function is_disabled(info)
		return not module:IsEnabled() and true or not not _G.InCombatLockdown(); -- this API returns either 1 or nil, so we ensure a bool
	end
	
	function module:GetOptions()
		return {
			draggable = {
				type = "toggle",
				name = L["Draggable"],
				desc = L["You may drag the frame around when this option is set."],
				order = 1,
				get = function()
					return module.db.profile.draggable;
				end,
				set = function(_, value)
					module.db.profile.draggable = value;
					self:SetDraggable(value);
				end,
			},
			scale = {
				type = "range",
				name = L["Frame scale"],
				min = 0.5,
				max = 2.0,
				step = 0.05,
				order = 2,
				get = function()
					return self.db.profile.scale;
				end,
				set = function(_, value)
					self.db.profile.scale = value;
					_G.PTHealBandageFrame:SetScale(value);
				end,
			},
			mousebutton = {
				type = "select",
				name = L["Mouse button"],
				desc = L["Select the mouse button on which clicks will execute actions."],
				order = 3,
				get = function()
					return self.db.profile.mousebutton;
				end,
				set = function(_, value)
					self:SetBindings(true, false, value);
					self.db.profile.mousebutton = value;
				end,
				values = {
					["type1"] = L["Left"],
					["type2"] = L["Right"],
					["type*"] = _G.ALL,
				},
				disabled = is_disabled,
			},
			modifier = {
				type = "select",
				name = L["Modifier"],
				desc = L["Choose whether you need to push a modifier key or not, when clicking an action button."],
				order = 4,
				get = function()
					return self.db.profile.modifier;
				end,
				set = function(_, value)
					self:SetBindings(false, true, value);
					self.db.profile.modifier = value;
				end,
				values = {
					[""] = _G.NONE,
					["shift-"] = L["Shift"],
					["alt-"]   = L["Alt"],
					["ctrl-"]  = L["Ctrl"],
				},
				disabled = is_disabled,
			},
		};
	end
end