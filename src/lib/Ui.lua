--[[
    Sigma Spy UI Module
    Handles all user interface elements, log display, and user interactions
    
    Optimizations:
    - Better memory management with weak tables
    - Improved log queue processing
    - Enhanced error handling
    - More efficient element creation
    - Type safety improvements
]]

export type Log = {
    Remote: Instance,
    Method: string,
    Args: {any},
    IsReceive: boolean?,
    MetaMethod: string?,
    OrignalFunc: ((...any) -> ...any)?,
    CallingScript: Instance?,
    CallingFunction: ((...any) -> ...any)?,
    ClassData: {[string]: any}?,
    ReturnValues: {any}?,
    RemoteData: {Excluded: boolean, Blocked: boolean}?,
    Id: string,
    Selectable: any?,
    HeaderData: any?,
    ValueSwaps: {[any]: any}?,
    Timestamp: number,
    IsExploit: boolean,
    Tab: any?,
    Task: string?,
    SourceScript: Instance?
}

export type CreateButtonsConfig = {
    Base: {[string]: any}?,
    Buttons: {{Text: string, Callback: (...any) -> ...any, [string]: any}},
    NoTable: boolean?
}

export type AskConfig = {
    Title: string,
    Content: {string},
    Options: {string}
}

export type DisplayTableConfig = {
    Rows: {string},
    Flags: {[string]: any}?,
    ToDisplay: {string},
    Table: {[string]: any}
}

local Ui = {
    DefaultEditorContent = [[--[[
    Sigma Spy, written by depso
    Optimized version with improved performance
    
    Discord: https://discord.gg/bkUkm2vSbv
    Github: https://github.com/depthso/Sigma-Spy
]]]],
    LogLimit = 100,
    SeasonLabels = { 
        January = "⛄ %s ⛄", 
        February = "🌨️ %s 🏂", 
        March = "🌹 %s 🌺", 
        April = "🐣 %s ✝️", 
        May = "🐝 %s 🌞", 
        June = "🌲 %s 🥕", 
        July = "🌊 %s 🌅", 
        August = "☀️ %s 🌞", 
        September = "🍁 %s 🍁", 
        October = "🎃 %s 🎃", 
        November = "🍂 %s 🍂", 
        December = "🎄 %s 🎁"
    },
    Scales = {
        ["Mobile"] = UDim2.fromOffset(480, 280),
        ["Desktop"] = UDim2.fromOffset(600, 400),
    },
    BaseConfig = {
        Theme = "SigmaSpy",
        NoScroll = true,
    },
    OptionTypes = {
        boolean = "Checkbox",
    },
    DisplayRemoteInfo = {
        "MetaMethod",
        "Method",
        "Remote",
        "CallingScript",
        "IsActor",
        "Id"
    },

    Window = nil,
    RandomSeed = Random.new(tick()),
    Logs = setmetatable({}, {__mode = "k"}),
    LogQueue = setmetatable({}, {__mode = "v"}),
    
    --// UI Elements
    RemotesList = nil,
    InfoSelector = nil,
    CodeEditor = nil,
    Console = nil,
    CanvasLayout = nil,
    FontJsonFile = nil
}

--// Compatibility
local SetClipboard = setclipboard or toclipboard or set_clipboard

--// Libraries
local ReGui

--// Modules
local Flags
local Generation
local Process
local Hook 
local Config
local Communication
local Files

--// State
local ActiveData: Log? = nil
local RemotesCount = 0
local TextFont = Font.fromEnum(Enum.Font.Code)
local FontSuccess = false
local CommChannel

--// Localized functions
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local table_clear = table.clear
local string_format = string.format
local string_sub = string.sub
local string_gsub = string.gsub
local string_lower = string.lower
local typeof = typeof
local next = next
local pcall = pcall
local wait = wait
local task_spawn = task.spawn
local task_wait = task.wait
local math_random = math.random

--[[
    Initializes the UI module
    @param Data table - Initialization data
]]
function Ui:Init(Data: {Modules: {[string]: any}})
    local Modules = Data.Modules

    --// Store module references
    Flags = Modules.Flags
    Generation = Modules.Generation
    Process = Modules.Process
    Hook = Modules.Hook
    Config = Modules.Config
    Communication = Modules.Communication
    Files = Modules.Files

    --// Load ReGui library
    local Success, Result = pcall(function()
        return loadstring(game:HttpGet('https://github.com/depthso/Dear-ReGui/raw/refs/heads/main/ReGui.lua'), "ReGui")()
    end)
    
    if Success then
        ReGui = Result
    else
        error("[UI] Failed to load ReGui: " .. tostring(Result))
    end

    --// Initialize UI
    self:LoadFont()
    self:LoadReGui()
    self:CheckScale()
end

--[[
    Sets the communication channel
    @param NewCommChannel BindableEvent - The channel
]]
function Ui:SetCommChannel(NewCommChannel: BindableEvent)
    CommChannel = NewCommChannel
end

--[[
    Checks and sets the appropriate UI scale for the device
]]
function Ui:CheckScale()
    local BaseConfig = self.BaseConfig
    local Scales = self.Scales

    local IsMobile = ReGui:IsMobileDevice()
    local Device = IsMobile and "Mobile" or "Desktop"

    BaseConfig.Size = Scales[Device]
end

--[[
    Sets clipboard content
    @param Content string - Content to copy
]]
function Ui:SetClipboard(Content: string)
    if SetClipboard then
        SetClipboard(Content)
    end
end

--[[
    Applies seasonal decoration to text
    @param Text string - The text to decorate
    @return string - Decorated text
]]
function Ui:TurnSeasonal(Text: string): string
    local SeasonLabels = self.SeasonLabels
    local Month = os.date("%B")
    local Base = SeasonLabels[Month]

    if Base then
        return string_format(Base, Text)
    end
    
    return Text
end

--[[
    Loads the custom font
]]
function Ui:LoadFont()
    local FontFile = self.FontJsonFile

    if not FontFile then
        return
    end

    --// Get FontFace AssetId
    local AssetId = Files:LoadCustomasset(FontFile)
    if not AssetId then 
        return 
    end

    --// Create custom FontFace
    local Success, NewFont = pcall(Font.new, AssetId)
    
    if Success and NewFont then
        TextFont = NewFont
        FontSuccess = true
    end
end

--[[
    Sets the font file path
    @param FontFile string - Path to font JSON
]]
function Ui:SetFontFile(FontFile: string)
    self.FontJsonFile = FontFile
end

--[[
    Shows font loading failure message
]]
function Ui:FontWasSuccessful()
    if FontSuccess then 
        return 
    end

    self:ShowModal({
        "Your executor was unable to load the custom font.",
        "Switched to default dark theme.",
        "\nTo use the ImGui theme, download the font",
        "(assets/ProggyClean.ttf) and place it in:",
        "Sigma Spy/assets"
    })
end

--[[
    Initializes ReGui with custom theme
]]
function Ui:LoadReGui()
    local ThemeConfig = Config.ThemeConfig
    ThemeConfig.TextFont = TextFont

    ReGui:DefineTheme("SigmaSpy", ThemeConfig)
end

--[[
    Creates a group of buttons
    @param Parent any - Parent element
    @param Data CreateButtonsConfig - Button configuration
]]
function Ui:CreateButtons(Parent: any, Data: CreateButtonsConfig)
    local Base = Data.Base or {}
    local Buttons = Data.Buttons
    local NoTable = Data.NoTable

    --// Create table layout if needed
    if not NoTable then
        Parent = Parent:Table({
            MaxColumns = 3
        }):NextRow()
    end

    --// Create buttons
    for _, Button in next, Buttons do
        local Container = Parent
        
        if not NoTable then
            Container = Parent:NextColumn()
        end

        ReGui:CheckConfig(Button, Base)
        Container:Button(Button)
    end
end

--[[
    Creates a window with merged configuration
    @param WindowConfig table? - Window configuration
    @return any - The window object
]]
function Ui:CreateWindow(WindowConfig: {[string]: any}?): any
    local BaseConfig = self.BaseConfig
    local MergedConfig = Process:DeepCloneTable(BaseConfig)
    Process:Merge(MergedConfig, WindowConfig)

    local Window = ReGui:Window(MergedConfig)

    --// Switch to dark theme if font failed
    if not FontSuccess then 
        Window:SetTheme("DarkTheme")
    end
    
    return Window
end

--[[
    Shows a dialog asking the user a question
    @param DialogConfig AskConfig - Dialog configuration
    @return string - The selected answer
]]
function Ui:AskUser(DialogConfig: AskConfig): string
    local Window = self.Window
    local Answered = false

    local ModalWindow = Window:PopupModal({
        Title = DialogConfig.Title
    })
    
    ModalWindow:Label({
        Text = table_concat(DialogConfig.Content, "\n"),
        TextWrapped = true
    })
    ModalWindow:Separator()

    local Row = ModalWindow:Row({
        Expanded = true
    })
    
    for _, Answer in next, DialogConfig.Options do
        Row:Button({
            Text = Answer,
            Callback = function()
                Answered = Answer
                ModalWindow:ClosePopup()
            end,
        })
    end

    repeat 
        wait() 
    until Answered
    
    return Answered
end

--[[
    Creates the main application window
    @return any - The window object
]]
function Ui:CreateMainWindow(): any
    local Window = self:CreateWindow()
    self.Window = Window

    self:FontWasSuccessful()
    self:AuraCounterService()

    --// UI visibility flag callback
    Flags:SetFlagCallback("UiVisible", function(_, Visible)
        Window:SetVisible(Visible)
    end)

    return Window
end

--[[
    Shows a modal dialog
    @param Lines table - Lines to display
]]
function Ui:ShowModal(Lines: {string})
    local Window = self.Window
    local Message = table_concat(Lines, "\n")

    local ModalWindow = Window:PopupModal({
        Title = "Sigma Spy"
    })
    
    ModalWindow:Label({
        Text = Message,
        RichText = true,
        TextWrapped = true
    })
    
    ModalWindow:Button({
        Text = "Okay",
        Callback = function()
            ModalWindow:ClosePopup()
        end,
    })
end

--[[
    Shows unsupported executor message
    @param Name string - Executor name
]]
function Ui:ShowUnsupportedExecutor(Name: string)
    self:ShowModal({
        "Sigma Spy is not supported on your executor.",
        "Recommended free option: Swift (discord.gg/getswiftgg)",
        string_format("\nYour executor: %s", Name)
    })
end

--[[
    Shows unsupported function message
    @param FuncName string - Missing function name
]]
function Ui:ShowUnsupported(FuncName: string)
    self:ShowModal({
        "Sigma Spy is not supported on your executor.",
        string_format("\nMissing function: %s", FuncName)
    })
end

--[[
    Creates option elements for a dictionary
    @param Parent any - Parent element
    @param Dict table - Dictionary to create options for
    @param Callback function? - Change callback
]]
function Ui:CreateOptionsForDict(Parent: any, Dict: {[string]: any}, Callback: (() -> ())?)
    local Options = {}

    for Key, Value in next, Dict do
        Options[Key] = {
            Value = Value,
            Label = Key,
            Callback = function(_, NewValue)
                Dict[Key] = NewValue
                
                if Callback then
                    Callback()
                end
            end
        }
    end

    self:CreateElements(Parent, Options)
end

--[[
    Checks and creates keybind layout if needed
    @param Container any - Parent container
    @param KeyCode Enum.KeyCode? - The keybind
    @param Callback function - Keybind callback
    @return any - The container
]]
function Ui:CheckKeybindLayout(Container: any, KeyCode: Enum.KeyCode?, Callback: () -> ()): any
    if not KeyCode then 
        return Container 
    end

    Container = Container:Row({
        HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
    })

    Container:Keybind({
        Label = "",
        Value = KeyCode,
        LayoutOrder = 2,
        IgnoreGameProcessed = false,
        Callback = function()
            local Enabled = Flags:GetFlagValue("KeybindsEnabled")
            if Enabled then
                Callback()
            end
        end,
    })

    return Container
end

--[[
    Creates UI elements from options dictionary
    @param Parent any - Parent element
    @param Options table - Options configuration
]]
function Ui:CreateElements(Parent: any, Options: {[string]: {Value: any, Label: string?, [string]: any}})
    local OptionTypes = self.OptionTypes
    
    local Table = Parent:Table({
        MaxColumns = 3
    }):NextRow()

    for Name, Data in next, Options do
        local Value = Data.Value
        local Type = typeof(Value)

        ReGui:CheckConfig(Data, {
            Class = OptionTypes[Type],
            Label = Name,
        })
        
        local Class = Data.Class
        assert(Class, string_format("[UI] No element type for '%s'", Type))

        local Container = Table:NextColumn()
        local Checkbox = nil

        local Keybind = Data.Keybind
        Container = self:CheckKeybindLayout(Container, Keybind, function()
            if Checkbox and Checkbox.Toggle then
                Checkbox:Toggle()
            end
        end)
        
        Checkbox = Container[Class](Container, Data)
    end
end

--[[
    Displays and updates the aura counter
]]
function Ui:DisplayAura()
    local Window = self.Window
    local Rand = self.RandomSeed

    local AURA = Rand:NextInteger(1, 9999999)
    local AURADELAY = Rand:NextInteger(1, 5)

    local Title = string_format("Sigma Spy | AURA: %d", AURA)
    local Seasonal = self:TurnSeasonal(Title)
    Window:SetTitle(Seasonal)

    wait(AURADELAY)
end

--[[
    Starts the aura counter service
]]
function Ui:AuraCounterService()
    task_spawn(function()
        while true do
            local Success, Error = pcall(function()
                self:DisplayAura()
            end)
            
            if not Success then
                warn("[UI] Aura service error:", Error)
                wait(5)
            end
        end
    end)
end

--[[
    Creates the main window content
    @param Window any - The window object
]]
function Ui:CreateWindowContent(Window: any)
    local Layout = Window:List({
        UiPadding = 2,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        VerticalFlex = Enum.UIFlexAlignment.Fill,
        FillDirection = Enum.FillDirection.Vertical,
        Fill = true
    })

    self.RemotesList = Layout:Canvas({
        Scroll = true,
        UiPadding = 5,
        AutomaticSize = Enum.AutomaticSize.None,
        FlexMode = Enum.UIFlexMode.None,
        Size = UDim2.new(0, 130, 1, 0)
    })

    local InfoSelector = Layout:TabSelector({
        NoAnimation = true,
        Size = UDim2.new(1, -130, 0.4, 0),
    })

    self.InfoSelector = InfoSelector
    self.CanvasLayout = Layout

    self:MakeEditorTab(InfoSelector)
    self:MakeOptionsTab(InfoSelector)
    
    if Config.Debug then
        self:ConsoleTab(InfoSelector)
    end
end

--[[
    Creates the console tab
    @param InfoSelector any - Tab selector
]]
function Ui:ConsoleTab(InfoSelector: any)
    local Tab = InfoSelector:CreateTab({
        Name = "Console"
    })

    local Console
    local ButtonsRow = Tab:Row()

    ButtonsRow:Button({
        Text = "Clear",
        Callback = function()
            Console:Clear()
        end
    })
    
    ButtonsRow:Button({
        Text = "Copy",
        Callback = function()
            self:SetClipboard(Console:GetValue())
        end
    })
    
    ButtonsRow:Button({
        Text = "Pause",
        Callback = function(self)
            local Enabled = not Console.Enabled
            self.Text = Enabled and "Pause" or "Paused"
            Console.Enabled = Enabled
        end,
    })
    
    ButtonsRow:Expand()

    Console = Tab:Console({
        Text = "-- Sigma Spy Console",
        ReadOnly = true,
        Border = false,
        Fill = true,
        Enabled = true,
        AutoScroll = true,
        RichText = true,
        MaxLines = 50
    })

    self.Console = Console
end

--[[
    Logs to the console
    @param ... any - Messages to log
]]
function Ui:ConsoleLog(...: string?)
    local Console = self.Console
    if Console then
        Console:AppendText(...)
    end
end

--[[
    Creates the options tab
    @param InfoSelector any - Tab selector
]]
function Ui:MakeOptionsTab(InfoSelector: any)
    local Tab = InfoSelector:CreateTab({
        Name = "Options"
    })

    Tab:Separator({Text = "Logs"})
    
    self:CreateButtons(Tab, {
        Base = {
            Size = UDim2.new(1, 0, 0, 20),
            AutomaticSize = Enum.AutomaticSize.Y,
        },
        Buttons = {
            {
                Text = "Clear logs",
                Callback = function()
                    local CurrentTab = ActiveData and ActiveData.Tab or nil

                    if CurrentTab then
                        InfoSelector:RemoveTab(CurrentTab)
                    end

                    ActiveData = nil
                    self:ClearLogs()
                end,
            },
            {
                Text = "Clear blocks",
                Callback = function()
                    Process:UpdateAllRemoteData("Blocked", false)
                end,
            },
            {
                Text = "Clear excludes",
                Callback = function()
                    Process:UpdateAllRemoteData("Excluded", false)
                end,
            },
            {
                Text = "Join Discord",
                Callback = function()
                    Process:PromptDiscordInvite("s9ngmUDWgb")
                    self:SetClipboard("https://discord.gg/s9ngmUDWgb")
                end,
            },
            {
                Text = "Copy Github",
                Callback = function()
                    self:SetClipboard("https://github.com/depthso/Sigma-Spy")
                end,
            },
            {
                Text = "Edit Spoofs",
                Callback = function()
                    self:EditFile("Return spoofs.lua", true, function(EditWindow, Content: string)
                        EditWindow:Close()
                        CommChannel:Fire("UpdateSpoofs", Content)
                    end)
                end,
            }
        }
    })

    Tab:Separator({Text = "Settings"})
    self:CreateElements(Tab, Flags:GetFlags())

    self:AddDetailsSection(Tab)
end

--[[
    Adds the details section to options
    @param OptionsTab any - The options tab
]]
function Ui:AddDetailsSection(OptionsTab: any)
    OptionsTab:Separator({Text = "Information"})
    OptionsTab:BulletText({
        Rows = {
            "Sigma Spy - Written by depso",
            "Libraries: Roblox-Parser, Dear-ReGui",
            "Optimized version with improved performance"
        }
    })
end

--[[
    Creates a callback wrapper for active data methods
    @param Name string - Method name
    @return function - The callback
]]
local function MakeActiveDataCallback(Name: string): (...any) -> ...any
    return function(...)
        if not ActiveData then 
            return 
        end
        return ActiveData[Name](ActiveData, ...)
    end
end

--[[
    Creates the editor tab
    @param InfoSelector any - Tab selector
]]
function Ui:MakeEditorTab(InfoSelector: any)
    local Default = self.DefaultEditorContent
    local SyntaxColors = Config.SyntaxColors

    local EditorTab = InfoSelector:CreateTab({
        Name = "Editor"
    })

    local CodeEditor = EditorTab:CodeEditor({
        Fill = true,
        Editable = true,
        FontSize = 13,
        Colors = SyntaxColors,
        FontFace = TextFont,
        Text = Default
    })

    local ButtonsRow = EditorTab:Row()
    
    self:CreateButtons(ButtonsRow, {
        NoTable = true,
        Buttons = {
            {
                Text = "Copy",
                Callback = function()
                    local Script = CodeEditor:GetText()
                    self:SetClipboard(Script)
                end
            },
            {
                Text = "Run",
                Callback = function()
                    local Script = CodeEditor:GetText()
                    local Func, Error = loadstring(Script, "SigmaSpy-USERSCRIPT")

                    if not Func then
                        self:ShowModal({"Error running script!\n", Error})
                        return
                    end

                    local Success, RunError = pcall(Func)
                    if not Success then
                        self:ShowModal({"Runtime error!\n", RunError})
                    end
                end
            },
            {
                Text = "Get return",
                Callback = MakeActiveDataCallback("GetReturn")
            },
            {
                Text = "Script",
                Callback = MakeActiveDataCallback("ScriptOptions")
            },
            {
                Text = "Build",
                Callback = MakeActiveDataCallback("BuildScript")
            },
            {
                Text = "Pop-out",
                Callback = function()
                    local Script = CodeEditor:GetText()
                    local Title = ActiveData and ActiveData.Task or "Sigma Spy"
                    self:MakeEditorPopoutWindow(Script, {
                        Title = Title
                    })
                end
            },
        }
    })
    
    self.CodeEditor = CodeEditor
end

--[[
    Checks if a tab should be focused
    @param Tab any - The tab to check
    @return boolean - Whether to focus
]]
function Ui:ShouldFocus(Tab: any): boolean
    local InfoSelector = self.InfoSelector
    local ActiveTab = InfoSelector.ActiveTab

    if not ActiveTab then
        return true
    end

    return InfoSelector:CompareTabs(ActiveTab, Tab)
end

--[[
    Creates an editor popout window
    @param Content string? - Initial content
    @param WindowConfig table - Window configuration
    @return any - The code editor
    @return any - The window
]]
function Ui:MakeEditorPopoutWindow(Content: string?, WindowConfig: {Title: string, Buttons: {{Text: string, Callback: () -> ()}}?}): (any, any)
    local Window = self:CreateWindow(WindowConfig)
    local Buttons = WindowConfig.Buttons or {}
    local Colors = Config.SyntaxColors

    local CodeEditor = Window:CodeEditor({
        Text = Content or "",
        Editable = true,
        Fill = true,
        FontSize = 13,
        Colors = Colors,
        FontFace = TextFont
    })

    table_insert(Buttons, {
        Text = "Copy",
        Callback = function()
            local Script = CodeEditor:GetText()
            self:SetClipboard(Script)
        end
    })

    local ButtonsRow = Window:Row()
    self:CreateButtons(ButtonsRow, {
        NoTable = true,
        Buttons = Buttons
    })

    Window:Center()
    return CodeEditor, Window
end

--[[
    Opens a file for editing
    @param FilePath string - File path
    @param InFolder boolean - Whether path is relative to folder
    @param OnSaveFunc function? - Save callback
]]
function Ui:EditFile(FilePath: string, InFolder: boolean, OnSaveFunc: ((any, string) -> ())?)
    local Folder = Files.FolderName
    local CodeEditor, EditWindow

    if InFolder then
        FilePath = string_format("%s/%s", Folder, FilePath)
    end

    local Success, Content = pcall(readfile, FilePath)
    
    if not Success then
        self:ShowModal({"Failed to read file:", FilePath})
        return
    end
    
    Content = string_gsub(Content, "\r\n", "\n")
    
    local Buttons = {
        {
            Text = "Save",
            Callback = function()
                local Script = CodeEditor:GetText()
                local LoadSuccess, Error = loadstring(Script, "SigmaSpy-Editor")

                if not LoadSuccess then
                    self:ShowModal({"Error saving file!\n", Error})
                    return
                end
                
                local WriteSuccess, WriteError = pcall(writefile, FilePath, Script)
                
                if not WriteSuccess then
                    self:ShowModal({"Failed to save file!\n", WriteError})
                    return
                end

                if OnSaveFunc then
                    OnSaveFunc(EditWindow, Script)
                end
            end
        }
    }

    CodeEditor, EditWindow = self:MakeEditorPopoutWindow(Content, {
        Title = string_format("Editing: %s", FilePath),
        Buttons = Buttons
    })
end

--[[
    Creates a button menu popup
    @param Button Instance - The button element
    @param Unpack table - Arguments to unpack
    @param Options table - Menu options
]]
function Ui:MakeButtonMenu(Button: Instance, Unpack: {any}, Options: {[string]: (...any) -> ()})
    local Window = self.Window
    
    local Popup = Window:PopupCanvas({
        RelativeTo = Button,
        MaxSizeX = 500,
    })

    for Name, Func in next, Options do
        Popup:Selectable({
            Text = Name,
            Callback = function()
                Func(Process:Unpack(Unpack))
            end,
        })
    end
end

--[[
    Removes the previous active tab
    @return boolean - Whether the tab was focused
]]
function Ui:RemovePreviousTab(): boolean
    if not ActiveData then 
        return false 
    end

    local InfoSelector = self.InfoSelector
    local PreviousTab = ActiveData.Tab
    local PreviousSelectable = ActiveData.Selectable

    local TabFocused = self:ShouldFocus(PreviousTab)
    InfoSelector:RemoveTab(PreviousTab)
    
    if PreviousSelectable and PreviousSelectable.SetSelected then
        PreviousSelectable:SetSelected(false)
    end

    return TabFocused
end

--[[
    Creates table headers
    @param Table any - Table element
    @param Rows table - Header names
]]
function Ui:MakeTableHeaders(Table: any, Rows: {string})
    local HeaderRow = Table:HeaderRow()
    
    for _, Category in next, Rows do
        local Column = HeaderRow:NextColumn()
        Column:Label({Text = Category})
    end
end

--[[
    Decompiles a script and displays in editor
    @param Editor any - Code editor
    @param Script Instance - Script to decompile
]]
function Ui:Decompile(Editor: any, Script: Instance)
    local Header = "-- Decompiled with Sigma Spy"
    Editor:SetText("-- Decompiling...")

    local Decompiled, IsError = Process:Decompile(Script)

    if not IsError then
        Decompiled = string_format("%s\n%s", Header, Decompiled)
    end

    Editor:SetText(Decompiled)
end

--[[
    Displays a table in the UI
    @param Parent any - Parent element
    @param TableConfig DisplayTableConfig - Table configuration
    @return any - The table element
]]
function Ui:DisplayTable(Parent: any, TableConfig: DisplayTableConfig): any
    local Rows = TableConfig.Rows
    local TableFlags = TableConfig.Flags
    local DataTable = TableConfig.Table
    local ToDisplay = TableConfig.ToDisplay

    TableFlags.MaxColumns = #Rows

    local Table = Parent:Table(TableFlags)

    self:MakeTableHeaders(Table, Rows)

    for _, Name in next, ToDisplay do
        local Row = Table:Row()
        
        for _, Category in next, Rows do
            local Column = Row:NextColumn()
            
            local Value = Category == "Name" and Name or DataTable[Name]
            if not Value then 
                continue 
            end

            local String = self:FilterName(tostring(Value), 150)
            Column:Label({Text = String})
        end
    end

    return Table
end

--[[
    Sets the focused remote and creates its tab
    @param Data Log - The log data
]]
function Ui:SetFocusedRemote(Data: Log)
    local Remote = Data.Remote
    local Method = Data.Method
    local IsReceive = Data.IsReceive
    local Script = Data.CallingScript
    local ClassData = Data.ClassData
    local HeaderData = Data.HeaderData
    local ValueSwaps = Data.ValueSwaps
    local Args = Data.Args
    local Id = Data.Id

    local TableArgs = Flags:GetFlagValue("TableArgs")
    local NoVariables = Flags:GetFlagValue("NoVariables")

    local RemoteData = Process:GetRemoteData(Id)
    local IsRemoteFunction = ClassData and ClassData.IsRemoteFunction
    local RemoteName = self:FilterName(tostring(Remote), 50)

    local CodeEditor = self.CodeEditor
    local ToDisplay = self.DisplayRemoteInfo
    local InfoSelector = self.InfoSelector

    local TabFocused = self:RemovePreviousTab()
    local Tab = InfoSelector:CreateTab({
        Name = self:FilterName(string_format("Remote: %s", RemoteName), 50),
        Focused = TabFocused
    })

    local Module = Generation:NewParser({
        NoVariables = NoVariables
    })
    local Parser = Module.Parser
    local Formatter = Module.Formatter
    
    if ValueSwaps then
        Formatter:SetValueSwaps(ValueSwaps)
    end

    ActiveData = Data
    Data.Tab = Tab
    
    if Data.Selectable and Data.Selectable.SetSelected then
        Data.Selectable:SetSelected(true)
    end

    local function SetIDEText(Content: string, TaskName: string?)
        Data.Task = TaskName or "Sigma Spy"
        CodeEditor:SetText(Content)
    end
    
    local function DataConnection(Name: string, ...: any): () -> ()
        local ConnectionArgs = {...}
        return function()
            return Data[Name](Data, Process:Unpack(ConnectionArgs))
        end
    end
    
    local function ScriptCheck(CheckScript: Instance?, NoMissingCheck: boolean?): boolean?
        if IsReceive then 
            Ui:ShowModal({
                "Receives do not have a script because they are Connections."
            })
            return nil
        end

        if not CheckScript and not NoMissingCheck then 
            Ui:ShowModal({"The script has been destroyed by the game."})
            return nil
        end

        return true
    end

    --// Data methods
    function Data:ScriptOptions(Button: GuiButton)
        Ui:MakeButtonMenu(Button, {self}, {
            ["Caller Info"] = DataConnection("GenerateInfo"),
            ["Decompile"] = DataConnection("Decompile", "SourceScript"),
            ["Decompile Calling"] = DataConnection("Decompile", "CallingScript"),
            ["Repeat Call"] = DataConnection("RepeatCall"),
            ["Save Bytecode"] = DataConnection("SaveBytecode"),
        })
    end
    
    function Data:BuildScript(Button: GuiButton)
        Ui:MakeButtonMenu(Button, {self}, {
            ["Save"] = DataConnection("SaveScript"),
            ["Call Remote"] = DataConnection("MakeScript", "Remote"),
            ["Block Remote"] = DataConnection("MakeScript", "Block"),
            ["Repeat For"] = DataConnection("MakeScript", "Repeat"),
            ["Spam Remote"] = DataConnection("MakeScript", "Spam")
        })
    end
    
    function Data:SaveScript()
        local FilePath = Generation:TimeStampFile(self.Task or "script.lua")
        
        local Success, Error = pcall(writefile, FilePath, CodeEditor:GetText())
        
        if Success then
            Ui:ShowModal({"Saved script to", FilePath})
        else
            Ui:ShowModal({"Failed to save:", Error})
        end
    end
    
    function Data:SaveBytecode()
        if not ScriptCheck(Script, true) then 
            return 
        end

        local Success, Bytecode = pcall(getscriptbytecode, Script)
        
        if not Success then
            Ui:ShowModal({"Failed to get script bytecode."})
            return
        end

        local PathBase = string_format("%s %%s.txt", tostring(Script))
        local FilePath = Generation:TimeStampFile(PathBase)
        
        local WriteSuccess, Error = pcall(writefile, FilePath, Bytecode)
        
        if WriteSuccess then
            Ui:ShowModal({"Saved bytecode to", FilePath})
        else
            Ui:ShowModal({"Failed to save:", Error})
        end
    end
    
    function Data:MakeScript(ScriptType: string)
        local GeneratedScript = Generation:RemoteScript(Module, self, ScriptType)
        SetIDEText(GeneratedScript, string_format("Editing: %s.lua", RemoteName))
    end
    
    function Data:RepeatCall()
        local Signal = Hook:Index(Remote, Method)

        if IsReceive then
            firesignal(Signal, Process:Unpack(Args))
        else
            Signal(Remote, Process:Unpack(Args))
        end
    end
    
    function Data:GetReturn()
        local ReturnValues = self.ReturnValues

        if not IsRemoteFunction then
            Ui:ShowModal({"This Remote is not a RemoteFunction."})
            return
        end
        
        if not ReturnValues then
            Ui:ShowModal({"No return values recorded."})
            return
        end

        local GeneratedScript = Generation:TableScript(Module, ReturnValues)
        SetIDEText(GeneratedScript, string_format("Return Values for: %s", RemoteName))
    end
    
    function Data:GenerateInfo()
        if not ScriptCheck(nil, true) then 
            return 
        end

        local GeneratedScript = Generation:AdvancedInfo(Module, self)
        SetIDEText(GeneratedScript, string_format("Advanced Info for: %s", RemoteName))
    end
    
    function Data:Decompile(WhichScript: string)
        local DecompilePopout = Flags:GetFlagValue("DecompilePopout")
        local ToDecompile = self[WhichScript]

        if not ScriptCheck(ToDecompile, true) then 
            return 
        end
        
        local TaskName = Ui:FilterName(string_format("Viewing: %s.lua", tostring(ToDecompile)), 200)
        
        local Editor = CodeEditor
        
        if DecompilePopout then
            Editor = Ui:MakeEditorPopoutWindow("", {
                Title = TaskName
            })
        end

        Ui:Decompile(Editor, ToDecompile)
    end
    
    --// Remote options
    self:CreateOptionsForDict(Tab, RemoteData, function()
        Process:UpdateRemoteData(Id, RemoteData)
    end)

    --// Instance options buttons
    self:CreateButtons(Tab, {
        Base = {
            Size = UDim2.new(1, 0, 0, 20),
            AutomaticSize = Enum.AutomaticSize.Y,
        },
        Buttons = {
            {
                Text = "Copy script path",
                Callback = function()
                    if Script then
                        self:SetClipboard(Parser:MakePathString({
                            Object = Script,
                            NoVariables = true
                        }))
                    end
                end,
            },
            {
                Text = "Copy remote path",
                Callback = function()
                    self:SetClipboard(Parser:MakePathString({
                        Object = Remote,
                        NoVariables = true
                    }))
                end,
            },
            {
                Text = "Remove log",
                Callback = function()
                    InfoSelector:RemoveTab(Tab)
                    
                    if Data.Selectable and Data.Selectable.Remove then
                        Data.Selectable:Remove()
                    end
                    
                    if HeaderData and HeaderData.Remove then
                        HeaderData:Remove()
                    end
                    
                    ActiveData = nil
                end,
            },
            {
                Text = "Dump logs",
                Callback = function()
                    if HeaderData and HeaderData.Entries then
                        local Logs = HeaderData.Entries
                        local FilePath = Generation:DumpLogs(Logs)
                        self:ShowModal({"Saved dump to", FilePath})
                    end
                end,
            },
            {
                Text = "View Connections",
                Callback = function()
                    if ClassData and ClassData.Receive then
                        local ReceiveMethod = ClassData.Receive[1]
                        local Signal = Remote[ReceiveMethod]
                        self:ViewConnections(RemoteName, Signal)
                    end
                end,
            }
        }
    })

    --// Remote information table
    self:DisplayTable(Tab, {
        Rows = {"Name", "Value"},
        Table = Data,
        ToDisplay = ToDisplay,
        Flags = {
            Border = true,
            RowBackground = true,
            MaxColumns = 2
        }
    })
    
    --// Arguments table script
    if TableArgs then
        local Parsed = Generation:TableScript(Module, Args)
        SetIDEText(Parsed, string_format("Arguments for %s", RemoteName))
        return
    end

    --// Remote call script
    Data:MakeScript("Remote")
end

--[[
    Views connections for a signal
    @param RemoteName string - The remote name
    @param Signal RBXScriptSignal - The signal
]]
function Ui:ViewConnections(RemoteName: string, Signal: RBXScriptSignal)
    local Window = self:CreateWindow({
        Title = string_format("Connections for: %s", RemoteName),
        Size = UDim2.fromOffset(450, 250)
    })

    local ToDisplay = {
        "Enabled",
        "LuaConnection",
        "Script"
    }

    local Connections = Process:FilterConnections(Signal)

    local Table = Window:Table({
        Border = true,
        RowBackground = true,
        MaxColumns = 3
    })

    local ButtonsForValues = {
        ["Script"] = function(Row, Value)
            Row:Button({
                Text = "Decompile",
                Callback = function()
                    local TaskName = self:FilterName(string_format("Viewing: %s.lua", tostring(Value)), 200)
                    local Editor = self:MakeEditorPopoutWindow(nil, {
                        Title = TaskName
                    })
                    self:Decompile(Editor, Value)
                end
            })
        end,
        ["Enabled"] = function(Row, Enabled, Connection)
            Row:Button({
                Text = Enabled and "Disable" or "Enable",
                Callback = function(ButtonSelf)
                    Enabled = not Enabled
                    ButtonSelf.Text = Enabled and "Disable" or "Enable"

                    if Enabled then
                        Connection:Enable()
                    else
                        Connection:Disable()
                    end
                end
            })
        end
    }

    self:MakeTableHeaders(Table, ToDisplay)

    for _, Connection in next, Connections do
        local Row = Table:Row()

        for _, Property in next, ToDisplay do
            local Column = Row:NextColumn()
            local ColumnRow = Column:Row()

            local Value = Connection[Property]
            local Callback = ButtonsForValues[Property]

            ColumnRow:Label({Text = tostring(Value)})

            if Callback then
                Callback(ColumnRow, Value, Connection)
            end
        end
    end

    Window:Center()
end

--[[
    Gets or creates a remote header for stacking logs
    @param Data Log - The log data
    @return table - The header data
]]
function Ui:GetRemoteHeader(Data: Log): {LogCount: number, Data: Log, Entries: {Log}, TreeNode: any?, Remove: () -> (), LogAdded: (self: any, Data: Log) -> any, CheckLimit: (self: any) -> ()}
    local LogLimit = self.LogLimit
    local Logs = self.Logs
    local RemotesList = self.RemotesList

    local Id = Data.Id
    local Remote = Data.Remote
    local RemoteName = self:FilterName(tostring(Remote), 30)

    local NoTreeNodes = Flags:GetFlagValue("NoTreeNodes")

    local Existing = Logs[Id]
    if Existing then 
        return Existing 
    end

    local HeaderData = {    
        LogCount = 0,
        Data = Data,
        Entries = {}
    }

    RemotesCount = RemotesCount + 1

    if not NoTreeNodes then
        HeaderData.TreeNode = RemotesList:TreeNode({
            LayoutOrder = -1 * RemotesCount,
            Title = RemoteName
        })
    end

    function HeaderData:CheckLimit()
        local Entries = self.Entries
        
        if #Entries < LogLimit then 
            return 
        end
            
        local OldLog = table_remove(Entries, 1)
        
        if OldLog and OldLog.Selectable and OldLog.Selectable.Remove then
            OldLog.Selectable:Remove()
        end
    end

    function HeaderData:LogAdded(LogData: Log)
        self.LogCount = self.LogCount + 1
        self:CheckLimit()

        local Entries = self.Entries
        table_insert(Entries, LogData)
        
        return self
    end

    function HeaderData:Remove()
        local TreeNode = self.TreeNode
        
        if TreeNode and TreeNode.Remove then
            TreeNode:Remove()
        end

        Logs[Id] = nil
        table_clear(HeaderData)
    end

    Logs[Id] = HeaderData
    return HeaderData
end

--[[
    Clears all logs
]]
function Ui:ClearLogs()
    local Logs = self.Logs
    local RemotesList = self.RemotesList

    RemotesCount = 0
    RemotesList:ClearChildElements()

    table_clear(Logs)
end

--[[
    Queues a log for processing
    @param Data table - The log data
]]
function Ui:QueueLog(Data: {Args: {any}, ReturnValues: {any}?, [string]: any})
    local LogQueue = self.LogQueue
    
    Process:Merge(Data, {
        Args = Process:DeepCloneTable(Data.Args),
    })

    if Data.ReturnValues then
        Data.ReturnValues = Process:DeepCloneTable(Data.ReturnValues)
    end
    
    table_insert(LogQueue, Data)
end

--[[
    Processes the log queue
]]
function Ui:ProcessLogQueue()
    local Queue = self.LogQueue
    
    if #Queue <= 0 then 
        return 
    end

    --// Process queue in batches
    local BatchSize = 10
    local Processed = 0
    
    while #Queue > 0 and Processed < BatchSize do
        local Data = table_remove(Queue, 1)
        
        if Data then
            local Success, Error = pcall(function()
                self:CreateLog(Data)
            end)
            
            if not Success then
                warn("[UI] Log creation error:", Error)
            end
        end
        
        Processed = Processed + 1
    end
end

--[[
    Starts the log processing service
]]
function Ui:BeginLogService()
    coroutine.wrap(function()
        while true do
            self:ProcessLogQueue()
            task_wait()
        end
    end)()
end

--[[
    Filters and cleans a name string
    @param Name string - The name to filter
    @param CharacterLimit number? - Maximum characters
    @return string - The filtered name
]]
function Ui:FilterName(Name: string, CharacterLimit: number?): string
    local Trimmed = string_sub(Name, 1, CharacterLimit or 20)
    local Filtered = string_gsub(Trimmed, "[\n\r]", "")
    Filtered = Generation:MakePrintable(Filtered)

    return Filtered
end

--[[
    Creates a log entry in the UI
    @param Data Log - The log data
]]
function Ui:CreateLog(Data: Log)
    local Remote = Data.Remote
    local Method = Data.Method
    local Args = Data.Args
    local IsReceive = Data.IsReceive
    local Id = Data.Id
    local Timestamp = Data.Timestamp
    local IsExploit = Data.IsExploit
    
    local IsNilParent = Hook:Index(Remote, "Parent") == nil
    local RemoteData = Process:GetRemoteData(Id)

    --// Check pause flag
    local Paused = Flags:GetFlagValue("Paused")
    if Paused then 
        return 
    end

    --// Check exploit logging
    local LogExploit = Flags:GetFlagValue("LogExploit")
    if not LogExploit and IsExploit then 
        return 
    end

    --// Check nil parent ignore
    local IgnoreNil = Flags:GetFlagValue("IgnoreNil")
    if IgnoreNil and IsNilParent then 
        return 
    end

    --// Check receive logging
    local LogRecives = Flags:GetFlagValue("LogRecives")
    if not LogRecives and IsReceive then 
        return 
    end

    local SelectNewest = Flags:GetFlagValue("SelectNewest")
    local NoTreeNodes = Flags:GetFlagValue("NoTreeNodes")

    --// Check exclusion
    if RemoteData.Excluded then 
        return 
    end

    --// Deserialize arguments
    Args = Communication:DeserializeTable(Args)

    --// Deep clone data
    local ClonedArgs = Process:DeepCloneTable(Args)
    Data.Args = ClonedArgs
    Data.ValueSwaps = Generation:MakeValueSwapsTable()

    --// Generate log title
    local Color = Config.MethodColors[string_lower(Method)]
    local Text = NoTreeNodes and string_format("%s | %s", tostring(Remote), Method) or Method

    --// Find string for name
    local FindString = Flags:GetFlagValue("FindStringForName")
    
    if FindString then
        for _, Arg in next, ClonedArgs do
            if typeof(Arg) == "string" then
                local Filtered = self:FilterName(Arg)
                Text = string_format("%s | %s", Filtered, Text)
                break
            end
        end
    end

    --// Get or create header
    local Header = self:GetRemoteHeader(Data)
    local RemotesList = self.RemotesList

    local LogCount = Header.LogCount
    local TreeNode = Header.TreeNode 
    local Parent = TreeNode or RemotesList

    if NoTreeNodes then
        RemotesCount = RemotesCount + 1
        LogCount = RemotesCount
    end

    --// Create selectable element
    Data.HeaderData = Header
    Data.Selectable = Parent:Selectable({
        Text = Text,
        LayoutOrder = -1 * LogCount,
        TextColor3 = Color,
        TextXAlignment = Enum.TextXAlignment.Left,
        Callback = function()
            self:SetFocusedRemote(Data)
        end,
    })

    Header:LogAdded(Data)

    --// Auto-select newest
    local GroupSelected = ActiveData and ActiveData.HeaderData == Header
    if SelectNewest and GroupSelected then
        self:SetFocusedRemote(Data)
    end
end

return Ui
