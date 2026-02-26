function __winvm_set_perf
	set -l compose_file ~/.config/winapps/compose.yaml
	set -l ram $argv[1]
	set -l cores $argv[2]
	sed -i "s/RAM_SIZE: .*/RAM_SIZE: \"$ram\"/" $compose_file
	sed -i "s/CPU_CORES: .*/CPU_CORES: \"$cores\"/" $compose_file
	echo "Set $ram RAM, $cores cores. Run 'winvm restart' to apply."
end

function winvm
	set -l compose_file ~/.config/winapps/compose.yaml
	switch $argv[1]
		case start up
			docker compose --file $compose_file up -d
		case stop down
			docker compose --file $compose_file stop
		case kill
			docker compose --file $compose_file kill
		case restart
			docker compose --file $compose_file down
			docker compose --file $compose_file up -d
		case status
			docker ps --filter name=WinApps --format "table {{.Status}}\t{{.Ports}}"
		case vnc
			xdg-open http://127.0.0.1:8006/
		case rdp
			xfreerdp /u:WinUser /p:1 /v:127.0.0.1 /cert:tofu +home-drive /sound /microphone
		case nuke
			docker compose --file $compose_file down --rmi=all --volumes
		case max_perf
			__winvm_set_perf 50G 26
		case min_perf
			__winvm_set_perf 2G 2
		case norm_perf
			__winvm_set_perf 4G 4
		case '*'
			echo "Usage: winvm {start|stop|kill|restart|status|vnc|rdp|nuke|max_perf|min_perf|norm_perf}"
	end
end

alias wayland_wine="DISPLAY='' wine64"
