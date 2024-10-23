package main

import (
	"goShellScripts/cmd/internal"
	"os"
)

func main() {
	base_cmd := os.Args[1]
	args := os.Args[2:]

	switch base_cmd {
	case "cpp_watch":
		internal.CppWatch()
	case "ce":
		internal.CargoNextestShorthand(args)
	default:
		panic("Command not found: " + base_cmd)
	}
}
