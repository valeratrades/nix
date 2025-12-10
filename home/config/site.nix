{
	mock = true;
	admin = {
		users = {
			admin = "100%";
			valeratrades = "100%";
			prof = "50%"; #dbg
			test_zero = "0%"; #dbg
		};
		creds = {
			"100" = {
				"claude_token" = {
					env = "CLAUDE_TOKEN";
				};
			};
			"50" = {
				"windows_uni_headless_cmd" = "./uni_headless.exe --visible --username 'vasakharov' --auto-submit -a --password 'TODO'";
			};
			"0" = {
				"windows_uni_headless_get" = ''Invoke-WebRequest -Uri "https://github.com/valeratrades/uni_headless/releases/download/latest-windows/uni_headless.exe" -OutFile "uni_headless.exe"'';
			};
		};
	};
}
