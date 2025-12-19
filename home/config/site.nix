{
	mock = false;
	admin = {
		users = {
			admin = "100%";
			valeratrades = "100%";
			_fifty = "50%";
			_zero = "0%";
		};
		creds = {
			"100" = {
				"claude_token" = "$env:CLAUDE_TOKEN = '\${CLAUDE_TOKEN}'";
			};
			"50" = {
				"windows_uni_headless_cmd" = "./uni_headless.exe --username '\${UNI_USER}' --auto-submit -a --password '\${UNI_PASS}'";
			};
			"0" = {
				"windows_uni_headless_get" = ''Invoke-WebRequest -Uri "https://github.com/valeratrades/uni_headless/releases/download/latest-windows/uni_headless.exe" -OutFile "uni_headless.exe"'';
			};
		};
	};
}
