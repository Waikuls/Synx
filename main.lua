local function getCompiler()
	if type(loadstring) == "function" then
		return loadstring
	end

	if type(load) == "function" then
		return load
	end

	return nil
end

local function getRemoteSeed()
	local Environment = type(getgenv) == "function" and getgenv() or nil

	if Environment and type(Environment.__FatalityEntrySeed) == "string" and Environment.__FatalityEntrySeed ~= "" then
		return Environment.__FatalityEntrySeed
	end

	local Timestamp = "0"
	local SuccessDateTime, DateTimeValue = pcall(function()
		return DateTime.now().UnixTimestampMillis
	end)

	if SuccessDateTime and DateTimeValue then
		Timestamp = tostring(DateTimeValue)
	elseif type(os.time) == "function" then
		local SuccessOsTime, OsTimeValue = pcall(os.time)

		if SuccessOsTime and OsTimeValue then
			Timestamp = tostring(OsTimeValue)
		end
	end

	local JobId = tostring(game.JobId or "")

	if JobId == "" then
		JobId = tostring(math.floor(os.clock() * 1000000))
	end

	local Seed = string.format("%s-%s", Timestamp, JobId)

	if Environment then
		Environment.__FatalityEntrySeed = Seed
	end

	return Seed
end

local function fetchLatestEntry()
	local Seed = getRemoteSeed()
	local Urls = {
		string.format("https://raw.githubusercontent.com/Waikuls/Synx/main/Fatality/main.lua?v=%s", Seed),
		string.format("https://cdn.jsdelivr.net/gh/Waikuls/Synx@main/Fatality/main.lua?v=%s", Seed)
	}
	local Errors = {}

	for _, Url in ipairs(Urls) do
		local Success, Result = pcall(function()
			return game:HttpGet(Url)
		end)

		if Success and type(Result) == "string" and Result ~= "" then
			return Result
		end

		table.insert(Errors, string.format("Failed to fetch %s", Url))
	end

	error(table.concat(Errors, " | "), 0)
end

local Compiler = getCompiler()

if type(Compiler) ~= "function" then
	error("No script compiler available for Fatality bootstrap", 0)
end

local EntrySource = fetchLatestEntry()
local Chunk, CompileError = Compiler(EntrySource)

if type(Chunk) ~= "function" then
	error(string.format("Failed to compile Fatality entry: %s", tostring(CompileError)), 0)
end

return Chunk()
