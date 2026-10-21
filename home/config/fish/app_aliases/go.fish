function gor --wraps 'go run'; /usr/local/bin/go run -gcflags="-nounusederrors" $argv; end
function gob --wraps 'go build'; /usr/local/bin/go build -gcflags="-nounusederrors" $argv; end
