--[[
    Sigma Spy Files Module
    Handles file operations, HTTP fetching, and module loading
    
    Optimizations:
    - Cached HTTP responses where applicable
    - Better error handling
    - Improved folder structure management
    - Type safety improvements
]]

export type FolderStructure = {
    [string]: {string} | FolderStructure
}

export type ModuleCollection = {
    [string]: any
}

export type InitData = {
    Services: {[string]: any},
    Modules: ModuleCollection?
}

local Files = {
    UseWorkspace = false,
    FolderName = "Sigma Spy",
    RepoUrl = nil :: string?,
    FolderStructure = {
        ["Sigma Spy"] = {
            "assets",
        }
    } :: FolderStructure,
    
    --// Cache for loaded modules
    ModuleCache = {} :: {[string]: any},
    
    --// HTTP request cache
    HttpCache = setmetatable({}, {__mode = "v"}) :: {[string]: string}
}

--// Services
local HttpService: HttpService

--// Localized functions for performance
local table_insert = table.insert
local table_clear = table.clear
local string_format = string.format
local string_gsub = string.gsub
local pcall = pcall

--[[
    Initializes the Files module
    @param Data InitData - Initialization data containing services
]]
function Files:Init(Data: InitData)
    local Services = Data.Services
    HttpService = Services.HttpService
    
    --// Create folder structure
    local FolderStructure = self.FolderStructure
    self:CheckFolders(FolderStructure)
end

--[[
    Pushes configuration values into the module
    @param Config table - Configuration values to merge
]]
function Files:PushConfig(Config: {[string]: any})
    for Key, Value in next, Config do
        self[Key] = Value
    end
end

--[[
    Fetches content from a URL via HTTP request
    @param Url string - The URL to fetch
    @return string - The response body
    @return table? - The full response object
]]
function Files:UrlFetch(Url: string): (string, table?)
    --// Check cache first
    local Cached = self.HttpCache[Url]
    if Cached then
        return Cached
    end
    
    --// Prepare request
    local RequestData = {
        Url = string_gsub(Url, " ", "%%20"), 
        Method = "GET"
    }

    --// Send HTTP request
    local Success, Response = pcall(request, RequestData)

    --// Error handling
    if not Success then 
        warn("[Files] HTTP request error for URL:", Url)
        warn("[Files] Error:", Response)
        return ""
    end

    local Body = Response.Body
    local StatusCode = Response.StatusCode

    --// Handle 404 errors
    if StatusCode == 404 then
        warn("[Files] 404 - File not found:", Url)
        return ""
    end
    
    --// Handle other error codes
    if StatusCode >= 400 then
        warn("[Files] HTTP error", StatusCode, "for URL:", Url)
        return ""
    end

    --// Cache successful responses
    self.HttpCache[Url] = Body

    return Body, Response
end

--[[
    Constructs a path relative to the main folder
    @param Path string - The relative path
    @return string - The full path
]]
function Files:MakePath(Path: string): string
    local Folder = self.FolderName
    return string_format("%s/%s", Folder, Path)
end

--[[
    Loads a custom asset and returns its asset ID
    @param Path string - The file path to load
    @return string? - The custom asset ID or nil
]]
function Files:LoadCustomasset(Path: string): string?
    if not getcustomasset then 
        return nil 
    end
    
    if not Path then 
        return nil 
    end
    
    --// Verify file exists and has content
    local Success, Content = pcall(readfile, Path)
    if not Success or not Content or #Content <= 0 then 
        return nil 
    end

    --// Load custom AssetId
    local AssetSuccess, AssetId = pcall(getcustomasset, Path)
    
    if not AssetSuccess then 
        return nil 
    end
    
    if not AssetId or #AssetId <= 0 then 
        return nil 
    end

    return AssetId
end

--[[
    Gets a file from either local workspace or remote repository
    @param Path string - The relative file path
    @param CustomAsset boolean? - Whether to return as a custom asset
    @return string? - The file content or asset ID
]]
function Files:GetFile(Path: string, CustomAsset: boolean?): string?
    local RepoUrl = self.RepoUrl
    local UseWorkspace = self.UseWorkspace
    local LocalPath = self:MakePath(Path)
    local Content = ""

    --// Fetch from workspace or remote
    if UseWorkspace then
        local Success, FileContent = pcall(readfile, LocalPath)
        Content = Success and FileContent or ""
    else
        --// Download with HTTP request
        Content = self:UrlFetch(string_format("%s/%s", RepoUrl, Path))
    end

    --// Handle custom asset conversion
    if CustomAsset then
        --// Ensure file exists locally
        self:FileCheck(LocalPath, function()
            return Content
        end)

        return self:LoadCustomasset(LocalPath)
    end

    return Content
end

--[[
    Gets a template file by name
    @param Name string - The template name (without .lua extension)
    @return string - The template content
]]
function Files:GetTemplate(Name: string): string
    return self:GetFile(string_format("templates/%s.lua", Name))
end

--[[
    Checks if a file exists, creating it from a callback if not
    @param Path string - The file path to check
    @param Callback function - Callback that returns content for new file
]]
function Files:FileCheck(Path: string, Callback: () -> string)
    if isfile(Path) then 
        return 
    end

    --// Create and write the template to the missing file
    local Template = Callback()
    
    local Success, Error = pcall(writefile, Path, Template)
    if not Success then
        warn("[Files] Failed to write file:", Path, Error)
    end
end

--[[
    Checks if a folder exists, creating it if not
    @param Path string - The folder path to check
]]
function Files:FolderCheck(Path: string)
    if isfolder(Path) then 
        return 
    end
    
    local Success, Error = pcall(makefolder, Path)
    if not Success then
        warn("[Files] Failed to create folder:", Path, Error)
    end
end

--[[
    Constructs a path from parent and child
    @param Parent string? - The parent path
    @param Child string - The child path component
    @return string - The combined path
]]
function Files:CheckPath(Parent: string?, Child: string): string
    if Parent then
        return string_format("%s/%s", Parent, Child)
    end
    return Child
end

--[[
    Recursively checks and creates folder structure
    @param Structure FolderStructure - The folder structure to create
    @param Path string? - The current base path
]]
function Files:CheckFolders(Structure: FolderStructure, Path: string?)
    for ParentName, Name in next, Structure do
        --// Handle nested folder structures
        if typeof(Name) == "table" then
            local NewPath = self:CheckPath(Path, ParentName)
            self:FolderCheck(NewPath)
            self:CheckFolders(Name, NewPath)
            continue
        end

        --// Handle simple folder names
        local FolderPath = self:CheckPath(Path, Name)
        self:FolderCheck(FolderPath)
    end
end

--[[
    Checks if a file exists, creating it from a template if not
    @param Path string - The file path
    @param TemplateName string - The template to use if file doesn't exist
]]
function Files:TemplateCheck(Path: string, TemplateName: string)
    self:FileCheck(Path, function()
        return self:GetTemplate(TemplateName)
    end)
end

--[[
    Gets an asset file
    @param Name string - The asset filename
    @param CustomAsset boolean? - Whether to return as custom asset
    @return string - The asset content or ID
]]
function Files:GetAsset(Name: string, CustomAsset: boolean?): string
    return self:GetFile(string_format("assets/%s", Name), CustomAsset)
end

--[[
    Gets a module file, optionally from a template
    @param Name string - The module name
    @param TemplateName string? - Optional template name for fallback
    @return string - The module content
]]
function Files:GetModule(Name: string, TemplateName: string?): string
    local Path = string_format("%s.lua", Name)

    --// Use template if specified
    if TemplateName then
        self:TemplateCheck(Path, TemplateName)

        --// Verify it loads successfully
        local Success, Content = pcall(readfile, Path)
        if Success then
            local LoadSuccess = pcall(loadstring, Content)
            if LoadSuccess then 
                return Content 
            end
        end

        return self:GetTemplate(TemplateName)
    end

    return self:GetFile(Path)
end

--[[
    Loads multiple libraries from script content
    @param Scripts table - Dictionary of script names to content
    @param ... any - Additional arguments to pass to loaded modules
    @return ModuleCollection - Dictionary of loaded modules
]]
function Files:LoadLibraries(Scripts: {[string]: string | {string} | any}, ...: any): ModuleCollection
    local Modules = {}
    local Args = {...}
    
    for Name, Content in next, Scripts do
        --// Handle Base64 encoded content
        local IsBase64 = typeof(Content) == "table" and Content[1] == "base64"
        if IsBase64 then
            Content = Content[2]
        end

        --// Handle non-string content (already loaded modules)
        if typeof(Content) ~= "string" and not IsBase64 then 
            Modules[Name] = Content
            continue 
        end

        --// Decode Base64 if necessary
        if IsBase64 and crypt and crypt.base64decode then
            Content = crypt.base64decode(Content)
            Scripts[Name] = Content
        end

        --// Compile and load the library
        local Closure, Error = loadstring(Content, Name)
        
        if not Closure then
            warn(string_format("[Files] Failed to load %s: %s", Name, tostring(Error)))
            continue
        end
        
        local Success, Result = pcall(Closure, unpack(Args))
        
        if not Success then
            warn(string_format("[Files] Error executing %s: %s", Name, tostring(Result)))
            continue
        end

        Modules[Name] = Result
    end
    
    return Modules
end

--[[
    Initializes all modules with provided data
    @param Modules ModuleCollection - The modules to initialize
    @param Data InitData - Initialization data to pass to modules
]]
function Files:LoadModules(Modules: ModuleCollection, Data: InitData)
    for Name, Module in next, Modules do
        --// Check if module has Init function
        if typeof(Module) ~= "table" then
            continue
        end
        
        local Init = Module.Init
        if not Init then 
            continue 
        end
        
        --// Invoke :Init function with error handling
        local Success, Error = pcall(Init, Module, Data)
        
        if not Success then
            warn(string_format("[Files] Failed to initialize %s: %s", Name, tostring(Error)))
        end
    end
end

--[[
    Creates a custom font JSON file
    @param Name string - The font name
    @param AssetId string? - The font asset ID
    @return string? - The path to the created JSON file
]]
function Files:CreateFont(Name: string, AssetId: string?): string?
    if not AssetId then 
        return nil 
    end

    --// Custom font JSON structure
    local FileName = string_format("assets/%s.json", Name)
    local JsonPath = self:MakePath(FileName)
    
    local Data = {
        name = Name,
        faces = {
            {
                name = "Regular",
                weight = 400,
                style = "Normal",
                assetId = AssetId
            }
        }
    }

    --// Write JSON
    local Json = HttpService:JSONEncode(Data)
    
    local Success, Error = pcall(writefile, JsonPath, Json)
    if not Success then
        warn("[Files] Failed to create font file:", Error)
        return nil
    end

    return JsonPath
end

--[[
    Compiles multiple scripts into a single module string
    @param Scripts table - Dictionary of script names to content
    @return string - The compiled module code
]]
function Files:CompileModule(Scripts: {[string]: string | any}): string
    local Parts = {"local Libraries = {\n"}
    
    for Name, Content in next, Scripts do
        if typeof(Content) ~= "string" then 
            continue 
        end
        
        table_insert(Parts, string_format("\t%s = (function()\n%s\nend)(),\n", Name, Content))
    end
    
    table_insert(Parts, "}")
    
    return table.concat(Parts)
end

--[[
    Creates the actor script code for parallel execution
    @param Scripts table - The scripts to include
    @param ChannelId number - The communication channel ID
    @return string - The compiled actor code
]]
function Files:MakeActorScript(Scripts: {[string]: string | any}, ChannelId: number): string
    local ActorCode = self:CompileModule(Scripts)
    
    ActorCode = ActorCode .. [[

local ExtraData = {
    IsActor = true
}
Libraries.Hook:BeginService(Libraries, ExtraData, ]] .. tostring(ChannelId) .. [[)
]]
    
    return ActorCode
end

--[[
    Clears the HTTP cache
]]
function Files:ClearCache()
    table_clear(self.HttpCache)
    table_clear(self.ModuleCache)
end

return Files
