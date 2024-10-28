#!/bin/sh

# doesn't work this thing.

dbus-send --session --dest=org.telegram.tdesktop --type=method_call --print-reply /org/telegram/tdesktop org.freedesktop.DBus.Properties.Get string:org.telegram.tdesktop.TelegramDesktop string:UnreadCount 2> /dev/null | awk '/int/ {print $3}'

