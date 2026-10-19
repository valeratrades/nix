"""`apply`: declared OBS config -> ~/.config/obs-studio (HM activation). `capture`: GUI changes -> repo (`obs_capture`)."""
import configparser, glob, json, os, sys

mode, repo, live = sys.argv[1:4]
assert mode in ("apply", "capture"), mode
INIS = ["global.ini", "user.ini", "basic/profiles/Untitled/basic.ini"]
SCENES = "basic/scenes/Untitled.json"
# MANUAL: set once in the GUI per machine: these (portal grant, restream chat token), the stream key (profile service.json) and the websocket password. Repo is public.
LIVE_ONLY = {"pipewire-screen-capture-source": "RestoreToken", "browser_source": "url"}

if any(open(c).read().strip() == "obs" for c in glob.glob("/proc/[0-9]*/comm") if os.path.exists(c)):
    print("\x1b[33mOBS is running and only saves its config on exit; close it and re-run\x1b[0m")
    sys.exit(mode == "capture")


def ini(path):
    p = configparser.ConfigParser(interpolation=None)
    p.optionxform = str
    p.read(path)
    return p


def write_ini(p, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        p.write(f, space_around_delimiters=False)


def load_json(path):
    with open(path) as f:
        return json.load(f)


for rel in INIS:
    declared_path, live_path = f"{repo}/{os.path.basename(rel)}", f"{live}/{rel}"
    declared, current = ini(declared_path), ini(live_path)
    for sec in declared.sections():  # the repo's key set is the contract both ways; keys it doesn't name (window geometry, LastVersion, ...) stay machine-local
        if mode == "apply":
            if not current.has_section(sec):
                current.add_section(sec)
            current[sec].update(declared[sec])
        else:
            for key in declared[sec]:
                assert current.has_option(sec, key), f"{live_path} has no [{sec}] {key}: OBS dropped it, so drop it from {declared_path} too"
                declared[sec][key] = current[sec][key]
    write_ini(current, live_path) if mode == "apply" else write_ini(declared, declared_path)

if mode == "capture":
    scenes = load_json(f"{live}/{SCENES}")
    for s in scenes["sources"]:
        if s["id"] in LIVE_ONLY:
            s["settings"].pop(LIVE_ONLY[s["id"]], None)  # absent when never granted/set on this machine
    with open(f"{repo}/scenes/Untitled.json", "w") as f:
        json.dump(scenes, f, indent=4, ensure_ascii=False)
        f.write("\n")
    sys.exit()

scenes = load_json(f"{repo}/scenes/Untitled.json")
live_settings = {s["uuid"]: s["settings"] for s in load_json(f"{live}/{SCENES}")["sources"]} if os.path.exists(f"{live}/{SCENES}") else {}
for s in scenes["sources"]:
    key = LIVE_ONLY.get(s["id"])
    if key is None:
        continue
    assert key not in s["settings"], f"{key} of '{s['name']}' must not be committed"
    if key in live_settings.get(s["uuid"], {}):
        s["settings"][key] = live_settings[s["uuid"]][key]
    else:
        print(f"\x1b[33mOBS '{s['name']}': no {key} yet, set it once in the GUI\x1b[0m")
os.makedirs(os.path.dirname(f"{live}/{SCENES}"), exist_ok=True)
with open(os.open(f"{live}/{SCENES}", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(scenes, f, indent=4)
