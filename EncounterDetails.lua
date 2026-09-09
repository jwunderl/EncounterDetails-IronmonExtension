local function EncounterDetailsExtension()
	-- Define descriptive attributes of the custom extension that are displayed on the Tracker settings
	local self = {}
	self.version = "2.0"
	self.name = "EncounterDetails"
	self.author = "jwunderl"
	self.description = "Track extra details on every encounter you've faced."
	self.github = "jwunderl/EncounterDetails-IronmonExtension"
	self.url = string.format("https://github.com/%s", self.github or "")

	local DB_SUFFIX = ".db"
	self.dbKey =
		FileManager.prependDir(FileManager.Folders.Custom ..
			FileManager.slash .. GameSettings.getRomName():gsub(" ", "") .. self.name .. DB_SUFFIX)
	self.encounterTableKey = self.name .. "Encounters"
	self.battleTableKey = self.name .. "Battles"
	self.encounterBattleTableKey = self.name .. "EncounterBattles"
	self.timelineTableKey = self.name .. "BattleEvents"
	local extensionSettings = {
		noPiggy = false,
		ignoreWilds = false,
		storeBattleLogs = true,
		showHPPixels = true,
	}
	local ACTION_TYPES = {
		[0] = "Move",
		[1] = "Item",
		[2] = "Switch",
		[3] = "Run",
	}
	local BATTLE_STATE_PREFIXES = { "ownleft", "otherleft", "ownright", "otherright" }
	local STAT_STAGE_KEYS = { "atk", "def", "spa", "spd", "spe", "acc", "eva" }
	local STAT_STAGE_NAMES = {
		atk = "ATK",
		def = "DEF",
		spa = "SPA",
		spd = "SPD",
		spe = "SPE",
		acc = "ACC",
		eva = "EVA",
	}
	local STAT_STAGE_UNKNOWN = 99
	local WEATHER = {
		UNKNOWN = -1,
		NONE = 0,
		RAIN = 1,
		SANDSTORM = 2,
		SUNLIGHT = 3,
		HAIL = 4,
	}
	local WEATHER_NAMES = {
		[WEATHER.NONE] = "clear",
		[WEATHER.RAIN] = "Rain",
		[WEATHER.SANDSTORM] = "Sandstorm",
		[WEATHER.SUNLIGHT] = "Sunlight",
		[WEATHER.HAIL] = "Hail",
	}
	local MAJOR_STATUS = {
		UNKNOWN = -1,
		NONE = 0,
		SLEEP = 1,
		POISON = 2,
		TOXIC = 3,
		BURN = 4,
		FREEZE = 5,
		PARALYSIS = 6,
	}
	local MAJOR_STATUS_NAMES = {
		[MAJOR_STATUS.NONE] = "clear",
		[MAJOR_STATUS.SLEEP] = "SLP",
		[MAJOR_STATUS.POISON] = "PSN",
		[MAJOR_STATUS.TOXIC] = "TOX",
		[MAJOR_STATUS.BURN] = "BRN",
		[MAJOR_STATUS.FREEZE] = "FRZ",
		[MAJOR_STATUS.PARALYSIS] = "PAR",
	}
	local CONFUSION_UNKNOWN = -1
	local HP_UNKNOWN = -1
	local HP_BAR_PIXELS = 48
	local BATTLEMON_HP_OFFSET = 0x28
	local BATTLEMON_MAXHP_OFFSET = 0x2C
	local BATTLEMON_STATUS1_OFFSET = 0x4C
	local BATTLEMON_STATUS2_OFFSET = 0x50
	local BATTLERS_BY_TURN_ORDER_OFFSET = 4
	local CRIT_MESSAGE_OPCODE = 0x0D
	local WAIT_MESSAGE_OPCODE = 0x12
	local BATTLE_COMM_MESSAGE_DISPLAY_OFFSET = 7
	local HITMARKER_ATTACKSTRING_PRINTED = 0x400
	local HITMARKER_UNABLE_TO_USE_MOVE = 0x80000
	local EVENT_KIND = { TICK = 1, BLOCKED = 2, RECOVERY = 3, EFFECT = 4 }
	local EVENT_REASON = {
		POISON = 1, TOXIC = 2, BURN = 3, SAND = 4, HAIL = 5,
		SLEEP = 6, FREEZE = 7, PARALYSIS = 8, WAKE = 9, THAW = 10,
		FLINCH = 11, CONFUSION = 12, RECHARGE = 13, ATTRACTION = 14,
		TRAPPING = 15, CURSE = 16, NIGHTMARE = 17, LEFTOVERS = 18, INGRAIN = 19,
		LEECH_SEED = 20, RECOIL = 21, LEECH_OOZE = 22,
	}
	local EVENT_LABELS = {
		[EVENT_REASON.POISON] = "Poison damage",
		[EVENT_REASON.TOXIC] = "Toxic damage",
		[EVENT_REASON.BURN] = "Burn damage",
		[EVENT_REASON.SAND] = "Sandstorm damage",
		[EVENT_REASON.HAIL] = "Hail damage",
		[EVENT_REASON.SLEEP] = "Unable: asleep",
		[EVENT_REASON.FREEZE] = "Unable: frozen",
		[EVENT_REASON.PARALYSIS] = "Unable: paralysis",
		[EVENT_REASON.WAKE] = "Woke up",
		[EVENT_REASON.THAW] = "Thawed out",
		[EVENT_REASON.FLINCH] = "Unable: flinched",
		[EVENT_REASON.CONFUSION] = "Confusion self-hit",
		[EVENT_REASON.RECHARGE] = "Unable: recharge",
		[EVENT_REASON.ATTRACTION] = "Unable: attraction",
		[EVENT_REASON.TRAPPING] = "Trapping damage",
		[EVENT_REASON.CURSE] = "Curse damage",
		[EVENT_REASON.NIGHTMARE] = "Nightmare damage",
		[EVENT_REASON.LEFTOVERS] = "Leftovers healing",
		[EVENT_REASON.INGRAIN] = "Ingrain healing",
		[EVENT_REASON.LEECH_SEED] = "Leech Seed drain",
		[EVENT_REASON.RECOIL] = "Recoil damage",
		[EVENT_REASON.LEECH_OOZE] = "Leech Seed: Liquid Ooze",
	}
	local MESSAGE_EVENTS = {
		[42] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.POISON },
		[48] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.BURN },
		[102] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.SAND },
		[103] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.HAIL },
		[107] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.SLEEP },
		[51] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.FREEZE },
		[57] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.PARALYSIS },
		[108] = { kind = EVENT_KIND.RECOVERY, reason = EVENT_REASON.WAKE },
		[110] = { kind = EVENT_KIND.RECOVERY, reason = EVENT_REASON.WAKE },
		[52] = { kind = EVENT_KIND.RECOVERY, reason = EVENT_REASON.THAW, target = true },
		[53] = { kind = EVENT_KIND.RECOVERY, reason = EVENT_REASON.THAW },
		[54] = { kind = EVENT_KIND.RECOVERY, reason = EVENT_REASON.THAW },
		[74] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.FLINCH },
		[230] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.CONFUSION, waitForHP = true },
		[130] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.RECHARGE },
		[71] = { kind = EVENT_KIND.BLOCKED, reason = EVENT_REASON.ATTRACTION },
		[94] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.TRAPPING },
		[147] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.CURSE },
		[145] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.NIGHTMARE },
		[301] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.LEFTOVERS },
		[180] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.INGRAIN },
		[106] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.LEECH_SEED, hpUpdatesBeforeMessage = 2, leechTable = true },
		[100] = { kind = EVENT_KIND.EFFECT, reason = EVENT_REASON.RECOIL, hpUpdatesBeforeMessage = 1 },
		[313] = { kind = EVENT_KIND.TICK, reason = EVENT_REASON.LEECH_OOZE, hpUpdatesBeforeMessage = 2, leechTable = true },
	}
	local BATTLE_SCRIPT = {
		ROM_START = 0x08000000, ROM_END = 0x0A000000,
		PRINT = 0x10, PRINT_TABLE = 0x13, DATA_HP = 0x0C,
		PRINT_SIZE = 3, PRINT_TABLE_SIZE = 5, TABLE_SELECTOR_OFFSET = 5,
		TARGET = 0, ATTACKER = 1, RECENT_HP_UPDATES = 2,
		LEECH_MESSAGES = { 104, 105, 27, 106, 313 },
	}
	local BATTLE_TYPE_GHOST_BIT = 15
	local BATTLE_TYPE_GHOST_UNVEILED_BIT = 13
	local currentBattle = nil

	local function dumpTable(o)
		if type(o) == 'table' then
			local s = '{ '
			for k, v in pairs(o) do
				if type(k) ~= 'number' then k = '"' .. k .. '"' end
				s = s .. '[' .. k .. '] = ' .. dumpTable(v) .. ','
			end
			return s .. '} '
		else
			return tostring(o)
		end
	end

	local function reformatSqlReadResult(res)
		local output = {}

		if res == "No rows found" then
			return output
		end

		for key, value in pairs(res) do
			local gmatchRes = string.gmatch(key, "[^%s]+")
			local actualKey = gmatchRes()
			local index = tonumber(gmatchRes()) + 1
			if output[index] == nil then
				output[index] = {}
			end
			output[index][actualKey] = value
		end

		return output
	end

	local function listToSqlCmd(commandParts)
		local res = table.concat(commandParts, " ")
		-- print(res)
		return res
	end

	local function loadData()
		local currGameHash = GameSettings.getRomHash()

		SQL.opendatabase(self.dbKey)

		if TrackerAPI.getExtensionSetting(self.name, "savedHash") ~= currGameHash then
			for _, tableKey in ipairs({
				self.timelineTableKey,
				self.encounterBattleTableKey,
				self.battleTableKey,
				self.encounterTableKey,
			}) do
				SQL.writecommand(listToSqlCmd({ "DROP TABLE IF EXISTS", tableKey }))
			end
		end

		local encounterTableCreateCommand = listToSqlCmd({
			"CREATE TABLE IF NOT EXISTS",
			self.encounterTableKey,
			"(",
			"pokemonid INTEGER,",
			"timestamp INTEGER,",
			"level INTEGER,",
			"playerlevel INTEGER,",
			"playerid INTEGER,",
			"trainerid INTEGER,",
			"routeid INTEGER,",
			"iswild INTEGER", -- BOOLEAN: 1 true, 0 false
			");"
		})

		local createIndexCommand = listToSqlCmd({
			"CREATE INDEX IF NOT EXISTS POKEMON_ID ON",
			self.encounterTableKey,
			"( pokemonid )"
		})
		local battleTableCreateCommand = listToSqlCmd({
			"CREATE TABLE IF NOT EXISTS",
			self.battleTableKey,
			"(",
			"battleid INTEGER PRIMARY KEY AUTOINCREMENT,",
			"timestamp INTEGER,",
			"routeid INTEGER,",
			"trainerid INTEGER,",
			"iswild INTEGER",
			");"
		})
		local encounterBattleTableCreateCommand = listToSqlCmd({
			"CREATE TABLE IF NOT EXISTS",
			self.encounterBattleTableKey,
			"(",
			"pokemonid INTEGER,",
			"encountertimestamp INTEGER,",
			"battleid INTEGER",
			");"
		})
		local encounterBattleIndexCommand = listToSqlCmd({
			"CREATE INDEX IF NOT EXISTS EncounterDetailsEncounterBattle ON",
			self.encounterBattleTableKey,
			"( pokemonid, encountertimestamp )"
		})
		-- HP is stored as -1 unknown or the number of filled pixels in the 48px bar.
		-- Stages are stored as signed -6..6 values, never the raw in-memory 0..12 values.
		-- Weather and confusion are normalized display values, not raw engine flags.
		local timelineColumns = {
			"battleid INTEGER",
			"sequence INTEGER",
			"turn INTEGER",
			"actionindex INTEGER",
			"actorindex INTEGER",
			"actorpokemonid INTEGER",
			"actiontype INTEGER",
			"moveid INTEGER",
			"iscritical INTEGER",
			"weather INTEGER",
			"eventkind INTEGER",
			"eventreason INTEGER",
			"subjectindex INTEGER",
			"subjectpokemonid INTEGER",
		}
		for _, prefix in ipairs(BATTLE_STATE_PREFIXES) do
			for _, field in ipairs({ "id", "hp", "status", "confused" }) do
				table.insert(timelineColumns, prefix .. field .. " INTEGER")
			end
			for _, stageKey in ipairs(STAT_STAGE_KEYS) do
				table.insert(timelineColumns, prefix .. stageKey .. "stage INTEGER")
			end
		end
		table.insert(timelineColumns, "PRIMARY KEY ( battleid, sequence )")
		local timelineTableCreateCommand = listToSqlCmd({
			"CREATE TABLE IF NOT EXISTS",
			self.timelineTableKey,
			"(",
			table.concat(timelineColumns, ", "),
			");"
		})

		SQL.writecommand(encounterTableCreateCommand)
		SQL.writecommand(createIndexCommand)
		SQL.writecommand(battleTableCreateCommand)
		SQL.writecommand(encounterBattleTableCreateCommand)
		SQL.writecommand(encounterBattleIndexCommand)
		SQL.writecommand(timelineTableCreateCommand)

		TrackerAPI.saveExtensionSetting(self.name, "savedHash", GameSettings.getRomHash())
	end

	local function getEncounterData(pokemonID, wildCheck)
		local readEncounterDataCommand = listToSqlCmd({
			"SELECT *",
			"FROM",
			self.encounterTableKey,
			"WHERE",
			"pokemonid =",
			pokemonID,
			wildCheck or ""
		})
		SQL.opendatabase(self.dbKey)
		local res = SQL.readcommand(readEncounterDataCommand)
		return reformatSqlReadResult(res);
	end

	local function getBattleTimeline(battleID)
		if battleID == nil then
			return {}
		end

		SQL.opendatabase(self.dbKey)
		local res = SQL.readcommand(listToSqlCmd({
			"SELECT * FROM", self.timelineTableKey,
			"WHERE battleid =",
			battleID,
			"ORDER BY sequence ASC"
		}))
		return reformatSqlReadResult(res)
	end

	local function getBattleIDForEncounter(encounter)
		if encounter == nil then
			return nil
		end

		SQL.opendatabase(self.dbKey)
		local res = SQL.readcommand(listToSqlCmd({
			"SELECT encounterbattle.battleid FROM",
			self.encounterBattleTableKey,
			"encounterbattle INNER JOIN",
			self.battleTableKey,
			"battle ON battle.battleid = encounterbattle.battleid",
			"WHERE encounterbattle.pokemonid =",
			encounter.pokemonid,
			"AND encounterbattle.encountertimestamp =",
			encounter.timestamp,
			"ORDER BY encounterbattle.battleid DESC LIMIT 1"
		}))
		local rows = reformatSqlReadResult(res)
		return rows[1] and tonumber(rows[1].battleid) or nil
	end

	local function createBattleRecord()
		local battleTimestamp = os.time()
		SQL.opendatabase(self.dbKey)
		SQL.writecommand(listToSqlCmd({
			"INSERT INTO",
			self.battleTableKey,
			"(timestamp, routeid, trainerid, iswild) VALUES (",
			battleTimestamp, ",",
			Program.GameData.mapId, ",",
			Battle.opposingTrainerId, ",",
			Utils.inlineIf(Battle.isWildEncounter, "1", "0"),
			")"
		}))

		local rows = reformatSqlReadResult(SQL.readcommand(listToSqlCmd({
			"SELECT battleid FROM",
			self.battleTableKey,
			"WHERE timestamp =",
			battleTimestamp,
			"ORDER BY battleid DESC LIMIT 1"
		})))
		return rows[1] and tonumber(rows[1].battleid) or nil
	end

	local function getActivePokemonID(battlerIndex)
		local baseAddress = GameSettings.gBattleMons or 0
		if baseAddress == 0 or battlerIndex < 0 or battlerIndex >= Battle.numBattlers then
			return 0
		end

		local monAddress = baseAddress + battlerIndex * Program.Addresses.sizeofBattlePokemon
		local pokemonID = Memory.readword(monAddress)
		return PokemonData.isValid(pokemonID) and pokemonID or 0
	end

	local function getHPBarPixels(battlerIndex)
		local baseAddress = GameSettings.gBattleMons or 0
		if baseAddress == 0 or battlerIndex < 0 or battlerIndex >= Battle.numBattlers then
			return HP_UNKNOWN
		end

		local monAddress = baseAddress + battlerIndex * Program.Addresses.sizeofBattlePokemon
		local species = Memory.readword(monAddress)
		local maxHP = Memory.readword(monAddress + BATTLEMON_MAXHP_OFFSET)
		if not PokemonData.isValid(species) or maxHP <= 0 then
			return HP_UNKNOWN
		end

		local currentHP = math.max(0, math.min(Memory.readword(monAddress + BATTLEMON_HP_OFFSET), maxHP))
		local filledPixels = math.floor(currentHP * HP_BAR_PIXELS / maxHP)
		if filledPixels == 0 and currentHP > 0 then
			filledPixels = 1
		end
		return filledPixels
	end

	local function readMajorStatus(battlerIndex)
		local baseAddress = GameSettings.gBattleMons or 0
		if baseAddress == 0 or battlerIndex < 0 or battlerIndex >= Battle.numBattlers then
			return MAJOR_STATUS.UNKNOWN
		end

		local monAddress = baseAddress + battlerIndex * Program.Addresses.sizeofBattlePokemon
		if not PokemonData.isValid(Memory.readword(monAddress)) then
			return MAJOR_STATUS.UNKNOWN
		end
		local status = Memory.readdword(monAddress + BATTLEMON_STATUS1_OFFSET)
		if status % 8 > 0 then return MAJOR_STATUS.SLEEP end
		if math.floor(status / 0x80) % 2 == 1 then return MAJOR_STATUS.TOXIC end
		if math.floor(status / 0x08) % 2 == 1 then return MAJOR_STATUS.POISON end
		if math.floor(status / 0x10) % 2 == 1 then return MAJOR_STATUS.BURN end
		if math.floor(status / 0x20) % 2 == 1 then return MAJOR_STATUS.FREEZE end
		if math.floor(status / 0x40) % 2 == 1 then return MAJOR_STATUS.PARALYSIS end
		return MAJOR_STATUS.NONE
	end

	local function readConfused(battlerIndex)
		local baseAddress = GameSettings.gBattleMons or 0
		if baseAddress == 0 or battlerIndex < 0 or battlerIndex >= Battle.numBattlers then
			return CONFUSION_UNKNOWN
		end

		local monAddress = baseAddress + battlerIndex * Program.Addresses.sizeofBattlePokemon
		if not PokemonData.isValid(Memory.readword(monAddress)) then
			return CONFUSION_UNKNOWN
		end
		return Utils.inlineIf(Memory.readdword(monAddress + BATTLEMON_STATUS2_OFFSET) % 8 > 0, 1, 0)
	end

	local function getDefaultStatStages(value)
		local stages = {}
		for _, stageKey in ipairs(STAT_STAGE_KEYS) do
			stages[stageKey] = value
		end
		return stages
	end

	local function readStatStages(battlerIndex)
		local baseAddress = GameSettings.gBattleMons or 0
		if baseAddress == 0 or battlerIndex < 0 or battlerIndex >= Battle.numBattlers then
			return getDefaultStatStages(STAT_STAGE_UNKNOWN)
		end

		local monAddress = baseAddress + battlerIndex * Program.Addresses.sizeofBattlePokemon
		if not PokemonData.isValid(Memory.readword(monAddress)) then
			return getDefaultStatStages(STAT_STAGE_UNKNOWN)
		end

		local stageOffset = Program.Addresses.offsetBattlePokemonStatStages
		local hpAtkDefSpe = Memory.readdword(monAddress + stageOffset)
		local spaSpdAccEva = Memory.readdword(monAddress + stageOffset + 4)
		if Utils.getbits(hpAtkDefSpe, 0, 8) == 0 then
			return getDefaultStatStages(0)
		end

		local rawStages = {
			atk = Utils.getbits(hpAtkDefSpe, 8, 8),
			def = Utils.getbits(hpAtkDefSpe, 16, 8),
			spe = Utils.getbits(hpAtkDefSpe, 24, 8),
			spa = Utils.getbits(spaSpdAccEva, 0, 8),
			spd = Utils.getbits(spaSpdAccEva, 8, 8),
			acc = Utils.getbits(spaSpdAccEva, 16, 8),
			eva = Utils.getbits(spaSpdAccEva, 24, 8),
		}
		local stages = getDefaultStatStages(STAT_STAGE_UNKNOWN)
		for stageKey, rawStage in pairs(rawStages) do
			if rawStage >= 0 and rawStage <= 12 then
				stages[stageKey] = rawStage - 6
			end
		end
		return stages
	end

	local function readWeather()
		local weatherAddress = GameSettings.gBattleWeather or 0
		if weatherAddress == 0 then
			return WEATHER.UNKNOWN
		end

		local weatherByte = Memory.readbyte(weatherAddress)
		if weatherByte == 0 then
			return WEATHER.NONE
		end
		local weatherBitIndex = 0
		while weatherByte > 1 do
			weatherByte = Utils.bit_rshift(weatherByte, 1)
			weatherBitIndex = weatherBitIndex + 1
		end
		if weatherBitIndex <= 2 then return WEATHER.RAIN end
		if weatherBitIndex <= 4 then return WEATHER.SANDSTORM end
		if weatherBitIndex <= 6 then return WEATHER.SUNLIGHT end
		if weatherBitIndex == 7 then return WEATHER.HAIL end
		return WEATHER.UNKNOWN
	end

	local function getBattleState()
		local state = {
			weather = readWeather(),
			ownleftid = getActivePokemonID(0),
			ownlefthp = getHPBarPixels(0),
			ownleftstatus = readMajorStatus(0),
			ownleftconfused = readConfused(0),
			otherleftid = getActivePokemonID(1),
			otherlefthp = getHPBarPixels(1),
			otherleftstatus = readMajorStatus(1),
			otherleftconfused = readConfused(1),
			ownrightid = Utils.inlineIf(Battle.numBattlers == 4, getActivePokemonID(2), 0),
			ownrighthp = Utils.inlineIf(Battle.numBattlers == 4, getHPBarPixels(2), HP_UNKNOWN),
			ownrightstatus = Utils.inlineIf(Battle.numBattlers == 4, readMajorStatus(2), MAJOR_STATUS.UNKNOWN),
			ownrightconfused = Utils.inlineIf(Battle.numBattlers == 4, readConfused(2), CONFUSION_UNKNOWN),
			otherrightid = Utils.inlineIf(Battle.numBattlers == 4, getActivePokemonID(3), 0),
			otherrighthp = Utils.inlineIf(Battle.numBattlers == 4, getHPBarPixels(3), HP_UNKNOWN),
			otherrightstatus = Utils.inlineIf(Battle.numBattlers == 4, readMajorStatus(3), MAJOR_STATUS.UNKNOWN),
			otherrightconfused = Utils.inlineIf(Battle.numBattlers == 4, readConfused(3), CONFUSION_UNKNOWN),
		}
		for battlerIndex, prefix in ipairs(BATTLE_STATE_PREFIXES) do
			local stages = readStatStages(battlerIndex - 1)
			for _, stageKey in ipairs(STAT_STAGE_KEYS) do
				state[prefix .. stageKey .. "stage"] = stages[stageKey]
			end
		end
		return state
	end

	local function mergeUnknownState(state, previousState)
		if previousState == nil then
			return state
		end
		if state.weather == WEATHER.UNKNOWN then
			state.weather = previousState.weather
		end
		for _, prefix in ipairs(BATTLE_STATE_PREFIXES) do
			local idKey = prefix .. "id"
			local hpKey = prefix .. "hp"
			local statusKey = prefix .. "status"
			local confusedKey = prefix .. "confused"
			if state[hpKey] == HP_UNKNOWN and state[idKey] == previousState[idKey] then
				state[hpKey] = previousState[hpKey]
			end
			if state[statusKey] == MAJOR_STATUS.UNKNOWN and state[idKey] == previousState[idKey] then
				state[statusKey] = previousState[statusKey]
			end
			if state[confusedKey] == CONFUSION_UNKNOWN and state[idKey] == previousState[idKey] then
				state[confusedKey] = previousState[confusedKey]
			end
			for _, stageKey in ipairs(STAT_STAGE_KEYS) do
				local field = prefix .. stageKey .. "stage"
				if state[field] == STAT_STAGE_UNKNOWN and state[idKey] == previousState[idKey] then
					state[field] = previousState[field]
				end
			end
		end
		return state
	end

	local function battleStatesEqual(first, second)
		if first == nil or second == nil then
			return false
		end
		if first.weather ~= second.weather then
			return false
		end
		for _, prefix in ipairs(BATTLE_STATE_PREFIXES) do
			if first[prefix .. "id"] ~= second[prefix .. "id"]
				or first[prefix .. "hp"] ~= second[prefix .. "hp"]
				or first[prefix .. "status"] ~= second[prefix .. "status"]
				or first[prefix .. "confused"] ~= second[prefix .. "confused"] then
				return false
			end
			for _, stageKey in ipairs(STAT_STAGE_KEYS) do
				local field = prefix .. stageKey .. "stage"
				if first[field] ~= second[field] then
					return false
				end
			end
		end
		return true
	end

	local function saveTimelineEvent(action, state)
		local current = currentBattle
		if current == nil or current.id == nil or action == nil or state == nil then
			return
		end

		local columns = {
			"battleid", "sequence", "turn", "actionindex", "actorindex", "actorpokemonid",
			"actiontype", "moveid", "iscritical", "weather", "eventkind", "eventreason", "subjectindex", "subjectpokemonid",
		}
		local values = {
			current.id, action.sequence, action.turn, action.actionindex, action.actorindex,
			action.actorpokemonid, action.actiontype, action.moveid, action.iscritical or 0, state.weather,
			action.eventkind or 0, action.eventreason or 0, action.subjectindex or action.actorindex,
			action.subjectpokemonid or action.actorpokemonid,
		}
		for _, prefix in ipairs(BATTLE_STATE_PREFIXES) do
			for _, field in ipairs({ "id", "hp", "status", "confused" }) do
				table.insert(columns, prefix .. field)
				table.insert(values, state[prefix .. field])
			end
			for _, stageKey in ipairs(STAT_STAGE_KEYS) do
				local field = prefix .. stageKey .. "stage"
				table.insert(columns, field)
				table.insert(values, state[field])
			end
		end
		SQL.opendatabase(self.dbKey)
		SQL.writecommand(listToSqlCmd({
			"INSERT OR REPLACE INTO", self.timelineTableKey,
			"(" .. table.concat(columns, ", ") .. ")",
			"VALUES (" .. table.concat(values, ", ") .. ")"
		}))
	end

	local function getBattleScriptPointer()
		if not GameSettings.gBattlescriptCurrInstr then return nil end
		local pointer = Memory.readdword(GameSettings.gBattlescriptCurrInstr)
		if pointer >= BATTLE_SCRIPT.ROM_START and pointer < BATTLE_SCRIPT.ROM_END then return pointer end
		return nil
	end

	local function updateBattleState()
		local current = currentBattle
		if current == nil then
			return
		end

		local nextState = mergeUnknownState(getBattleState(), current.latestState)
		local changed = not battleStatesEqual(nextState, current.latestState)
		current.latestState = nextState
		local action = current.pendingAction or current.initialAction
		if action.sealed then return end
		if changed then saveTimelineEvent(action, current.latestState) end
		if action.waitForHP then
			local pointer = getBattleScriptPointer()
			if action.hpUpdatePointer and pointer ~= action.hpUpdatePointer then
				action.sealed = true
			elseif pointer and Memory.readbyte(pointer) == BATTLE_SCRIPT.DATA_HP then
				action.hpUpdatePointer = pointer
			end
		end
	end

	local function observeHPUpdate()
		local current = currentBattle
		if not current or GameSettings.game ~= 3 then return end
		local pointer = getBattleScriptPointer()
		if current.hpUpdate and pointer ~= current.hpUpdate.pointer then
			table.insert(current.recentHPUpdates, current.hpUpdate)
			if #current.recentHPUpdates > BATTLE_SCRIPT.RECENT_HP_UPDATES then table.remove(current.recentHPUpdates, 1) end
			current.hpUpdate = nil
		end
		if not pointer or Memory.readbyte(pointer) ~= BATTLE_SCRIPT.DATA_HP or current.hpUpdate then return end
		local operand = Memory.readbyte(pointer + 1)
		local address
		if operand == BATTLE_SCRIPT.ATTACKER then address = GameSettings.gBattlerAttacker end
		if operand == BATTLE_SCRIPT.TARGET then address = GameSettings.gBattlerTarget end
		if not address then return end
		local subject = Memory.readbyte(address)
		if subject >= Battle.numBattlers or getActivePokemonID(subject) == 0 then return end
		current.hpUpdate = {
			pointer = pointer, subject = subject,
			owner = current.pendingAction or current.initialAction,
			before = mergeUnknownState(getBattleState(), current.latestState),
		}
	end

	local function startBattleLog()
		local battleID = createBattleRecord()
		currentBattle = {
			id = battleID,
			actionKey = nil,
			pendingAction = nil,
			waitingForCritMessage = false,
			latestState = nil,
			recentHPUpdates = {},
			nextSequence = 1,
			initialAction = {
				sequence = 0,
				turn = 0,
				actionindex = -1,
				actorindex = -1,
				actorpokemonid = 0,
				actiontype = -1,
				moveid = 0,
				iscritical = 0,
			},
		}
		currentBattle.latestState = getBattleState()
		saveTimelineEvent(currentBattle.initialAction, currentBattle.latestState)
	end

	local function getBattleAction()
		local current = currentBattle
		if current == nil or not Battle.inActiveBattle() or Battle.turnCount < 0 then
			return nil
		end

		if Memory.readdword(GameSettings.gBattleMainFunc) == GameSettings.HandleTurnActionSelectionState then
			return nil
		end

		local actionIndex = Memory.readbyte(GameSettings.gCurrentTurnActionNumber)
		if actionIndex < 0 or actionIndex >= Battle.numBattlers then
			return nil
		end
		local actionType = Memory.readbyte(GameSettings.gActionsByTurnOrder + actionIndex)
		if ACTION_TYPES[actionType] == nil then
			return nil
		end
		local actorIndex = Memory.readbyte(GameSettings.gActionsByTurnOrder
			+ BATTLERS_BY_TURN_ORDER_OFFSET + actionIndex)
		if actorIndex < 0 or actorIndex >= Battle.numBattlers then
			return nil
		end
		if actionType == 0 and getHPBarPixels(actorIndex) == 0 then
			return nil
		end
		local turn = Battle.turnCount + 1
		return {
			key = string.format("%s:%s", turn, actionIndex),
			turn = turn,
			actionindex = actionIndex,
			actorindex = actorIndex,
			actorpokemonid = getActivePokemonID(actorIndex),
			actiontype = actionType,
			moveid = 0,
			iscritical = 0,
		}
	end

	local function updateBattleAction()
		local current = currentBattle
		local action = getBattleAction()
		if current == nil or action == nil then
			return
		end

		if current.actionKey == action.key then
			return
		end

		updateBattleState()
		current.actionKey = action.key
		current.hpUpdate, current.recentHPUpdates = nil, {}
		current.waitingForCritMessage = false
		action.sequence = current.nextSequence
		current.nextSequence = current.nextSequence + 1
		current.pendingAction = action
		saveTimelineEvent(action, current.latestState)
	end

	local function updateVisibleMove()
		local current = currentBattle
		if current == nil or current.pendingAction == nil then
			return
		end
		local action = current.pendingAction
		local hitMarker = Memory.readdword(GameSettings.gHitMarker)
		if Utils.bit_and(hitMarker, HITMARKER_UNABLE_TO_USE_MOVE) ~= 0 then return end
		if action.eventkind == EVENT_KIND.RECOVERY and Utils.bit_and(hitMarker, HITMARKER_ATTACKSTRING_PRINTED) ~= 0 then
			local resumed = getBattleAction()
			if resumed and resumed.key == current.actionKey and resumed.actorindex == action.subjectindex then
				resumed.sequence = current.nextSequence
				current.nextSequence = current.nextSequence + 1
				current.pendingAction = resumed
				action = resumed
				saveTimelineEvent(action, current.latestState)
			end
		end
		if action.eventkind then return end
		if action.actiontype ~= 0 or action.moveid ~= 0
			or Memory.readbyte(GameSettings.gCurrentTurnActionNumber) ~= action.actionindex then
			return
		end

		if Utils.bit_and(hitMarker, HITMARKER_ATTACKSTRING_PRINTED) == 0 then
			return
		end

		local sideOffset = (action.actorindex % 2) * Program.Addresses.sizeofLastAttackerMove
		local moveID = Memory.readword(GameSettings.gBattleResults
			+ Program.Addresses.offsetBattleResultsLastAttackerMove + sideOffset)
		if MoveData.isValid(moveID) then
			action.moveid = moveID
			saveTimelineEvent(action, current.latestState)
		end
	end

	local function updateBattleMessage()
		local current = currentBattle
		if not current or GameSettings.game ~= 3 then return end
		local pointer = getBattleScriptPointer()
		if not pointer or Memory.readbyte(pointer) ~= WAIT_MESSAGE_OPCODE
			or Memory.readbyte(GameSettings.gBattleCommunication + BATTLE_COMM_MESSAGE_DISPLAY_OFFSET) ~= 1 then
			current.messageKey = nil
			return
		end
		local messageID, tablePointer
		local tableCommand = pointer - BATTLE_SCRIPT.PRINT_TABLE_SIZE
		local printCommand = pointer - BATTLE_SCRIPT.PRINT_SIZE
		if tableCommand >= BATTLE_SCRIPT.ROM_START and Memory.readbyte(tableCommand) == BATTLE_SCRIPT.PRINT_TABLE then
			tablePointer = Memory.readdword(tableCommand + 1)
			local selector = Memory.readbyte(GameSettings.gBattleCommunication + BATTLE_SCRIPT.TABLE_SELECTOR_OFFSET)
			local entryPointer = tablePointer + selector * 2
			if tablePointer >= BATTLE_SCRIPT.ROM_START and entryPointer + 2 <= BATTLE_SCRIPT.ROM_END then
				messageID = Memory.readword(entryPointer)
			end
		elseif printCommand >= BATTLE_SCRIPT.ROM_START and Memory.readbyte(printCommand) == BATTLE_SCRIPT.PRINT then
			messageID = Memory.readword(printCommand + 1)
		end
		local definition = MESSAGE_EVENTS[messageID]
		if not definition then current.messageKey = nil return end
		if definition.leechTable then
			if not tablePointer or tablePointer < BATTLE_SCRIPT.ROM_START
				or tablePointer + #BATTLE_SCRIPT.LEECH_MESSAGES * 2 > BATTLE_SCRIPT.ROM_END then return end
			for index, expected in ipairs(BATTLE_SCRIPT.LEECH_MESSAGES) do
				if Memory.readword(tablePointer + (index - 1) * 2) ~= expected then return end
			end
		end
		local subjectAddress = definition.target and GameSettings.gBattlerTarget or GameSettings.gBattlerAttacker
		if not subjectAddress then return end
		local subject = Memory.readbyte(subjectAddress)
		if subject >= Battle.numBattlers or getActivePokemonID(subject) == 0 then return end
		local messageKey = string.format("%s:%s:%s", pointer, messageID, subject)
		if current.messageKey == messageKey then return end
		current.messageKey = messageKey
		if definition.reason == EVENT_REASON.SLEEP
			and Utils.bit_and(Memory.readdword(GameSettings.gHitMarker), HITMARKER_UNABLE_TO_USE_MOVE) == 0 then return end
		if definition.reason == EVENT_REASON.CONFUSION and readConfused(subject) ~= 1 then return end
		local reason = definition.reason
		if reason == EVENT_REASON.POISON and readMajorStatus(subject) == MAJOR_STATUS.TOXIC then reason = EVENT_REASON.TOXIC end
		local pending = current.pendingAction
		local actor = subject
		if definition.hpUpdatesBeforeMessage == 2 then
			if not GameSettings.gBattlerTarget then return end
			actor = Memory.readbyte(GameSettings.gBattlerTarget)
			if actor == subject or actor >= Battle.numBattlers or getActivePokemonID(actor) == 0 then return end
		end
		if definition.hpUpdatesBeforeMessage then
			local updates = current.recentHPUpdates
			local first = updates[#updates - definition.hpUpdatesBeforeMessage + 1]
			local last = updates[#updates]
			if first and last and first.subject == subject and last.subject == actor
				and first.owner == last.owner and first.owner == (pending or current.initialAction) and not first.owner.sealed then
				saveTimelineEvent(first.owner, first.before)
			end
		end
		local reuseAction = (definition.kind == EVENT_KIND.BLOCKED or definition.kind == EVENT_KIND.RECOVERY)
			and pending and not pending.eventkind
			and pending.actiontype == 0 and pending.moveid == 0 and pending.actorindex == subject
		local waitForHP = not definition.hpUpdatesBeforeMessage and (definition.kind == EVENT_KIND.TICK or definition.waitForHP == true)
		local event = {
			sequence = reuseAction and pending.sequence or current.nextSequence,
			turn = pending and pending.turn or math.max(0, Battle.turnCount + 1),
			actionindex = definition.kind == EVENT_KIND.BLOCKED and pending and pending.actionindex or -1,
			actorindex = actor, actorpokemonid = getActivePokemonID(actor),
			actiontype = -1, moveid = 0, iscritical = 0,
			eventkind = definition.kind, eventreason = reason,
			subjectindex = subject, subjectpokemonid = getActivePokemonID(subject),
			waitForHP = waitForHP,
			sealed = not waitForHP,
		}
		if not reuseAction then current.nextSequence = current.nextSequence + 1 end
		current.pendingAction = event
		current.hpUpdate, current.recentHPUpdates = nil, {}
		current.waitingForCritMessage = false
		current.latestState = mergeUnknownState(getBattleState(), current.latestState)
		saveTimelineEvent(event, current.latestState)
	end

	local function updateCriticalHit()
		local current = currentBattle
		if current == nil then
			return
		end
		local action = current.pendingAction
		if action == nil or action.actiontype ~= 0
			or Memory.readbyte(GameSettings.gCurrentTurnActionNumber) ~= action.actionindex then
			return
		end

		local scriptPointerAddress = GameSettings.gBattlescriptCurrInstr or 0
		if scriptPointerAddress == 0 then
			return
		end

		local scriptAddress = Memory.readdword(scriptPointerAddress)
		if scriptAddress < 0x08000000 or scriptAddress >= 0x0A000000 then
			current.waitingForCritMessage = false
			return
		end

		local opcode = Memory.readbyte(scriptAddress)
		if opcode == CRIT_MESSAGE_OPCODE then
			current.waitingForCritMessage = true
			return
		end
		if not current.waitingForCritMessage then
			return
		end
		current.waitingForCritMessage = false

		local messageDisplayed = Memory.readbyte(GameSettings.gBattleCommunication
			+ BATTLE_COMM_MESSAGE_DISPLAY_OFFSET)
		if opcode == WAIT_MESSAGE_OPCODE and messageDisplayed == 1 then
			action.iscritical = 1
			saveTimelineEvent(action, current.latestState)
		end
	end

	local function finishBattleLog()
		local current = currentBattle
		if current ~= nil and current.pendingAction ~= nil and not current.pendingAction.sealed then
			saveTimelineEvent(current.pendingAction, current.latestState)
		end
		currentBattle = nil
	end

	local function discardBattleLog()
		local current = currentBattle
		if current == nil or current.id == nil then
			currentBattle = nil
			return
		end

		SQL.opendatabase(self.dbKey)
		for _, deleteCommand in ipairs({
			listToSqlCmd({ "DELETE FROM", self.timelineTableKey, "WHERE battleid =", current.id }),
			listToSqlCmd({ "DELETE FROM", self.encounterBattleTableKey, "WHERE battleid =", current.id }),
			listToSqlCmd({ "DELETE FROM", self.battleTableKey, "WHERE battleid =", current.id }),
		}) do
			SQL.writecommand(deleteCommand)
		end
		currentBattle = nil
	end

	local function shouldIgnoreBattle()
		if Battle.isGhost or (Battle.isWildEncounter and extensionSettings.ignoreWilds) then
			return true
		end
		if GameSettings.game == 3 then
			local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)
			return Utils.getbits(battleFlags, BATTLE_TYPE_GHOST_BIT, 1) == 1
				and Utils.getbits(battleFlags, BATTLE_TYPE_GHOST_UNVEILED_BIT, 1) == 0
		end
		return false
	end

	local function trackEncounter(pokemon, isWild)
		local playerMon = Tracker.getPokemon(Battle.Combatants.LeftOwn, true);
		local encounterTimestamp = os.time()
		local trackEncounterCommand = listToSqlCmd({
			"INSERT INTO",
			self.encounterTableKey,
			"(pokemonid, timestamp, level, playerlevel, playerid, routeid, trainerid, iswild) VALUES (",
			pokemon.pokemonID, ",",
			encounterTimestamp, ",",
			pokemon.level, ",",
			playerMon.level, ",",
			playerMon.pokemonID, ",",
			Program.GameData.mapId, ",",
			Battle.opposingTrainerId, ",",
			Utils.inlineIf(isWild, "1", "0"),
			")"
		})
		SQL.opendatabase(self.dbKey)
		SQL.writecommand(trackEncounterCommand)
		if currentBattle ~= nil and currentBattle.id ~= nil then
			SQL.writecommand(listToSqlCmd({
				"INSERT INTO",
				self.encounterBattleTableKey,
				"(pokemonid, encountertimestamp, battleid) VALUES (",
				pokemon.pokemonID, ",", encounterTimestamp, ",", currentBattle.id,
				")"
			}))
		end
	end

	--
	------------------------------------ Encounter Details Screen ------------------------------------
	--
	local BattleTimelineScreen
	local PreviousEncountersScreen = {
		Colors = {
			text = "Default text",
			highlight = "Intermediate text",
			border = "Upper box border",
			boxFill = "Upper box background"
		},
		Tabs = {
			All = {
				index = 1,
				tabKey = "All",
				resourceKey = "TabAll"
			},
			Wild = {
				index = 2,
				tabKey = "Wild",
				resourceKey = "TabWild"
			},
			Trainer = {
				index = 3,
				tabKey = "Trainer",
				resourceKey = "TabTrainer"
			}
		},
		currentView = 1,
		currentTab = nil,
		currentPokemonID = nil,
		examiningEncounter = nil,
		examiningBattleID = nil,
	}

	local PE_SCREEN = PreviousEncountersScreen
	local PE_TAB_HEIGHT = 12
	local PE_OFFSET_FOR_NAME = 8

	PE_SCREEN.Buttons = {
		NameLabel = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				return PokemonData.Pokemon[PE_SCREEN.currentPokemonID].name
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN - 3,
				Constants.SCREEN.MARGIN - 4,
				50,
				10
			},
			onClick = function()
				PE_SCREEN.openPokemonSelectWindow()
			end
		},
		CurrentTimeLabel = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				local currentTime = os.time()
				return os.date("%b%d, %I:%M:%S%p", currentTime)
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 64,
				Constants.SCREEN.MARGIN - 4,
				50,
				10
			},
		},
		CurrentPage = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				return PE_SCREEN.Pager:getPageText()
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 56,
				Constants.SCREEN.MARGIN + 136,
				50,
				10
			},
			isVisible = function()
				return PE_SCREEN.Pager.totalPages > 1
			end
		},
		PrevPage = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.LEFT_ARROW,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 44,
				Constants.SCREEN.MARGIN + 137,
				10,
				10
			},
			isVisible = function()
				return PE_SCREEN.Pager.totalPages > 1
			end,
			onClick = function(self)
				PE_SCREEN.Pager:prevPage()
			end
		},
		NextPage = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.RIGHT_ARROW,
			box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 87, Constants.SCREEN.MARGIN + 137, 10, 10 },
			isVisible = function()
				return PE_SCREEN.Pager.totalPages > 1
			end,
			onClick = function(self)
				PE_SCREEN.Pager:nextPage()
			end
		},
		ExamineModal = {
			type = Constants.ButtonTypes.FULL_BORDER,
			getText = function(self)
				local timestamp = PE_SCREEN.examiningEncounter["timestamp"]
				return os.date("%b %d,  %I:%M:%S %p", timestamp)
			end,
			box = {
				Constants.SCREEN.WIDTH + 10,
				Constants.SCREEN.MARGIN + PE_TAB_HEIGHT + PE_OFFSET_FOR_NAME + 5,
				Constants.SCREEN.RIGHT_GAP - 20,
				Constants.SCREEN.HEIGHT - PE_TAB_HEIGHT - PE_OFFSET_FOR_NAME - 30
			},
			draw = function(self, shadowcolor)
				local Y_OFFSET = 10
				local x, y = self.box[1] + 1, self.box[2] + Y_OFFSET
				local w, h = self.box[3], self.box[4]
				local color = Theme.COLORS[self.boxColors[1]]
				local bgColor = Theme.COLORS[self.boxColors[2]]
				local encounter = PE_SCREEN.examiningEncounter
				if encounter == nil then
					return
				end
				-- draw level seen
				Drawing.drawText(
					x,
					y,
					"seen at lvl " .. encounter.level,
					Theme.COLORS[self.textColor],
					shadowcolor
				)
				y = y + Y_OFFSET
				Drawing.drawText(
					x,
					y,
					"while at lvl " .. encounter.playerlevel,
					Theme.COLORS[self.textColor],
					shadowcolor
				)
				y = y + Y_OFFSET
				Drawing.drawText(
					x,
					y,
					"while in:",
					Theme.COLORS[self.textColor],
					shadowcolor
				)
				y = y + Y_OFFSET
				Drawing.drawText(
					x,
					y,
					"  " .. RouteData.Info[encounter.routeid].name,
					Theme.COLORS[self.textColor],
					shadowcolor
				)
				if encounter.iswild == 0 then
					y = y + Y_OFFSET
					Drawing.drawText(
						x,
						y,
						"fighting trainer:",
						Theme.COLORS[self.textColor],
						shadowcolor
					)
					y = y + Y_OFFSET
					Drawing.drawText(
						x,
						y,
						"  " .. TrainerData.getTrainerInfo(encounter.trainerid).class.filename,
						Theme.COLORS[self.textColor],
						shadowcolor
					)
				end

				y = y + Y_OFFSET
				Drawing.drawText(
					x,
					y,
					"as " .. PokemonData.Pokemon[encounter.playerid].name,
					Theme.COLORS[self.textColor],
					shadowcolor
				)
			end,
			isVisible = function()
				return PE_SCREEN.examiningEncounter ~= nil
			end
		},
		BattleLog = {
			type = Constants.ButtonTypes.ICON_BORDER,
			image = Constants.PixelImages.RIGHT_ARROW,
			getText = function()
				return "Battle log"
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 58,
				Constants.SCREEN.HEIGHT - 31,
				72,
				14
			},
			isVisible = function()
				return PE_SCREEN.examiningEncounter ~= nil and PE_SCREEN.examiningBattleID ~= nil
			end,
			onClick = function()
				BattleTimelineScreen.open(PE_SCREEN.examiningBattleID)
			end
		},
		Back = Drawing.createUIElementBackButton(
			function()
				if PE_SCREEN.examiningEncounter then
					PE_SCREEN.examiningEncounter = nil
					PE_SCREEN.examiningBattleID = nil
				else
					Program.changeScreenView(PE_SCREEN.previousScreen or TrackerScreen)
					PE_SCREEN.previousScreen = nil
				end
			end
		)
	}

	PE_SCREEN.Pager = {
		Buttons = {},
		currentPage = 0,
		totalPages = 0,
		defaultSort = function(a, b)
			return (a.sortValue or 0) > (b.sortValue or 0) or (a.sortValue == b.sortValue and a.id < b.id)
		end,
		realignButtonsToGrid = function(self)
			table.sort(self.Buttons, self.defaultSort)
			local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
			local y = Constants.SCREEN.MARGIN + PE_TAB_HEIGHT + PE_OFFSET_FOR_NAME + 1
			local cutoffX = Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN
			local cutoffY = Constants.SCREEN.HEIGHT - Constants.SCREEN.MARGIN - 10
			local totalPages = Utils.gridAlign(self.Buttons, x, y, 2, 2, true, cutoffX, cutoffY)
			self.currentPage = 1
			self.totalPages = totalPages or 1
		end,
		getPageText = function(self)
			if self.totalPages <= 1 then
				return Resources.AllScreens.Page
			end
			local buffer = Utils.inlineIf(self.currentPage > 9, "", " ") .. Utils.inlineIf(self.totalPages > 9, "", " ")
			return buffer .. string.format("%s/%s", self.currentPage, self.totalPages)
		end,
		prevPage = function(self)
			if self.totalPages <= 1 then
				return
			end
			PE_SCREEN.examiningEncounter = nil
			PE_SCREEN.examiningBattleID = nil
			self.currentPage = ((self.currentPage - 2 + self.totalPages) % self.totalPages) + 1
			Program.redraw(true)
		end,
		nextPage = function(self)
			if self.totalPages <= 1 then
				return
			end
			PE_SCREEN.examiningEncounter = nil
			PE_SCREEN.examiningBattleID = nil
			self.currentPage = (self.currentPage % self.totalPages) + 1
			Program.redraw(true)
		end
	}

	function PreviousEncountersScreen.initialize()
		PE_SCREEN.currentView = 1
		PE_SCREEN.currentTab = PE_SCREEN.Tabs.All
		PE_SCREEN.createButtons()

		for _, button in pairs(PE_SCREEN.Buttons) do
			if button.textColor == nil then
				button.textColor = PE_SCREEN.Colors.text
			end
			if button.boxColors == nil then
				button.boxColors = { PE_SCREEN.Colors.border, PE_SCREEN.Colors.boxFill }
			end
		end

		PE_SCREEN.refreshButtons()
	end

	function PreviousEncountersScreen.refreshButtons()
		for _, button in pairs(PE_SCREEN.Buttons) do
			if button.updateSelf ~= nil then
				button:updateSelf()
			end
		end
		for _, button in pairs(PE_SCREEN.Pager.Buttons) do
			if button.updateSelf ~= nil then
				button:updateSelf()
			end
		end
	end

	function PreviousEncountersScreen.createButtons()
		local startX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
		local startY = Constants.SCREEN.MARGIN + PE_OFFSET_FOR_NAME
		local tabPadding = 5

		local allTabs = Utils.getSortedList(PE_SCREEN.Tabs)
		for _, tab in ipairs(allTabs) do
			PE_SCREEN.Buttons["Tab" .. tab.tabKey] = nil
		end

		local tabsToCreate
		if extensionSettings.ignoreWilds then
			tabsToCreate = { PE_SCREEN.Tabs.Trainer }
		else
			tabsToCreate = allTabs
		end

		-- TABS
		for _, tab in ipairs(tabsToCreate) do
			local tabText = tab.tabKey
			local tabWidth = (tabPadding * 2) + Utils.calcWordPixelLength(tabText)
			PE_SCREEN.Buttons["Tab" .. tab.tabKey] = {
				type = Constants.ButtonTypes.NO_BORDER,
				getText = function(self)
					return tabText
				end,
				tab = PE_SCREEN.Tabs[tab.tabKey],
				isSelected = false,
				box = { startX, startY, tabWidth, PE_TAB_HEIGHT },
				updateSelf = function(self)
					self.isSelected = (self.tab == PE_SCREEN.currentTab)
					self.textColor = Utils.inlineIf(self.isSelected, PE_SCREEN.Colors.highlight, PE_SCREEN.Colors.text)
				end,
				draw = function(self, shadowcolor)
					local x, y = self.box[1], self.box[2]
					local w, h = self.box[3], self.box[4]
					local color = Theme.COLORS[self.boxColors[1]]
					local bgColor = Theme.COLORS[self.boxColors[2]]
					gui.drawRectangle(x + 1, y + 1, w - 1, h - 2, bgColor, bgColor) -- Box fill
					if not self.isSelected then
						gui.drawRectangle(
							x + 1,
							y + 1,
							w - 1,
							h - 2,
							Drawing.ColorEffects.DARKEN,
							Drawing.ColorEffects.DARKEN
						)
					end
					gui.drawLine(x + 1, y, x + w - 1, y, color) -- Top edge
					gui.drawLine(x, y + 1, x, y + h - 1, color) -- Left edge
					gui.drawLine(x + w, y + 1, x + w, y + h - 1, color) -- Right edge
					if self.isSelected then
						gui.drawLine(x + 1, y + h, x + w - 1, y + h, bgColor) -- Remove bottom edge
					end
					local centeredOffsetX = Utils.getCenteredTextX(self:getText(), w) - 2
					Drawing.drawText(x + centeredOffsetX, y, self:getText(), Theme.COLORS[self.textColor], shadowcolor)
				end,
				onClick = function(self)
					PE_SCREEN.changeTab(self.tab)
				end
			}
			startX = startX + tabWidth
		end
	end

	function PreviousEncountersScreen.buildPagedButtons(tab)
		tab = tab or PE_SCREEN.currentTab
		PE_SCREEN.Pager.Buttons = {}

		local encountersCheck
		if tab == PE_SCREEN.Tabs.Wild then
			encountersCheck = "AND iswild = 1"
		elseif tab == PE_SCREEN.Tabs.Trainer then
			encountersCheck = "AND iswild = 0"
		end

		local encounters
		if PE_SCREEN.currentPokemonID ~= nil then
			encounters = getEncounterData(PE_SCREEN.currentPokemonID, encountersCheck)
		end

		local trackerCenterX = Constants.SCREEN.WIDTH + (Constants.SCREEN.RIGHT_GAP / 2)
		local encounterButtonWidth = 110
		for _, encounter in ipairs(encounters) do
			local levelText = "Lv." .. encounter.level
			local encounterTime = os.date("%b %d,  %I:%M:%S %p", encounter.timestamp)
			local button = {
				type = Constants.ButtonTypes.NO_BORDER,
				tab = tab,
				id = encounter.timestamp,
				sortValue = encounter.timestamp,
				dimensions = {
					width = encounterButtonWidth,
					height = 11
				},
				textColor = PE_SCREEN.Colors.text,
				boxColors = {
					PE_SCREEN.Colors.border,
					PE_SCREEN.Colors.boxFill
				},
				isVisible = function(self)
					return PE_SCREEN.Pager.currentPage == self.pageVisible and PE_SCREEN.examiningEncounter == nil
				end,
				includeInGrid = function(self)
					return PE_SCREEN.currentTab == self.tab
				end,
				onClick = function(self)
					PE_SCREEN.examiningEncounter = encounter
					PE_SCREEN.examiningBattleID = getBattleIDForEncounter(encounter)
				end,
				draw = function(self, shadowcolor)
					local x, y = self.box[1], self.box[2]
					Drawing.drawText(
						trackerCenterX - (encounterButtonWidth / 2),
						y,
						levelText,
						Theme.COLORS[self.textColor],
						shadowcolor
					)
					Drawing.drawText(
						trackerCenterX + (encounterButtonWidth / 2) - Utils.calcWordPixelLength(encounterTime),
						y,
						encounterTime,
						Theme.COLORS[self.textColor],
						shadowcolor
					)
				end
			}
			table.insert(PE_SCREEN.Pager.Buttons, button)
		end
		PE_SCREEN.Pager:realignButtonsToGrid()
	end

	local function rebuildPEScreen()
		PE_SCREEN.buildPagedButtons()
		PE_SCREEN.refreshButtons()
		Program.redraw(true)
	end

	function PreviousEncountersScreen.changeTab(tab)
		PE_SCREEN.currentTab = tab
		PE_SCREEN.examiningEncounter = nil
		PE_SCREEN.examiningBattleID = nil
		rebuildPEScreen()
	end

	function PreviousEncountersScreen.changePokemonID(pokemonID)
		PE_SCREEN.currentPokemonID = pokemonID
		PE_SCREEN.examiningEncounter = nil
		PE_SCREEN.examiningBattleID = nil
		rebuildPEScreen()
	end

	function PreviousEncountersScreen.openPokemonSelectWindow(cb)
		local form = Utils.createBizhawkForm(Resources.AllScreens.Lookup, 360, 105)

		local pokemonName
		if PokemonData.isValid(PE_SCREEN.currentPokemonID) then -- infoLookup = pokemonID
			pokemonName = PokemonData.Pokemon[PE_SCREEN.currentPokemonID].name
		else
			pokemonName = ""
		end
		local pokedexData = PokemonData.namesToList()

		forms.label(form, Resources.InfoScreen.PromptLookupPokemon .. ":", 49, 10, 250, 20)
		local pokedexDropdown = forms.dropdown(form, { ["Init"] = "Loading Pokedex" }, 50, 30, 145, 30)
		forms.setdropdownitems(pokedexDropdown, pokedexData, true) -- true = alphabetize the list
		forms.setproperty(pokedexDropdown, "AutoCompleteSource", "ListItems")
		forms.setproperty(pokedexDropdown, "AutoCompleteMode", "Append")
		forms.settext(pokedexDropdown, pokemonName)

		forms.button(form, Resources.AllScreens.Lookup, function()
			local pokemonNameFromForm = forms.gettext(pokedexDropdown)
			local pokemonId = PokemonData.getIdFromName(pokemonNameFromForm)

			if pokemonId ~= nil and pokemonId ~= 0 then
				PE_SCREEN.changePokemonID(pokemonId)
				Program.redraw(true)
			end
			Utils.closeBizhawkForm(form)
			if cb ~= nil then
				cb()
			end
		end, 212, 29)
	end

	-- USER INPUT FUNCTIONS
	function PreviousEncountersScreen.checkInput(xmouse, ymouse)
		Input.checkButtonsClicked(xmouse, ymouse, PE_SCREEN.Buttons)
		Input.checkButtonsClicked(xmouse, ymouse, PE_SCREEN.Pager.Buttons)
	end

	-- DRAWING FUNCTIONS
	function PreviousEncountersScreen.drawScreen()
		Drawing.drawBackgroundAndMargins()

		local canvas = {
			x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
			y = Constants.SCREEN.MARGIN + PE_TAB_HEIGHT + PE_OFFSET_FOR_NAME,
			width = Constants.SCREEN.RIGHT_GAP - (Constants.SCREEN.MARGIN * 2),
			height = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2) - PE_TAB_HEIGHT - PE_OFFSET_FOR_NAME,
			text = Theme.COLORS[PE_SCREEN.Colors.text],
			border = Theme.COLORS[PE_SCREEN.Colors.border],
			fill = Theme.COLORS[PE_SCREEN.Colors.boxFill],
			shadow = Utils.calcShadowColor(Theme.COLORS[PE_SCREEN.Colors.boxFill])
		}

		-- Draw top border box
		gui.defaultTextBackground(canvas.fill)
		gui.drawRectangle(canvas.x, canvas.y, canvas.width, canvas.height, canvas.border, canvas.fill)

		-- Draw all buttons
		Drawing.drawButton(PE_SCREEN.Buttons.ExamineModal, canvas.shadow)
		for buttonKey, button in pairs(PE_SCREEN.Buttons) do
			if buttonKey ~= "ExamineModal" then
				Drawing.drawButton(button, canvas.shadow)
			end
		end
		for _, button in pairs(PE_SCREEN.Pager.Buttons) do
			Drawing.drawButton(button, canvas.shadow)
		end
	end

	--
	------------------------------------ END Encounter Details Screen ------------------------------------
	--

	--
	------------------------------------ Battle Timeline Screen ------------------------------------
	--
	BattleTimelineScreen = {
		Colors = {
			text = "Default text",
			highlight = "Intermediate text",
			border = "Upper box border",
			boxFill = "Upper box background"
		},
		entries = {},
		currentIndex = 1,
	}
	local BT_SCREEN = BattleTimelineScreen
	local TIMELINE_HP_BAR_HEIGHT = 5
	local TIMELINE_NUMBER_FIELDS = {
		"battleid", "sequence", "turn", "actionindex", "actorindex", "actorpokemonid", "actiontype", "moveid",
		"iscritical", "weather", "eventkind", "eventreason", "subjectindex", "subjectpokemonid",
	}
	for _, prefix in ipairs(BATTLE_STATE_PREFIXES) do
		for _, field in ipairs({ "id", "hp", "status", "confused" }) do
			table.insert(TIMELINE_NUMBER_FIELDS, prefix .. field)
		end
		for _, stageKey in ipairs(STAT_STAGE_KEYS) do
			table.insert(TIMELINE_NUMBER_FIELDS, prefix .. stageKey .. "stage")
		end
	end

	local function getPokemonName(pokemonID)
		if PokemonData.isValid(pokemonID) then
			return PokemonData.Pokemon[pokemonID].name
		end
		return Constants.BLANKLINE
	end

	local function fitTimelineText(text, maxWidth)
		if Utils.calcWordPixelLength(text) <= maxWidth then
			return text
		end
		local shortened = text
		while #shortened > 0 and Utils.calcWordPixelLength(shortened .. "..") > maxWidth do
			shortened = shortened:sub(1, #shortened - 1)
		end
		return shortened .. ".."
	end

	local function drawHPBar(x, y, barPixels, canvas)
		barPixels = barPixels or HP_UNKNOWN
		local filledPixels = math.max(0, math.min(math.floor(barPixels), HP_BAR_PIXELS))
		local fillColor = Theme.COLORS["Negative text"]
		if filledPixels >= math.ceil(HP_BAR_PIXELS * 0.5) then
			fillColor = Theme.COLORS["Positive text"]
		elseif filledPixels >= math.ceil(HP_BAR_PIXELS * 0.2) then
			fillColor = Theme.COLORS["Intermediate text"]
		end

		for row = 0, TIMELINE_HP_BAR_HEIGHT - 1 do
			gui.drawLine(x, y + row, x + HP_BAR_PIXELS - 1, y + row, canvas.fill)
			if filledPixels > 0 then
				gui.drawLine(x, y + row, x + filledPixels - 1, y + row, fillColor)
			end
		end
		gui.drawLine(x - 1, y - 1, x + HP_BAR_PIXELS, y - 1, canvas.border)
		gui.drawLine(x - 1, y + TIMELINE_HP_BAR_HEIGHT, x + HP_BAR_PIXELS,
			y + TIMELINE_HP_BAR_HEIGHT, canvas.border)
		gui.drawLine(x - 1, y - 1, x - 1, y + TIMELINE_HP_BAR_HEIGHT, canvas.border)
		gui.drawLine(x + HP_BAR_PIXELS, y - 1, x + HP_BAR_PIXELS,
			y + TIMELINE_HP_BAR_HEIGHT, canvas.border)
		for percent = 0, 100, 10 do
			local markerX = x + math.floor((HP_BAR_PIXELS * percent / 100) + 0.5)
			gui.drawLine(markerX, y - 2, markerX, y, canvas.text)
		end
		for percent = 0, 100, 25 do
			local markerX = x + math.floor((HP_BAR_PIXELS * percent / 100) + 0.5)
			gui.drawLine(markerX, y + TIMELINE_HP_BAR_HEIGHT - 1, markerX,
				y + TIMELINE_HP_BAR_HEIGHT + 1, canvas.text)
		end
		if barPixels < 0 then
			local textWidth = Utils.calcWordPixelLength(Constants.HIDDEN_INFO)
			local textX = math.floor(x + (HP_BAR_PIXELS - 1 - textWidth) / 2)
			Drawing.drawText(textX, y - 3, Constants.HIDDEN_INFO, canvas.text, canvas.shadow)
		end
	end

	local function getPokemonStateText(entry, previousEntry, prefix)
		local parts = {}
		for _, stageKey in ipairs(STAT_STAGE_KEYS) do
			local stage = entry[prefix .. stageKey .. "stage"]
			if stage ~= nil and stage ~= STAT_STAGE_UNKNOWN and stage ~= 0 then
				table.insert(parts, string.format("%+d %s", stage, STAT_STAGE_NAMES[stageKey]))
			end
		end

		local currentStatus = entry[prefix .. "status"] or MAJOR_STATUS.UNKNOWN
		local previousStatus = MAJOR_STATUS.UNKNOWN
		if previousEntry ~= nil then
			previousStatus = previousEntry[prefix .. "status"] or MAJOR_STATUS.UNKNOWN
		end

		if currentStatus ~= MAJOR_STATUS.UNKNOWN and previousStatus ~= MAJOR_STATUS.UNKNOWN
			and previousStatus ~= currentStatus then
			local currentName = MAJOR_STATUS_NAMES[currentStatus] or Constants.HIDDEN_INFO
			local previousName = MAJOR_STATUS_NAMES[previousStatus] or Constants.HIDDEN_INFO
			table.insert(parts, previousName .. " > " .. currentName)
		elseif currentStatus ~= MAJOR_STATUS.UNKNOWN and currentStatus ~= MAJOR_STATUS.NONE then
			table.insert(parts, (MAJOR_STATUS_NAMES[currentStatus] or Constants.HIDDEN_INFO) .. " ongoing")
		end

		local currentConfused = entry[prefix .. "confused"] or CONFUSION_UNKNOWN
		local previousConfused = CONFUSION_UNKNOWN
		if previousEntry ~= nil then
			previousConfused = previousEntry[prefix .. "confused"] or CONFUSION_UNKNOWN
		end
		if currentConfused ~= CONFUSION_UNKNOWN and previousConfused ~= CONFUSION_UNKNOWN
			and previousConfused ~= currentConfused then
			table.insert(parts, Utils.inlineIf(currentConfused == 1, "clear > CNF", "CNF > clear"))
		elseif currentConfused == 1 then
			table.insert(parts, "CNF ongoing")
		end

		if #parts == 0 then return nil end
		return table.concat(parts, ", ")
	end

	local function getWeatherText(entry, previousEntry)
		local weather = entry.weather
		if weather == nil or weather == WEATHER.UNKNOWN then
			return nil
		end
		local previousWeather = previousEntry and previousEntry.weather or WEATHER.UNKNOWN
		local weatherName = WEATHER_NAMES[weather] or Constants.HIDDEN_INFO
		if previousWeather ~= WEATHER.UNKNOWN and previousWeather ~= weather then
			local previousName = WEATHER_NAMES[previousWeather] or Constants.HIDDEN_INFO
			return string.format("Weather: %s > %s", previousName, weatherName)
		end
		if weather ~= WEATHER.NONE then
			return "Weather: " .. weatherName
		end
		return nil
	end

	BT_SCREEN.Buttons = {
		Previous = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.LEFT_ARROW,
			box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 88, Constants.SCREEN.MARGIN + 1, 10, 10 },
			isVisible = function()
				return BT_SCREEN.currentIndex > 1
			end,
			onClick = function()
				BT_SCREEN.changeStep(-1)
			end,
		},
		Step = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function()
				local actionCount = math.max(#BT_SCREEN.entries - 1, 0)
				if BT_SCREEN.currentIndex == 1 then
					return "Start"
				end
				return string.format("%s/%s", BT_SCREEN.currentIndex - 1, actionCount)
			end,
			box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 99, Constants.SCREEN.MARGIN, 27, 10 },
		},
		Next = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.RIGHT_ARROW,
			box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 127, Constants.SCREEN.MARGIN + 1, 10, 10 },
			isVisible = function()
				return BT_SCREEN.currentIndex < #BT_SCREEN.entries
			end,
			onClick = function()
				BT_SCREEN.changeStep(1)
			end,
		},
		Back = Drawing.createUIElementBackButton(
			function()
				Program.changeScreenView(PreviousEncountersScreen)
			end
		),
	}

	function BattleTimelineScreen.initialize()
		for _, button in pairs(BT_SCREEN.Buttons) do
			if button.textColor == nil then
				button.textColor = BT_SCREEN.Colors.text
			end
			if button.boxColors == nil then
				button.boxColors = { BT_SCREEN.Colors.border, BT_SCREEN.Colors.boxFill }
			end
		end
	end

	function BattleTimelineScreen.open(battleID)
		BT_SCREEN.entries = getBattleTimeline(battleID)
		for _, entry in ipairs(BT_SCREEN.entries) do
			for _, field in ipairs(TIMELINE_NUMBER_FIELDS) do
				entry[field] = tonumber(entry[field]) or 0
			end
		end
		BT_SCREEN.currentIndex = 1
		Program.changeScreenView(BattleTimelineScreen)
	end

	function BattleTimelineScreen.changeStep(offset)
		BT_SCREEN.currentIndex = math.max(1, math.min(#BT_SCREEN.entries, BT_SCREEN.currentIndex + offset))
		Program.redraw(true)
	end

	function BattleTimelineScreen.checkInput(xmouse, ymouse)
		Input.checkButtonsClicked(xmouse, ymouse, BT_SCREEN.Buttons)
	end

	function BattleTimelineScreen.drawScreen()
		Drawing.drawBackgroundAndMargins()
		local canvas = {
			x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
			y = Constants.SCREEN.MARGIN + 12,
			width = Constants.SCREEN.RIGHT_GAP - (Constants.SCREEN.MARGIN * 2),
			height = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2) - 12,
			text = Theme.COLORS[BT_SCREEN.Colors.text],
			border = Theme.COLORS[BT_SCREEN.Colors.border],
			fill = Theme.COLORS[BT_SCREEN.Colors.boxFill],
			shadow = Utils.calcShadowColor(Theme.COLORS[BT_SCREEN.Colors.boxFill])
		}
		gui.defaultTextBackground(canvas.fill)
		gui.drawRectangle(canvas.x, canvas.y, canvas.width, canvas.height, canvas.border, canvas.fill)
		Drawing.drawText(canvas.x, Constants.SCREEN.MARGIN - 2, "Battle log",
			Theme.COLORS[BT_SCREEN.Colors.highlight], canvas.shadow)

		local entry = BT_SCREEN.entries[BT_SCREEN.currentIndex]
		local y = canvas.y + 4
		if entry == nil then
			Drawing.drawText(canvas.x + 4, y, "No battle actions recorded.", canvas.text, canvas.shadow)
		else
			local previousEntry = BT_SCREEN.entries[BT_SCREEN.currentIndex - 1]
			if entry.sequence == 0 then
				Drawing.drawText(canvas.x + 4, y, "Battle start", canvas.text, canvas.shadow)
			else
				local heading = string.format("Turn %s, action %s", entry.turn, entry.actionindex + 1)
				if entry.eventkind == EVENT_KIND.TICK then
					heading = string.format("Turn %s, end turn", entry.turn)
				elseif entry.eventkind == EVENT_KIND.RECOVERY or entry.actionindex < 0 then
					heading = string.format("Turn %s", entry.turn)
				end
				Drawing.drawText(canvas.x + 4, y,
					fitTimelineText(heading, canvas.width - 8), canvas.text, canvas.shadow)
				y = y + Constants.SCREEN.LINESPACING
				local subject = entry.eventkind ~= 0 and entry.subjectindex or entry.actorindex
				local pokemonID = entry.eventkind ~= 0 and entry.subjectpokemonid or entry.actorpokemonid
				local side = Utils.inlineIf(subject % 2 == 0, "Player", "Foe")
				if entry.ownrightid ~= 0 or entry.otherrightid ~= 0 then
					side = side .. " " .. tostring(math.floor(subject / 2) + 1)
				end
				local subjectText = side .. ": " .. getPokemonName(pokemonID)
				if entry.eventreason == EVENT_REASON.LEECH_SEED or entry.eventreason == EVENT_REASON.LEECH_OOZE then
					local recipient = Utils.inlineIf(entry.actorindex % 2 == 0, "Player", "Foe")
					if entry.ownrightid ~= 0 or entry.otherrightid ~= 0 then
						recipient = recipient .. " " .. tostring(math.floor(entry.actorindex / 2) + 1)
					end
					subjectText = side .. " -> " .. recipient
				end
				Drawing.drawText(canvas.x + 4, y,
					fitTimelineText(subjectText, canvas.width - 8),
					canvas.text, canvas.shadow)
				y = y + Constants.SCREEN.LINESPACING
				local actionText = ACTION_TYPES[entry.actiontype] or "Action"
				if entry.actiontype == 0 then
					actionText = "Nothing happened"
					if MoveData.isValid(entry.moveid) then
						actionText = MoveData.Moves[entry.moveid].name
					end
				end
				actionText = EVENT_LABELS[entry.eventreason] or ("Action: " .. actionText)
				Drawing.drawText(canvas.x + 4, y, fitTimelineText(actionText, canvas.width - 8),
					Theme.COLORS[BT_SCREEN.Colors.highlight], canvas.shadow)
				if entry.iscritical == 1 then
					y = y + Constants.SCREEN.LINESPACING
					Drawing.drawText(canvas.x + 4, y, "critical hit",
						Theme.COLORS[BT_SCREEN.Colors.highlight], canvas.shadow)
				end
			end

			y = y + Constants.SCREEN.LINESPACING + 3
			local stateHeading = Utils.inlineIf(entry.sequence == 0, "Before", "After")
			local weatherText = getWeatherText(entry, previousEntry)
			if weatherText ~= nil then
				stateHeading = stateHeading .. " | " .. weatherText
			end
			Drawing.drawText(canvas.x + 4, y, fitTimelineText(stateHeading, canvas.width - 8),
				Theme.COLORS[BT_SCREEN.Colors.highlight], canvas.shadow)
			y = y + Constants.SCREEN.LINESPACING
			local isDoubleBattle = entry.ownrightid ~= 0 or entry.otherrightid ~= 0
			local stateRows = {
				{ label = Utils.inlineIf(entry.ownrightid ~= 0, "P1", "Player"), prefix = "ownleft" },
				{ label = Utils.inlineIf(entry.otherrightid ~= 0, "F1", "Foe"),  prefix = "otherleft" },
				{ label = "P2",                                                  prefix = "ownright" },
				{ label = "F2",                                                  prefix = "otherright" },
			}
			local barX = canvas.x + 5
			local conditionX = barX + HP_BAR_PIXELS + 6
			for _, row in ipairs(stateRows) do
				local pokemonID = entry[row.prefix .. "id"] or 0
				if pokemonID ~= 0 then
					local text = row.label .. " " .. getPokemonName(pokemonID)
					local conditionText = getPokemonStateText(entry, previousEntry, row.prefix)
					if conditionText == nil then
						Drawing.drawText(canvas.x + 4, y, fitTimelineText(text, canvas.width - 8),
							canvas.text, canvas.shadow)
					else
						local maxConditionWidth = math.floor((canvas.width - 12) * 0.65)
						conditionText = fitTimelineText(conditionText, maxConditionWidth)
						local conditionWidth = Utils.calcWordPixelLength(conditionText)
						local nameWidth = canvas.width - conditionWidth - 13
						Drawing.drawText(canvas.x + 4, y, fitTimelineText(text, nameWidth),
							canvas.text, canvas.shadow)
						Drawing.drawText(canvas.x + canvas.width - conditionWidth - 4, y, conditionText,
							canvas.text, canvas.shadow)
					end
					y = y + Constants.SCREEN.LINESPACING + Utils.inlineIf(isDoubleBattle, 0, 1)
					local hpPixels = entry[row.prefix .. "hp"] or HP_UNKNOWN
					drawHPBar(barX, y + 1, hpPixels, canvas)
					if extensionSettings.showHPPixels and hpPixels >= 0 then
						local filledPixels = math.max(0, math.min(math.floor(hpPixels), HP_BAR_PIXELS))
						Drawing.drawText(conditionX, y,
							string.format("%s/%s pixels", filledPixels, HP_BAR_PIXELS),
							canvas.text, canvas.shadow)
					end
					y = y + TIMELINE_HP_BAR_HEIGHT + Utils.inlineIf(isDoubleBattle, 3, 4)
				end
			end
		end

		for _, button in pairs(BT_SCREEN.Buttons) do
			Drawing.drawButton(button, canvas.shadow)
		end
	end

	--
	------------------------------------ END Battle Timeline Screen ------------------------------------
	--


	--
	------------------------------------ Move Search Screen ------------------------------------
	--
	local MovesByPokemonScreen = {
		Colors = {
			text = "Default text",
			highlight = "Intermediate text",
			border = "Upper box border",
			boxFill = "Upper box background"
		},
		Tabs = {
			All = {
				index = 1,
				tabKey = "All",
				resourceKey = "TabAll"
			}
			-- todo hook up so we can list out encounters we've had with mon within range it could exist?
			-- Wild = {
			-- 	index = 2,
			-- 	tabKey = "Wild",
			-- 	resourceKey = "TabWild"
			-- },
			-- Trainer = {
			-- 	index = 3,
			-- 	tabKey = "Trainer",
			-- 	resourceKey = "TabTrainer"
			-- }
		},
		currentView = 1,
		currentTab = nil,
		currentMoveID = nil
	}

	local MV_SCREEN = MovesByPokemonScreen
	local MV_TAB_HEIGHT = 12
	local MV_OFFSET_FOR_NAME = 8

	local function movesToList()
		local moveNames = {}
		for id, move in ipairs(MoveData.Moves) do
			if MoveData.isValid(tonumber(move.id)) and move.name ~= Constants.BLANKLINE then
				table.insert(moveNames, move.name)
			end
		end
		return moveNames
	end

	local function moveIDFromName(moveName)
		for id, move in pairs(MoveData.Moves) do
			if move.name == moveName then
				return id
			end
		end

		return nil
	end

	local function getPokemonKnownToHaveMove(moveToFind)
		local monsWithMove = {}
		for id, pkmn in ipairs(PokemonData.Pokemon) do
			local knownMoves = Tracker.getMoves(pkmn.pokemonID)
			for _, move in ipairs(knownMoves) do
				local moveId = move.id or move.moveId
				if moveId == moveToFind then
					table.insert(monsWithMove, {
						pokemon = pkmn,
						trackedMove = move
					})
				end
			end
		end

		return monsWithMove
	end


	MV_SCREEN.Buttons = {
		NameLabel = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				return MoveData.Moves[MV_SCREEN.currentMoveID].name
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN - 3,
				Constants.SCREEN.MARGIN - 4,
				50,
				10
			},
			onClick = function()
				MV_SCREEN.openMoveSelectWindow()
			end
		},
		CurrentPage = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				return MV_SCREEN.Pager:getPageText()
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 56,
				Constants.SCREEN.MARGIN + 136,
				50,
				10
			},
			isVisible = function()
				return MV_SCREEN.Pager.totalPages > 1
			end
		},
		PrevPage = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.LEFT_ARROW,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 44,
				Constants.SCREEN.MARGIN + 137,
				10,
				10
			},
			isVisible = function()
				return MV_SCREEN.Pager.totalPages > 1
			end,
			onClick = function(self)
				MV_SCREEN.Pager:prevPage()
			end
		},
		NextPage = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.RIGHT_ARROW,
			box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 87, Constants.SCREEN.MARGIN + 137, 10, 10 },
			isVisible = function()
				return MV_SCREEN.Pager.totalPages > 1
			end,
			onClick = function(self)
				MV_SCREEN.Pager:nextPage()
			end
		},
		Back = Drawing.createUIElementBackButton(
			function()
				Program.changeScreenView(TrackerScreen)
			end
		)
	}

	MV_SCREEN.Pager = {
		Buttons = {},
		currentPage = 0,
		totalPages = 0,
		defaultSort = function(a, b)
			return (a.sortValue or 0) > (b.sortValue or 0) or (a.sortValue == b.sortValue and a.id < b.id)
		end,
		realignButtonsToGrid = function(self)
			table.sort(self.Buttons, self.defaultSort)
			local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
			local y = Constants.SCREEN.MARGIN + MV_TAB_HEIGHT + MV_OFFSET_FOR_NAME + 1
			local cutoffX = Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN
			local cutoffY = Constants.SCREEN.HEIGHT - Constants.SCREEN.MARGIN - 10
			local totalPages = Utils.gridAlign(self.Buttons, x, y, 2, 2, true, cutoffX, cutoffY)
			self.currentPage = 1
			self.totalPages = totalPages or 1
		end,
		getPageText = function(self)
			if self.totalPages <= 1 then
				return Resources.AllScreens.Page
			end
			local buffer = Utils.inlineIf(self.currentPage > 9, "", " ") .. Utils.inlineIf(self.totalPages > 9, "", " ")
			return buffer .. string.format("%s/%s", self.currentPage, self.totalPages)
		end,
		prevPage = function(self)
			if self.totalPages <= 1 then
				return
			end
			self.currentPage = ((self.currentPage - 2 + self.totalPages) % self.totalPages) + 1
			Program.redraw(true)
		end,
		nextPage = function(self)
			if self.totalPages <= 1 then
				return
			end
			self.currentPage = (self.currentPage % self.totalPages) + 1
			Program.redraw(true)
		end
	}

	function MovesByPokemonScreen.initialize()
		MV_SCREEN.currentView = 1
		MV_SCREEN.currentTab = MV_SCREEN.Tabs.All
		MV_SCREEN.createButtons()

		for _, button in pairs(MV_SCREEN.Buttons) do
			if button.textColor == nil then
				button.textColor = MV_SCREEN.Colors.text
			end
			if button.boxColors == nil then
				button.boxColors = { MV_SCREEN.Colors.border, MV_SCREEN.Colors.boxFill }
			end
		end

		MV_SCREEN.refreshButtons()
	end

	function MovesByPokemonScreen.refreshButtons()
		for _, button in pairs(MV_SCREEN.Buttons) do
			if button.updateSelf ~= nil then
				button:updateSelf()
			end
		end
		for _, button in pairs(MV_SCREEN.Pager.Buttons) do
			if button.updateSelf ~= nil then
				button:updateSelf()
			end
		end
	end

	function MovesByPokemonScreen.createButtons()
		local startX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
		local startY = Constants.SCREEN.MARGIN + MV_OFFSET_FOR_NAME
		local tabPadding = 5

		local allTabs = Utils.getSortedList(MV_SCREEN.Tabs)
		for _, tab in ipairs(allTabs) do
			MV_SCREEN.Buttons["Tab" .. tab.tabKey] = nil
		end

		-- local tabsToCreate
		-- if extensionSettings.ignoreWilds then
		-- 	tabsToCreate = { MV_SCREEN.Tabs.Trainer }
		-- else
		-- 	tabsToCreate = allTabs
		-- end
		local tabsToCreate = allTabs

		-- TABS
		for _, tab in ipairs(tabsToCreate) do
			local tabText = tab.tabKey
			local tabWidth = (tabPadding * 2) + Utils.calcWordPixelLength(tabText)
			MV_SCREEN.Buttons["Tab" .. tab.tabKey] = {
				type = Constants.ButtonTypes.NO_BORDER,
				getText = function(self)
					return tabText
				end,
				tab = MV_SCREEN.Tabs[tab.tabKey],
				isSelected = false,
				box = { startX, startY, tabWidth, MV_TAB_HEIGHT },
				updateSelf = function(self)
					self.isSelected = (self.tab == MV_SCREEN.currentTab)
					self.textColor = Utils.inlineIf(self.isSelected, MV_SCREEN.Colors.highlight, MV_SCREEN.Colors.text)
				end,
				draw = function(self, shadowcolor)
					local x, y = self.box[1], self.box[2]
					local w, h = self.box[3], self.box[4]
					local color = Theme.COLORS[self.boxColors[1]]
					local bgColor = Theme.COLORS[self.boxColors[2]]
					gui.drawRectangle(x + 1, y + 1, w - 1, h - 2, bgColor, bgColor) -- Box fill
					if not self.isSelected then
						gui.drawRectangle(
							x + 1,
							y + 1,
							w - 1,
							h - 2,
							Drawing.ColorEffects.DARKEN,
							Drawing.ColorEffects.DARKEN
						)
					end
					gui.drawLine(x + 1, y, x + w - 1, y, color) -- Top edge
					gui.drawLine(x, y + 1, x, y + h - 1, color) -- Left edge
					gui.drawLine(x + w, y + 1, x + w, y + h - 1, color) -- Right edge
					if self.isSelected then
						gui.drawLine(x + 1, y + h, x + w - 1, y + h, bgColor) -- Remove bottom edge
					end
					local centeredOffsetX = Utils.getCenteredTextX(self:getText(), w) - 2
					Drawing.drawText(x + centeredOffsetX, y, self:getText(), Theme.COLORS[self.textColor], shadowcolor)
				end,
				onClick = function(self)
					MV_SCREEN.changeTab(self.tab)
				end
			}
			startX = startX + tabWidth
		end
	end

	function MovesByPokemonScreen.buildPagedButtons(tab)
		tab = tab or MV_SCREEN.currentTab
		MV_SCREEN.Pager.Buttons = {}

		local monsWithThisMove
		if MV_SCREEN.currentMoveID ~= nil then
			monsWithThisMove = getPokemonKnownToHaveMove(MV_SCREEN.currentMoveID)
		end

		local trackerCenterX = Constants.SCREEN.WIDTH + (Constants.SCREEN.RIGHT_GAP / 2)
		local encounterButtonWidth = 100
		for _, monWithMove in ipairs(monsWithThisMove) do
			local minLv = monWithMove.trackedMove.minLv or monWithMove.trackedMove.level
			local maxLv = monWithMove.trackedMove.maxLv or monWithMove.trackedMove.level
			local levelRange = "min:" .. minLv .. ", max:" .. maxLv
			local monName = monWithMove.pokemon.name
			local button = {
				type = Constants.ButtonTypes.NO_BORDER,
				tab = tab,
				id = monWithMove.timestamp,
				sortValue = monWithMove.timestamp,
				dimensions = {
					width = encounterButtonWidth,
					height = 11
				},
				textColor = MV_SCREEN.Colors.text,
				boxColors = {
					MV_SCREEN.Colors.border,
					MV_SCREEN.Colors.boxFill
				},
				isVisible = function(self)
					return MV_SCREEN.Pager.currentPage == self.pageVisible
				end,
				includeInGrid = function(self)
					return MV_SCREEN.currentTab == self.tab
				end,
				-- onClick = function(self)
				--  -- TODO could open up mon info screen?
				-- 	InfoScreen.changeScreenView(InfoScreen.Screens.ITEM_INFO, self.id) -- implied redraw
				-- end,
				draw = function(self, shadowcolor)
					local x, y = self.box[1], self.box[2]
					Drawing.drawText(
						trackerCenterX - (encounterButtonWidth / 2),
						y,
						levelRange,
						Theme.COLORS[self.textColor],
						shadowcolor
					)
					Drawing.drawText(
						trackerCenterX + (encounterButtonWidth / 2) - Utils.calcWordPixelLength(monName),
						y,
						monName,
						Theme.COLORS[self.textColor],
						shadowcolor
					)
				end
			}
			table.insert(MV_SCREEN.Pager.Buttons, button)
		end
		MV_SCREEN.Pager:realignButtonsToGrid()
	end

	local function rebuildMVScreen()
		MV_SCREEN.buildPagedButtons()
		MV_SCREEN.refreshButtons()
		Program.redraw(true)
	end

	function MovesByPokemonScreen.changeTab(tab)
		MV_SCREEN.currentTab = tab
		rebuildMVScreen()
	end

	function MovesByPokemonScreen.changeMoveID(moveID)
		MV_SCREEN.currentMoveID = moveID
		rebuildMVScreen()
	end

	function MovesByPokemonScreen.openMoveSelectWindow(cb)
		local form = Utils.createBizhawkForm(Resources.AllScreens.Lookup, 360, 105)

		local moveName
		if MoveData.isValid(MV_SCREEN.currentMoveID) then -- infoLookup = pokemonID
			moveName = MoveData.Moves[MV_SCREEN.currentMoveID].name
		else
			moveName = ""
		end
		local pokedexData = movesToList()

		forms.label(form, "Choose a move to look up:", 49, 10, 250, 20)
		local moveDexDropdown = forms.dropdown(form, { ["Init"] = "Loading Moves" }, 50, 30, 145, 30)
		forms.setdropdownitems(moveDexDropdown, pokedexData, true) -- true = alphabetize the list
		forms.setproperty(moveDexDropdown, "AutoCompleteSource", "ListItems")
		forms.setproperty(moveDexDropdown, "AutoCompleteMode", "Append")
		forms.settext(moveDexDropdown, moveName)

		forms.button(form, Resources.AllScreens.Lookup, function()
			local moveNameFromForm = forms.gettext(moveDexDropdown)
			local moveId = moveIDFromName(moveNameFromForm)

			if moveId ~= nil and moveId ~= 0 then
				MV_SCREEN.changeMoveID(moveId)
				Program.redraw(true)
			end
			Utils.closeBizhawkForm(form)
			if cb ~= nil then
				cb()
			end
		end, 212, 29)
	end

	-- USER INPUT FUNCTIONS
	function MovesByPokemonScreen.checkInput(xmouse, ymouse)
		Input.checkButtonsClicked(xmouse, ymouse, MV_SCREEN.Buttons)
		Input.checkButtonsClicked(xmouse, ymouse, MV_SCREEN.Pager.Buttons)
	end

	-- DRAWING FUNCTIONS
	function MovesByPokemonScreen.drawScreen()
		Drawing.drawBackgroundAndMargins()

		local canvas = {
			x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
			y = Constants.SCREEN.MARGIN + MV_TAB_HEIGHT + MV_OFFSET_FOR_NAME,
			width = Constants.SCREEN.RIGHT_GAP - (Constants.SCREEN.MARGIN * 2),
			height = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2) - MV_TAB_HEIGHT - MV_OFFSET_FOR_NAME,
			text = Theme.COLORS[MV_SCREEN.Colors.text],
			border = Theme.COLORS[MV_SCREEN.Colors.border],
			fill = Theme.COLORS[MV_SCREEN.Colors.boxFill],
			shadow = Utils.calcShadowColor(Theme.COLORS[MV_SCREEN.Colors.boxFill])
		}

		-- Draw top border box
		gui.defaultTextBackground(canvas.fill)
		gui.drawRectangle(canvas.x, canvas.y, canvas.width, canvas.height, canvas.border, canvas.fill)

		-- Draw all buttons
		for _, button in pairs(MV_SCREEN.Buttons) do
			Drawing.drawButton(button, canvas.shadow)
		end
		for _, button in pairs(MV_SCREEN.Pager.Buttons) do
			Drawing.drawButton(button, canvas.shadow)
		end
	end

	--
	------------------------------------ END Move Search Screen ------------------------------------
	--

	--
	------------------------------------------- Tracker Buttons ------------------------------------------
	--

	local pigColors = {
		0xFF000000, -- black
		0xFFEAC3CE, -- pale pink
		0xFFFF0000, -- red
		0xFFEB7069, -- dark pink
		0xFFFFFFFF -- white
	}
	local piggyPixelImage = {
		-- 15x12
		{ 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0 },
		{ 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1 },
		{ 1, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 1 },
		{ 0, 1, 2, 1, 1, 2, 2, 2, 2, 2, 1, 1, 2, 1, 0 },
		{ 1, 2, 2, 1, 5, 2, 2, 2, 2, 2, 5, 1, 2, 2, 1 },
		{ 1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1 },
		{ 1, 2, 3, 2, 1, 2, 2, 2, 2, 2, 1, 2, 3, 2, 1 },
		{ 1, 2, 3, 2, 1, 2, 1, 2, 1, 2, 1, 2, 3, 2, 1 },
		{ 1, 2, 2, 2, 1, 2, 2, 2, 2, 2, 1, 2, 2, 2, 1 },
		{ 0, 1, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 1, 0 },
		{ 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 0 },
		{ 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0 }
	}

	local trackerPiggyBtnBox = {
		Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 80, -- x
		Constants.SCREEN.MARGIN + 10,                    -- y
		15,                                              -- w
		12                                               -- h
	}

	local shouldShowTrackerBtn = function()
		local viewedPokemon = Battle.getViewedPokemon(true) or {}
		local viewingOpponentInBattle =
			Program.currentScreen == TrackerScreen and Battle.inActiveBattle() and not Battle.isViewingOwn and
			PokemonData.isValid(viewedPokemon.pokemonID) and
			not (extensionSettings.ignoreWilds and Battle.isWildEncounter)
		return viewingOpponentInBattle
	end

	local onShowEncounterDetails = function()
		local pokemon = Tracker.getViewedPokemon() or {}
		if not PokemonData.isValid(pokemon.pokemonID) then
			return
		end

		local defaultTab =
			Utils.inlineIf(
				Battle.isWildEncounter,
				PreviousEncountersScreen.Tabs.Wild,
				PreviousEncountersScreen.Tabs.Trainer
			)
		PE_SCREEN.previousScreen = nil
		PreviousEncountersScreen.changePokemonID(pokemon.pokemonID)
		PreviousEncountersScreen.changeTab(defaultTab)
		Program.changeScreenView(PreviousEncountersScreen)
	end

	local trackerPigBtn = {
		type = Constants.ButtonTypes.PIXELIMAGE,
		textColor = "Default text",
		box = trackerPiggyBtnBox,
		isVisible = shouldShowTrackerBtn,
		draw = function()
			local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
			Drawing.drawImageAsPixels(piggyPixelImage, trackerPiggyBtnBox[1], trackerPiggyBtnBox[2], pigColors,
				shadowcolor)
		end,
		onClick = onShowEncounterDetails
	}

	local invisibleTextOverlayBtn = {
		-- Invisible clickable button
		type = Constants.ButtonTypes.NO_BORDER,
		box = {
			Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 33,
			Constants.SCREEN.MARGIN + 10 + 12,
			60,
			7
		},
		isVisible = shouldShowTrackerBtn,
		onClick = onShowEncounterDetails
	}

	local extensionPiggyBtnBox = {
		Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 120, -- x
		Constants.SCREEN.MARGIN + 4,                      -- y
		15,                                               -- w
		12                                                -- h
	}
	local extensionPagePigBtn = {
		type = Constants.ButtonTypes.PIXELIMAGE,
		textColor = "Default text",
		box = extensionPiggyBtnBox,
		isVisible = function()
			local extensionScreenIsDisplayed = Program.currentScreen == SingleExtensionScreen and
				SingleExtensionScreen.extensionKey == self.name
			return extensionScreenIsDisplayed
		end,
		draw = function()
			local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
			Drawing.drawImageAsPixels(piggyPixelImage, extensionPiggyBtnBox[1], extensionPiggyBtnBox[2], pigColors,
				shadowcolor)
		end,
		onClick = function()
			PE_SCREEN.openPokemonSelectWindow(function()
				if PokemonData.isValid(PE_SCREEN.currentPokemonID) then
					PE_SCREEN.previousScreen = nil
					Program.changeScreenView(PreviousEncountersScreen)
				end
			end)
		end
	}

	local NOTEBOOK_PIGGY = { WIDTH = 15, HEIGHT = 12, RIGHT_PADDING = 3, BOTTOM_PADDING = 3, TEXT_GAP = 4 }
	local notebookRows = {}
	local notebookOriginalBuild, notebookOriginalInput
	local notebookBuild, notebookInput
	local notebookNoteBinding

	local function openNotebookHistory(pokemonID, previousScreen)
		if not PokemonData.isValid(pokemonID) then return end
		PE_SCREEN.previousScreen = previousScreen
		PE_SCREEN.currentTab = extensionSettings.ignoreWilds and PE_SCREEN.Tabs.Trainer or PE_SCREEN.Tabs.All
		PE_SCREEN.changePokemonID(pokemonID)
		Program.changeScreenView(PE_SCREEN)
	end

	local function decorateNotebookRows()
		notebookRows = {}
		for _, row in ipairs(NotebookPokemonSeen.Pager.Buttons) do
			local label = row.buttonList[2]
			local pokemonID = row.pokemon.id
			local pigButton = {
				type = Constants.ButtonTypes.PIXELIMAGE,
				image = piggyPixelImage,
				iconColors = pigColors,
				textColor = "Default text",
				box = { 0, 0, NOTEBOOK_PIGGY.WIDTH, NOTEBOOK_PIGGY.HEIGHT },
				isVisible = function()
					return row:isVisible() and PokemonData.isValid(pokemonID)
				end,
				alignToBox = function(button, box)
					button.box[1] = box[1] + box[3] - NOTEBOOK_PIGGY.WIDTH - NOTEBOOK_PIGGY.RIGHT_PADDING
					button.box[2] = box[2] + box[4] - NOTEBOOK_PIGGY.HEIGHT - NOTEBOOK_PIGGY.BOTTOM_PADDING
				end,
				onClick = function()
					openNotebookHistory(pokemonID, NotebookPokemonSeen)
				end,
			}
			pigButton:alignToBox(row.box)
			local originalDraw = label.draw
			local labelDraw = function(button, shadowcolor)
				local tracked = Tracker.Data.allPokemon[pokemonID] or {}
				local trainers, wilds = tracked.eT or 0, tracked.eW or 0
				local seen = Resources.NotebookPokemonSeen.LabelSeen
				if trainers > 0 and wilds > 0 then
					seen = string.format("%s: %s(T) + %s(W)", seen, trainers, wilds)
				else
					seen = string.format("%s: %s", seen, trainers + wilds)
				end
				local textX, textY = button.box[1], button.box[2] + 2
				local textWidth = pigButton.box[1] - textX - NOTEBOOK_PIGGY.TEXT_GAP
				local fill = Theme.COLORS[NotebookPokemonSeen.Colors.boxFill]
				Drawing.drawTransparentTextbox(textX, textY, Utils.shortenText(button:getCustomText(), textWidth, true),
					Theme.COLORS[button.textColor], fill, shadowcolor)
				Drawing.drawTransparentTextbox(textX, textY + Constants.SCREEN.LINESPACING,
					Utils.shortenText(seen, textWidth, true),
					Theme.COLORS[NotebookPokemonSeen.Colors.text], fill, shadowcolor)
			end
			label.draw = labelDraw
			table.insert(row.buttonList, pigButton)
			table.insert(notebookRows,
				{ row = row, button = pigButton, label = label, originalDraw = originalDraw, labelDraw = labelDraw })
		end
	end

	local function installNotebookButtons()
		if notebookOriginalBuild or not NotebookPokemonSeen then return end
		notebookOriginalBuild = NotebookPokemonSeen.buildScreen
		notebookOriginalInput = NotebookPokemonSeen.checkInput
		notebookBuild = function(navFilter)
			local result = notebookOriginalBuild(navFilter)
			decorateNotebookRows()
			return result
		end
		notebookInput = function(mouseX, mouseY)
			for _, entry in ipairs(notebookRows) do
				local button = entry.button
				local box = button.box
				if button:isVisible() and Input.isMouseInArea(mouseX, mouseY, box[1], box[2], box[3], box[4]) then
					Input.checkButtonsClicked(mouseX, mouseY, { button })
					return
				end
			end
			notebookOriginalInput(mouseX, mouseY)
		end
		NotebookPokemonSeen.buildScreen = notebookBuild
		NotebookPokemonSeen.checkInput = notebookInput
		decorateNotebookRows()
	end

	local function removeNotebookButtons()
		if not notebookOriginalBuild then return end
		if NotebookPokemonSeen.buildScreen == notebookBuild then NotebookPokemonSeen.buildScreen = notebookOriginalBuild end
		if NotebookPokemonSeen.checkInput == notebookInput then NotebookPokemonSeen.checkInput = notebookOriginalInput end
		for _, entry in ipairs(notebookRows) do
			if entry.label.draw == entry.labelDraw then entry.label.draw = entry.originalDraw end
			for index = #entry.row.buttonList, 1, -1 do
				if entry.row.buttonList[index] == entry.button then table.remove(entry.row.buttonList, index) end
			end
		end
		if PE_SCREEN.previousScreen == NotebookPokemonSeen then
			if Program.currentScreen == PE_SCREEN or Program.currentScreen == BattleTimelineScreen then
				Program.changeScreenView(NotebookPokemonSeen)
			end
			PE_SCREEN.previousScreen = nil
		end
		notebookRows = {}
		notebookOriginalBuild, notebookOriginalInput = nil, nil
		notebookBuild, notebookInput = nil, nil
	end

	local function installNotebookNoteButton()
		if notebookNoteBinding or not NotebookPokemonNoteView then return end
		local notes = NotebookPokemonNoteView
		local noteButton = notes.Buttons.Note
		local backArea = notes.Buttons.Back.clickableArea or notes.Buttons.Back.box
		local originalGetText = noteButton.getText
		local originalArea = noteButton.clickableArea
		local pigButton = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = piggyPixelImage,
			iconColors = pigColors,
			textColor = notes.Colors.bottomText,
			location = "bottom",
			box = {
				backArea[1] - NOTEBOOK_PIGGY.WIDTH - NOTEBOOK_PIGGY.TEXT_GAP, noteButton.box[2],
				NOTEBOOK_PIGGY.WIDTH, NOTEBOOK_PIGGY.HEIGHT,
			},
			isVisible = function()
				return notes.Data.isReady and PokemonData.isValid(notes.Data.pokemonID)
			end,
			onClick = function()
				if notes.Data.isReady then openNotebookHistory(notes.Data.pokemonID, notes) end
			end,
		}
		local getText = function(button)
			local textX = button.box[1] + button.box[3] + 1
			return Utils.shortenText(originalGetText(button), pigButton.box[1] - textX - NOTEBOOK_PIGGY.TEXT_GAP, true)
		end
		local clickableArea = {
			originalArea[1], originalArea[2],
			pigButton.box[1] - originalArea[1] - NOTEBOOK_PIGGY.TEXT_GAP, originalArea[4],
		}
		notebookNoteBinding = {
			noteButton = noteButton,
			pigButton = pigButton,
			originalGetText = originalGetText,
			originalArea = originalArea,
			getText = getText,
			clickableArea = clickableArea,
			previousButton = notes.Buttons.EncounterDetails,
		}
		noteButton.getText = getText
		noteButton.clickableArea = clickableArea
		notes.Buttons.EncounterDetails = pigButton
	end

	local function removeNotebookNoteButton()
		if not notebookNoteBinding then return end
		local binding = notebookNoteBinding
		local notes = NotebookPokemonNoteView
		if binding.noteButton.getText == binding.getText then binding.noteButton.getText = binding.originalGetText end
		if binding.noteButton.clickableArea == binding.clickableArea then binding.noteButton.clickableArea = binding
			.originalArea end
		if notes.Buttons.EncounterDetails == binding.pigButton then notes.Buttons.EncounterDetails = binding
			.previousButton end
		if PE_SCREEN.previousScreen == notes then
			if Program.currentScreen == PE_SCREEN or Program.currentScreen == BattleTimelineScreen then
				Program.changeScreenView(notes)
			end
			PE_SCREEN.previousScreen = nil
		end
		notebookNoteBinding = nil
	end

	local extensionMoveSearchBox = {
		Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 120, -- x
		Constants.SCREEN.MARGIN + 24,                     -- y
		13,                                               -- w
		12                                                -- h
	}
	local extensionPageMoveSearchButton = {
		type = Constants.ButtonTypes.PIXELIMAGE,
		image = Constants.PixelImages.MAGNIFYING_GLASS,
		textColor = "Default text",
		box = extensionMoveSearchBox,
		isVisible = function()
			local extensionScreenIsDisplayed = Program.currentScreen == SingleExtensionScreen and
				SingleExtensionScreen.extensionKey == self.name
			return extensionScreenIsDisplayed
		end,
		onClick = function()
			MV_SCREEN.openMoveSelectWindow(function()
				if PokemonData.isValid(MV_SCREEN.currentMoveID) then
					Program.changeScreenView(MovesByPokemonScreen)
				end
			end)
		end
	}

	--------------------------------------
	-- INTERNAL TRACKER FUNCTIONS BELOW
	-- Add any number of these below functions to your extension that you want to use.
	-- If you don't need a function, don't add it at all; leave ommitted for faster code execution.
	--------------------------------------

	-- Executed when the user clicks the "Check for Updates" button while viewing the extension details within the Tracker's UI
	-- Returns [true, downloadUrl] if an update is available (downloadUrl auto opens in browser for user); otherwise returns [false, downloadUrl]
	-- Remove this function if you choose not to implement a version update check for your extension
	function self.checkForUpdates()
		-- Update the pattern below to match your version. You can check what this looks like by visiting the above url
		local versionResponsePattern = '"tag_name":%s+"%w+(%d+%.%d+)"' -- matches "1.0" in "tag_name": "v1.0"
		local versionCheckUrl = string.format("https://api.github.com/repos/%s/releases/latest", self.github or "")
		local downloadUrl = string.format("https://github.com/%s/releases/latest", self.github or "")
		local compareFunc = function(a, b)
			return a ~= b and not Utils.isNewerVersion(a, b)
		end -- if current version is *older* than online version
		local isUpdateAvailable =
			Utils.checkForVersionUpdate(versionCheckUrl, self.version, versionResponsePattern, compareFunc)
		return isUpdateAvailable, downloadUrl
	end

	-- Executed only once: When the extension is enabled by the user, and/or when the Tracker first starts up, after it loads all other required files and code
	function self.startup()
		if not Main.IsOnBizhawk() then
			return
		end

		extensionSettings.noPiggy = TrackerAPI.getExtensionSetting(self.name, "noPiggy") or false
		extensionSettings.ignoreWilds = TrackerAPI.getExtensionSetting(self.name, "ignoreWilds") or false
		extensionSettings.storeBattleLogs = TrackerAPI.getExtensionSetting(self.name, "storeBattleLogs") ~= false
		extensionSettings.showHPPixels = TrackerAPI.getExtensionSetting(self.name, "showHPPixels") ~= false

		loadData()
		PreviousEncountersScreen.initialize()
		BattleTimelineScreen.initialize()
		MovesByPokemonScreen.initialize()

		TrackerScreen.Buttons.EncounterDetails = trackerPigBtn
		TrackerScreen.Buttons.InvisibleEncounterDetails = invisibleTextOverlayBtn
		SingleExtensionScreen.Buttons.EncounterDetails = extensionPagePigBtn
		SingleExtensionScreen.Buttons.MoveSearchButton = extensionPageMoveSearchButton
		installNotebookButtons()
		installNotebookNoteButton()
	end

	-- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		if not Main.IsOnBizhawk() then
			return
		end
		finishBattleLog()
		removeNotebookButtons()
		removeNotebookNoteButton()

		TrackerScreen.Buttons.EncounterDetails = nil
		TrackerScreen.Buttons.InvisibleEncounterDetails = nil
		SingleExtensionScreen.Buttons.EncounterDetails = nil
		SingleExtensionScreen.Buttons.MoveSearchButton = nil
	end

	-- Executed once every 30 frames or after any redraw event is scheduled (i.e. most button presses)
	function self.afterRedraw()
		if not Main.IsOnBizhawk() then
			return
		end

		if TrackerScreen.Buttons.EncounterDetails ~= nil and TrackerScreen.Buttons.EncounterDetails:isVisible() then
			local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
			if not extensionSettings.noPiggy then
				Drawing.drawButton(TrackerScreen.Buttons.EncounterDetails, shadowcolor)
			end
			Drawing.drawButton(TrackerScreen.Buttons.InvisibleEncounterDetails, shadowcolor)
		end

		if SingleExtensionScreen.Buttons.EncounterDetails ~= nil and SingleExtensionScreen.Buttons.EncounterDetails:isVisible() then
			local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
			Drawing.drawButton(SingleExtensionScreen.Buttons.EncounterDetails, shadowcolor)
			Drawing.drawButton(SingleExtensionScreen.Buttons.MoveSearchButton, shadowcolor)
		end
	end

	local enemyPokemonMarkedEncountered = nil

	-- Executed once every 30 frames, after any battle related data from game memory is read in
	function self.afterBattleDataUpdate()
		if enemyPokemonMarkedEncountered == nil then
			return
		end
		if shouldIgnoreBattle() then
			discardBattleLog()
			return
		end

		local enemyTeam = Battle.BattleParties[1]

		for slot, mon in ipairs(enemyTeam) do
			if mon.seenAlready and not enemyPokemonMarkedEncountered[slot] then
				enemyPokemonMarkedEncountered[slot] = true
				local toTrack = Tracker.getPokemon(slot, false)
				trackEncounter(toTrack, Battle.isWildEncounter)
				if Program.currentScreen == PreviousEncountersScreen then
					rebuildPEScreen()
				end
			end
		end
	end

	-- Executed after a new battle begins (wild or trainer), and only once per battle
	function self.afterBattleBegins()
		if shouldIgnoreBattle() then
			return
		end

		enemyPokemonMarkedEncountered = {}
		if extensionSettings.storeBattleLogs then
			startBattleLog()
		end
	end

	-- Executed after a battle ends, and only once per battle
	function self.afterBattleEnds()
		if Program.currentScreen == PreviousEncountersScreen or Program.currentScreen == BattleTimelineScreen then
			Program.changeScreenView(TrackerScreen)
		end

		finishBattleLog()
		enemyPokemonMarkedEncountered = nil
	end

	-- -- Executed once every 30 frames, after most data from game memory is read in
	-- function self.afterProgramDataUpdate()
	--     -- [ADD CODE HERE]
	-- end
	-- -- Executed before a button's onClick() is processed, and only once per click per button
	-- -- Param: button: the button object being clicked
	-- function self.onButtonClicked(button)
	--     -- [ADD CODE HERE]
	-- end

	-- [Bizhawk only] Executed each frame (60 frames per second)
	-- CAUTION: Avoid unnecessary calculations here, as this can easily affect performance.
	-- function self.inputCheckBizhawk()
	--     -- Uncomment to use, otherwise leave commented out
	--     -- local mouseInput = input.getmouse() -- lowercase 'input' pulls directly from Bizhawk API
	--     -- local joypadButtons = Input.getJoypadInputFormatted() -- uppercase 'Input' uses Tracker formatted input
	--     -- [ADD CODE HERE]
	-- end

	-- [MGBA only] Executed each frame (60 frames per second)
	-- CAUTION: Avoid unnecessary calculations here, as this can easily affect performance.
	-- function self.inputCheckMGBA()
	--     -- Uncomment to use, otherwise leave commented out
	--     -- local joypadButtons = Input.getJoypadInputFormatted()
	--     -- [ADD CODE HERE]
	-- end

	-- Executed each frame of the game loop, after most data from game memory is read in but before any natural redraw events occur
	function self.afterEachFrame()
		if not Main.IsOnBizhawk() or currentBattle == nil or not Battle.inActiveBattle() then
			return
		end
		if shouldIgnoreBattle() then
			discardBattleLog()
			return
		end

		updateBattleAction()
		observeHPUpdate()
		updateBattleMessage()
		updateVisibleMove()
		updateCriticalHit()
		updateBattleState()
	end

	-- -- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
	-- -- Remove this function if you choose not to include a way for the user to configure options for your extension
	-- -- NOTE: You'll need to implement a way to save & load changes for your extension options, similar to Tracker's Settings.ini file
	function self.configureOptions()
		if not Main.IsOnBizhawk() then return end
		Program.destroyActiveForm()
		local form = forms.newform(320, 170, "Encounter Details Settings", function() client.unpause() end)
		Utils.setFormLocation(form, 100, 50)
		local ignoreWildsOriginal = extensionSettings.ignoreWilds
		local storeBattleLogsOriginal = extensionSettings.storeBattleLogs

		local noPiggySelection = forms.checkbox(form, "no piggy : (", 10, 30)
		local ignoreWildsSelection = forms.checkbox(form, "ignore wilds", 10, 50)
		local storeBattleLogsSelection = forms.checkbox(form, "store battle logs", 10, 70)
		local showHPPixelsSelection = forms.checkbox(form, "show HP as N/48 pixels", 10, 90)
		forms.setproperty(noPiggySelection, "Checked", extensionSettings.noPiggy)
		forms.setproperty(ignoreWildsSelection, "Checked", extensionSettings.ignoreWilds)
		forms.setproperty(storeBattleLogsSelection, "Checked", extensionSettings.storeBattleLogs)
		forms.setproperty(showHPPixelsSelection, "Checked", extensionSettings.showHPPixels)

		forms.button(form, "Save", function()
			extensionSettings.ignoreWilds = forms.ischecked(ignoreWildsSelection)
			extensionSettings.noPiggy = forms.ischecked(noPiggySelection)
			extensionSettings.storeBattleLogs = forms.ischecked(storeBattleLogsSelection)
			extensionSettings.showHPPixels = forms.ischecked(showHPPixelsSelection)

			TrackerAPI.saveExtensionSetting(self.name, "ignoreWilds", extensionSettings.ignoreWilds)
			TrackerAPI.saveExtensionSetting(self.name, "noPiggy", extensionSettings.noPiggy)
			TrackerAPI.saveExtensionSetting(self.name, "storeBattleLogs", extensionSettings.storeBattleLogs)
			TrackerAPI.saveExtensionSetting(self.name, "showHPPixels", extensionSettings.showHPPixels)
			if (storeBattleLogsOriginal and not extensionSettings.storeBattleLogs)
				or (Battle.isWildEncounter and extensionSettings.ignoreWilds) then
				discardBattleLog()
			end

			if ignoreWildsOriginal ~= extensionSettings.ignoreWilds then
				if Battle.inBattleScreen and Battle.isWildEncounter and not shouldIgnoreBattle() then
					enemyPokemonMarkedEncountered = enemyPokemonMarkedEncountered or {}
					if extensionSettings.storeBattleLogs and currentBattle == nil then
						startBattleLog()
					end
				end
				PE_SCREEN.initialize()
			end
			client.unpause()
			forms.destroy(form)
		end, 90, 115)
		forms.button(form, "Cancel", function()
			client.unpause()
			forms.destroy(form)
		end, 10, 115)
	end

	return self
end
return EncounterDetailsExtension
