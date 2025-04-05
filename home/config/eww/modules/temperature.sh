temperature=$(sensors | grep -i "CPU:" | awk '{gsub(/[+°C]/,"",$NF); printf "%.0f\n", $NF}')
if [ "$temperature" -lt 30 ]; then
	icon=""
elif [ "$temperature" -lt 45 ]; then
	icon=""
elif [ "$temperature" -lt 60 ]; then
	icon=""
elif [ "$temperature" -lt 70 ]; then
	icon=""
else
	icon=""
fi

echo "{\"content\": \"$temperature\", \"icon\": \"$icon\"}"
