{
	mock = false;
	site_url = "https://valeratrades.com";
	google_oauth = {
		client_id = "350565753492-iltccminubv2bi8b6m1355mdsdmo6238.apps.googleusercontent.com";
		client_secret = { env = "GOOGLE_CLOUD_CLIENT_site_SECRET"; };
	};
	smtp = {
		host = "smtp.gmail.com";
		port = 587;
		#HACK: is using my own actual email lol. But whatever
		username = "valeratrades@gmail.com";
		password = { env = "IMAP_PASS"; };
		from_email = "valeratrades@gmail.com";
		from_name = "valeratrades";
	};
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
