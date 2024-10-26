#!/bin/sh
# File is source on `cs` into the project's root. Allows to define a set of project-specific commands and aliases.

# effectively a quite "cargo run" alias. Needed when I look at the errors via `cargo watch` in another window, and don't want to trash terminal history when running the code.
alias qr="./target/debug/PROJECT_NAME_PLACEHOLDER"
