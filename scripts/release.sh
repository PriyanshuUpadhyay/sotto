#!/bin/sh
# Release from a clean main: bump the version, tag it, push, and follow the
# Release workflow (.github/workflows/release.yml), which builds, signs, and
# publishes the tag.
# Usage: scripts/release.sh patch|minor|major [--dry-run]
set -eu

die() { printf '%s\n' "release: $*" >&2; exit 1; }
dry=false
bump=
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry=true ;;
        patch|minor|major) [ -z "$bump" ] || die 'give one bump'; bump=$arg ;;
        *) die "unknown argument $arg" ;;
    esac
done
[ -n "$bump" ] || die 'usage: scripts/release.sh patch|minor|major [--dry-run]'
for tool in git gh python3; do
    command -v "$tool" >/dev/null || die "missing tool $tool"
done
root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
pbx="$root/Sotto.xcodeproj/project.pbxproj"

# Prints "old_version old_build new_version new_build"; with a fifth argument
# "write", also writes the new values into the project file.
versions() {
    python3 - "$pbx" "$bump" "${1:-}" <<'PY'
import re
import sys

path, bump, mode = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
blocks = re.findall(r"buildSettings = \{.*?\n\t\t\t\};", text, re.S)
app = [b for b in blocks if "PRODUCT_BUNDLE_IDENTIFIER = com.sotto.Sotto;" in b]
marketing = {m for b in app for m in re.findall(r"MARKETING_VERSION = ([^;]+);", b)}
builds = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", text))
if len(app) == 0 or len(marketing) != 1:
    sys.exit(f"release: expected one app MARKETING_VERSION, found {sorted(marketing)}")
if len(builds) != 1:
    sys.exit(f"release: expected one CURRENT_PROJECT_VERSION, found {sorted(builds)}")
old, build = marketing.pop(), builds.pop()
if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", old):
    sys.exit(f"release: {old} is not a major.minor.patch version")
if not build.isdigit():
    sys.exit(f"release: build number {build} is not an integer")
major, minor, patch = map(int, old.split("."))
if bump == "major":
    major, minor, patch = major + 1, 0, 0
elif bump == "minor":
    minor, patch = minor + 1, 0
else:
    patch += 1
new, new_build = f"{major}.{minor}.{patch}", str(int(build) + 1)
if mode == "write":
    def bump_block(block):
        if block in app:
            block = block.replace(f"MARKETING_VERSION = {old};", f"MARKETING_VERSION = {new};")
        return block
    text = re.sub(r"buildSettings = \{.*?\n\t\t\t\};", lambda m: bump_block(m[0]), text, flags=re.S)
    text = text.replace(f"CURRENT_PROJECT_VERSION = {build};", f"CURRENT_PROJECT_VERSION = {new_build};")
    open(path, "w").write(text)
print(old, build, new, new_build)
PY
}

current=$(versions)
read -r old build version new_build <<EOF
$current
EOF
tag=v$version

if "$dry"; then
    printf '%s\n' \
        "Bump $old ($build) to $version ($new_build), tag $tag." \
        'Require main, no changes outside tmp/, and HEAD = origin/main after git fetch.' \
        "Require tag $tag to be absent locally and on origin." \
        "Set MARKETING_VERSION and CURRENT_PROJECT_VERSION in Sotto.xcodeproj/project.pbxproj." \
        "Commit \"Bump to $version ($new_build)\", create annotated tag $tag, push main and the tag atomically." \
        'Watch the Release workflow for the tag; it builds, signs, uploads the DMG, then pushes docs/appcast.xml.' \
        'Pull the appcast commit into main.'
    exit 0
fi

[ "$(git -C "$root" branch --show-current)" = main ] || die 'run this from main'
changes=$(git -C "$root" status --porcelain --untracked-files=all -- . ':(exclude)tmp')
[ -z "$changes" ] || die 'the tree has changes outside tmp/'
git -C "$root" fetch origin
[ "$(git -C "$root" rev-parse HEAD)" = "$(git -C "$root" rev-parse origin/main)" ] || die 'HEAD differs from origin/main'
if git -C "$root" show-ref --verify --quiet "refs/tags/$tag"; then die "tag $tag already exists"; fi
[ -z "$(git -C "$root" ls-remote --tags origin "refs/tags/$tag")" ] || die "tag $tag already exists on origin"

versions write >/dev/null
git -C "$root" commit -m "Bump to $version ($new_build)" -- Sotto.xcodeproj/project.pbxproj
git -C "$root" tag -a "$tag" -m "$tag"
head=$(git -C "$root" rev-parse HEAD)
git -C "$root" push --atomic origin main "refs/tags/$tag" \
    || die "push failed; check origin before retrying. If nothing was pushed, run git -C \"$root\" tag -d $tag, then git -C \"$root\" reset --keep origin/main"

repo=$(gh repo view "$(git -C "$root" remote get-url origin)" --json nameWithOwner --jq .nameWithOwner)
printf '%s\n' "Pushed $tag. Waiting for the Release workflow..."
run=
tries=0
while [ -z "$run" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 30 ] || die "no Release run for $tag after 5 minutes; check https://github.com/$repo/actions"
    sleep 10
    run=$(gh run list -R "$repo" --workflow release.yml --commit "$head" --limit 1 --json databaseId --jq '.[0].databaseId // empty') || run=
done
gh run watch "$run" -R "$repo" --exit-status \
    || die "Release run $run failed. Fix it, then run gh run rerun $run -R $repo"
git -C "$root" pull --ff-only origin main
printf '%s\n' "Released $tag: https://github.com/$repo/releases/tag/$tag"
