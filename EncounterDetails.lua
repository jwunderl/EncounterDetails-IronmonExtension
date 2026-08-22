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
	self.timelineTableKey = self.name .. "BattleTimeline"
	local extensionSettings = {
		noPiggy = false,
		ignoreWilds = false,
		storeBattleLogs = true,
	}
	local ACTION_TYPES = {
		[0] = "Move",
		[1] = "Item",
		[2] = "Switch",
		[3] = "Run",
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
	-- gCritMultiplier is three bytes before gBattlescriptCurrInstr in each supported game.
	local CRIT_MULTIPLIER_OFFSET = -3
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
		-- Confusion is stored as -1 unknown, 0 clear, or 1 confused.
		local timelineTableCreateCommand = listToSqlCmd({
			"CREATE TABLE IF NOT EXISTS",
			self.timelineTableKey,
			"(",
			"battleid INTEGER,",
			"sequence INTEGER,",
			"turn INTEGER,",
			"actionindex INTEGER,",
			"actorindex INTEGER,",
			"actorpokemonid INTEGER,",
			"actiontype INTEGER,",
			"moveid INTEGER,",
			"iscritical INTEGER,",
			"ownleftid INTEGER,",
			"ownlefthp INTEGER,",
			"ownleftstatus INTEGER,",
			"ownleftconfused INTEGER,",
			"otherleftid INTEGER,",
			"otherlefthp INTEGER,",
			"otherleftstatus INTEGER,",
			"otherleftconfused INTEGER,",
			"ownrightid INTEGER,",
			"ownrighthp INTEGER,",
			"ownrightstatus INTEGER,",
			"ownrightconfused INTEGER,",
			"otherrightid INTEGER,",
			"otherrighthp INTEGER,",
			"otherrightstatus INTEGER,",
			"otherrightconfused INTEGER,",
			"PRIMARY KEY ( battleid, sequence )",
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
			"SELECT * FROM",
			self.timelineTableKey,
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
			"SELECT battleid FROM",
			self.encounterBattleTableKey,
			"WHERE pokemonid =",
			encounter.pokemonid,
			"AND encountertimestamp =",
			encounter.timestamp,
			"ORDER BY battleid DESC LIMIT 1"
		}))
		local rows = reformatSqlReadResult(res)
		return rows[1] and tonumber(rows[1].battleid) or nil
	end

	local function createBattleRecord()
		SQL.opendatabase(self.dbKey)
		SQL.writecommand(listToSqlCmd({
			"INSERT INTO",
			self.battleTableKey,
			"(timestamp, routeid, trainerid, iswild) VALUES (",
			os.time(), ",",
			Program.GameData.mapId, ",",
			Battle.opposingTrainerId, ",",
			Utils.inlineIf(Battle.isWildEncounter, "1", "0"),
			")"
		}))

		local rows = reformatSqlReadResult(SQL.readcommand("SELECT last_insert_rowid() AS battleid"))
		return rows[1] and tonumber(rows[1].battleid) or nil
	end

	local function getActivePokemonID(battlerIndex)
		local combatantKey = Battle.IndexMap[battlerIndex]
		local slot = combatantKey and Battle.Combatants[combatantKey]
		if slot == nil then
			return 0
		end
		local pokemon = Tracker.getPokemon(slot, battlerIndex % 2 == 0) or {}
		return PokemonData.isValid(pokemon.pokemonID) and pokemon.pokemonID or 0
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

	local function getBattleState()
		return {
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
	end

	local function mergeUnknownState(state, previousState)
		if previousState == nil then
			return state
		end
		for _, prefix in ipairs({ "ownleft", "otherleft", "ownright", "otherright" }) do
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
		end
		return state
	end

	local function battleStatesEqual(first, second)
		if first == nil or second == nil then
			return false
		end
		for _, prefix in ipairs({ "ownleft", "otherleft", "ownright", "otherright" }) do
			if first[prefix .. "id"] ~= second[prefix .. "id"]
				or first[prefix .. "hp"] ~= second[prefix .. "hp"]
				or first[prefix .. "status"] ~= second[prefix .. "status"]
				or first[prefix .. "confused"] ~= second[prefix .. "confused"] then
				return false
			end
		end
		return true
	end

	local function saveTimelineEvent(action, state)
		local current = currentBattle
		if current == nil or current.id == nil or action == nil or state == nil then
			return
		end

		SQL.opendatabase(self.dbKey)
		SQL.writecommand(listToSqlCmd({
			"INSERT OR REPLACE INTO",
			self.timelineTableKey,
			"(battleid, sequence, turn, actionindex, actorindex, actorpokemonid, actiontype, moveid, iscritical,",
			"ownleftid, ownlefthp, ownleftstatus, ownleftconfused,",
			"otherleftid, otherlefthp, otherleftstatus, otherleftconfused,",
			"ownrightid, ownrighthp, ownrightstatus, ownrightconfused,",
			"otherrightid, otherrighthp, otherrightstatus, otherrightconfused)",
			"VALUES (",
			current.id, ",", action.sequence, ",", action.turn, ",", action.actionindex, ",",
			action.actorindex, ",", action.actorpokemonid, ",", action.actiontype, ",", action.moveid, ",",
			action.iscritical or 0, ",",
			state.ownleftid, ",", state.ownlefthp, ",", state.ownleftstatus, ",", state.ownleftconfused, ",",
			state.otherleftid, ",", state.otherlefthp, ",", state.otherleftstatus, ",", state.otherleftconfused, ",",
			state.ownrightid, ",", state.ownrighthp, ",", state.ownrightstatus, ",", state.ownrightconfused, ",",
			state.otherrightid, ",", state.otherrighthp, ",", state.otherrightstatus, ",", state.otherrightconfused,
			")"
		}))
	end

	local function updateBattleState()
		local current = currentBattle
		if current == nil then
			return
		end

		local nextState = mergeUnknownState(getBattleState(), current.latestState)
		if battleStatesEqual(nextState, current.latestState) then
			return
		end
		current.latestState = nextState

		saveTimelineEvent(current.pendingAction or current.initialAction, current.latestState)
	end

	local function startBattleLog()
		local battleID = createBattleRecord()
		currentBattle = {
			id = battleID,
			actionKey = nil,
			observedTurn = nil,
			actionsConfirmed = false,
			pendingAction = nil,
			atCritMessage = false,
			latestState = nil,
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

		if current.observedTurn ~= Battle.turnCount then
			current.observedTurn = Battle.turnCount
			current.actionsConfirmed = false
		end
		if not current.actionsConfirmed then
			local confirmedCount = Memory.readbyte(GameSettings.gBattleCommunication
				+ Program.Addresses.offsetBattleCommConfirmedCount)
			if confirmedCount >= Battle.numBattlers then
				current.actionsConfirmed = true
			end
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
		local moveID = 0
		if actionType == 0 then
			local sideOffset = (actorIndex % 2) * Program.Addresses.sizeofLastAttackerMove
			moveID = Memory.readword(GameSettings.gBattleResults
				+ Program.Addresses.offsetBattleResultsLastAttackerMove + sideOffset)
			if not MoveData.isValid(moveID) then
				moveID = 0
			end
		end

		local turn = Battle.turnCount + 1
		return {
			key = string.format("%s:%s", turn, actionIndex),
			turn = turn,
			actionindex = actionIndex,
			actorindex = actorIndex,
			actorpokemonid = getActivePokemonID(actorIndex),
			actiontype = actionType,
			moveid = moveID,
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
			if current.pendingAction ~= nil and action.moveid ~= 0
				and current.pendingAction.moveid ~= action.moveid then
				current.pendingAction.moveid = action.moveid
				saveTimelineEvent(current.pendingAction, current.latestState)
			end
			return
		end

		updateBattleState()
		current.actionKey = action.key
		current.atCritMessage = false
		action.sequence = current.nextSequence
		current.nextSequence = current.nextSequence + 1
		current.pendingAction = action
		saveTimelineEvent(action, current.latestState)
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
		local atCritMessage = scriptAddress >= 0x08000000 and scriptAddress < 0x0A000000
			and Memory.readbyte(scriptAddress) == CRIT_MESSAGE_OPCODE
		if not atCritMessage then
			current.atCritMessage = false
			return
		end
		if current.atCritMessage then
			return
		end
		current.atCritMessage = true

		local critAddress = scriptPointerAddress + CRIT_MULTIPLIER_OFFSET
		if Memory.readbyte(critAddress) == 2 then
			action.iscritical = 1
			saveTimelineEvent(action, current.latestState)
		end
	end

	local function finishBattleLog()
		local current = currentBattle
		if current ~= nil and current.pendingAction ~= nil then
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

	local function trackEncounter(pokemon, isWild)
		local playerMon = Tracker.getPokemon(1, true);
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
					Program.changeScreenView(TrackerScreen)
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
		"iscritical",
		"ownleftid", "ownlefthp", "ownleftstatus", "ownleftconfused",
		"otherleftid", "otherlefthp", "otherleftstatus", "otherleftconfused",
		"ownrightid", "ownrighthp", "ownrightstatus", "ownrightconfused",
		"otherrightid", "otherrighthp", "otherrightstatus", "otherrightconfused",
	}

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

	local function getConditionText(entry, previousEntry, prefix)
		local parts = {}
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
				Drawing.drawText(canvas.x + 4, y,
					string.format("Turn %s, action %s", entry.turn, entry.actionindex + 1), canvas.text, canvas.shadow)
				y = y + Constants.SCREEN.LINESPACING
				local side = Utils.inlineIf(entry.actorindex % 2 == 0, "Player", "Foe")
				Drawing.drawText(canvas.x + 4, y,
					fitTimelineText(side .. ": " .. getPokemonName(entry.actorpokemonid), canvas.width - 8),
					canvas.text, canvas.shadow)
				y = y + Constants.SCREEN.LINESPACING
				local actionText = ACTION_TYPES[entry.actiontype] or "Action"
				if entry.actiontype == 0 and MoveData.isValid(entry.moveid) then
					actionText = MoveData.Moves[entry.moveid].name
				end
				Drawing.drawText(canvas.x + 4, y, fitTimelineText("Action: " .. actionText, canvas.width - 8),
					Theme.COLORS[BT_SCREEN.Colors.highlight], canvas.shadow)
				if entry.iscritical == 1 then
					y = y + Constants.SCREEN.LINESPACING
					Drawing.drawText(canvas.x + 4, y, "critical hit",
						Theme.COLORS[BT_SCREEN.Colors.highlight], canvas.shadow)
				end
			end

			y = y + Constants.SCREEN.LINESPACING + 3
			Drawing.drawText(canvas.x + 4, y, Utils.inlineIf(entry.sequence == 0, "Before", "After"),
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
					Drawing.drawText(canvas.x + 4, y, fitTimelineText(text, canvas.width - 8),
						canvas.text, canvas.shadow)
					y = y + Constants.SCREEN.LINESPACING + Utils.inlineIf(isDoubleBattle, 0, 1)
					drawHPBar(barX, y + 1, entry[row.prefix .. "hp"], canvas)
					local conditionText = getConditionText(entry, previousEntry, row.prefix)
					if conditionText ~= nil then
						local conditionWidth = canvas.x + canvas.width - 4 - conditionX
						Drawing.drawText(conditionX, y, fitTimelineText(conditionText, conditionWidth),
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
					Program.changeScreenView(PreviousEncountersScreen)
				end
			end)
		end
	}

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

		loadData()
		PreviousEncountersScreen.initialize()
		BattleTimelineScreen.initialize()
		MovesByPokemonScreen.initialize()

		TrackerScreen.Buttons.EncounterDetails = trackerPigBtn
		TrackerScreen.Buttons.InvisibleEncounterDetails = invisibleTextOverlayBtn
		SingleExtensionScreen.Buttons.EncounterDetails = extensionPagePigBtn
		SingleExtensionScreen.Buttons.MoveSearchButton = extensionPageMoveSearchButton
	end

	-- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		if not Main.IsOnBizhawk() then
			return
		end
		finishBattleLog()

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
		if Battle.isGhost then
			return
		end
		if Battle.isWildEncounter and extensionSettings.ignoreWilds then
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

		updateBattleAction()
		updateCriticalHit()
		updateBattleState()
	end

	-- -- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
	-- -- Remove this function if you choose not to include a way for the user to configure options for your extension
	-- -- NOTE: You'll need to implement a way to save & load changes for your extension options, similar to Tracker's Settings.ini file
	function self.configureOptions()
		if not Main.IsOnBizhawk() then return end
		Program.destroyActiveForm()
		local form = forms.newform(320, 150, "Encounter Details Settings", function() client.unpause() end)
		Utils.setFormLocation(form, 100, 50)
		local ignoreWildsOriginal = extensionSettings.ignoreWilds
		local storeBattleLogsOriginal = extensionSettings.storeBattleLogs

		local noPiggySelection = forms.checkbox(form, "no piggy : (", 10, 30)
		local ignoreWildsSelection = forms.checkbox(form, "ignore wilds", 10, 50)
		local storeBattleLogsSelection = forms.checkbox(form, "store battle logs", 10, 70)
		forms.setproperty(noPiggySelection, "Checked", extensionSettings.noPiggy)
		forms.setproperty(ignoreWildsSelection, "Checked", extensionSettings.ignoreWilds)
		forms.setproperty(storeBattleLogsSelection, "Checked", extensionSettings.storeBattleLogs)

		forms.button(form, "Save", function()
			extensionSettings.ignoreWilds = forms.ischecked(ignoreWildsSelection)
			extensionSettings.noPiggy = forms.ischecked(noPiggySelection)
			extensionSettings.storeBattleLogs = forms.ischecked(storeBattleLogsSelection)

			TrackerAPI.saveExtensionSetting(self.name, "ignoreWilds", extensionSettings.ignoreWilds)
			TrackerAPI.saveExtensionSetting(self.name, "noPiggy", extensionSettings.noPiggy)
			TrackerAPI.saveExtensionSetting(self.name, "storeBattleLogs", extensionSettings.storeBattleLogs)
			if storeBattleLogsOriginal and not extensionSettings.storeBattleLogs then
				discardBattleLog()
			end

			if ignoreWildsOriginal ~= extensionSettings.ignoreWilds then
				PE_SCREEN.initialize()
			end
			client.unpause()
			forms.destroy(form)
		end, 90, 95)
		forms.button(form, "Cancel", function()
			client.unpause()
			forms.destroy(form)
		end, 10, 95)
	end

	return self
end
return EncounterDetailsExtension
