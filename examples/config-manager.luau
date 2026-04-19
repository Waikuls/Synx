-- Example focused on config usage.
local Fatality = loadstring(game:HttpGet("https://raw.githubusercontent.com/4lpaca-pin/Fatality/refs/heads/main/src/source.luau"))();
local Notification = Fatality:CreateNotifier();

Fatality:Loader({
	Name = "KELV",
	Duration = 4
});

local Window = Fatality.new({
	Name = "KELV",
	Expire = "never",
});

local Config = Window:AddConfig();

Config:Init("Counter-Strike 2","KELV-Win");

local Rage = Window:AddMenu({
	Name = "RAGE",
	Icon = "skull"
})

local Weapon = Rage:AddSection({
	Position = 'left',
	Name = "WEAPON"
});

Weapon:AddToggle({
	Name = "Toggle",
	Flag = "Toggle", -- this will save value to config
	Default = false
})
