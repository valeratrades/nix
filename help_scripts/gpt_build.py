#!/usr/bin/python3

import openai
import requests
import json
import time
import sys
import os

api_key = os.getenv("OPENAI_KEY")
# second var is cost of 1k tokens
gpt35 = ("gpt-3.5-turbo", 0.002)
gpt4t = ("gpt-4-1106-preview", 0.015)  # price is a guess, and is not to be trusted

openai.api_type = "azure"
openai.api_key = api_key

bulid_instruction = """You build programs from source"""


# ex_readme {{{
ex_readme = """\
<h1 align="center">
  <img src="https://raw.githubusercontent.com/neovim/neovim.github.io/master/logos/neovim-logo-300x87.png" alt="Neovim">

  <a href="https://neovim.io/doc/">Documentation</a> |
  <a href="https://app.element.io/#/room/#neovim:matrix.org">Chat</a>
</h1>

[![Coverity Scan analysis](https://scan.coverity.com/projects/2227/badge.svg)](https://scan.coverity.com/projects/2227)
[![Clang analysis](https://neovim.io/doc/reports/clang/badge.svg)](https://neovim.io/doc/reports/clang)
[![Packages](https://repology.org/badge/tiny-repos/neovim.svg)](https://repology.org/metapackage/neovim)
[![Debian CI](https://badges.debian.net/badges/debian/testing/neovim/version.svg)](https://buildd.debian.org/neovim)
[![Downloads](https://img.shields.io/github/downloads/neovim/neovim/total.svg?maxAge=2592001)](https://github.com/neovim/neovim/releases/)

Neovim is a project that seeks to aggressively refactor [Vim](https://www.vim.org/) in order to:

- Simplify maintenance and encourage [contributions](CONTRIBUTING.md)
- Split the work between multiple developers
- Enable [advanced UIs] without modifications to the core
- Maximize [extensibility](https://neovim.io/doc/user/ui.html)

See the [Introduction](https://github.com/neovim/neovim/wiki/Introduction) wiki page and [Roadmap]
for more information.

Features
--------

- Modern [GUIs](https://github.com/neovim/neovim/wiki/Related-projects#gui)
- [API access](https://github.com/neovim/neovim/wiki/Related-projects#api-clients)
  from any language including C/C++, C#, Clojure, D, Elixir, Go, Haskell, Java/Kotlin,
  JavaScript/Node.js, Julia, Lisp, Lua, Perl, Python, Racket, Ruby, Rust
- Embedded, scriptable [terminal emulator](https://neovim.io/doc/user/nvim_terminal_emulator.html)
- Asynchronous [job control](https://github.com/neovim/neovim/pull/2247)
- [Shared data (shada)](https://github.com/neovim/neovim/pull/2506) among multiple editor instances
- [XDG base directories](https://github.com/neovim/neovim/pull/3470) support
- Compatible with most Vim plugins, including Ruby and Python plugins

See [`:help nvim-features`][nvim-features] for the full list, and [`:help news`][nvim-news] for noteworthy changes in the latest version!

Install from package
--------------------

Pre-built packages for Windows, macOS, and Linux are found on the
[Releases](https://github.com/neovim/neovim/releases/) page.

[Managed packages] are in [Homebrew], [Debian], [Ubuntu], [Fedora], [Arch Linux], [Void Linux], [Gentoo], and more!

Install from source
-------------------

See [BUILD.md](./BUILD.md) and [supported platforms](https://neovim.io/doc/user/support.html#supported-platforms) for details.

The build is CMake-based, but a Makefile is provided as a convenience.
After installing the dependencies, run the following command.

    make CMAKE_BUILD_TYPE=RelWithDebInfo
    sudo make install

To install to a non-default location:

    make CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_INSTALL_PREFIX=/full/path/
    make install

CMake hints for inspecting the build:

- `cmake --build build --target help` lists all build targets.
- `build/CMakeCache.txt` (or `cmake -LAH build/`) contains the resolved values of all CMake variables.
- `build/compile_commands.json` shows the full compiler invocations for each translation unit.

Transitioning from Vim
--------------------

See [`:help nvim-from-vim`](https://neovim.io/doc/user/nvim.html#nvim-from-vim) for instructions.

Project layout
--------------

    ├─ cmake/           CMake utils
    ├─ cmake.config/    CMake defines
    ├─ cmake.deps/      subproject to fetch and build dependencies (optional)
    ├─ runtime/         plugins and docs
    ├─ src/nvim/        application source code (see src/nvim/README.md)
    │  ├─ api/          API subsystem
    │  ├─ eval/         Vimscript subsystem
    │  ├─ event/        event-loop subsystem
    │  ├─ generators/   code generation (pre-compilation)
    │  ├─ lib/          generic data structures
    │  ├─ lua/          Lua subsystem
    │  ├─ msgpack_rpc/  RPC subsystem
    │  ├─ os/           low-level platform code
    │  └─ tui/          built-in UI
    └─ test/            tests (see test/README.md)

License
-------

Neovim contributions since [b17d96][license-commit] are licensed under the
Apache 2.0 license, except for contributions copied from Vim (identified by the
`vim-patch` token). See LICENSE for details.

    Vim is Charityware.  You can use and copy it as much as you like, but you are
    encouraged to make a donation for needy children in Uganda.  Please see the
    kcc section of the vim docs or visit the ICCF web site, available at these URLs:

            https://iccf-holland.org/
            https://www.vim.org/iccf/
            https://www.iccf.nl/

    You can also sponsor the development of Vim.  Vim sponsors can vote for
    features.  The money goes to Uganda anyway.

[license-commit]: https://github.com/neovim/neovim/commit/b17d9691a24099c9210289f16afb1a498a89d803
[nvim-features]: https://neovim.io/doc/user/vim_diff.html#nvim-features
[nvim-news]: https://neovim.io/doc/user/news.html
[Roadmap]: https://neovim.io/roadmap/
[advanced UIs]: https://github.com/neovim/neovim/wiki/Related-projects#gui
[Managed packages]: ./INSTALL.md#install-from-package
[Debian]: https://packages.debian.org/testing/neovim
[Ubuntu]: https://packages.ubuntu.com/search?keywords=neovim
[Fedora]: https://packages.fedoraproject.org/pkgs/neovim/neovim/
[Arch Linux]: https://www.archlinux.org/packages/?q=neovim
[Void Linux]: https://voidlinux.org/packages/?arch=x86_64&q=neovim
[Gentoo]: https://packages.gentoo.org/packages/app-editors/neovim
[Homebrew]: https://formulae.brew.sh/formula/neovim

<!-- vim: set tw=80: -->"""
# }}}
ex_name = "neovim"
ex_response = """```sh
make CMAKE_BUILD_TYPE=RelWithDebInfo && sudo make install
```"""


def formulate_request(name, readme):
    question = f"""On my arch linux I have copied source code of {name}, and cd'ed into it. Give me one exact command to build and then install it, based on their README: ````md
    {readme}````"""

    return question


def request(question, model=gpt4t):
    system_line = {"role": "system", "content": bulid_instruction}
    ex_1_user = {"role": "user", "content": formulate_request(ex_name, ex_readme)}
    ex_1_assistant = {"role": "assistant", "content": ex_response}
    user_line = {"role": "user", "content": question}
    conversation = [system_line] + [ex_1_user] + [ex_1_assistant] + [user_line]

    url = "https://api.openai.com/v1/chat/completions"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

    data = {
        "model": f"{model[0]}",
        "messages": conversation,
        "temperature": 0,
        # "max_tokens": 100,
    }
    start_time = time.time()
    r = requests.post(url, headers=headers, data=json.dumps(data)).json()
    end_time = time.time()

    return r["choices"][0]["message"]["content"].split(";")[0]


def main():
    source_path = sys.argv[1]
    if source_path[-1] == "/":
        source_path = source_path[:-1]
    readme = open(source_path + "/README.md").read()
    name = source_path.split("/")[-1]
    question = formulate_request(name, readme)

    response = request(question)
    n_commands = response.count("```sh")
    command = ""
    if n_commands == 1:
        command = response.split("```sh")[1].split("```")[0]
        command = command.strip()
    else:
        print("We did a fucky wakky and returned multiple commands")
        print(f"Here is the full response:\n{response}")
        return 1

    if len(sys.argv) == 3 and sys.argv[2] == "--noconfirm":
        print(f"running: `{command}`")
    else:
        confirm = input(f"gonna run: `{command}`. [Y/n] ")
        if confirm.lower() == "y":
            os.system(command)


if __name__ == "__main__":
    main()
