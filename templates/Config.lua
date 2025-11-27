--[[
    Sigma Spy Configuration Module
    Optimized and improved version with better organization and type safety
]]

export type SyntaxColors = {
    Text: Color3,
    Background: Color3,
    Selection: Color3,
    SelectionBack: Color3,
    Operator: Color3,
    Number: Color3,
    String: Color3,
    Comment: Color3,
    Keyword: Color3,
    BuiltIn: Color3,
    LocalMethod: Color3,
    LocalProperty: Color3,
    Nil: Color3,
    Bool: Color3,
    Function: Color3,
    Local: Color3,
    Self: Color3,
    FunctionName: Color3,
    Bracket: Color3
}

export type MethodColors = {
    [string]: Color3
}

export type ThemeConfig = {
    BaseTheme: string,
    TextSize: number,
    TextFont: Font?
}

export type ConfigType = {
    ForceUseCustomComm: boolean,
    ReplaceMetaCallFunc: boolean,
    NoReceiveHooking: boolean,
    BlackListedServices: {string},
    ForceKonstantDecompiler: boolean,
    VariableNames: {string},
    SyntaxColors: SyntaxColors,
    MethodColors: MethodColors,
    ThemeConfig: ThemeConfig,
    Debug: boolean?
}

local Config: ConfigType = {
    --// Hooking Configuration
    ForceUseCustomComm = false,
    ReplaceMetaCallFunc = false,
    NoReceiveHooking = false,
    NoFunctionPatching = false,
    BlackListedServices = {
        "RobloxReplicatedStorage"
    },

    --// Processing Configuration
    ForceKonstantDecompiler = false,

    --// Debug Mode
    Debug = false,

    --// Editor Variable Names (%.d will be replaced with a number)
    VariableNames = {
        "Argument%.d",
        "Variable%.d", 
        "Value%.d", 
        "Data%.d", 
        "Param%.d",
        "Input%.d",
        "Element%.d",
        "Item%.d",
    },

    --// Syntax Highlighting Colors (VSCode-inspired dark theme)
    SyntaxColors = {
        Text = Color3.fromRGB(212, 212, 212),
        Background = Color3.fromRGB(30, 30, 30),
        Selection = Color3.fromRGB(255, 255, 255),
        SelectionBack = Color3.fromRGB(38, 79, 120),
        Operator = Color3.fromRGB(212, 212, 212),
        Number = Color3.fromRGB(181, 206, 168),
        String = Color3.fromRGB(206, 145, 120),
        Comment = Color3.fromRGB(106, 153, 85),
        Keyword = Color3.fromRGB(86, 156, 214),
        BuiltIn = Color3.fromRGB(220, 220, 170),
        LocalMethod = Color3.fromRGB(220, 220, 170),
        LocalProperty = Color3.fromRGB(156, 220, 254),
        Nil = Color3.fromRGB(86, 156, 214),
        Bool = Color3.fromRGB(86, 156, 214),
        Function = Color3.fromRGB(197, 134, 192),
        Local = Color3.fromRGB(86, 156, 214),
        Self = Color3.fromRGB(86, 156, 214),
        FunctionName = Color3.fromRGB(220, 220, 170),
        Bracket = Color3.fromRGB(212, 212, 212)
    },

    --// UI Method Colors for Remote Types
    MethodColors = {
        ["fireserver"] = Color3.fromRGB(242, 200, 59),
        ["invokeserver"] = Color3.fromRGB(129, 116, 255),
        ["onclientevent"] = Color3.fromRGB(77, 245, 105),
        ["onclientinvoke"] = Color3.fromRGB(77, 178, 245),
        ["event"] = Color3.fromRGB(77, 245, 181),
        ["invoke"] = Color3.fromRGB(255, 107, 107),
        ["oninvoke"] = Color3.fromRGB(255, 107, 209),
        ["fire"] = Color3.fromRGB(255, 171, 107),
    },

    --// Theme Configuration
    ThemeConfig = {
        BaseTheme = "ImGui",
        TextSize = 13
    }
}

return Config
