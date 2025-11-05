# Rust Plugin Integration Guide

## What was done

Your Neovim config now has Rust integration using `nvim-oxi`. The `FindTodo()` function has been rewritten in Rust for better performance and type safety.

## Directory Structure

```
nvim/
├── rust_plugins/           # Rust project directory
│   ├── src/
│   │   └── lib.rs         # Main Rust code
│   ├── Cargo.toml         # Rust dependencies
│   ├── build.sh           # Build script
│   └── target/            # Compiled artifacts (gitignore this)
├── lua/
│   └── rust_plugins/
│       ├── init.lua       # Loader module
│       └── rust_plugins.so # Compiled shared library
└── after/plugin/
    └── comment.lua        # Still contains FindTodo() as fallback
```

## How it works

1. **Rust Code** (`rust_plugins/src/lib.rs`):
   - Uses `nvim-oxi` crate for Neovim API bindings
   - Exports `find_todo()` function
   - Calls `rg` + `awk` commands just like the Lua version
   - Directly manipulates quickfix list via Neovim API

2. **Build Process** (`rust_plugins/build.sh`):
   - Compiles Rust to shared library (`.so`)
   - Copies to `lua/rust_plugins/rust_plugins.so`
   - Neovim can load this via `require('rust_plugins')`

3. **Lua Integration** (`lua/valera/plugins/telescope.lua:38-47`):
   - Tries to load Rust version first
   - Falls back to Lua `FindTodo()` if not available
   - Seamless integration with existing keybinding `<space>st`

## Building/Rebuilding

After modifying Rust code:
```bash
cd ~/nix/home/config/nvim/rust_plugins
./build.sh
```

Then restart Neovim or run `:luafile %` on the telescope config.

## Adding More Rust Functions

1. Add function in `rust_plugins/src/lib.rs`:
```rust
fn my_new_function() -> Result<String> {
    Ok("Hello from Rust!".to_string())
}
```

2. Export it in the plugin macro:
```rust
#[nvim_oxi::plugin]
fn rust_plugins() -> Result<Dictionary> {
    let find_todo: Function<(), ()> = Function::from_fn(|()| find_todo_impl());
    let my_new_fn: Function<(), String> = Function::from_fn(|()| my_new_function());

    Ok(Dictionary::from_iter([
        ("find_todo", Object::from(find_todo)),
        ("my_new_fn", Object::from(my_new_fn)),
    ]))
}
```

3. Rebuild with `./build.sh`

4. Use in Lua:
```lua
local rust_plugins = require('rust_plugins')
print(rust_plugins.my_new_fn())
```

## Benefits

- **Type Safety**: Rust's type system prevents many bugs
- **Performance**: Compiled code is faster than interpreted Lua
- **Full API Access**: `nvim-oxi` provides complete Neovim API
- **Error Handling**: Rust's Result type makes error handling explicit
- **Maintainability**: Complex logic is easier to manage in Rust

## Limitations

- Requires Rust toolchain to build
- Adds compilation step to updates
- Shared library is platform-specific (need separate builds for Linux/macOS)
