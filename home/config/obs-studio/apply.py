"""Write the declared OBS config over ~/.config/obs-studio. Runs on HM activation."""
import configparser, glob, json, os, sys

src, dst = sys.argv[1], sys.argv[2]
INIS = ["global.ini", "user.ini", "basic/profiles/Untitled/basic.ini"]
SCENES = "basic/scenes/Untitled.json"
# MANUAL: set once in the GUI per machine: these (portal grant, restream chat token), the stream key (profile service.json) and the websocket password. Repo is public.
LIVE_ONLY = {"pipewire-screen-capture-source": "RestoreToken", "browser_source": "url"}

if any(open(c).read().strip() == "obs" for c in glob.glob("/proc/[0-9]*/comm") if os.path.exists(c)):
    print("\x1b[33mOBS is running, so it would overwrite the declared config on exit; close it and re-run activation\x1b[0m")
    sys.exit(0)


def ini(path):
    p = configparser.ConfigParser(interpolation=None)
    p.optionxform = str
    p.read(path)
    return p


for rel in INIS:
    live, declared = ini(f"{dst}/{rel}"), ini(f"{src}/{os.path.basename(rel)}")
    for sec in declared.sections():  # declared wins; keys OBS keeps per-machine (window geometry, LastVersion, ...) survive
        if not live.has_section(sec):
            live.add_section(sec)
        live[sec].update(declared[sec])
    os.makedirs(os.path.dirname(f"{dst}/{rel}") or dst, exist_ok=True)
    with open(f"{dst}/{rel}", "w") as f:
        live.write(f, space_around_delimiters=False)

with open(f"{src}/scenes/Untitled.json") as f:
    scenes = json.load(f)
live_settings = {}
if os.path.exists(f"{dst}/{SCENES}"):
    with open(f"{dst}/{SCENES}") as f:
        live_settings = {s["uuid"]: s["settings"] for s in json.load(f)["sources"]}
for s in scenes["sources"]:
    key = LIVE_ONLY.get(s["id"])
    if key is None:
        continue
    assert key not in s["settings"], f"{key} of '{s['name']}' must not be committed"
    if key in live_settings.get(s["uuid"], {}):
        s["settings"][key] = live_settings[s["uuid"]][key]
    else:
        print(f"\x1b[33mOBS '{s['name']}': no {key} yet, set it once in the GUI\x1b[0m")
os.makedirs(os.path.dirname(f"{dst}/{SCENES}"), exist_ok=True)
with open(os.open(f"{dst}/{SCENES}", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(scenes, f, indent=4)
