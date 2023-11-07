local function EncounterDetailsExtension()
    -- Define descriptive attributes of the custom extension that are displayed on the Tracker settings
    local self = {}
    self.version = "1.0"
    self.name = "EncounterDetails"
    self.author = "jwunderl"
    self.description = "Track extra details on every encounter you've faced."
    self.github = "jwunderl/EncounterDetails-IronmonExtension"
    self.url = string.format("https://github.com/%s", self.github or "")

    self.encounterData = nil

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

    local function getPokemonEncounterData(pokemonID)
        return Tracker.getEncounterData(SCREEN.currentPokemonID)
        -- return self.encounterData[pokemonID]
    end

    local function trackPokemonEncounter(pokemon)
    end

    -- TODO: probably should close this screen automatically when opposing pokemon changes
    --		or encounter ends. Maybe this goes into InfoScreen to handle that?
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
            }
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
            box = {Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 87, Constants.SCREEN.MARGIN + 137, 10, 10},
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
                button.boxColors = {SCREEN.Colors.border, SCREEN.Colors.boxFill}
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
        function padEnd(inp, targetLength, char)
            if char == nil then
                char = " "
            end
            -- todo: padding with " " doesn't line up as space a little thinner than others;
            -- does this need to be manually rendered instead of aligned?
            return inp .. string.rep(char, targetLength - (#inp))
        end

        local startX = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN
        local startY = Constants.SCREEN.MARGIN + OFFSET_FOR_NAME
        local tabPadding = 5

        -- TABS
        for _, tab in ipairs(Utils.getSortedList(SCREEN.Tabs)) do
            local tabText = tab.tabKey
            -- local tabText = Resources.PreviousEncountersScreen[tab.resourceKey]
            local tabWidth = (tabPadding * 2) + Utils.calcWordPixelLength(tabText)
            SCREEN.Buttons["Tab" .. tab.tabKey] = {
                type = Constants.ButtonTypes.NO_BORDER,
                getText = function(self)
                    return tabText
                end,
                tab = SCREEN.Tabs[tab.tabKey],
                isSelected = false,
                box = {startX, startY, tabWidth, TAB_HEIGHT},
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

        local tabContents = {}

        local encounters = getPokemonEncounterData(SCREEN.currentPokemonID)
        if tab == SCREEN.Tabs.Wild then
            for _, wildEncounter in ipairs(encounters.wild) do
                table.insert(tabContents, wildEncounter)
            end
        elseif tab == SCREEN.Tabs.Trainer then
            for _, trainerEncounter in ipairs(encounters.trainer) do
                table.insert(tabContents, trainerEncounter)
            end
        elseif tab == SCREEN.Tabs.All then
            for bagKey, itemGroup in pairs(encounters) do
                if type(itemGroup) == "table" then
                    for _, encounter in pairs(itemGroup) do
                        table.insert(tabContents, encounter)
                    end
                end
            end
        end

        local trackerCenterX = Constants.SCREEN.WIDTH + (Constants.SCREEN.RIGHT_GAP / 2)
        local encounterButtonWidth = 100
        for _, encounter in ipairs(tabContents) do
            -- todo remove or "" when ready, don't need to nullsafe any values that will always be there
            local levelText = "Lv." .. (encounter.level or "")
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

    function PreviousEncountersScreen.changeTab(tab)
        SCREEN.currentTab = tab
        SCREEN.buildPagedButtons(tab)
        SCREEN.refreshButtons()
        Program.redraw(true)
    end

    function PreviousEncountersScreen.changePokemonID(pokemonID)
        SCREEN.currentPokemonID = pokemonID
        SCREEN.buildPagedButtons(tab)
        SCREEN.refreshButtons()
        Program.redraw(true)
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

    --0 = transparent
    --1 = black
    --2 = pale pink
    local heartPixelImage = {
        -- 15x16
        {0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0},
        {1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1},
        {1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1},
        {0, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 0},
        {0, 1, 2, 1, 1, 2, 2, 2, 2, 2, 1, 1, 2, 1, 0},
        {1, 2, 2, 1, 1, 2, 2, 2, 2, 2, 1, 1, 2, 2, 1},
        {1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 2, 1},
        {1, 2, 2, 2, 1, 2, 2, 2, 2, 2, 1, 2, 2, 2, 1},
        {1, 2, 2, 2, 1, 2, 1, 2, 1, 2, 1, 2, 2, 2, 1},
        {1, 2, 2, 2, 1, 2, 2, 2, 2, 2, 1, 2, 2, 2, 1},
        {0, 1, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 1, 0},
        {0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 0},
        {0, 0, 1, 2, 1, 2, 2, 2, 2, 2, 1, 2, 1, 0, 0},
        {0, 0, 1, 2, 2, 1, 1, 1, 1, 1, 2, 2, 1, 0, 0},
        {0, 0, 1, 2, 2, 1, 0, 0, 0, 1, 2, 2, 1, 0, 0},
        {0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0}
    }

    local trackerBtnBox = {
        Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 84, -- x
        58, -- y
        15, -- w
        16 -- h
    }

    local trackerBtn = {
        type = Constants.ButtonTypes.PIXELIMAGE,
        textColor = "Default text",
        box = trackerBtnBox,
        isVisible = function()
            local viewedPokemon = Battle.getViewedPokemon(true) or {}
            local opponentInBattle =
                Program.currentScreen == TrackerScreen and Battle.inActiveBattle() and not Battle.isViewingOwn and
                PokemonData.isValid(viewedPokemon.pokemonID)
            return opponentInBattle
            -- local allowedLegacy = (Program.Screens ~= nil and Program.currentScreen == Program.Screens.TRACKER)
            -- local allowedCurrent = (Program.currentScreen == TrackerScreen)
            -- return Tracker.Data.isViewingOwn and (allowedLegacy or allowedCurrent) and PokemonData.isValid(viewedPokemon.pokemonID)
        end,
        draw = function()
            local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])

            local colors = {
                0xFF000000, -- black
                0xFFEAC3CE -- pale pink
            }

            Drawing.drawImageAsPixels(heartPixelImage, trackerBtnBox[1], trackerBtnBox[2], colors, shadowcolor)
        end,
        onClick = function()
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
            PreviousEncountersScreen.changeTab(defaultTab)
            PreviousEncountersScreen.changePokemonID(pokemon.pokemonID)
            Program.changeScreenView(PreviousEncountersScreen)
        end
    }

    --------------------------------------
    -- INTERNAL TRACKER FUNCTIONS BELOW
    -- Add any number of these below functions to your extension that you want to use.
    -- If you don't need a function, don't add it at all; leave ommitted for faster code execution.
    --------------------------------------

    -- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
    -- Remove this function if you choose not to include a way for the user to configure options for your extension
    -- NOTE: You'll need to implement a way to save & load changes for your extension options, similar to Tracker's Settings.ini file
    function self.configureOptions()
        -- [ADD CODE HERE]
    end

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

    -- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
    -- Remove this function if you choose not to include a way for the user to configure options for your extension
    -- NOTE: You'll need to implement a way to save & load changes for your extension options, similar to Tracker's Settings.ini file
    function self.configureOptions()
        -- [ADD CODE HERE]
    end

    -- Executed only once: When the extension is enabled by the user, and/or when the Tracker first starts up, after it loads all other required files and code
    function self.startup()
        if not Main.IsOnBizhawk() then
            return
        end
        PreviousEncountersScreen.initialize()
        TrackerScreen.Buttons.EncounterDetails = trackerBtn
        -- [ADD CODE HERE]
    end

    -- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
    function self.unload()
        if not Main.IsOnBizhawk() then
            return
        end
        TrackerScreen.Buttons.EncounterDetails = nil
    end

    -- Executed once every 30 frames or after any redraw event is scheduled (i.e. most button presses)
    function self.afterRedraw()
        if not Main.IsOnBizhawk() then
            return
        end
        if TrackerScreen.Buttons.EncounterDetails ~= nil and TrackerScreen.Buttons.EncounterDetails:isVisible() then
            local shadowcolor = Utils.calcShadowColor(Theme.COLORS["Upper box background"])
            Drawing.drawButton(TrackerScreen.Buttons.EncounterDetails, shadowcolor)
        end
    end

    -- Executed once every 30 frames, after most data from game memory is read in
    function self.afterProgramDataUpdate()
        -- [ADD CODE HERE]
    end

    -- Executed once every 30 frames, after any battle related data from game memory is read in
    function self.afterBattleDataUpdate()
        -- [ADD CODE HERE]
    end

    -- Executed before a button's onClick() is processed, and only once per click per button
    -- Param: button: the button object being clicked
    function self.onButtonClicked(button)
        -- [ADD CODE HERE]
    end

    -- Executed after a new battle begins (wild or trainer), and only once per battle
    function self.afterBattleBegins()
        -- [ADD CODE HERE]
    end

    -- Executed after a battle ends, and only once per battle
    function self.afterBattleEnds()
        -- [ADD CODE HERE]
    end

    -- [Bizhawk only] Executed each frame (60 frames per second)
    -- CAUTION: Avoid unnecessary calculations here, as this can easily affect performance.
    function self.inputCheckBizhawk()
        -- Uncomment to use, otherwise leave commented out
        -- local mouseInput = input.getmouse() -- lowercase 'input' pulls directly from Bizhawk API
        -- local joypadButtons = Input.getJoypadInputFormatted() -- uppercase 'Input' uses Tracker formatted input
        -- [ADD CODE HERE]
    end

    -- [MGBA only] Executed each frame (60 frames per second)
    -- CAUTION: Avoid unnecessary calculations here, as this can easily affect performance.
    function self.inputCheckMGBA()
        -- Uncomment to use, otherwise leave commented out
        -- local joypadButtons = Input.getJoypadInputFormatted()
        -- [ADD CODE HERE]
    end

    -- Executed each frame of the game loop, after most data from game memory is read in but before any natural redraw events occur
    -- CAUTION: Avoid code here if possible, as this can easily affect performance. Most Tracker updates occur at 30-frame intervals, some at 10-frame.
    function self.afterEachFrame()
        -- [ADD CODE HERE]
    end

    return self
end
return EncounterDetailsExtension
