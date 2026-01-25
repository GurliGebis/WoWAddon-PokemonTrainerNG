local LoadWithOptions = false;
local function LoadPokemonTrainer() 
    if( not C_AddOns.IsAddOnLoaded("Blizzard_Collections") ) then
        C_AddOns.LoadAddOn("Blizzard_Collections");
    end
end

-- this one will get overwritten as soon as PT loads
_G.SlashCmdList["PT"] = function() LoadWithOptions = true; LoadPokemonTrainer() end
_G["SLASH_PT1"] = "/pt";

-- create event frame
local f = CreateFrame("Frame");
--f:RegisterEvent("PLAYER_ENTERING_WORLD"); -- disabled this one because sometimes, it isn't needed
f:RegisterEvent("ADDON_LOADED");
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT");
f:SetScript("OnEvent", function(self, event, ...)
    if( event == "PLAYER_ENTERING_WORLD" ) then
        LoadPokemonTrainer(false);
        f:UnregisterEvent(event);
    elseif( event == "ADDON_LOADED" ) then
        local addon = ...;
        if( addon == "PokemonTrainer" ) then
            if( LoadWithOptions ) then
                _G.SlashCmdList["PT"]();
                _G.SlashCmdList["PT"]();
            end
            f:UnregisterEvent(event);
        end
    elseif( event == "UPDATE_MOUSEOVER_UNIT" ) then
        local name, unit = _G.GameTooltip:GetUnit();

        -- Handle Classic, where issecretvalue is not defined.
        local issecretvalue = issecretvalue or function(not_used) return false end

        -- If the unit is a secret value, we cannot do anything.
        if( unit and not issecretvalue(unit) and _G.UnitIsBattlePet(unit) ) then
            LoadPokemonTrainer();
            f:UnregisterEvent(event);
        end
    end
end);