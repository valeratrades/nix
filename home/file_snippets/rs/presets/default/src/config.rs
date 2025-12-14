use v_utils::macros as v_macros;

fn __default_example_greet() -> String {
	"World".to_string()
}

#[derive(Clone, Debug, Default, v_macros::LiveSettings, v_macros::MyConfigPrimitives, v_macros::Settings)]
pub struct AppConfig {
	#[primitives(skip)]
	#[serde(default = "__default_example_greet")]
	pub example_greet: String,
}
