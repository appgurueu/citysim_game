#!/usr/bin/env bash
#
# Verify that every upstream import commit is a byte-exact copy of upstream.
#
# An import commit is any commit whose message carries an `Upstream-Commit:` trailer.
# For each one this checks two things:
#
#   1. The tree at Local-Path is identical to the upstream tree at Upstream-Commit.
#      Git tree hashes are content-addressed, so an equal hash across two unrelated
#      repositories means the content is identical -- no file-by-file diff needed.
#   2. The commit touches nothing outside Local-Path.
#
# Together those mean the commit can be *verified* rather than read. Review effort
# then goes entirely to the commits that follow it, which carry the local changes.
#
# Submodule paths are handled too: there the gitlink must equal Upstream-Commit.
#
# Usage:
#   tools/verify-upstream-imports.sh [<rev-range>]      # default: HEAD
#
# Env:
#   CITYSIM_UPSTREAM_CACHE   where to cache upstream mirrors
#                            (default: ${XDG_CACHE_HOME:-~/.cache}/citysim-upstream)
#
# Exits non-zero if any import commit fails verification.

set -uo pipefail

RANGE="${1:-HEAD}"
CACHE="${CITYSIM_UPSTREAM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/citysim-upstream}"

if [ -t 1 ]; then
	R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
else
	R=""; G=""; Y=""; B=""; N=""
fi

cd "$(git rev-parse --show-toplevel)" || exit 2
mkdir -p "$CACHE"

trailer() {
	# trailer <commit> <key> -- prints the value, empty if absent
	git log -1 --format=%B "$1" | git interpret-trailers --parse \
		| sed -n "s/^$2: *//p" | head -1
}

# Fetch <commit> from <url> into a bare mirror, printing the mirror path.
# Tries a cheap single-commit fetch first; falls back to fetching all refs for
# servers that refuse arbitrary SHAs (uploadpack.allowReachableSHA1InWant off).
mirror_for() {
	local url="$1" want="$2" slug mirror
	slug=$(printf '%s' "$url" | tr -c 'A-Za-z0-9._-' '_')
	mirror="$CACHE/$slug.git"

	[ -d "$mirror" ] || git init --bare -q "$mirror" || return 1

	if git --git-dir="$mirror" cat-file -e "$want^{commit}" 2>/dev/null; then
		printf '%s' "$mirror"; return 0
	fi
	git --git-dir="$mirror" fetch -q --no-tags "$url" "$want" 2>/dev/null \
		|| git --git-dir="$mirror" fetch -q --tags "$url" '+refs/heads/*:refs/heads/*' 2>/dev/null \
		|| return 1

	git --git-dir="$mirror" cat-file -e "$want^{commit}" 2>/dev/null || return 1
	printf '%s' "$mirror"
}

mapfile -t COMMITS < <(git log --format=%H --grep='^Upstream-Commit:' "$RANGE")

if [ "${#COMMITS[@]}" -eq 0 ]; then
	printf '%sNo upstream import commits in %s.%s\n' "$Y" "$RANGE" "$N"
	printf 'Nothing to verify (this is not a failure).\n'
	exit 0
fi

pass=0; fail=0

for c in "${COMMITS[@]}"; do
	short=$(git rev-parse --short "$c")
	repo=$(trailer "$c" Upstream-Repo)
	want=$(trailer "$c" Upstream-Commit)
	sub=$(trailer "$c" Upstream-Subpath); sub="${sub:-.}"
	path=$(trailer "$c" Local-Path)
	subj=$(git log -1 --format=%s "$c")

	printf '%s%s%s  %s\n' "$B" "$short" "$N" "$subj"

	if [ -z "$repo" ] || [ -z "$want" ] || [ -z "$path" ]; then
		printf '  %sFAIL%s missing trailer (need Upstream-Repo, Upstream-Commit, Local-Path)\n' "$R" "$N"
		fail=$((fail + 1)); continue
	fi

	# (2) nothing outside Local-Path may be touched.
	stray=$(git show --pretty=format: --name-only "$c" | sed '/^$/d' | grep -v "^$path\(/\|$\)")
	if [ -n "$stray" ]; then
		printf '  %sFAIL%s touches paths outside %s:\n' "$R" "$N" "$path"
		printf '        %s\n' $stray
		fail=$((fail + 1)); continue
	fi

	mode=$(git ls-tree "$c" "$path" | awk '{print $1}')

	if [ "$mode" = "160000" ]; then
		# Submodule: the gitlink itself is the upstream commit.
		have=$(git ls-tree "$c" "$path" | awk '{print $3}')
		if [ "$have" = "$want" ]; then
			printf '  %sOK%s   submodule gitlink == %s\n' "$G" "$N" "${want:0:12}"
			pass=$((pass + 1))
		else
			printf '  %sFAIL%s gitlink %s != upstream %s\n' "$R" "$N" "${have:0:12}" "${want:0:12}"
			fail=$((fail + 1))
		fi
		continue
	fi

	if ! m=$(mirror_for "$repo" "$want"); then
		printf '  %sFAIL%s could not fetch %s from %s\n' "$R" "$N" "${want:0:12}" "$repo"
		fail=$((fail + 1)); continue
	fi

	if [ "$sub" = "." ]; then
		uptree=$(git --git-dir="$m" rev-parse "$want^{tree}" 2>/dev/null)
	else
		uptree=$(git --git-dir="$m" rev-parse "$want:$sub" 2>/dev/null)
	fi
	ourtree=$(git rev-parse "$c:$path" 2>/dev/null)

	if [ -z "$uptree" ]; then
		printf '  %sFAIL%s upstream has no tree at %s:%s\n' "$R" "$N" "${want:0:12}" "$sub"
		fail=$((fail + 1))
	elif [ "$uptree" = "$ourtree" ]; then
		printf '  %sOK%s   %s == %s at %s\n' "$G" "$N" "$path" "$sub" "${want:0:12}"
		pass=$((pass + 1))
	else
		printf '  %sFAIL%s tree mismatch: ours %s, upstream %s\n' "$R" "$N" "${ourtree:0:12}" "${uptree:0:12}"
		printf '        not a verbatim import -- local content leaked into the fetch commit\n'
		fail=$((fail + 1))
	fi
done

printf '\n'
if [ "$fail" -eq 0 ]; then
	printf '%s%d/%d import commits verified byte-exact.%s\n' "$G" "$pass" "${#COMMITS[@]}" "$N"
	exit 0
fi
printf '%s%d/%d FAILED%s (%d passed).\n' "$R" "$fail" "${#COMMITS[@]}" "$N" "$pass"
exit 1
