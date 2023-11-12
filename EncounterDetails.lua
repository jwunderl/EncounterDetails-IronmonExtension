local function EncounterDetailsExtension()
	-- Define descriptive attributes of the custom extension that are displayed on the Tracker settings
	local self = {}
	self.version = "1.0"
	self.name = "EncounterDetails"
	self.author = "jwunderl"
	self.description = "Track extra details on every encounter you've faced."
	self.github = "jwunderl/EncounterDetails-IronmonExtension"
	self.url = string.format("https://github.com/%s", self.github or "")

	local DB_SUFFIX = ".db"
	self.serializationKey =
		FileManager.Folders.Custom ..
		FileManager.slash .. GameSettings.getRomName():gsub(" ", "") .. self.name .. FileManager.Extensions.TRACKED_DATA
	self.dbKey =
		FileManager.prependDir(FileManager.Folders.Custom ..
			FileManager.slash .. GameSettings.getRomName():gsub(" ", "") .. self.name .. DB_SUFFIX)
	self.encounterTableKey = self.name .. "Encounters"
	local extensionSettings = {
		noPiggy = false,
		ignoreWilds = false,
	}

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
		local result = ""

		for ind, part in ipairs(commandParts) do
			result = result .. part
			if (ind ~= #commandParts) then
				result = result .. " "
			end
		end
		return result
	end

	local function serializeData()
		-- todo probably move this to db separate table
		local filepath = self.serializationKey
		local persistedData = {
			h = GameSettings.getRomHash()
		}
		FileManager.writeTableToFile(persistedData, filepath)
	end

	local function loadData()
		local filepath = FileManager.prependDir(self.serializationKey)
		local fileData = FileManager.readTableFromFile(filepath)
		local currGameHash = GameSettings.getRomHash()

		-- SQL.createdatabase(self.dbKey) -- todo is this necessary
		SQL.opendatabase(self.dbKey)
		if fileData == nil or fileData.h ~= currGameHash then
			local dropTableCommand = "DROP TABLE IF EXISTS " .. self.encounterTableKey
			local encounterTableCreateCommand = listToSqlCmd({
				"CREATE TABLE IF NOT EXISTS " .. self.encounterTableKey .. " (",
				"pokemonid INTEGER,",
				"timestamp INTEGER,",
				"level INTEGER,",
				"iswild INTEGER", -- BOOLEAN: 1 true, 0 false
				");"
			})
			local createIndexCommand = listToSqlCmd({
				"CREATE INDEX POKEMON_ID ON",
				self.encounterTableKey,
				" ( pokemonid )"
			})
			SQL.writecommand(dropTableCommand)
			SQL.writecommand(encounterTableCreateCommand)
			SQL.writecommand(createIndexCommand)
			-- save updated hash, can probably just move this over to a config table to keep clean
			serializeData()
			return
		end
	end

	local function getEncounterData(pokemonID, wildCheck)
		local readEncounterDataCommand = listToSqlCmd({
			"SELECT * ",
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

	local function trackEncounter(pokemon, isWild)
		local trackEncounterCommand = listToSqlCmd({
			"INSERT INTO ",
			self.encounterTableKey,
			" (pokemonid, timestamp, level, iswild) VALUES (",
			pokemon.pokemonID, ", ",
			os.time(), ", ",
			pokemon.level, ", ",
			Utils.inlineIf(isWild, "1", "0"),
			")"
		})
		SQL.opendatabase(self.dbKey)
		local res = SQL.writecommand(trackEncounterCommand)
	end

	--
	------------------------------------ Encounter Details Screen ------------------------------------
	--
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
		currentPokemonID = nil
	}

	local SCREEN = PreviousEncountersScreen
	local TAB_HEIGHT = 12
	local OFFSET_FOR_NAME = 8

	SCREEN.Buttons = {
		NameLabel = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				return PokemonData.Pokemon[SCREEN.currentPokemonID].name
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN - 3,
				Constants.SCREEN.MARGIN - 4,
				50,
				10
			},
			onClick = function()
				SCREEN.openPokemonSelectWindow()
			end
		},
		CurrentPage = {
			type = Constants.ButtonTypes.NO_BORDER,
			getText = function(self)
				return SCREEN.Pager:getPageText()
			end,
			box = {
				Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 56,
				Constants.SCREEN.MARGIN + 136,
				50,
				10
			},
			isVisible = function()
				return SCREEN.Pager.totalPages > 1
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
				return SCREEN.Pager.totalPages > 1
			end,
			onClick = function(self)
				SCREEN.Pager:prevPage()
			end
		},
		NextPage = {
			type = Constants.ButtonTypes.PIXELIMAGE,
			image = Constants.PixelImages.RIGHT_ARROW,
			box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 87, Constants.SCREEN.MARGIN + 137, 10, 10 },
			isVisible = function()
				return SCREEN.Pager.totalPages > 1
			end,
			onClick = function(self)
				SCREEN.Pager:nextPage()
			end
		},
		Back = Drawing.createUIElementBackButton(
			function()
				Program.changeScreenView(TrackerScreen)
			end
		)
	}

	SCREEN.Pager = {
		Buttons = {},
		currentPage = 0,
		totalPages = 0,
		defaultSort = function(a, b)
			return (a.sortValue or 0) > (b.sortValue or 0) or (a.sortValue == b.sortValue and a.id < b.id)
		end,
		realignButtonsToGrid = function(self)
			table.sort(self.Buttons, self.defaultSort)
			local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
			local y = Constants.SCREEN.MARGIN + TAB_HEIGHT + OFFSET_FOR_NAME + 1
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

	function PreviousEncountersScreen.initialize()
		SCREEN.currentView = 1
		SCREEN.currentTab = SCREEN.Tabs.All
		SCREEN.createButtons()

		for _, button in pairs(SCREEN.Buttons) do
			if button.textColor == nil then
				button.textColor = SCREEN.Colors.text
			end
			if button.boxColors == nil then
				button.boxColors = { SCREEN.Colors.border, SCREEN.Colors.boxFill }
			end
		end

		SCREEN.refreshButtons()
	end

	function PreviousEncountersScreen.refreshButtons()
		for _, button in pairs(SCREEN.Buttons) do
			if button.updateSelf ~= nil then
				button:updateSelf()
			end
		end
		for _, button in pairs(SCREEN.Pager.Buttons) do
			if button.updateSelf ~= nil then
				button:updateSelf()
			end
		end
	end

	function PreviousEncountersScreen.createButtons()
		local startX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
		local startY = Constants.SCREEN.MARGIN + OFFSET_FOR_NAME
		local tabPadding = 5

		local allTabs = Utils.getSortedList(SCREEN.Tabs)
		for _, tab in ipairs(allTabs) do
			SCREEN.Buttons["Tab" .. tab.tabKey] = nil
		end

		local tabsToCreate
		if extensionSettings.ignoreWilds then
			tabsToCreate = { SCREEN.Tabs.Trainer }
		else
			tabsToCreate = allTabs
		end

		-- TABS
		for _, tab in ipairs(tabsToCreate) do
			local tabText = tab.tabKey
			local tabWidth = (tabPadding * 2) + Utils.calcWordPixelLength(tabText)
			SCREEN.Buttons["Tab" .. tab.tabKey] = {
				type = Constants.ButtonTypes.NO_BORDER,
				getText = function(self)
					return tabText
				end,
				tab = SCREEN.Tabs[tab.tabKey],
				isSelected = false,
				box = { startX, startY, tabWidth, TAB_HEIGHT },
				updateSelf = function(self)
					self.isSelected = (self.tab == SCREEN.currentTab)
					self.textColor = Utils.inlineIf(self.isSelected, SCREEN.Colors.highlight, SCREEN.Colors.text)
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
					SCREEN.changeTab(self.tab)
				end
			}
			startX = startX + tabWidth
		end
	end

	function PreviousEncountersScreen.buildPagedButtons(tab)
		tab = tab or SCREEN.currentTab
		SCREEN.Pager.Buttons = {}

		local encountersCheck
		if tab == SCREEN.Tabs.Wild then
			encountersCheck = "AND iswild = 1"
		elseif tab == SCREEN.Tabs.Trainer then
			encountersCheck = "AND iswild = 0"
		end

		local encounters
		if SCREEN.currentPokemonID ~= nil then
			encounters = getEncounterData(SCREEN.currentPokemonID, encountersCheck)
		end

		local trackerCenterX = Constants.SCREEN.WIDTH + (Constants.SCREEN.RIGHT_GAP / 2)
		local encounterButtonWidth = 100
		for _, encounter in ipairs(encounters) do
			local levelText = "Lv." .. encounter.level
			local encounterTime = os.date("%b %d,  %I:%M %p", encounter.timestamp)
			local button = {
				type = Constants.ButtonTypes.NO_BORDER,
				tab = tab,
				id = encounter.timestamp,
				sortValue = encounter.timestamp,
				dimensions = {
					width = encounterButtonWidth,
					height = 11
				},
				textColor = SCREEN.Colors.text,
				boxColors = {
					SCREEN.Colors.border,
					SCREEN.Colors.boxFill
				},
				isVisible = function(self)
					return SCREEN.Pager.currentPage == self.pageVisible
				end,
				includeInGrid = function(self)
					return SCREEN.currentTab == self.tab
				end,
				-- onClick = function(self)
				--  -- TODO if we append more info on tracked data can render state of mon at that time
				-- 	InfoScreen.changeScreenView(InfoScreen.Screens.ITEM_INFO, self.id) -- implied redraw
				-- end,
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
			table.insert(SCREEN.Pager.Buttons, button)
		end
		SCREEN.Pager:realignButtonsToGrid()
	end

	local function rebuild()
		SCREEN.buildPagedButtons()
		SCREEN.refreshButtons()
		Program.redraw(true)
	end

	function PreviousEncountersScreen.changeTab(tab)
		SCREEN.currentTab = tab
		rebuild()
	end

	function PreviousEncountersScreen.changePokemonID(pokemonID)
		SCREEN.currentPokemonID = pokemonID
		rebuild()
	end

	function PreviousEncountersScreen.openPokemonSelectWindow(cb)
		local form = Utils.createBizhawkForm(Resources.AllScreens.Lookup, 360, 105)

		local pokemonName
		if PokemonData.isValid(SCREEN.currentPokemonID) then -- infoLookup = pokemonID
			pokemonName = PokemonData.Pokemon[SCREEN.currentPokemonID].name
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
				SCREEN.changePokemonID(pokemonId)
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
		Input.checkButtonsClicked(xmouse, ymouse, SCREEN.Buttons)
		Input.checkButtonsClicked(xmouse, ymouse, SCREEN.Pager.Buttons)
	end

	-- DRAWING FUNCTIONS
	function PreviousEncountersScreen.drawScreen()
		Drawing.drawBackgroundAndMargins()

		local canvas = {
			x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
			y = Constants.SCREEN.MARGIN + TAB_HEIGHT + OFFSET_FOR_NAME,
			width = Constants.SCREEN.RIGHT_GAP - (Constants.SCREEN.MARGIN * 2),
			height = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2) - TAB_HEIGHT - OFFSET_FOR_NAME,
			text = Theme.COLORS[SCREEN.Colors.text],
			border = Theme.COLORS[SCREEN.Colors.border],
			fill = Theme.COLORS[SCREEN.Colors.boxFill],
			shadow = Utils.calcShadowColor(Theme.COLORS[SCREEN.Colors.boxFill])
		}

		-- Draw top border box
		gui.defaultTextBackground(canvas.fill)
		gui.drawRectangle(canvas.x, canvas.y, canvas.width, canvas.height, canvas.border, canvas.fill)

		-- Draw all buttons
		for _, button in pairs(SCREEN.Buttons) do
			Drawing.drawButton(button, canvas.shadow)
		end
		for _, button in pairs(SCREEN.Pager.Buttons) do
			Drawing.drawButton(button, canvas.shadow)
		end
	end

	--
	------------------------------------ END Encounter Details Screen ------------------------------------
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
		box = { -- TODO does this need to be changed for trainer encounter screen? in that case do we have to dup it?
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
			SCREEN.openPokemonSelectWindow(function()
				if PokemonData.isValid(SCREEN.currentPokemonID) then
					Program.changeScreenView(PreviousEncountersScreen)
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

		loadData()
		PreviousEncountersScreen.initialize()

		TrackerScreen.Buttons.EncounterDetails = trackerPigBtn
		TrackerScreen.Buttons.InvisibleEncounterDetails = invisibleTextOverlayBtn
		SingleExtensionScreen.Buttons.EncounterDetails = extensionPagePigBtn
	end

	-- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		if not Main.IsOnBizhawk() then
			return
		end
		TrackerScreen.Buttons.EncounterDetails = nil
		TrackerScreen.Buttons.InvisibleEncounterDetails = nil
		SingleExtensionScreen.Buttons.EncounterDetails = nil
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
					rebuild()
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
	end

	-- Executed after a battle ends, and only once per battle
	function self.afterBattleEnds()
		if Program.currentScreen == PreviousEncountersScreen then
			Program.changeScreenView(TrackerScreen)
		end

		if enemyPokemonMarkedEncountered == nil then
			-- tracked data did not change, do not save
			return
		end

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
	-- CAUTION: Avoid code here if possible, as this can easily affect performance. Most Tracker updates occur at 30-frame intervals, some at 10-frame.
	-- function self.afterEachFrame()
	--     -- [ADD CODE HERE]
	-- end

	-- -- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
	-- -- Remove this function if you choose not to include a way for the user to configure options for your extension
	-- -- NOTE: You'll need to implement a way to save & load changes for your extension options, similar to Tracker's Settings.ini file
	function self.configureOptions()
		if not Main.IsOnBizhawk() then return end
		Program.destroyActiveForm()
		local form = forms.newform(320, 130, "Encounter Details Settings", function() client.unpause() end)
		Utils.setFormLocation(form, 100, 50)
		local ignoreWildsOriginal = extensionSettings.ignoreWilds

		local noPiggySelection = forms.checkbox(form, "no piggy : (", 10, 30)
		local ignoreWildsSelection = forms.checkbox(form, "ignore wilds", 10, 50)

		forms.button(form, "Save", function()
			extensionSettings.ignoreWilds = forms.ischecked(ignoreWildsSelection)
			extensionSettings.noPiggy = forms.ischecked(noPiggySelection)

			TrackerAPI.saveExtensionSetting(self.name, "ignoreWilds", extensionSettings.ignoreWilds)
			TrackerAPI.saveExtensionSetting(self.name, "noPiggy", extensionSettings.noPiggy)

			if ignoreWildsOriginal ~= extensionSettings.ignoreWilds then
				SCREEN.initialize()
			end
			client.unpause()
			forms.destroy(form)
		end, 90, 70)
		forms.button(form, "Cancel", function()
			client.unpause()
			forms.destroy(form)
		end, 10, 70)
	end

	return self
end
return EncounterDetailsExtension
