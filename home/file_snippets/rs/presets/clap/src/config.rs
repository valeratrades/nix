use color_eyre::eyre::Result;
use v_utils::macros::MyConfigPrimitives;

#[derive(Clone, Debug, Default, MyConfigPrimitives)]
pub struct AppConfig {}

impl AppConfig {
	pub fn read() -> Result<Self> {
		let app_name = env!("CARGO_PKG_NAME");
		let locations = [
			format!("{}/{app_name}", env!("XDG_CONFIG_HOME")),
			format!("{}/{app_name}/config", env!("XDG_CONFIG_HOME")), //
		];

		let mut builder = config::Config::builder().add_source(config::Environment::default());
		for location in locations.iter() {
			builder = builder.add_source(config::File::with_name(location).required(false));
		}
		let raw: config::Config = builder.build()?;

		match raw.try_deserialize() {
			Ok(config) => Ok(config),
			Err(e) => {
				eprintln!("Config file does not exist or is invalid:");
				Err(e.into())
			}
		}
	}
}
