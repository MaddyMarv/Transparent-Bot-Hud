local mod = get_mod("bot_hud_transparency")

local DialogueExtension = require("scripts/extension_systems/dialogue/dialogue_extension")
local DialogueSystemSubtitle = require("scripts/extension_systems/dialogue/dialogue_system_subtitle")
local PlayerCompositions = require("scripts/utilities/players/player_compositions")

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
        local data = marker.data
        if data and type(data) == "table" and data.is_human_controlled then
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

        if mod:get("hide_bot_rescue_markers") then
            local template_name = marker.template and marker.template.name
            if template_name == "player_assistance" or marker.markers_aio_type == "player_assistance" or marker.type == "player_assistance" then
                local unit = marker.unit
                if unit and type(unit) == "userdata" and Unit.alive(unit) then
                    local player_manager = Managers.player
                    if player_manager then
                        local player = player_manager:player_by_unit(unit)
                        if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
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

mod:hook(DialogueExtension, "play_event", function(func, self, event)
    if mod:get("mute_hogtied_bots") then
        local unit = self._unit or self.unit
        if unit then
            local player_manager = Managers.player
            if player_manager then
                local player = player_manager:player_by_unit(unit)
                if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
                    if is_player_hogtied(player) then
                        return
                    end
                end
            end
        end
    end
    return func(self, event)
end)

mod:hook(DialogueSystemSubtitle, "add_playing_localized_dialogue", function(func, self, speaker_name, dialogue)
    if mod:get("mute_hogtied_bots") then
        if dialogue and dialogue.currently_playing_unit then
            local player_manager = Managers.player
            if player_manager then
                local player = player_manager:player_by_unit(dialogue.currently_playing_unit)
                if player and type(player.is_human_controlled) == "function" and not player:is_human_controlled() then
                    if is_player_hogtied(player) then
                        return
                    end
                end
            end
        end
    end
    return func(self, speaker_name, dialogue)
end)
