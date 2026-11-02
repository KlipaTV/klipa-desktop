"""Apply Klipa's LGPL profile to an mpv-winbuild-cmake checkout by meaning
(drop GPL and unused dependencies, switch their options off), so the patch can
be regenerated with `git diff` on a newer upstream revision. Run from the
checkout root after `git apply` of the hunks that still apply cleanly
(libplacebo.cmake, spirv-cross.cmake)."""

from pathlib import Path

FFMPEG_DROP = {
    "avisynth-headers", "libdvdnav", "libdvdread", "libmodplug", "x264",
    "${ffmpeg_x265}", "xvidcore", "libopenmpt", "libjxl", "shaderc",
    "libplacebo", "${ffmpeg_uavs3d}", "${ffmpeg_davs2}", "vapoursynth",
    "rubberband", "openal-soft",
    "--enable-gpl", "--enable-avisynth", "--enable-vapoursynth",
    "--enable-libdvdnav", "--enable-libdvdread", "--enable-libmodplug",
    "--enable-libopenmpt", "--enable-librubberband", "--enable-libx264",
    "--enable-libx265", "${ffmpeg_davs2_cmd}", "${ffmpeg_uavs3d_cmd}",
    "--enable-libxvid", "--enable-libjxl", "--enable-libshaderc",
    "--enable-openal",
}
MPV_DROP = {
    "libdvdnav", "libdvdread", "luajit", "rubberband", "openal-soft", "mujs",
    "vulkan", "shaderc", "spirv-cross", "vapoursynth", "libsdl2", "subrandr",
    "libsixel",
}
MPV_DISABLE = [
    "pdf-build", "lua", "javascript", "sdl2-gamepad", "dvdnav", "rubberband",
    "openal", "spirv-cross", "vulkan", "vapoursynth", "subrandr", "sixel",
]


def rewrite(path, fn):
    p = Path(path)
    lines = p.read_text(encoding="utf-8").split("\n")
    out, report = fn(lines)
    p.write_text("\n".join(out), encoding="utf-8")
    print(path, report)


def ffmpeg(lines):
    out, seen = [], set()
    for line in lines:
        s = line.strip()
        if s in FFMPEG_DROP:
            seen.add(s)
            continue
        if s == "--enable-libplacebo":
            indent = line[: len(line) - len(line.lstrip())]
            out += [indent + "--disable-libplacebo", indent + "--disable-vulkan"]
            seen.add(s)
            continue
        out.append(line)
    missing = sorted(FFMPEG_DROP - seen)
    assert "--enable-libplacebo" in seen and "--enable-gpl" in seen, "ffmpeg profile anchors missing"
    return out, f"dropped {len(seen)}; not present upstream: {missing}"


def mpv(lines):
    out, seen, disabled = [], set(), []
    in_depends = False
    for line in lines:
        s = line.strip()
        if s == "DEPENDS":
            in_depends = True
        elif s.startswith("GIT_REPOSITORY"):
            in_depends = False
        if in_depends and s in MPV_DROP:
            seen.add(s)
            continue
        if "mpv.pdf" in s:
            seen.add("mpv.pdf")
            continue
        for option in MPV_DISABLE:
            if s == f"-D{option}=enabled":
                line = line.replace("=enabled", "=disabled")
                disabled.append(option)
        if s == "-Dc_args='-Wno-error=int-conversion'":
            line = line.replace("int-conversion'", "int-conversion -DEGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE=0x3207'")
            seen.add("c_args")
        out.append(line)
        if s == "-Dlibmpv=true":
            out.append(line.replace("-Dlibmpv=true", "-Dgpl=false"))
            seen.add("gpl")
    assert {"gpl", "c_args", "mpv.pdf"} <= seen, f"mpv profile anchors missing: {seen}"
    return out, f"dropped/changed {sorted(seen)}; disabled {disabled}; not present: {sorted(set(MPV_DISABLE) - set(disabled))}"


def cppwinrt(lines):
    old = "https://github.com/microsoft/windows-rs/raw/master/crates/libs/default/Windows.winmd"
    new = "https://github.com/microsoft/windows-rs/raw/8786f59d1f6bc216324b202ec17d3de696d3b843/crates/libs/default/Windows.winmd"
    out = []
    for line in lines:
        if old in line:
            indent = "    "
            out += [
                indent + "# Windows.winmd is read from windows-rs `master`, which moves; fetch",
                indent + "# the revision master served when this mpv-winbuild-cmake commit was made.",
            ]
            line = line.replace(old, new)
        out.append(line)
    assert any(new in l for l in out), "winmd URL not found"
    return out, "pinned windows-rs 8786f59"


rewrite("packages/ffmpeg.cmake", ffmpeg)
rewrite("packages/mpv.cmake", mpv)
rewrite("toolchain/cppwinrt.cmake", cppwinrt)
