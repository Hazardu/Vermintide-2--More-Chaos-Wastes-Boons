local mod = get_mod("other-class-boons")
local buff_perks = require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names")

-- Text Localization
local _language_id = Application.user_setting("language_id")
local _localization_database = {}
mod._quick_localize = function (self, text_id)
    local mod_localization_table = _localization_database
    if mod_localization_table then
        local text_translations = mod_localization_table[text_id]
        if text_translations then
            return text_translations[_language_id] or text_translations["en"]
        end
    end
end
function mod.add_text(self, text_id, text)
    if type(text) == "table" then
        _localization_database[text_id] = text
    else
        _localization_database[text_id] = {
            en = text
        }
    end
end
mod:hook("Localize", function(func, text_id)
    local str = mod:_quick_localize(text_id)
    if str then return str end
    return func(text_id)
end)



local get_buffs_table = function (buffid, classname)
	local talent = nil
	local buffs_table = {}
	for k,v in pairs(Talents[classname]) do
		if v.name and v.name == buffid then
			talent = v
			break
		end
	end
	if talent then
		for i, v in ipairs(talent.buffs) do
			buffs_table[i] = table.clone(TalentBuffTemplates[classname][v]["buffs"][1])
		end
	elseif TalentBuffTemplates[classname][buffid] and TalentBuffTemplates[classname][buffid].buffs then
		return table.clone(TalentBuffTemplates[classname][buffid]["buffs"])
	end
	return buffs_table
end

local add_talent_as_global_powerup = function (powerup)
	local talent = nil
	for k,v in pairs(Talents[powerup.classname]) do
		if v.name and v.name == powerup.powerup_id then
			talent = v
			break
		end
	end
	
	local buffs_copy = {}
	local desc_var = powerup.powerup_id .. "_desc"
	local name_var = powerup.powerup_id
	local icon_var = "icons_placeholder"
	
	local description_values_var = {}
	if type(powerup.forced_description) == "string" then
		mod:add_text(desc_var, powerup.forced_description)
	end
	if type(powerup.forced_name) == "string" then
		mod:add_text(name_var, powerup.forced_name)
	end

	if talent then
		desc_var = talent.description
		name_var = talent.name
		icon_var = talent.icon
		description_values_var = talent.description_values
		for i, v in ipairs(talent.buffs) do
			buffs_copy[i] = table.clone(TalentBuffTemplates[powerup.classname][v]["buffs"][1])
		end
    elseif TalentBuffTemplates[powerup.classname][powerup.powerup_id] and TalentBuffTemplates[powerup.classname][powerup.powerup_id].buffs or powerup.force_use_buff then
		buffs_copy = table.clone(TalentBuffTemplates[powerup.classname][powerup.powerup_id]["buffs"])
	else
        mod:info("No buff with id %s ", powerup.powerup_id)
		return false
	end

	if powerup.additional_buffs then
		for _, buff in ipairs(powerup.additional_buffs) do
			mod:info("additional buff %s ", buff)
			local buffs_to_append = get_buffs_table(buff, powerup.classname)
			mod:dump(buffs_to_append, "dumped buffs_to_append", 1)
			for k, v in ipairs(buffs_to_append) do
				local nextidx = #buffs_copy + 1
				buffs_copy[nextidx] = v
			end
		end
	end
	if powerup.icon ~= nil then
		icon_var = powerup.icon
	end
	DeusPowerUpTemplates[powerup.powerup_id] = {
		rectangular_icon = true,
		advanced_description = desc_var,
		max_amount = 1,
		icon = icon_var,
		display_name = name_var,
		description_values = description_values_var,
		buff_template = {
			buffs = {}
		}
	}

	for id, buff in ipairs(buffs_copy) do
		DeusPowerUpTemplates[powerup.powerup_id].buff_template.buffs[id] = {
			max_stacks = 1
		}
		if DeusPowerUpTemplates[powerup.powerup_id].buff_template.buffs[id].name == nil then
			DeusPowerUpTemplates[powerup.powerup_id].buff_template.buffs[id].name = powerup.powerup_id
		end
		for k, field in pairs(buff) do
			DeusPowerUpTemplates[powerup.powerup_id].buff_template.buffs[id][k] = field
		end
		if talent and (talent.buffer == "server" or talent.buffer == "both") then
			DeusPowerUpTemplates[powerup.powerup_id].buff_template.buffs[id].authority = "server"
		end	
		if powerup.authority ~= nil then
			DeusPowerUpTemplates[powerup.powerup_id].buff_template.buffs[id].authority = powerup.authority
		end

	end

	-- deus_power_up_templates
	local index = #NetworkLookup.deus_power_up_templates + 1
	NetworkLookup.deus_power_up_templates[index] = powerup.powerup_id
	NetworkLookup.deus_power_up_templates[powerup.powerup_id] = index

	-- buff_templates
	index = #NetworkLookup.buff_templates + 1
	local buff_template_name = "power_up_" .. powerup.powerup_id .. "_" .. powerup.rarity
	NetworkLookup.buff_templates[index] = buff_template_name
	NetworkLookup.buff_templates[buff_template_name] = index

	index = #DeusPowerUpRarityPool[powerup.rarity] + 1
	DeusPowerUpRarityPool[powerup.rarity][index] = {
		powerup.powerup_id,
		{
			DeusPowerUpAvailabilityTypes.cursed_chest,
			DeusPowerUpAvailabilityTypes.weapon_chest,
			DeusPowerUpAvailabilityTypes.shrine
		},
		{}
	}
	if powerup.add_to_original_career ~= true then
		DeusPowerUpExclusionList[powerup.career_name][powerup.powerup_id]=true
	end
	if powerup.excluded_careers ~= nil then
		for _, career in ipairs(powerup.excluded_careers) do
			DeusPowerUpExclusionList[career][powerup.powerup_id]=true
		end
	end
	return true
end


local update_powerups = function()
	for career_name, incompatibility_list in pairs(DeusPowerUpIncompatibilityPairs) do
		for _, pair in ipairs(incompatibility_list) do
			local power_up_1 = pair[1]
			local power_up_2 = pair[2]
			local power_up_1_template = DeusPowerUpTemplates[power_up_1]
			local power_up_2_template = DeusPowerUpTemplates[power_up_2]
	
			assert(power_up_1_template, tostring(power_up_1) .. "in DeusPowerUpIncompatibilityPairs, but not in DeusPowerUpTemplates")
			assert(power_up_2_template, tostring(power_up_2) .. "in DeusPowerUpIncompatibilityPairs, but not in DeusPowerUpTemplates")
	
			local incompatibility_1 = power_up_1_template.incompatibility or {}
			local incompatibility_2 = power_up_2_template.incompatibility or {}
			local career_incompatibility_1 = incompatibility_1[career_name] or {}
			local career_incompatibility_2 = incompatibility_2[career_name] or {}
	
			career_incompatibility_1[#career_incompatibility_1 + 1] = power_up_2
			career_incompatibility_2[#career_incompatibility_2 + 1] = power_up_1
			incompatibility_1[career_name] = career_incompatibility_1
			incompatibility_2[career_name] = career_incompatibility_2
			power_up_1_template.incompatibility = incompatibility_1
			power_up_2_template.incompatibility = incompatibility_2
		end
	end

	-- for rarity, power_up_configs in pairs(DeusPowerUpRarityPool) do
	-- 	DeusPowerUpsArray[rarity] = {}
	-- 	DeusPowerUps[rarity] = {}
	-- end
	--mod:info("Done adding incompatibilities")

	for rarity, power_up_configs in pairs(DeusPowerUpRarityPool) do
		DeusPowerUps[rarity] = DeusPowerUps[rarity] or {}
		DeusPowerUpsArray[rarity] = DeusPowerUpsArray[rarity] or {}

	
		for _, power_up_config in ipairs(power_up_configs) do
			local power_up_name = power_up_config[1]
			if not DeusPowerUps[rarity][power_up_name] then
				local availability = power_up_config[2]
				local mutators = power_up_config[3]
				local template = DeusPowerUpTemplates[power_up_name]
				local new_power_up  = nil
		

				if template.talent then
					new_power_up = {
						talent = true,
						name = power_up_name,
						talent_tier = template.talent_tier,
						talent_index = template.talent_index,
						rarity = rarity,
						max_amount = template.max_amount or 1,
						availability = availability,
						mutators = mutators,
						incompatibility = template.incompatibility,
					}
				else
					new_power_up = {
						display_name = template.display_name,
						plain_display_name = template.plain_display_name,
						name = power_up_name,
						rarity = rarity,
						buff_name = power_up_name,
						max_amount = template.max_amount or 1,
						advanced_description = template.advanced_description,
						description_values = template.description_values,
						icon = template.icon,
						availability = availability,
						mutators = mutators,
						incompatibility = template.incompatibility,
					}
		
					local buff_template = table.clone(template.buff_template)
					local tweak_data = MorrisBuffTweakData[power_up_name]
		
					if tweak_data then
						for key, value in pairs(tweak_data) do
							buff_template.buffs[1][key] = value
						end
					end
		
					buff_template.buffs[1].name = new_power_up.buff_name
					DeusPowerUpBuffTemplates[new_power_up.buff_name] = buff_template
				end
		
				DeusPowerUps[rarity][power_up_name] = new_power_up
		
				table.insert(DeusPowerUpsArray[rarity], new_power_up)
		
				DeusPowerUps[rarity][power_up_name].id = #DeusPowerUpsArray[rarity]
				DeusPowerUps[rarity][power_up_name].lookup_id = #DeusPowerUpsLookup + 1
				DeusPowerUpsLookup[#DeusPowerUpsLookup + 1] = new_power_up
				DeusPowerUpsLookup[power_up_name] = new_power_up
			end
		end
	end

	for _, power_up_set in pairs(DeusPowerUpSets) do
		for _, set_piece_settings in pairs(power_up_set.pieces) do
			local rarity = set_piece_settings.rarity
			local name = set_piece_settings.name
	
			DeusPowerUpSetLookup[rarity][name] = DeusPowerUpSetLookup[rarity][name] or {}
	
			table.insert(DeusPowerUpSetLookup[rarity][name], power_up_set)
		end
	
		for _, set_reward_settings in pairs(power_up_set.rewards) do
			local rarity = set_reward_settings.rarity
			local name = set_reward_settings.name
	
			DeusPowerUpSetLookup[rarity][name] = DeusPowerUpSetLookup[rarity][name] or {}
	
			table.insert(DeusPowerUpSetLookup[rarity][name], power_up_set)
		end
	end


	mod:info("Done adding boons from all careers")
end
-- add_talent_powerup_safe("bardin_engineer_stacking_damage_reduction", "dwarf_ranger", "exotic", "dr_engineer")

-- add_talent_powerup_safe("sienna_necromancer_5_2", "bright_wizard", "exotic", "bw_necromancer", nil, {"sienna_necromancer_5_2_counter_remover"})
-- add_talent_powerup_safe("sienna_necromancer_perk_dot_duration", "bright_wizard", "exotic", "bw_necromancer", "Necromancers's perk: 100%% DoT duration")

-- add_talent_powerup_safe("bardin_ironbreaker_gromril_stagger", "dwarf_ranger", "exotic", "dr_ironbreaker", nil, {"bardin_ironbreaker_gromril_buff"})
-- add_talent_powerup_safe("bardin_ironbreaker_gromril_attack_speed", "dwarf_ranger", "exotic", "dr_ironbreaker", nil, {"bardin_ironbreaker_gromril_buff"})
-- add_talent_powerup_safe("bardin_ironbreaker_gromril_buff", "dwarf_ranger", "exotic", "dr_ironbreaker")
-- add_talent_powerup_safe("bardin_ironbreaker_overcharge_increase_power_lowers_attack_speed", "dwarf_ranger", "exotic", "dr_ironbreaker")

local insert_talent_methods = function()
		
	local boons = {
		{
			powerup_id = "victor_bountyhunter_passive_crit_cooldown",
			classname = "witch_hunter",
			rarity = "rare",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight" },
			forced_description = "Guaranteed ranged crit every 10s",
			forced_name = "Blessed Shots",
			additional_buffs = { "victor_bountyhunter_passive_crit_buff_removal" },
		},
		{
			powerup_id = "victor_bountyhunter_passive_reload_speed",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			forced_description = "20%% Increased reload speed",
			forced_name = "Reload speed",
		},
		{
			powerup_id = "victor_bountyhunter_increased_melee_damage_on_no_ammo_add",
			classname = "witch_hunter",
			rarity = "plentiful",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			forced_description = "When firing your last shot, gain 15%% power and attack speed.",
			forced_name = "Original Steel Crescendo",
		},
		{
			powerup_id = "victor_bountyhunter_debuff_defence_on_crit",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_bountyhunter",
			excluded_careers = { "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained" },
		},
		{
			powerup_id = "victor_bountyhunter_power_level_on_clip_size",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
		},
		{
			powerup_id = "victor_bountyhunter_weapon_swap_buff",
			classname = "witch_hunter",
			rarity = "unique",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			additional_buffs = {"victor_bountyhunter_passive_crit_buff_removal", "victor_bountyhunter_passive_crit_cooldown"},
		},
		{
			powerup_id = "victor_bountyhunter_party_movespeed_on_ranged_crit",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", },
		},
		{
			powerup_id = "victor_bountyhunter_reload_on_kill",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_bountyhunter",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "dr_ironbreaker", "we_thornsister" },
		},
		{
			powerup_id = "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_bountyhunter",
		},
		{
			powerup_id = "victor_zealot_passive_increased_damage",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_zealot",
			forced_description = "Increased power for every 25 missing health",
			forced_name = "Fiery Faith",
		},
		{
			powerup_id = "victor_zealot_gain_invulnerability_on_lethal_damage_taken",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_zealot",
			forced_description = "Gain invulnerability on lethal damage taken",
			forced_name = "Fiery Faith",
		},
		{
			powerup_id = "victor_zealot_crit_count",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_zealot",
		},
		-- {
		-- 	powerup_id = "victor_zealot_attack_speed_on_health_percent",
		-- 	classname = "witch_hunter",
		-- 	rarity = "exotic",
		-- 	career_name = "wh_zealot",
		-- 	authority = "server",
		-- },
		{
			powerup_id = "victor_zealot_passive_move_speed",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_zealot",
		},
		{
			powerup_id = "victor_zealot_passive_healing_received",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_zealot",
		},
		{
			powerup_id = "victor_zealot_passive_damage_taken",
			classname = "witch_hunter",
			rarity = "common",
			career_name = "wh_zealot",
		},
		{
			powerup_id = "victor_zealot_move_speed_on_damage_taken",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_zealot",
		},
		{
			powerup_id = "victor_zealot_max_stamina_on_damage_taken",
			classname = "witch_hunter",
			rarity = "common",
			career_name = "wh_zealot",
		},
		{
			powerup_id = "victor_zealot_reduced_damage_taken_buff",
			classname = "witch_hunter",
			rarity = "common",
			career_name = "wh_zealot",
			forced_name = "Damage Reduction",
			forced_description = "Take 10%% less damage from attacks"
		},
		{
			powerup_id = "victor_witchhunter_headshot_damage_increase",
			classname = "witch_hunter",
			rarity = "plentiful",
			career_name = "wh_captain",
			add_to_original_career = true,
		},
		-- {
		-- 	powerup_id = "victor_witchhunter_guaranteed_crit_on_timed_block",
		-- 	classname = "witch_hunter",
		-- 	rarity = "plentiful",
		-- 	career_name = "wh_captain",
		-- },
		{
			powerup_id = "victor_witchhunter_passive_block_cost_reduction",
			classname = "witch_hunter",
			rarity = "common",
			career_name = "wh_captain",
			forced_description = "100%% block cost reduction on light frontal attacks",
			forced_name = "Eternal Guard",
		},
		{
			powerup_id = "victor_witchhunter_bleed_on_critical_hit",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_captain",
			excluded_careers = { "bw_necromancer" }
		},
		{
			powerup_id = "victor_witchhunter_critical_hit_chance_on_ping_target_killed",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_captain",
		},
		{
			powerup_id = "victor_witchhunter_stamina_regen_on_push",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_captain",
		},
		-- {
		-- 	powerup_id = "victor_witchhunter_dodge_range",
		-- 	classname = "witch_hunter",
		-- 	rarity = "plentiful",
		-- 	career_name = "wh_captain",
		-- 	add_to_original_career = true,
		-- },
		{
			powerup_id = "victor_witchhunter_headshot_crit_killing_blow",
			classname = "witch_hunter",
			rarity = "unique",
			career_name = "wh_captain",
			forced_description = "Instantly slay man sized enemies with melee crit headshots",
			forced_name = "Killing Shot",
		},
		{
			powerup_id = "victor_priest_2_3",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_priest",
		},
		{
			powerup_id = "victor_priest_2_2",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_priest",
		},
		{
			powerup_id = "victor_priest_2_1",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_priest",
		},
		{
			powerup_id = "victor_priest_2_1",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_priest",
		},
		{
			powerup_id = "victor_priest_curse_resistance",
			classname = "witch_hunter",
			rarity = "plentiful",
			career_name = "wh_priest",
			forced_description = "100%% Curse resistance",
			forced_name = "Incorruptible",
		},
		{
			powerup_id = "victor_priest_super_armour_damage",
			classname = "witch_hunter",
			rarity = "plentiful",
			career_name = "wh_priest",
			forced_description = "30%% increased damage to super armored enemies",
			forced_name = "Super Armor Damage",
			add_to_original_career = true,
		},
		{
			powerup_id = "victor_priest_super_armour_damage",
			classname = "witch_hunter",
			rarity = "exotic",
			career_name = "wh_priest",
			forced_description = "Portion of the damage taken is dealt over time",
			forced_name = "Delayed Damage",
		},
		{
			powerup_id = "sienna_scholar_increased_attack_speed",
			classname = "bright_wizard",
			rarity = "plentiful",
			career_name = "bw_scholar",
			add_to_original_career = true,
		},
		-- { 
		-- 	powerup_id = "sienna_scholar_crit_chance_above_health_threshold",
		-- 	classname = "bright_wizard",
		-- 	rarity = "exotic",
		-- 	career_name = "bw_scholar",
		-- 	authority = "server",
		-- },
		{
			powerup_id = "sienna_scholar_damage_taken_on_elite_or_special_kill",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_scholar",
		},
		{
			powerup_id = "sienna_scholar_move_speed_on_critical_hit",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_scholar",
		},
		{
			powerup_id = "sienna_scholar_passive_overcharge_pause_on_special_kill",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_scholar",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ironbreaker", "dr_engineer", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_scholar_passive_increased_power_level_on_high_overcharge",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_scholar",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ironbreaker", "dr_engineer", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_scholar_passive_increased_attack_speed_from_overcharge",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_scholar",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ironbreaker", "dr_engineer", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_scholar_passive",
			classname = "bright_wizard",
			rarity = "rare",
			career_name = "bw_scholar",
			forced_description = "Increased crit chance based on overcharge",
			forced_name = "Critical Mass",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ironbreaker", "dr_engineer", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_scholar_overcharge_no_slow",
			classname = "bright_wizard",
			rarity = "rare",
			career_name = "bw_scholar",
			forced_description = "No overcharge slowdown",
			forced_name = "Slave to Aqshy",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ironbreaker", "dr_engineer", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "bw_unchained" },
		},
		{
			powerup_id = "sienna_adept_increased_burn_damage",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_adept",
			forced_description = "Increases burn damage by 100%%, no to any other damage drawbacks.",
			forced_name = "Famished Flames",
			-- excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_adept_power_level_on_full_charge",
			classname = "bright_wizard",
			rarity = "unique",
			career_name = "bw_adept",
		},
		{
			powerup_id = "sienna_adept_damage_reduction_on_ignited_enemy",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_adept",
			-- excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_adept_cooldown_reduction_on_burning_enemy_killed",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_adept",
			-- excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary" },
		},
		{
			powerup_id = "sienna_adept_attack_speed_on_enemies_hit",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_adept",
		},
		{
			powerup_id = "sienna_adept_passive_overcharge_charge_speed_increased_buff",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_adept",
			forced_description = "Reduced charge time based on overcharge",
			forced_name = "Reckless Haste",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		},
		{
			powerup_id = "sienna_unchained_attack_speed_on_high_overcharge",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_unchained",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		},
		{
			powerup_id = "sienna_unchained_burn_push",
			classname = "bright_wizard",
			rarity = "common",
			career_name = "bw_unchained",
		},
		{
			powerup_id = "sienna_unchained_exploding_burning_enemies",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_unchained",
		},
		{
			powerup_id = "sienna_unchained_passive",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_unchained",
			forced_description = "50%% of damage taken is converted to overcharge",
			forced_name = "Blood Magic",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		},
		{
			powerup_id = "sienna_unchained_passive_increased_melee_power_on_overcharge",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_unchained",
			forced_description = "Melee damage increases with overcharge up to 60%%",
			forced_name = "Unstable Strength",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		},
		{
			powerup_id = "sienna_unchained_increased_vent_speed",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_unchained",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		},
		-- {
		-- 	powerup_id = "sienna_unchained_reduced_damage_taken_after_venting_2",
		-- 	classname = "bright_wizard",
		-- 	rarity = "exotic",
		-- 	career_name = "bw_unchained",
		-- 	excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		-- },
		{
			powerup_id = "sienna_unchained_reduced_overcharge",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_unchained",
			excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		},
		{
			powerup_id = "sienna_necromancer_2_2",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_necromancer",
		},
		{
			powerup_id = "sienna_necromancer_2_3",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_necromancer",
		},
		{
			powerup_id = "sienna_necromancer_4_1_cursed_blood",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_necromancer",
			forced_description = "Crits on burning enemies cause explosions.",
			forced_name = "Cursed Blood"
		},
		-- {
		-- 	powerup_id = "sienna_necromancer_4_2",
		-- 	classname = "bright_wizard",
		-- 	rarity = "exotic",
		-- 	career_name = "bw_necromancer",
		-- },
		{
			powerup_id = "sienna_necromancer_5_1_reduced_overcharge",
			classname = "bright_wizard",
			rarity = "exotic",
			career_name = "bw_necromancer",
			forced_description = "Killing an elite reduces ability cooldown by 7 seconds.",
			forced_name = "Spirit Leech",
		},
		-- {
		-- 	powerup_id = "sienna_necromancer_5_3",
		-- 	classname = "bright_wizard",
		-- 	rarity = "exotic",
		-- 	career_name = "bw_necromancer",
		-- 	excluded_careers = { "wh_captain", "wh_zealot", "wh_bountyhunter", "wh_priest", "we_shade", "we_maidenguard", "we_waywatcher", "dr_ranger", "dr_slayer", "wh_priest", "es_questingknight", "es_huntsman", "es_knight", "es_mercenary", "dr_engineer", "dr_ironbreaker" },
		-- },
		{
			powerup_id = "bardin_ironbreaker_gromril_armour",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ironbreaker",
			forced_description = "You're IB now.",
			forced_name = "Gromril Armor",
		},
		{
			powerup_id = "bardin_ironbreaker_power_on_nearby_allies",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ironbreaker",
		},
		{
			powerup_id = "bardin_ironbreaker_party_power_on_blocked_attacks_add",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ironbreaker",
			forced_description = "Give 2%% power to yourself and allies nearby when you block attack",
			forced_name = "Idk what this was named",
		},
		{
			powerup_id = "bardin_ironbreaker_regen_stamina_on_block_broken",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ironbreaker",
		},
		{
			powerup_id = "bardin_ironbreaker_cooldown_reduction_on_kill_while_full_stamina",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ironbreaker",
		},
		{
			powerup_id = "bardin_ironbreaker_regen_stamina_on_charged_attacks",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ironbreaker",
		},
		{
			powerup_id = "bardin_slayer_push_on_dodge",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_slayer",
		},
		{
			powerup_id = "bardin_slayer_passive_stacking_damage_buff_on_hit",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_slayer",
			forced_description = "Get 10%% power when hitting an enemy, stacks 3 times.",
			forced_name = "Trophy Hunter",
		},
		{
			powerup_id = "bardin_slayer_damage_taken_capped",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_slayer",
		},
		{
			powerup_id = "bardin_slayer_damage_reduction_on_melee_charge_action",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_slayer",
		},
		{
			powerup_id = "bardin_ranger_increased_melee_damage_on_no_ammo_add",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ranger",
			forced_description = "Gain 25%% melee power when out of ammunition",
			forced_name = "Last Resort",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },

		},
		{
			powerup_id = "bardin_ranger_cooldown_on_reload",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ranger",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
		},
		{
			powerup_id = "bardin_ranger_passive_reload_speed",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ranger",
			forced_description = "Increases reload speed by 15%%",
			forced_name = "Reload speed",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			add_to_original_career = true,
		},
		{
			powerup_id = "bardin_ranger_movement_speed",
			classname = "dwarf_ranger",
			rarity = "common",
			career_name = "dr_ranger",
			add_to_original_career = true,
		},
		-- {
		-- 	powerup_id = "bardin_ranger_reload_speed_on_multi_hit",
		-- 	classname = "dwarf_ranger",
		-- 	rarity = "exotic",
		-- 	career_name = "dr_ranger",
		-- 	excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
		-- },
		{
			powerup_id = "bardin_ranger_reduced_damage_taken_headshot",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ranger",
		},
		{
			powerup_id = "bardin_ranger_passive",
			classname = "dwarf_ranger",
			rarity = "exotic",
			career_name = "dr_ranger",
			forced_description = "Drop ammo pouches that restore 10%% ammunition on special kills",
			forced_name = "Survivalist Ammunition",
		},
		{
			powerup_id = "bardin_engineer_ranged_pierce",
			classname = "dwarf_ranger",
			rarity = "unique",
			career_name = "dr_engineer",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight" },
		},
		{
			powerup_id = "bardin_engineer_piston_powered",
			classname = "dwarf_ranger",
			rarity = "unique",
			career_name = "dr_engineer",
		},
		-- {
		-- 	powerup_id = "bardin_engineer_upgraded_grenades",
		-- 	classname = "dwarf_ranger",
		-- 	rarity = "unique",
		-- 	career_name = "dr_engineer",
		-- 	authority = "server",
		-- },
		-- {
		-- 	powerup_id = "bardin_engineer_stacking_damage_reduction",
		-- 	classname = "dwarf_ranger",
		-- 	rarity = "exotic",
		-- 	career_name = "dr_engineer",
		-- 	authority = "server",
		-- },
		{
			powerup_id = "kerillian_shade_increased_critical_strike_damage",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_shade",
			add_to_original_career = true,
		},
		{
			powerup_id = "kerillian_shade_increased_critical_strike_damage",
			classname = "wood_elf",
			rarity = "common",
			career_name = "we_shade",
			add_to_original_career = true,
		},
		{
			powerup_id = "kerillian_shade_increased_critical_strike_damage",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_shade",
			add_to_original_career = true,
		},
		{
			powerup_id = "kerillian_shade_increased_damage_on_poisoned_or_bleeding_enemy",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_shade",
		},
		{
			powerup_id = "kerillian_shade_stacking_headshot_damage_on_headshot",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_shade",
		},
		{
			powerup_id = "kerillian_shade_charged_backstabs",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_shade",
		},
		{
			powerup_id = "kerillian_shade_backstabs_cooldown_regeneration",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_shade",
		},
		{
			powerup_id = "kerillian_shade_backstabs_replenishes_ammunition",
			classname = "wood_elf",
			rarity = "common",
			career_name = "we_shade",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
		},
		{
			powerup_id = "kerillian_shade_damage_reduction_on_critical_hit",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_shade",
		},
		{
			powerup_id = "kerillian_shade_movement_speed_on_critical_hit",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_shade",
		},
		{
			powerup_id = "kerillian_shade_movement_speed",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_shade",
			add_to_original_career = true,
		},
		{
			powerup_id = "kerillian_shade_stealth_crits",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_shade",
			forced_description = "Melee attacks from stealth are always critical hits",
			forced_name = "Dagger In The Dark",
		},
		-- {
		-- 	powerup_id = "kerillian_shade_passive_stealth_on_backstab_kill",
		-- 	classname = "wood_elf",
		-- 	rarity = "unique",
		-- 	career_name = "we_shade",
		-- 	forced_description = "Gain stealth on backstab kill",
		-- 	forced_name = "Vanish",
		-- },
		{
			powerup_id = "kerillian_shade_passive_backstab_killing_blow",
			classname = "wood_elf",
			rarity = "unique",
			career_name = "we_shade",
			forced_description = "Charged backstabs instantly kill man sized enemies",
			forced_name = "Murderous Prowess",
		},
		{
			powerup_id = "kerillian_shade_passive_stealth_parry",
			classname = "wood_elf",
			rarity = "unique",
			career_name = "we_shade",
			forced_description = "Gain stealth on dodge after parrying (no stealth fx)",
			forced_name = "Blur",
		},
		{
			powerup_id = "kerillian_maidenguard_power_level_on_unharmed",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_maidenguard",
		},
		{
			powerup_id = "kerillian_maidenguard_speed_on_block",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_maidenguard",
		},
		{
			powerup_id = "kerillian_maidenguard_passive_attack_speed_on_dodge",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_maidenguard",
		},
		{
			powerup_id = "kerillian_maidenguard_versatile_dodge",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_maidenguard",
		},
		{
			powerup_id = "kerillian_maidenguard_passive_noclip_dodge_start",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_maidenguard",
			additional_buffs = { "kerillian_maidenguard_passive_noclip_dodge_end" },
			forced_description = "You can dodge through enemies",
			forced_name = "Wraith Walk",
		},
		{
			powerup_id = "kerillian_maidenguard_max_health",
			classname = "wood_elf",
			rarity = "common",
			career_name = "we_maidenguard",
			add_to_original_career = true
		},
		{
			powerup_id = "kerillian_maidenguard_max_health",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_maidenguard",
			add_to_original_career = true
		},
		{
			powerup_id = "kerillian_maidenguard_block_cost",
			classname = "wood_elf",
			rarity = "common",
			career_name = "we_maidenguard",
			add_to_original_career = true
		},
		{
			powerup_id = "kerillian_maidenguard_passive_stamina_regen_aura",
			classname = "wood_elf",
			rarity = "unique",
			career_name = "we_maidenguard",
			forced_description = "Gain an aura that increases stamina regeneration by 100%%",
			forced_name = "Stamina Regen Aura",
		},
		{
			powerup_id = "kerillian_maidenguard_ress_time",
			classname = "wood_elf",
			rarity = "plentiful",
			career_name = "we_maidenguard",
			forced_description = "You revive players faster and they gain green 20 health",
			forced_name = "Improved Revive",
		},
		{
			powerup_id = "kerillian_waywatcher_extra_arrow_melee_kill",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_waywatcher",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight" },
		},
		{
			powerup_id = "kerillian_waywatcher_critical_bleed",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_waywatcher",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight" },
		},
		{
			powerup_id = "kerillian_waywatcher_attack_speed_on_ranged_headshot",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_waywatcher",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight" },
		},
		{
			powerup_id = "kerillian_waywatcher_projectile_ricochet",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_waywatcher",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight" },
		},
		{
			powerup_id = "kerillian_waywatcher_passive_increased_ammunition",
			classname = "wood_elf",
			rarity = "common",
			career_name = "we_waywatcher",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			forced_description = "Increase reserve ammo by 100%%",
			forced_name = "Increased Reserve ammo",
			add_to_original_career = true
		},
		{
			powerup_id = "kerillian_waywatcher_passive_increased_ammunition",
			classname = "wood_elf",
			rarity = "rare",
			career_name = "we_waywatcher",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			forced_description = "Increase reserve ammo by 100%%",
			forced_name = "Increased Reserve ammo",
			add_to_original_career = true
		},
		{
			powerup_id = "kerillian_waywatcher_movement_speed_on_special_kill",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_waywatcher",
		},
		{
			powerup_id = "kerillian_thorn_sister_passive_temp_health_funnel_aura",
			classname = "wood_elf",
			rarity = "unique",
			career_name = "we_thornsister",
			forced_description = "If other players on full health gain temporary health it goes to you instead",
			forced_name = "Sustenance of the Leechlings",
		},
		{
			powerup_id = "kerillian_thorn_sister_attack_speed_on_full",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_thornsister",
		},
		{
			powerup_id = "kerillian_thorn_sister_big_bleed",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_thornsister",
			forced_description = "Apply AoE blackvenom poison to enemies on critical hits.",
			forced_name = "Lingering Poison",
		},
		{
			powerup_id = "kerillian_thorn_sister_big_push",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_thornsister",
		},
		{
			powerup_id = "kerillian_thorn_sister_damage_vs_wounded_enemies",
			classname = "wood_elf",
			rarity = "exotic",
			career_name = "we_thornsister",
			forced_description = "Deal increased damage to enemies based on their missing health, up to 50%%",
			forced_name = "Cull The Weak",
			add_to_original_career = true
		},
		-- {
		-- 	powerup_id = "kerillian_thorn_sister_crit_on_cast",
		-- 	classname = "wood_elf",
		-- 	rarity = "exotic",
		-- 	career_name = "we_thornsister",
		-- 	forced_description = "Gain 2 guaranteed crits when casting your ability",
		-- },
		{
			powerup_id = "markus_huntsman_headshot_no_ammo_count",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_huntsman",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
			forced_description = "Every third ranged attack costs no ammo",
			forced_name = "Three Free Shot",
		},
		{
			powerup_id = "markus_huntsman_headshot_damage",
			classname = "empire_soldier",
			rarity = "common",
			career_name = "es_huntsman",
			add_to_original_career = true
		},
		{
			powerup_id = "markus_huntsman_headshots_increase_reload_speed",
			classname = "empire_soldier",
			rarity = "common",
			career_name = "es_huntsman",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
		},
		{
			powerup_id = "markus_huntsman_passive_temp_health_on_headshot",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_huntsman",
			excluded_careers = { "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister", "dr_slayer", "wh_priest", "es_questingknight" },
		},
		{
			powerup_id = "markus_huntsman_ammo_on_special_kill",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_huntsman",
			excluded_careers = { "dr_slayer", "wh_priest", "es_questingknight", "bw_scholar", "bw_necromancer", "bw_adept", "bw_unchained", "we_thornsister" },
		},
		{
			powerup_id = "markus_knight_power_level_impact",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_knight",
			add_to_original_career = true
		},
		{
			powerup_id = "markus_knight_power_level_impact",
			classname = "empire_soldier",
			rarity = "common",
			career_name = "es_knight",
			add_to_original_career = true
		},
		{
			powerup_id = "markus_knight_power_level_impact",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_knight",
			add_to_original_career = true
		},
		{
			powerup_id = "markus_knight_power_level_on_stagger_elite",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_knight",
		},
		{
			powerup_id = "markus_knight_attack_speed_on_push",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_knight",
		},
		{
			powerup_id = "markus_knight_guard",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_knight",
		},
		{
			powerup_id = "markus_knight_movement_speed_on_incapacitated_allies",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_knight",
			forced_description = "Reset the cooldown of your ability when an ally gets disabled"
		},
		{
			powerup_id = "markus_knight_free_pushes_on_block",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_knight",
		},
		{
			powerup_id = "markus_knight_cooldown_on_stagger_elite",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_knight",
		},
		{
			powerup_id = "markus_questing_knight_kills_buff_power_stacking",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_questingknight",
		},
		{
			powerup_id = "markus_questing_knight_crit_can_insta_kill",
			classname = "empire_soldier",
			rarity = "unique",
			career_name = "es_questingknight",
		},
		{
			powerup_id = "markus_questing_knight_charged_attacks_increased_power",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_questingknight",
		},
		{
			powerup_id = "markus_questing_knight_health_refund_over_time",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_questingknight",
		},
		{
			powerup_id = "markus_questing_knight_parry_increased_power",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_questingknight",
		},
		-- {
		-- 	powerup_id = "markus_questing_knight_push_arc_stamina_reg",
		-- 	classname = "empire_soldier",
		-- 	rarity = "plentiful",
		-- 	career_name = "es_questingknight",
		-- },
		{
			powerup_id = "markus_questing_knight_perk_first_target_damage",
			classname = "empire_soldier",
			rarity = "rare",
			career_name = "es_questingknight",
			forced_description = "Deal 25%% increased damage to first enemy hit",
			forced_name = "Single Out",
		},
		{
			powerup_id = "markus_mercenary_increased_damage_on_enemy_proximity",
			classname = "empire_soldier",
			rarity = "exotic",
			career_name = "es_mercenary",
		},
		{
			powerup_id = "markus_mercenary_power_level_cleave",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_mercenary",
			add_to_original_career = true
		},
		{
			powerup_id = "markus_mercenary_passive",
			classname = "empire_soldier",
			rarity = "plentiful",
			career_name = "es_mercenary",
			forced_description = "When hitting 3 or more enemies with one attack gain 10%% attack speed",
			forced_name = "Paced Strikes",
		},
	}
	for k,v in pairs(boons) do
		local success, err = pcall(function() add_talent_as_global_powerup(v) end)
		
		if not success then
			mod:echo("adding %s powerup failed %s", v.powerup_id, err)
			mod:dump(v,"Error Boon",2)
		end
	end
		

	local success, err = pcall(function () update_powerups() end)
	if not success then
		mod:info("error in update_powerups %s", err)
	end
end



mod.added = false
mod.added_pere_talents = false

mod.on_all_mods_loaded = function()
    local Peregrinaje = get_mod("Peregrinaje")
    if Peregrinaje then
		Peregrinaje.register_callback(function()
			if not mod.added then
				local success, err = pcall(function () insert_talent_methods() end)
				mod.added = success
			end
		end)
	else
		mod:echo("Pere not found. Mod will not work.")
    end
end

mod:hook(BuffExtension, "_play_screen_effect", function (func, self, effect)
	local unit = self._unit
	if effect ~= "fx/screenspace_shade_skill_01" then
		if ScriptUnit.has_extension(unit, "first_person_system") then
			local first_person_extension = ScriptUnit.extension(unit, "first_person_system")
			local effect_id = first_person_extension:create_screen_particles(effect)
			return effect_id
		end
	end
	return nil
end)