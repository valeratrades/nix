use nvim_oxi::{api, Function, Object};

/// Helper to defer a Rust callback using vim.defer_fn
pub fn defer_fn<F>(delay_ms: i64, callback: F)
where
    F: Fn() + Send + 'static,
{
    let func = Function::from_fn(move |()| {
        callback();
    });
    let _ = api::call_function::<_, ()>("defer_fn", (Object::from(func), delay_ms));
}
