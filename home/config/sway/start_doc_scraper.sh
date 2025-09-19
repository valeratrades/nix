#!/usr/bin/env sh

source ~/.private/credentials.sh

#TODO: figure out how to access variables outside of the container
#doc_scraper check --path="~/tmp/doc_scraper_hashes.json" --telegram="${TELEGRAM_MAIN_BOT_TOKEN},${TELEGRAM_ALERTS_CHANNEL_ID}"
doc_scraper check --path="~/tmp/doc_scraper_hashes.json" --telegram="6225430873:AAEYlbJ2bY-WsLADxlWY1NS-z4r75sf9X5I,-1001800341082"
