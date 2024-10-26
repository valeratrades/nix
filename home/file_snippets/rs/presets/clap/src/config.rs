use anyhow::Result;
use std::path::Path;
use v_utils::macros::MyConfigPrimitives;

#[derive(Clone, Debug, Default, MyConfigPrimitives)]
pub struct AppConfig {}

impl AppConfig {
	//TODO!!!: figure out how to return error iff all potentail sources combined fail to provide all of the values;
	pub fn read(path: &Path) -> Result<Self> {
		match path.exists() {
			true => {
				let builder = config::Config::builder().add_source(config::File::with_name(path.to_str().unwrap()));
				let raw: config::Config = builder.build()?;
				Ok(raw.try_deserialize()?)
			}
			false => Err(anyhow::anyhow!("Config file does not exist: {:?}", path)),
		}
	}
}
