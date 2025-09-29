function code_quantm
	ssh-add ~/.ssh/id_ed25519
	code --remote ssh-remote+dev-server /home/valera/$argv[1]
end

function code_vincent
	ssh-add ~/.ssh/id_ed25519
	code --remote ssh-remote+dev-server /home/valera/$argv[1]
end

# not sure abuot the name. Especially considering it's hardcoded. But whatever.
function dump
	scp -r "$argv[1]" dev-server:/home/valera/tmp/
end
