local mod = get_mod("bot_hud_transparency")

local PlayerCompositions = require("scripts/utilities/players/player_compositions")

local function is_valid_player(player)
	if not player or type(player) ~= "table" or rawget(player, "__deleted") then
		return false
	end

	local success, player_type = pcall(function()
		return player.type and player:type()
	end)

	return success and (player_type == "HumanPlayer" or player_type == "BotPlayer" or player_type == "RemotePlayer")
end

local function is_player_completely_dead(player)
    if not player then return true end

    local unit = player.player_unit
    if not unit or not ALIVE[unit] then
        return true
    end

    local health_extension = ScriptUnit.has_extension(unit, "health_system")
    if health_extension and not health_extension:is_alive() then
        return true
    end

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
    if unit_data_extension then
        local character_state = unit_data_extension:read_component("character_state")
        if character_state and (character_state.state_name == "dead" or character_state.state_name == "hogtied") then
            return true
        end
    end

    return false
end

local function is_player_hogtied(player)
    if not player then return false end

    local unit = player.player_unit
    if not unit or not ALIVE[unit] then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
    if unit_data_extension then
        local character_state = unit_data_extension:read_component("character_state")
        if character_state and character_state.state_name == "hogtied" then
            return true
        end
    end

    return false
end

local DOWNED_STATES = {
    knocked_down = true,
    ledge_hanging = true,
    netted = true,
    pounced = true,
    mutant_charged = true,
    grabbed = true,
    consumed = true,
    catapulted = true,
    warp_grabbed = true,
    vortex_grabbed = true,
}

local BOT_DEATH_SOUNDS = {
    ["wwise/events/player/play_teammate_died"] = true,
}

local BOT_DOWNED_SOUNDS = {
    ["wwise/events/player/play_teammate_knocked_down"] = true,
    ["wwise/events/player/play_hud_player_hanging_stinger"] = true,
    ["wwise/events/player/play_hud_player_states_mutant_charger_downed"] = true,
    ["wwise/events/player/play_hud_player_states_netgunner_downed"] = true,
    ["wwise/events/player/play_hud_player_states_chaos_hound_downed"] = true,
    ["wwise/events/player/play_player_combat_experience_catapulted"] = true,
    ["wwise/events/player/play_player_vortex_grabbed_enter"] = true,
    ["wwise/events/player/play_enemy_daemonhost_grab_stinger"] = true,
}

local function is_player_dead(player)
    if not player then return true end

    local unit = player.player_unit
    if not unit or not ALIVE[unit] then
        return true
    end

    local health_extension = ScriptUnit.has_extension(unit, "health_system")
    if health_extension and not health_extension:is_alive() then
        return true
    end

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
    if unit_data_extension then
        local character_state = unit_data_extension:read_component("character_state")
        if character_state and character_state.state_name == "dead" then
            return true
        end
    end

    return false
end

local function is_player_downed(player)
    if not player then return false end

    local unit = player.player_unit
    if not unit or not ALIVE[unit] then
        return false
    end

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")
    if unit_data_extension then
        local character_state = unit_data_extension:read_component("character_state")
        if character_state and DOWNED_STATES[character_state.state_name] then
            return true
        end

        local disabled_state = unit_data_extension:read_component("disabled_character_state")
        if disabled_state and disabled_state.is_disabled then
            return true
        end
    end

    return false
end

local function is_bot_death_sound(event_name)
    if not event_name then return false end
    return BOT_DEATH_SOUNDS[event_name] or string.find(event_name, "play_teammate_died") ~= nil
end

local function is_bot_downed_sound(event_name)
    if not event_name then return false end
    return BOT_DOWNED_SOUNDS[event_name] or string.find(event_name, "play_teammate_knocked_down") ~= nil
end

local function should_mute_bot_dialogue(player)
    if not player or (type(player.is_human_controlled) == "function" and player:is_human_controlled()) then
        return false
    end

    if mod:get("mute_downed_bots") and (is_player_downed(player) or is_player_hogtied(player)) then
        return true
    end

    if mod:get("mute_bot_death_sound") and is_player_dead(player) then
        return true
    end

    return false
end

mod:hook_safe("HudElementTeamPlayerPanel", "update", function(self)
    local player = self._data and self._data.player
    if player then
        local is_bot = not player:is_human_controlled()

        local alpha = 1
        if is_bot then
            alpha = mod:get("bot_hud_transparency") / 100
        end

        for _, widget in ipairs(self._widgets) do
            widget.alpha_multiplier = alpha
        end

        if self._health_bar_segment_widgets then
            for _, widget in ipairs(self._health_bar_segment_widgets) do
                widget.alpha_multiplier = alpha
            end
        end
    end
end)

local temp_team_players = {}
local temp_new_unique_ids = {}

mod:hook("HudElementTeamPanelHandler", "_player_scan", function(func, self, ui_renderer)
    local player_composition_name = self._player_composition_name
    local players = PlayerCompositions.players(player_composition_name, temp_team_players)
    local player_panel_by_unique_id = self._player_panel_by_unique_id
    local player_panels_array = self._player_panels_array
    local num_composition_players = 0

    for unique_id, player in pairs(players) do
        num_composition_players = num_composition_players + 1

        if not player_panel_by_unique_id[unique_id] then
            temp_new_unique_ids[#temp_new_unique_ids + 1] = unique_id
        else
            player_panel_by_unique_id[unique_id].synced = true
        end
    end

    local panel_removed = false

    for i = #player_panels_array, 1, -1 do
        local data = player_panels_array[i]
        local unique_id = data.unique_id
        local player = data.player
        local player_deleted = player.__deleted

        local is_bot = player and not player_deleted and not player:is_human_controlled()
        local should_hide = false
        if is_bot then
            if mod:get("always_hide_bot_hud") then
                should_hide = true
            elseif mod:get("hide_dead_bot_hud") and is_player_completely_dead(player) then
                should_hide = true
            end
        end

        if not data.synced or player_deleted or should_hide then
            self:_remove_panel(unique_id, ui_renderer)
            panel_removed = true
        else
            data.synced = false
        end
    end

    if panel_removed then
        self:_on_panels_removed()
    end

    local num_players_to_add = #temp_new_unique_ids
    local max_panels = self._max_panels
    local players_added = false

    if num_players_to_add > 0 then
        for i = 1, num_players_to_add do
            local current_num_panels = self._num_panels

            if max_panels <= current_num_panels then
                break
            end

            local unique_id = temp_new_unique_ids[i]
            local player = PlayerCompositions.player_from_unique_id(player_composition_name, unique_id)

            local is_bot = player and not player:is_human_controlled()
            local should_hide = false
            if is_bot then
                if mod:get("always_hide_bot_hud") then
                    should_hide = true
                elseif mod:get("hide_dead_bot_hud") and is_player_completely_dead(player) then
                    should_hide = true
                end
            end

            if not should_hide then
                local should_add = false
                local num_other_player_panels = self:_num_other_player_panels()
                local max_other_player_panels = max_panels - 1
                local fixed_scenegraph_id

                if unique_id == self._my_unique_id then
                    fixed_scenegraph_id = "local_player"
                    should_add = true
                else
                    should_add = num_other_player_panels < max_other_player_panels and true or should_add
                end

                if should_add then
                    self:_add_panel(unique_id, ui_renderer, fixed_scenegraph_id)
                    players_added = true
                end
            end
        end

        table.clear(temp_new_unique_ids)
    end

    if players_added then
        self:_align_panels()
    end
end)

mod:hook_safe("HudElementWorldMarkers", "update", function(self)
    local bot_nametag_alpha = mod:get("bot_nametag_transparency") / 100
    local hide_dead = mod:get("hide_dead_bot_hud")
    local always_hide = mod:get("always_hide_bot_hud")

    for _, marker in ipairs(self._markers) do
        local template_name = marker.template and marker.template.name or marker.type
        local is_nameplate = template_name == "nameplate" or template_name == "nameplate_party" or template_name == "nameplate_party_hud"

        if is_nameplate then
            local data = marker.data
            if is_valid_player(data) then
                local is_bot = not data:is_human_controlled()

                local alpha = 1
                if is_bot then
                    if always_hide then
                        alpha = 0
                    elseif hide_dead and is_player_completely_dead(data) then
                        alpha = 0
                    else
                        alpha = bot_nametag_alpha
                    end
                end

                if marker.widget then
                    marker.widget.alpha_multiplier = alpha
                end
            end
        end

        if mod:get("hide_bot_rescue_markers") then
            local template_name = marker.template and marker.template.name
            if template_name == "player_assistance" or marker.markers_aio_type == "player_assistance" or marker.type == "player_assistance" then
                local unit = marker.unit
                if unit and ALIVE[unit] then
                    local player_manager = Managers.player
                    if player_manager then
                        local player = player_manager:player_by_unit(unit)
                        if is_valid_player(player) and not player:is_human_controlled() then
                            if marker.widget then
                                marker.widget.alpha_multiplier = 0
                            end
                            marker.draw = false
                        end
                    end
                end
            end
        end
    end
end)

mod:hook("DialogueExtension", "play_event", function(func, self, event)
    local unit = self._unit or self.unit
    if unit then
        local player_manager = Managers.player
        if player_manager then
            local player = player_manager:player_by_unit(unit)
            if should_mute_bot_dialogue(player) then
                return
            end
        end
    end
    return func(self, event)
end)

mod:hook("DialogueSystemSubtitle", "add_playing_localized_dialogue", function(func, self, speaker_name, dialogue)
    if dialogue and dialogue.currently_playing_unit then
        local player_manager = Managers.player
        if player_manager then
            local player = player_manager:player_by_unit(dialogue.currently_playing_unit)
            if should_mute_bot_dialogue(player) then
                return
            end
        end
    end
    return func(self, speaker_name, dialogue)
end)

mod:hook("PlayerUnitFxExtension", "rpc_play_player_sound", function(func, self, channel_id, game_object_id, event_id, source_id, attachment_id, append_husk_to_event_name)
    local player = self._player
    if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
        local sound_lookup = NetworkLookup and NetworkLookup.player_character_sounds
        local event_name = sound_lookup and sound_lookup[event_id]
        if event_name then
            if mod:get("mute_bot_death_sound") and is_bot_death_sound(event_name) then
                return
            end
            if mod:get("mute_downed_bots") and is_bot_downed_sound(event_name) then
                return
            end
            if mod:get("mute_downed_bots") and (is_player_downed(player) or is_player_hogtied(player)) and string.find(event_name, "_vce_") then
                return
            end
        end
    end
    return func(self, channel_id, game_object_id, event_id, source_id, attachment_id, append_husk_to_event_name)
end)

mod:hook("PlayerUnitFxExtension", "rpc_play_player_sound_with_position", function(func, self, channel_id, game_object_id, event_id, sound_position, append_husk_to_event_name)
    local player = self._player
    if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
        local sound_lookup = NetworkLookup and NetworkLookup.player_character_sounds
        local event_name = sound_lookup and sound_lookup[event_id]
        if event_name then
            if mod:get("mute_bot_death_sound") and is_bot_death_sound(event_name) then
                return
            end
            if mod:get("mute_downed_bots") and is_bot_downed_sound(event_name) then
                return
            end
            if mod:get("mute_downed_bots") and (is_player_downed(player) or is_player_hogtied(player)) and string.find(event_name, "_vce_") then
                return
            end
        end
    end
    return func(self, channel_id, game_object_id, event_id, sound_position, append_husk_to_event_name)
end)

mod:hook("PlayerUnitFxExtension", "trigger_gear_wwise_event_with_source", function(func, self, sound_alias, external_properties, source_name, sync_to_clients, include_client, optional_attachment_name)
    local player = self._player
    if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
        if sound_alias == "disabled_enter" and external_properties then
            local stinger_type = external_properties.stinger_type
            if stinger_type == "teammate_died" then
                if mod:get("mute_bot_death_sound") then
                    return
                end
            elseif mod:get("mute_downed_bots") then
                return
            end
        end
    end
    return func(self, sound_alias, external_properties, source_name, sync_to_clients, include_client, optional_attachment_name)
end)

mod:hook("PlayerUnitFxExtension", "trigger_gear_wwise_event_with_position", function(func, self, sound_alias, external_properties, sound_position, sync_to_clients, include_client)
    local player = self._player
    if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
        if sound_alias == "disabled_enter" and external_properties then
            local stinger_type = external_properties.stinger_type
            if stinger_type == "teammate_died" then
                if mod:get("mute_bot_death_sound") then
                    return
                end
            elseif mod:get("mute_downed_bots") then
                return
            end
        end
    end
    return func(self, sound_alias, external_properties, sound_position, sync_to_clients, include_client)
end)

mod:hook("PlayerUnitFxExtension", "trigger_voice_wwise_event_with_source", function(func, self, event_name, source_name, append_husk_to_event_name, include_client)
    local player = self._player
    if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
        if mod:get("mute_downed_bots") and (is_player_downed(player) or is_player_hogtied(player)) then
            return
        end
        if mod:get("mute_bot_death_sound") and is_player_dead(player) then
            return
        end
    end
    return func(self, event_name, source_name, append_husk_to_event_name, include_client)
end)

mod:hook("PlayerUnitFxExtension", "trigger_wwise_event_non_synced", function(func, self, dialogue_extension, event_name, source_name, append_husk_to_event_name, optional_attachment_name)
    local player = self._player
    if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
        if mod:get("mute_downed_bots") and (is_player_downed(player) or is_player_hogtied(player)) then
            return
        end
        if mod:get("mute_bot_death_sound") and is_player_dead(player) then
            return
        end
    end
    return func(self, dialogue_extension, event_name, source_name, append_husk_to_event_name, optional_attachment_name)
end)
