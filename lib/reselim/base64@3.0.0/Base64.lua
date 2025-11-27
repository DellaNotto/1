--[[
    Base64 Encoding/Decoding Module
    Original author: Reselim (https://github.com/Reselim/Base64)
    
    Optimized for performance with buffer operations and bit manipulation
]]

local Base64 = {}

--// Constants
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PADDING_BYTE = string.byte("=")

--// Lookup tables using buffers for fast access
local lookupValueToCharacter = buffer.create(64)
local lookupCharacterToValue = buffer.create(256)

--// Initialize lookup tables
do
    for index = 1, 64 do
        local value = index - 1
        local character = string.byte(ALPHABET, index)
        
        buffer.writeu8(lookupValueToCharacter, value, character)
        buffer.writeu8(lookupCharacterToValue, character, value)
    end
end

--// Bit manipulation helpers
local bit32_byteswap = bit32.byteswap
local bit32_rshift = bit32.rshift
local bit32_lshift = bit32.lshift
local bit32_band = bit32.band
local bit32_bor = bit32.bor

--// Buffer helpers
local buffer_create = buffer.create
local buffer_len = buffer.len
local buffer_readu8 = buffer.readu8
local buffer_readu32 = buffer.readu32
local buffer_writeu8 = buffer.writeu8

--// Math helpers
local math_ceil = math.ceil

--[[
    Encodes a buffer to Base64
    @param input buffer - The input buffer to encode
    @return buffer - The Base64 encoded buffer
]]
function Base64:Encode(input: buffer): buffer
    local inputLength = buffer_len(input)
    local inputChunks = math_ceil(inputLength / 3)
    
    local outputLength = inputChunks * 4
    local output = buffer_create(outputLength)
    
    --// Process all chunks except the last (to avoid buffer overread)
    for chunkIndex = 1, inputChunks - 1 do
        local inputIndex = (chunkIndex - 1) * 3
        local outputIndex = (chunkIndex - 1) * 4
        
        local chunk = bit32_byteswap(buffer_readu32(input, inputIndex))
        
        --// Extract 6-bit values: 8 + 24 - (6 * index)
        local value1 = bit32_rshift(chunk, 26)
        local value2 = bit32_band(bit32_rshift(chunk, 20), 0b111111)
        local value3 = bit32_band(bit32_rshift(chunk, 14), 0b111111)
        local value4 = bit32_band(bit32_rshift(chunk, 8), 0b111111)
        
        buffer_writeu8(output, outputIndex, buffer_readu8(lookupValueToCharacter, value1))
        buffer_writeu8(output, outputIndex + 1, buffer_readu8(lookupValueToCharacter, value2))
        buffer_writeu8(output, outputIndex + 2, buffer_readu8(lookupValueToCharacter, value3))
        buffer_writeu8(output, outputIndex + 3, buffer_readu8(lookupValueToCharacter, value4))
    end
    
    --// Handle the last chunk with potential padding
    local inputRemainder = inputLength % 3
    
    if inputRemainder == 1 then
        --// 1 byte remaining: encode to 2 characters + 2 padding
        local chunk = buffer_readu8(input, inputLength - 1)
        
        local value1 = bit32_rshift(chunk, 2)
        local value2 = bit32_band(bit32_lshift(chunk, 4), 0b111111)

        buffer_writeu8(output, outputLength - 4, buffer_readu8(lookupValueToCharacter, value1))
        buffer_writeu8(output, outputLength - 3, buffer_readu8(lookupValueToCharacter, value2))
        buffer_writeu8(output, outputLength - 2, PADDING_BYTE)
        buffer_writeu8(output, outputLength - 1, PADDING_BYTE)
        
    elseif inputRemainder == 2 then
        --// 2 bytes remaining: encode to 3 characters + 1 padding
        local chunk = bit32_bor(
            bit32_lshift(buffer_readu8(input, inputLength - 2), 8),
            buffer_readu8(input, inputLength - 1)
        )

        local value1 = bit32_rshift(chunk, 10)
        local value2 = bit32_band(bit32_rshift(chunk, 4), 0b111111)
        local value3 = bit32_band(bit32_lshift(chunk, 2), 0b111111)
        
        buffer_writeu8(output, outputLength - 4, buffer_readu8(lookupValueToCharacter, value1))
        buffer_writeu8(output, outputLength - 3, buffer_readu8(lookupValueToCharacter, value2))
        buffer_writeu8(output, outputLength - 2, buffer_readu8(lookupValueToCharacter, value3))
        buffer_writeu8(output, outputLength - 1, PADDING_BYTE)
        
    elseif inputRemainder == 0 and inputLength ~= 0 then
        --// 3 bytes remaining: encode to 4 characters (no padding)
        local chunk = bit32_bor(
            bit32_lshift(buffer_readu8(input, inputLength - 3), 16),
            bit32_lshift(buffer_readu8(input, inputLength - 2), 8),
            buffer_readu8(input, inputLength - 1)
        )

        local value1 = bit32_rshift(chunk, 18)
        local value2 = bit32_band(bit32_rshift(chunk, 12), 0b111111)
        local value3 = bit32_band(bit32_rshift(chunk, 6), 0b111111)
        local value4 = bit32_band(chunk, 0b111111)

        buffer_writeu8(output, outputLength - 4, buffer_readu8(lookupValueToCharacter, value1))
        buffer_writeu8(output, outputLength - 3, buffer_readu8(lookupValueToCharacter, value2))
        buffer_writeu8(output, outputLength - 2, buffer_readu8(lookupValueToCharacter, value3))
        buffer_writeu8(output, outputLength - 1, buffer_readu8(lookupValueToCharacter, value4))
    end
    
    return output
end

--[[
    Decodes a Base64 buffer
    @param input buffer - The Base64 encoded buffer to decode
    @return buffer - The decoded buffer
]]
function Base64:Decode(input: buffer): buffer
    local inputLength = buffer_len(input)
    local inputChunks = math_ceil(inputLength / 4)
    
    --// Calculate padding
    local inputPadding = 0
    if inputLength ~= 0 then
        if buffer_readu8(input, inputLength - 1) == PADDING_BYTE then 
            inputPadding = inputPadding + 1 
        end
        if buffer_readu8(input, inputLength - 2) == PADDING_BYTE then 
            inputPadding = inputPadding + 1 
        end
    end

    local outputLength = inputChunks * 3 - inputPadding
    local output = buffer_create(outputLength)
    
    --// Process all chunks except the last
    for chunkIndex = 1, inputChunks - 1 do
        local inputIndex = (chunkIndex - 1) * 4
        local outputIndex = (chunkIndex - 1) * 3
        
        local value1 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, inputIndex))
        local value2 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, inputIndex + 1))
        local value3 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, inputIndex + 2))
        local value4 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, inputIndex + 3))
        
        local chunk = bit32_bor(
            bit32_lshift(value1, 18),
            bit32_lshift(value2, 12),
            bit32_lshift(value3, 6),
            value4
        )
        
        local character1 = bit32_rshift(chunk, 16)
        local character2 = bit32_band(bit32_rshift(chunk, 8), 0b11111111)
        local character3 = bit32_band(chunk, 0b11111111)
        
        buffer_writeu8(output, outputIndex, character1)
        buffer_writeu8(output, outputIndex + 1, character2)
        buffer_writeu8(output, outputIndex + 2, character3)
    end
    
    --// Handle the last chunk with potential padding
    if inputLength ~= 0 then
        local lastInputIndex = (inputChunks - 1) * 4
        local lastOutputIndex = (inputChunks - 1) * 3
        
        local lastValue1 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, lastInputIndex))
        local lastValue2 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, lastInputIndex + 1))
        local lastValue3 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, lastInputIndex + 2))
        local lastValue4 = buffer_readu8(lookupCharacterToValue, buffer_readu8(input, lastInputIndex + 3))

        local lastChunk = bit32_bor(
            bit32_lshift(lastValue1, 18),
            bit32_lshift(lastValue2, 12),
            bit32_lshift(lastValue3, 6),
            lastValue4
        )
        
        if inputPadding <= 2 then
            local lastCharacter1 = bit32_rshift(lastChunk, 16)
            buffer_writeu8(output, lastOutputIndex, lastCharacter1)
            
            if inputPadding <= 1 then
                local lastCharacter2 = bit32_band(bit32_rshift(lastChunk, 8), 0b11111111)
                buffer_writeu8(output, lastOutputIndex + 1, lastCharacter2)
                
                if inputPadding == 0 then
                    local lastCharacter3 = bit32_band(lastChunk, 0b11111111)
                    buffer_writeu8(output, lastOutputIndex + 2, lastCharacter3)
                end
            end
        end
    end
    
    return output
end

--[[
    Encodes a string to Base64
    @param input string - The string to encode
    @return string - The Base64 encoded string
]]
function Base64:EncodeString(input: string): string
    local inputBuffer = buffer_create(#input)
    for i = 1, #input do
        buffer_writeu8(inputBuffer, i - 1, string.byte(input, i))
    end
    
    local outputBuffer = self:Encode(inputBuffer)
    local outputLength = buffer_len(outputBuffer)
    
    local chars = table.create(outputLength)
    for i = 0, outputLength - 1 do
        chars[i + 1] = string.char(buffer_readu8(outputBuffer, i))
    end
    
    return table.concat(chars)
end

--[[
    Decodes a Base64 string
    @param input string - The Base64 string to decode
    @return string - The decoded string
]]
function Base64:DecodeString(input: string): string
    local inputBuffer = buffer_create(#input)
    for i = 1, #input do
        buffer_writeu8(inputBuffer, i - 1, string.byte(input, i))
    end
    
    local outputBuffer = self:Decode(inputBuffer)
    local outputLength = buffer_len(outputBuffer)
    
    local chars = table.create(outputLength)
    for i = 0, outputLength - 1 do
        chars[i + 1] = string.char(buffer_readu8(outputBuffer, i))
    end
    
    return table.concat(chars)
end

return Base64
