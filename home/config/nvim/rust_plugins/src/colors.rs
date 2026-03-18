/**
Generate 7 shades of a color by varying lightness in OKLCH space, stepping down.
- `hue`: hue angle in degrees (irrelevant when chroma is 0)
- `chroma`: OKLCH chroma (0.0 for grey)
starting luminosity fixed at 0.85

# Usage
+ Select the desired color `hue` normally
+ now select `chroma` matching your desired color intensity.
  Human perception of colors produced from the same `chroma` will match. The higher, the more noticeable; 0 is grey (any hue at 0 chroma is grey btw)
*/
pub fn gradient7(hue: f64, chroma: f64) -> [String; 7] {
	static START_LUMINOSITY: f64 = 0.85;

	let h = hue.to_radians();
	let end_l = START_LUMINOSITY * 0.4;
	let step = (START_LUMINOSITY - end_l) / 6.0;

	std::array::from_fn(|i| {
		let l = START_LUMINOSITY - step * i as f64;
		oklch_to_hex(l, chroma, h)
	})
}

// linear RGB -> sRGB [0,1]
fn linear_to_srgb(c: f64) -> f64 {
	if c <= 0.0031308 {
		c * 12.92
	} else {
		1.055 * c.powf(1.0 / 2.4) - 0.055
	}
}

fn oklab_to_linear_rgb(l: f64, a: f64, b: f64) -> (f64, f64, f64) {
	let l_ = l + 0.3963377774 * a + 0.2158037573 * b;
	let m_ = l - 0.1055613458 * a - 0.0638541728 * b;
	let s_ = l - 0.0894841775 * a - 1.2914855480 * b;

	let l = l_ * l_ * l_;
	let m = m_ * m_ * m_;
	let s = s_ * s_ * s_;

	let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
	let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
	let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

	(r, g, b)
}

fn oklch_to_hex(l: f64, c: f64, h: f64) -> String {
	let a = c * h.cos();
	let b = c * h.sin();
	let (lr, lg, lb) = oklab_to_linear_rgb(l, a, b);
	let r = (linear_to_srgb(lr.clamp(0.0, 1.0)) * 255.0 + 0.5) as u8;
	let g = (linear_to_srgb(lg.clamp(0.0, 1.0)) * 255.0 + 0.5) as u8;
	let b = (linear_to_srgb(lb.clamp(0.0, 1.0)) * 255.0 + 0.5) as u8;
	format!("#{:02x}{:02x}{:02x}", r, g, b)
}

#[cfg(test)]
mod tests {
	use insta::assert_snapshot;

	use super::*;

	// sRGB [0,1] -> linear RGB
	fn srgb_to_linear(c: f64) -> f64 {
		if c <= 0.04045 {
			c / 12.92
		} else {
			((c + 0.055) / 1.055).powf(2.4)
		}
	}

	fn hex_to_oklch(hex: &str) -> (f64, f64, f64) {
		let hex = hex.trim_start_matches('#');
		let r = srgb_to_linear(u8::from_str_radix(&hex[0..2], 16).unwrap() as f64 / 255.0);
		let g = srgb_to_linear(u8::from_str_radix(&hex[2..4], 16).unwrap() as f64 / 255.0);
		let b = srgb_to_linear(u8::from_str_radix(&hex[4..6], 16).unwrap() as f64 / 255.0);

		let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
		let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
		let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

		let l_ = l.cbrt();
		let m_ = m.cbrt();
		let s_ = s.cbrt();

		let lab_l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
		let lab_a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
		let lab_b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

		let c = (lab_a * lab_a + lab_b * lab_b).sqrt();
		let h = lab_b.atan2(lab_a).to_degrees();
		(lab_l, c, h)
	}

	#[test]
	fn grey_gradient() {
		let old = ["#cccccc", "#b3b3b3", "#999999", "#808080", "#666666", "#4c4c4c", "#333333"];
		let colors = gradient7(0.0, 0.0);
		let s: String = colors
			.iter()
			.zip(&old)
			.map(|(new, old)| {
				let n = u8::from_str_radix(&new[1..3], 16).unwrap() as i16;
				let o = u8::from_str_radix(&old[1..3], 16).unwrap() as i16;
				let d = n - o;
				format!("{new} (was {old}, d={d:+})")
			})
			.collect::<Vec<_>>()
			.join("\n");
		assert_snapshot!(s, @"
		#cecece (was #cccccc, d=+2)
		#b2b2b2 (was #b3b3b3, d=-1)
		#989898 (was #999999, d=-1)
		#7f7f7f (was #808080, d=-1)
		#666666 (was #666666, d=+0)
		#4e4e4e (was #4c4c4c, d=+2)
		#383838 (was #333333, d=+5)
		");
	}

	#[test]
	fn purple_gradient() {
		let (l, c, h) = hex_to_oklch("#cca3f5");
		assert_snapshot!(format!("({h}, {c}, {l})"), @"(-53.303139554475614, 0.12143646788400682, 0.7818663310036628)");

		let colors = gradient7(-53., 0.05);
		assert_snapshot!(colors.join("\n"), @"
		#d6c6e8
		#bbabcc
		#a091b1
		#867797
		#6e5f7d
		#564764
		#3f314c
		");
	}
}
