#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_url="https://github.com/shinchiro/mpv-winbuild-cmake.git"
upstream_commit="04283f7e911149809c46bc236a834cf7134ba133"
work="${WINDOWS_MEDIA_WORKDIR:-$root/.build/windows-media}"
source_dir="$work/mpv-winbuild-cmake"
build_dir="$work/build-x86_64"
sources_dir="$work/sources"
output="$root/dist/windows-media/current"
patch_file="$root/third_party/windows-media/mpv-winbuild-lgpl.patch"
archive_source=false

if [[ "${1:-}" == "--archive-source" ]]; then
  archive_source=true
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--archive-source]" >&2
  exit 2
fi

for command in git curl cmake ninja meson nasm yasm 7z jq sha256sum tar zstd; do
  command -v "$command" >/dev/null || {
    echo "Required Windows media build tool is missing: $command" >&2
    exit 1
  }
done

meson_python="$(head -n 1 "$(command -v meson)" | sed 's/^#!//')"
"$meson_python" -c 'import jinja2' 2>/dev/null || {
  echo "Meson's Python environment requires the jinja2 build dependency." >&2
  exit 1
}

# GitHub occasionally terminates concurrent HTTP/2 fetches in WSL. Keep all
# child Git processes conservative; Ninja provides the outer concurrency.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=http.version
export GIT_CONFIG_VALUE_0=HTTP/1.1
export GIT_CONFIG_KEY_1=http.maxRequests
export GIT_CONFIG_VALUE_1=2

case "$work" in
  "$root"/.build/windows-media|/tmp/klipa-windows-media) ;;
  *) echo "Refusing unapproved media work directory: $work" >&2; exit 1 ;;
esac

mkdir -p "$work" "$sources_dir" "$root/dist/windows-media"
if [[ ! -d "$source_dir/.git" ]]; then
  git clone --filter=blob:none "$upstream_url" "$source_dir"
  git -C "$source_dir" checkout --detach "$upstream_commit"
  git -C "$source_dir" apply --check "$patch_file"
  git -C "$source_dir" apply "$patch_file"
  touch "$source_dir/.klipa-lgpl-profile"
else
  [[ "$(git -C "$source_dir" rev-parse HEAD)" == "$upstream_commit" ]] || {
    echo "Existing media build checkout is not the pinned revision." >&2
    exit 1
  }
  [[ -f "$source_dir/.klipa-lgpl-profile" ]] || {
    echo "Existing media build checkout lacks the Klipa LGPL profile marker." >&2
    exit 1
  }
fi

git -C "$source_dir" diff --check
grep -q -- '-Dgpl=false' "$source_dir/packages/mpv.cmake"
if grep -Eq -- '--enable-(gpl|nonfree)|--enable-lib(x264|x265|xvid|davs2|uavs3d)|-Dgpl=true' \
  "$source_dir/packages/ffmpeg.cmake" "$source_dir/packages/mpv.cmake"; then
  echo "GPL or nonfree media build option survived the release profile." >&2
  exit 1
fi

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
  -DTARGET_ARCH=x86_64-w64-mingw32 \
  -DGCC_ARCH=x86-64 \
  -DMAKEJOBS=4 \
  -DENABLE_CCACHE=ON \
  -DSINGLE_SOURCE_LOCATION="$sources_dir" \
  2>&1 | tee "$work/configure.log"

purge_incompatible_meson_builds() {
  local current recorded meson_private package_build package_name stamp_dir
  current="$(meson --version)"
  recorded="$(cat "$work/meson-version.txt" 2>/dev/null || true)"
  if [[ "$recorded" != "$current" ]]; then
    while IFS= read -r -d '' meson_private; do
      package_build="${meson_private%/meson-private}"
      case "$package_build" in
        "$build_dir"/packages/*-build)
          rm -rf -- "$package_build"
          mkdir -p "$package_build"
          package_name="$(basename "$package_build" -build)"
          stamp_dir="$(dirname "$package_build")/$package_name-stamp"
          find "$stamp_dir" -maxdepth 1 -type f \
            \( -name "$package_name-configure" -o -name "$package_name-build" \
               -o -name "$package_name-install" -o -name "$package_name-postremovebuild" \
               -o -name "$package_name-removebuild" -o -name "$package_name-force-meson-configure" \) \
            -delete 2>/dev/null || true
          ;;
        *) echo "Refusing unsafe Meson build cleanup: $package_build" >&2; return 1 ;;
      esac
    done < <(find "$build_dir/packages" -type d -name meson-private -print0 2>/dev/null)
  fi
  printf '%s\n' "$current" > "$work/meson-version.txt"
}

purge_incompatible_meson_builds

printf '%s\n' 'Aggregate download skipped; target builds fetch only reachable LGPL-profile dependencies.' \
  > "$work/download.log"

run_ninja() {
  local target="$1"
  local attempt
  for attempt in 1 2 3 4; do
    if ninja -C "$build_dir" -j 2 "$target"; then
      return 0
    fi
    if [[ "$attempt" -lt 4 ]]; then
      echo "Ninja target $target failed on attempt $attempt; retrying transient downloads."
      sleep 5
    fi
  done
  return 1
}

repair_partial_checkouts() {
  local repository remote commit slug archive attempt
  while IFS= read -r -d '' repository; do
    [[ -f "$repository/.klipa-codeload-repair" ]] && continue
    if find "$repository" -mindepth 1 -maxdepth 1 ! -name .git -print -quit | grep -q . &&
       ! git -C "$repository" status --short --untracked-files=no 2>/dev/null | grep -Eq '^( D|D )'; then
      continue
    fi

    remote="$(git -C "$repository" remote get-url origin)"
    commit="$(git -C "$repository" rev-parse HEAD)"
    case "$remote" in
      https://github.com/*.git) slug="${remote#https://github.com/}"; slug="${slug%.git}" ;;
      *) echo "Cannot repair empty non-GitHub checkout: $repository" >&2; return 1 ;;
    esac

    echo "Repairing empty partial checkout $slug at $commit."
    archive="$work/${slug//\//-}-$commit.tar.gz"
    for attempt in 1 2 3 4; do
      if curl --fail --location --http1.1 --retry 4 --retry-all-errors \
        --output "$archive" "https://codeload.github.com/$slug/tar.gz/$commit"; then
        break
      fi
      [[ "$attempt" -lt 4 ]] || return 1
      sleep 5
    done
    tar -xzf "$archive" --strip-components=1 -C "$repository"
    rm -f -- "$archive"
    # A failed promisor checkout can leave every path deleted in the index.
    # Re-read the pinned tree without contacting the remote, then verify the
    # archive content against it.
    git -C "$repository" read-tree HEAD
    # Source archives honor export-ignore and can omit CI or maintainer files.
    # No path supplied by the archive may differ from the pinned Git tree.
    if git -C "$repository" diff --name-only --diff-filter=MARC HEAD -- . | grep -q .; then
      echo "Reconstructed checkout changes pinned Git content: $repository" >&2
      return 1
    fi
    touch "$repository/.klipa-codeload-repair"
  done < <(find "$sources_dir" -mindepth 1 -maxdepth 2 -type d -name .git -printf '%h\0')
}

run_ninja gcc 2>&1 | tee "$work/gcc.log"
repair_partial_checkouts
run_ninja mpv 2>&1 | tee "$work/mpv.log"

dll="$(find "$build_dir" -type f -path '*/mpv-dev-*/*' -name libmpv-2.dll -print -quit)"
[[ -f "$dll" ]] || {
  echo "The LGPL libmpv build completed without libmpv-2.dll." >&2
  exit 1
}

staging="$root/dist/windows-media/.current-staging"
case "$staging" in
  "$root"/dist/windows-media/.current-staging) rm -rf -- "$staging" ;;
  *) echo "Refusing unsafe media staging path: $staging" >&2; exit 1 ;;
esac
mkdir -p "$staging/licenses"
cp "$dll" "$staging/libmpv-2.dll"
cp "$patch_file" "$staging/mpv-winbuild-lgpl.patch"
cp "$build_dir/CMakeCache.txt" "$staging/CMakeCache.txt"
cp "$work/configure.log" "$work/download.log" "$work/gcc.log" "$work/mpv.log" "$staging/"
printf '%s\n' "$upstream_commit" > "$staging/mpv-winbuild-commit.txt"
{
  cmake --version | head -n 1
  ninja --version | sed 's/^/ninja /'
  meson --version | sed 's/^/meson /'
  "$build_dir/install/bin/cross-gcc" --version | head -n 1
  "$meson_python" -c 'import jinja2; print("jinja2 " + jinja2.__version__)'
} > "$staging/toolchain-versions.txt"

ninja -C "$build_dir" -t query packages/mpv |
  sed -n 's#.*packages/CMakeFiles/\(.*\)-complete#\1#p' |
  sort -u > "$staging/compiled-targets.txt"
printf '%s\n' cppwinrt mingw-w64 >> "$staging/compiled-targets.txt"
sort -u -o "$staging/compiled-targets.txt" "$staging/compiled-targets.txt"

find "$sources_dir" -mindepth 1 -maxdepth 2 -type d -name .git -print0 |
  sort -z |
  while IFS= read -r -d '' repository_git; do
    repository="${repository_git%/.git}"
    relative="${repository#"$sources_dir"/}"
    component="${relative%%/*}"
    grep -Fxq "$component" "$staging/compiled-targets.txt" || continue
    printf '%s\t%s\t%s\n' \
      "$relative" \
      "$(git -C "$repository" rev-parse HEAD)" \
      "$(git -C "$repository" remote get-url origin 2>/dev/null || printf unknown)"
  done > "$staging/source-revisions.tsv"

find "$sources_dir" -type f \
  \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'COPYRIGHT*' \) -print0 |
  sort -z |
  while IFS= read -r -d '' license; do
    relative="${license#"$sources_dir"/}"
    component="${relative%%/*}"
    grep -Fxq "$component" "$staging/compiled-targets.txt" || continue
    safe_name="${relative//\//__}"
    cp "$license" "$staging/licenses/$safe_name"
  done

(cd "$staging" && sha256sum libmpv-2.dll > libmpv-2.dll.sha256)
(cd "$staging" && sha256sum mpv-winbuild-lgpl.patch > mpv-winbuild-lgpl.patch.sha256)

if $archive_source; then
  archive="$staging/klipa-libmpv-corresponding-source.tar.zst"
  source_paths=(mpv-winbuild-cmake)
  while IFS= read -r component; do
    [[ -e "$sources_dir/$component" ]] && source_paths+=("sources/$component")
  done < "$staging/compiled-targets.txt"
  tar --sort=name --owner=0 --group=0 --numeric-owner \
    -I 'zstd -19 -T0' -cf "$archive" \
    -C "$work" "${source_paths[@]}"
  (cd "$staging" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
fi

rm -rf -- "$output"
mv "$staging" "$output"
echo "Windows LGPL media runtime: $output/libmpv-2.dll"
