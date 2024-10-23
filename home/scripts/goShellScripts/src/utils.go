package u

import (
	"fmt"
	"os"
	"os/exec"
)

const CLEAR = "\x1B[2J\x1B[1;1H"

// will be ran in a subshell
func execute_command(command string) (string, error) {
	cmd := exec.Command("sh", "-c", command)
	cmd.Env = os.Environ()
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			//fmt.Printf("%s\n", exitErr.Stderr)
			err = fmt.Errorf("%d\n%s", exitErr.ExitCode(), exitErr.Stderr)
		}
	}
	return string(out), err
}

// alias to [command]
func C(command string) (string, error) {
	return execute_command(command)
}

// preserve color
func Cc(command string) string {
	preserve_color := fmt.Sprintf(`script -q /dev/null --command="%s"`, command)
	res, err := execute_command(preserve_color)
	if err != nil {
		panic(err)
	}
	return res
}
