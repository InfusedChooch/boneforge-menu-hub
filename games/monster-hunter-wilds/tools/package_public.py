"""Package the public Wilds menu for a game folder with REFramework installed."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
AUTORUN = "reframework/autorun"
MODULES = ("runtime", "options", "meals", "buffs", "extras", "positions",
           "teleporter_map", "teleporter_map_model")


def build(output):
    files = {
        "README.txt": ROOT / "public/INSTALL.txt",
        "LICENSE.txt": ROOT / "LICENSE",
        f"{AUTORUN}/BoneforgeWilds.lua": ROOT / "public/BoneforgeWilds.lua",
    }
    for module in MODULES:
        name = f"{AUTORUN}/GHLQOL/{module}.lua"
        files[name] = ROOT / "source" / name
    contents = {name: source.read_bytes().replace(b"\r\n", b"\n") for name, source in files.items()}
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w") as archive:
        for name, data in contents.items():
            archive.writestr(ZipInfo(name), data, compress_type=ZIP_DEFLATED)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    build(parser.parse_args().output)
