return function(Config)
	local HttpService = game:GetService("HttpService")
	local Notification = Config and Config.Notification

	local WebhookFeature = {
		Url = "",
		LastSentAt = 0,
		SendCooldown = 30,
	}

	local StoragePath = "KELV/webhook.txt"

	local function tryLoad()
		if type(readfile) ~= "function" then
			return
		end

		local Ok, Result = pcall(readfile, StoragePath)

		if Ok and type(Result) == "string" and Result ~= "" then
			WebhookFeature.Url = string.match(Result, "^%s*(.-)%s*$") or ""
		end
	end

	local function trySave(Url)
		if type(writefile) ~= "function" then
			return
		end

		if type(makefolder) == "function" then
			pcall(makefolder, "KELV")
		end

		pcall(writefile, StoragePath, Url)
	end

	local function doRequest(Url, Payload)
		local Body = HttpService:JSONEncode(Payload)

		if type(syn) == "table" and type(syn.request) == "function" then
			syn.request({
				Url = Url,
				Method = "POST",
				Headers = {["Content-Type"] = "application/json"},
				Body = Body,
			})
			return
		end

		if type(http) == "table" and type(http.request) == "function" then
			http.request({
				Url = Url,
				Method = "POST",
				Headers = {["Content-Type"] = "application/json"},
				Body = Body,
			})
			return
		end

		if type(request) == "function" then
			request({
				Url = Url,
				Method = "POST",
				Headers = {["Content-Type"] = "application/json"},
				Body = Body,
			})
			return
		end
	end

	function WebhookFeature:Send(Content)
		local Now = os.clock()

		if self.Url == "" then
			return false
		end

		if (Now - self.LastSentAt) < self.SendCooldown then
			return false
		end

		self.LastSentAt = Now

		task.spawn(function()
			pcall(doRequest, self.Url, {content = Content})
		end)

		return true
	end

	function WebhookFeature:SetUrl(Url)
		local Trimmed = type(Url) == "string" and string.match(Url, "^%s*(.-)%s*$") or ""
		self.Url = Trimmed
		trySave(Trimmed)

		if Notification then
			if Trimmed ~= "" then
				Notification:Notify({
					Title = "Webhook",
					Content = "URL saved",
					Icon = "check-circle"
				})
			else
				Notification:Notify({
					Title = "Webhook",
					Content = "URL cleared",
					Icon = "x-circle"
				})
			end
		end
	end

	function WebhookFeature:GetUrl()
		return self.Url
	end

	function WebhookFeature:IsConfigured()
		return self.Url ~= ""
	end

	tryLoad()

	return WebhookFeature
end
