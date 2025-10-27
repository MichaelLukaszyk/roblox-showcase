local HttpService = game:GetService("HttpService")

local DevKey = nil
local UserKey = nil
local Module = {}

local function ConvertData(DataFields)
	local Data = ""
	for Key, Value in pairs(DataFields) do
		Data = Data .. string.format("&%s=%s", HttpService:UrlEncode(Key), HttpService:UrlEncode(Value))
	end
	return string.sub(Data, 2)
end

function Module:Setup(Key, Username, Password)
	local Data = ConvertData({
		["api_dev_key"] = Key,
		["api_user_name"] = Username,
		["api_user_password"] = Password
	})
	local Success, Result = pcall(function()
		return HttpService:PostAsync("https://pastebin.com/api/api_login.php", Data, Enum.HttpContentType.ApplicationUrlEncoded)
	end)
	if Success then
		DevKey = Key
		UserKey = Result
	else
		warn("Pastebin setup failed")
	end
end

function Module:CreatePaste(Title, Text)
	if DevKey and UserKey then
		local Data = ConvertData({
			["api_dev_key"] = DevKey,
			["api_user_key"] = UserKey,
			["api_option"] = "paste",
			["api_paste_name"] = Title,
			["api_paste_code"] = Text
		})
		local Success, Result = pcall(function()
			return HttpService:PostAsync("https://pastebin.com/api/api_post.php", Data, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if Success then
			return string.sub(Result, 22, #Result)
		else
			warn("Pastebin create failed")
		end
	end
end

function Module:DeletePaste(PasteKey)
	if DevKey and UserKey then
		local Data = ConvertData({
			["api_dev_key"] = DevKey,
			["api_user_key"] = UserKey,
			["api_paste_key"] = PasteKey,
			["api_option"] = "delete"
		})
		local Success, Result = pcall(function()
			return HttpService:PostAsync("https://pastebin.com/api/api_post.php", Data, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if not Success then
			warn("Pastebin delete failed")
		end
	end
end

function Module:GetRaw(PasteKey)
	if DevKey and UserKey then
		local Data = ConvertData({
			["api_dev_key"] = DevKey,
			["api_user_key"] = UserKey,
			["api_paste_key"] = PasteKey,
			["api_option"] = "show_paste"
		})
		local Success, Result = pcall(function()
			return HttpService:PostAsync("https://pastebin.com/api/api_raw.php", Data, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if Success then
			return Result
		else
			warn("Pastebin get failed")
		end
	end
end

function Module:GetRawPublic(PasteKey)
	local Success, Result = pcall(function()
		return HttpService:GetAsync("https://pastebin.com/raw/" .. PasteKey)
	end)
	if Success then
		return Result
	else
		warn("Pastebin get public failed")
	end
end

function Module:GetPastes()
	if DevKey and UserKey then
		local Data = ConvertData({
			["api_dev_key"] = DevKey,
			["api_user_key"] = UserKey,
			["api_results_limit"] = 1000,
			["api_option"] = "list"
		})
		local Success, Result = pcall(function()
			return HttpService:PostAsync("https://pastebin.com/api/api_post.php", Data, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if Success then
			local Pastes = {}
			local SearchStart = 1
			repeat
				local _, PasteStart = string.find(Result, "<paste>", SearchStart)
				local PasteEnd, _ = string.find(Result, "</paste>", SearchStart)
				if PasteStart and PasteEnd then
					SearchStart = PasteEnd + 1
					local Paste = string.sub(Result, PasteStart + 1, PasteEnd - 1)
					local Properties = {
						["paste_key"] = "",
						["paste_date"] = "",
						["paste_title"] = "",
						["paste_size"] = "",
						["paste_expire_date"] = "",
						["paste_private"] = "",
						["paste_format_long"] = "",
						["paste_format_short"] = "",
						["paste_url"] = "",
						["paste_hits"] = ""
					}
					for Key, _ in pairs(Properties) do
						local OpeningStart, OpeningEnd = string.find(Paste, "<" .. Key .. ">")
						local ClosingStart, ClosingEnd = string.find(Paste, "</" .. Key .. ">")
						Properties[Key] = string.sub(Paste, OpeningEnd + 1, ClosingStart - 1)
					end
					table.insert(Pastes, Properties)
				end
			until not PasteStart or not PasteEnd
			return Pastes
		else
			warn("Pastebin get pastes failed")
		end
	end
end

function Module:GetUserInfo()
	if DevKey and UserKey then
		local Data = ConvertData({
			["api_dev_key"] = DevKey,
			["api_user_key"] = UserKey,
			["api_option"] = "userdetails"
		})
		local Success, Result = pcall(function()
			return HttpService:PostAsync("https://pastebin.com/api/api_post.php", Data, Enum.HttpContentType.ApplicationUrlEncoded)
		end)
		if Success then
			local Properties = {
				["user_name"] = "",
				["user_format_short"] = "",
				["user_expiration"] = "",
				["user_avatar_url"] = "",
				["user_private"] = "",
				["user_website"] = "",
				["user_email"] = "",
				["user_location"] = "",
				["user_account_type"] = ""
			}
			for Key, _ in pairs(Properties) do
				local OpeningStart, OpeningEnd = string.find(Result, "<" .. Key .. ">")
				local ClosingStart, ClosingEnd = string.find(Result, "</" .. Key .. ">")
				Properties[Key] = string.sub(Result, OpeningEnd + 1, ClosingStart - 1)
			end
			return Properties
		else
			warn("Pastebin get info failed")
		end
	end
end

function Module:FormatText(Text)
	local Lines = string.split(Text, "\n")
	for Index, Line in ipairs(Lines) do
		local Words = string.split(Line, " ")
		Lines[Index] = Words
	end
	return Lines
end

return Module
