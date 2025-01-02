use color_eyre::eyre::Result;
use v_utils::{io::ExpandedPath, macros::MyConfigPrimitives};

#[derive(Clone, Debug, Default, MyConfigPrimitives)]
pub struct AppConfig {}

impl AppConfig {
	pub fn read(path: Option<) -> Result<Self> {
		let mut builder = config::Config::builder().add_source(config::Environment::default());
		let settings: Self = match path {
			Some(path) => {
				let builder = builder.add_source(config::File::with_name(&path.to_string()).required(true));
				builder.build()?.try_deserialize()?
			}
			None => {
				let app_name = env!("CARGO_PKG_NAME");
				let config_dir = env!("XDG_CONFIG_HOME");
				let locations = [
					format!("{config_dir}/{app_name}"),
					format!("{config_dir}/{app_name}/config"), //
				];
				for location in locations.iter() {
					builder = builder.add_source(config::File::with_name(location).required(false));
				}
				let raw: config::Config = builder.build()?;

				match raw.try_deserialize() {
					Ok(settings) => settings,
					Err(e) => {
						eprintln!("Config file does not exist or is invalid:");
						return Err(e);
					}
				}
			}
		};
		Ok(settings)
	}
}
