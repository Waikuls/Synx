local function getCompiler()
	if type(loadstring) == "function" then
		return loadstring
	end

	if type(load) == "function" then
		return load
	end

	return nil
end

local RemoteRef = "edb9b16"

local function canReadLocalFile(LocalPath)
	if type(readfile) ~= "function" then
		return false
	end

	local Success, Result = pcall(readfile, LocalPath)

	return Success and type(Result) == "string" and Result ~= ""
end

local function tryReadLocalEntry()
	local LocalPath = "Fatality/main.lua"

	if not canReadLocalFile(LocalPath) then
		return false, string.format("Local %s unavailable", LocalPath)
	end

	local Success, Result = pcall(readfile, LocalPath)

	if Success and type(Result) == "string" and Result ~= "" then
		return true, Result
	end

	return false, string.format("Local %s unreadable", LocalPath)
end

local function getRemoteSeed()
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

	local Entropy = tostring(math.floor(os.clock() * 1000000))
	local SuccessGuid, GuidValue = pcall(function()
		return game:GetService("HttpService"):GenerateGUID(false)
	end)

	if SuccessGuid and type(GuidValue) == "string" and GuidValue ~= "" then
		Entropy = GuidValue
	end

	local Seed = string.format("%s-%s-%s", Timestamp, JobId, Entropy)

	return Seed
end

local function fetchLatestEntry()
	local Seed = getRemoteSeed()
	local Urls = {
		string.format("https://raw.githubusercontent.com/Waikuls/Synx/%s/Fatality/main.lua?v=%s", RemoteRef, Seed),
		string.format("https://cdn.jsdelivr.net/gh/Waikuls/Synx@%s/Fatality/main.lua?v=%s", RemoteRef, Seed)
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

local function executeEntrySource(SourceCode, SourceLabel)
	local Chunk, CompileError = Compiler(SourceCode)

	if type(Chunk) ~= "function" then
		error(string.format("Failed to compile %s: %s", tostring(SourceLabel), tostring(CompileError)), 0)
	end

	local Success, Result = pcall(Chunk)

	if not Success then
		error(string.format("Failed to run %s: %s", tostring(SourceLabel), tostring(Result)), 0)
	end

	return Result
end

do
	local Errors = {}
	local LocalSuccess, LocalResult = tryReadLocalEntry()

	if LocalSuccess then
		local ExecuteSuccess, ExecuteResult = pcall(executeEntrySource, LocalResult, "Fatality/main.lua")

		if ExecuteSuccess then
			return ExecuteResult
		end

		table.insert(Errors, tostring(ExecuteResult))
	else
		table.insert(Errors, LocalResult)
	end

	local RemoteSuccess, RemoteResult = pcall(fetchLatestEntry)

	if RemoteSuccess and type(RemoteResult) == "string" and RemoteResult ~= "" then
		local ExecuteSuccess, ExecuteResult = pcall(executeEntrySource, RemoteResult, "remote Fatality/main.lua")

		if ExecuteSuccess then
			return ExecuteResult
		end

		table.insert(Errors, tostring(ExecuteResult))
	else
		table.insert(Errors, tostring(RemoteResult))
	end

	error(table.concat(Errors, " | "), 0)
end
