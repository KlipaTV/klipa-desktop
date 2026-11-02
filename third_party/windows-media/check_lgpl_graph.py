"""Check the patched mpv-winbuild-cmake graph against Klipa's LGPL profile.

Usage: check_lgpl_graph.py <mpv-winbuild-cmake checkout>

Walks the DEPENDS closure of `mpv` and fails if a GPL package (or one the
profile removes) is reachable, if a reachable DEPENDS list still names an
unresolved CMake variable, or if a reachable recipe enables an option that
compiles GPL code into an otherwise LGPL library. Prints the closure, which
the build keeps as evidence.
"""

import re
import sys
from pathlib import Path

# GPL code, or code whose library contains GPL-only files.
GPL = {
    "avisynth-headers", "davs2", "frei0r", "libcdio", "libdvdnav", "libdvdread",
    "libzvbi", "lzo", "rubberband", "vapoursynth", "vidstab", "x264", "x265",
    "xavs", "xavs2", "xvidcore",
}
# Not GPL, but outside the profile (scripting, unused outputs, network stacks).
DROPPED = {
    "c-ares", "curl", "glslang", "libjxl", "libmodplug", "libopenmpt", "libpsl",
    "libsdl2", "libsixel", "luajit", "mujs", "nghttp2", "nghttp3", "ngtcp2",
    "openal-soft", "shaderc", "subrandr", "uavs3d", "vulkan",
}
# Options that compile GPL code into a reachable library.
FORBIDDEN_OPTIONS = {
    "lcms2": ["-Dfastfloat=true", "-Dthreaded=true"],
    "libarchive": ["-DENABLE_LZO=ON"],
    "ffmpeg": ["--enable-gpl", "--enable-nonfree", "--enable-libzvbi"],
}
REQUIRED_OPTIONS = {
    "ffmpeg": ["--enable-version3", "--enable-schannel"],
    "mpv": ["-Dgpl=false"],
}


def main(root: Path) -> int:
    recipes = {}
    for path in sorted(root.glob("packages/*.cmake")) + sorted(root.glob("toolchain/*.cmake")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"ExternalProject_Add\((\S+)(.*?)\n\)", text, re.S):
            depends = re.search(r"DEPENDS(.*?)(?:\n\s*[A-Z_]{4,}\s)", match.group(2), re.S)
            recipes[match.group(1)] = (depends.group(1).split() if depends else [], match.group(2))

    reachable, stack, unresolved = set(), ["mpv"], []
    while stack:
        name = stack.pop()
        if name in reachable:
            continue
        reachable.add(name)
        for dependency in recipes.get(name, ([], ""))[0]:
            if dependency.startswith("${"):
                unresolved.append(f"{name}: {dependency}")
            else:
                stack.append(dependency)

    problems = [f"GPL package reachable: {name}" for name in sorted(reachable & GPL)]
    problems += [f"package outside the profile reachable: {name}" for name in sorted(reachable & DROPPED)]
    problems += [f"unresolved dependency variable: {item}" for item in unresolved]
    for name, options in FORBIDDEN_OPTIONS.items():
        body = recipes.get(name, ([], ""))[1]
        words = body.split()
        problems += [f"{name} enables {option}" for option in options if option in words]
    for name, options in REQUIRED_OPTIONS.items():
        words = recipes.get(name, ([], ""))[1].split()
        problems += [f"{name} lacks {option}" for option in options if option not in words]

    print(f"mpv dependency closure ({len(reachable)} packages):")
    for name in sorted(reachable):
        print(f"  {name}")
    for problem in problems:
        print(f"LGPL profile violation: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(Path(sys.argv[1])))
