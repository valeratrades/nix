# File Snippets
The main utilisation is through [./init_projects.sh] script here, that is sourced from my .zshrc

## Example
```sh
can --clap hello_the_world
```
Will create a new initialized clap package with according name.

Git is also initialized with initial-commit-message.
On my system all what's left to then post it on git is to call `gn --private` or `gn --public`, and everything is pushed to remote immediately in a fully functional condition.

## Design Decisions
All files except for [./README.md] and [./init_project.sh] are owned by root:root with chmod 755
