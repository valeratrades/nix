package internal

import (
	"fmt"
	"goShellScripts/src"
)

func CppWatch() {
	for {
		fmt.Println(u.CLEAR)

		result := u.Cc("g++ -g -o ./target/debug/$(basename $(pwd)) ./src/*.cpp")
		fmt.Println(result)

		//result, err := C(`inotifywait -e modify,create,delete ./src/*.cpp 2>&1 | grep -v -e "Setting up watches." -e "Watches established." # to prevent annoying confirmation`)
		u.C(`inotifywait -e modify,create,delete ./src/*.cpp`)
	}
}
