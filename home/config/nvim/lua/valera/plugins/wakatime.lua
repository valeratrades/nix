return {
	'wakatime/vim-wakatime',
	-- Only load when wakatime commands are explicitly called
	-- This prevents startup errors when wakatime-cli is not installed
	cmd = { "WakaTimeApiKey", "WakaTimeDebugEnable", "WakaTimeDebugDisable", "WakaTimeToday", "WakaTimeFileExpert" },
}
