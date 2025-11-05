# Rust Plugins for Neovim Config

This directory contains Rust-based Neovim plugins using `nvim-oxi`. Rust code is compiled to shared libraries that Neovim loads at runtime via LuaJIT FFI.

to set up need:
1. Build the Rust code in release mode using cargo
2. Copy the compiled library to `../lua/rust_plugins.so`
which is already encoded in `nix build`, - so just use that.

## Adding New Rust Functions

1. **Edit the Rust code** (`src/lib.rs`):

```rust
fn my_new_function() -> String {
    "Hello from Rust!".to_string()
}

#[nvim_oxi::plugin]
fn rust_plugins() -> nvim_oxi::Result<Dictionary> {
    let find_todo = Function::from_fn(|()| find_todo_impl());
    let my_new_fn: Function<(), String> = Function::from_fn(|()| my_new_function());

    Ok(Dictionary::from_iter([
        ("find_todo", Object::from(find_todo)),
        ("my_new_fn", Object::from(my_new_fn)),
    ]))
}
```

2. **Rebuild**:
```bash
build
```

3. **Use in Lua**:
```lua
local rust_plugins = require('rust_plugins')
print(rust_plugins.my_new_fn())  -- "Hello from Rust!"
```
