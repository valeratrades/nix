# Discord web in Mullvad Browser, through `vpn_ns`, on a profile no other Discord client touches.
# Mullvad Browser over a second Vesktop: its fingerprint is the one shared by every Mullvad Browser user, while a second Electron client would carry the same GPU/canvas/UA as the main one.
profile="${XDG_STATE_HOME:-$HOME/.local/state}/discord_private/profile"
mkdir -p "$profile"
# always-private by default, which would drop the login on every exit
echo 'user_pref("browser.privatebrowsing.autostart", false);' >"$profile/user.js"

exec vpn_ns mullvad-browser --no-remote --name discord_private --profile "$profile" "${@:-https://discord.com/app}"
