# eww_dots
![image](https://github.com/Valera6/dots/assets/91695523/e1928bd0-235a-4e70-a329-b9086099a88e)

17px high bar.
Can be controlled from sway and custom scripts for additional functionality like hiding/zooming in/adding a timer.
Change of color on warn and urgent bells (like battery going below 10%).


## Classes
- "info" / ""
- "warn"
- "error"

## Widget text
Do not add whitespaces anywhere unless it's impossible to read the value without it.
Normally it's `<glyph> <value>` if glyph is fat, or `<gliph><value>` if not that much.\
Never ever `.*<value> ` - do not add spaces around just because. Space is precious.
Widgets never add padding around themselves, - it's the job of whoever composes.
