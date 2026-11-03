#!/usr/bin/env bash
# Pin the newest complete pi stable release in sources.json.
#
# Only prebuilt upstream release assets are referenced; nothing is built from
# source. The file is left untouched when no newer complete release exists.
#
# Environment:
#   PI_TAG  optional, pin this exact tag (e.g. v1.5.0)
set -euo pipefail

repo=earendil-works/pi
sources=sources.json
tag_override="${PI_TAG:-}"

[[ -f flake.nix ]] || { echo "Run from the repository root." >&2; exit 1; }
for tool in curl jq nix; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

github() {
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} "$@"
}

current=""
[[ -f "$sources" ]] && current="$(jq -r '.version // ""' "$sources")"

releases="$(github "https://api.github.com/repos/$repo/releases?per_page=100")"

# Select the newest stable release (by semantic version, not API order) whose
# required assets are all fully uploaded. Drafts and prereleases are ignored.
# Emits {latest, candidate}; candidate is null when nothing newer.
selection="$(jq -c --arg current "$current" --arg tag "$tag_override" '
  def stable: test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$");
  def key: ltrimstr("v") | split(".") | map(tonumber);
  def names: {
    "aarch64-darwin": "pi-darwin-arm64.tar.gz",
    "x86_64-linux": "pi-linux-x64.tar.gz",
    "aarch64-linux": "pi-linux-arm64.tar.gz"
  };
  def resolve:
    (.assets | map(select(.state == "uploaded")) | INDEX(.name)) as $a
    | {
        tag: .tag_name,
        version: (.tag_name | ltrimstr("v")),
        sums: ($a["SHA256SUMS"].browser_download_url // null),
        files: (names | map_values(
          $a[.] | if . == null then null else {url: .browser_download_url, digest: (.digest // null)} end
        ))
      };
  def complete: [.files[]] | all(. != null);

  ([.[]
    | select((.draft | not) and (.prerelease | not) and (.tag_name | stable))
    | select($tag == "" or .tag_name == $tag)]
   | sort_by(.tag_name | key) | reverse) as $releases
  | (if ($current | stable) then ($current | key) else [-1] end) as $pinned
  | {
      latest: ($releases[0].tag_name // null),
      candidate: (
        [$releases[] | resolve | select(complete)]
        | map(select($tag != "" or (.tag | key) > $pinned))
        | first // null
      )
    }
' <<<"$releases")"

latest="$(jq -r '.latest // empty' <<<"$selection")"
[[ -n "$latest" ]] || { echo "No stable release found${tag_override:+ for $tag_override}." >&2; exit 1; }

if [[ "$(jq -r '.candidate == null' <<<"$selection")" == true ]]; then
  if [[ "v$current" == "$latest" ]]; then
    echo "Already pinned to the newest release ($current)."
  else
    echo "Newest release $latest is incomplete or not newer; keeping ${current:-nothing pinned}."
  fi
  exit 0
fi

candidate="$(jq -c .candidate <<<"$selection")"
version="$(jq -r .version <<<"$candidate")"
echo "Pinning pi $version."

sums=""
sums_url="$(jq -r '.sums // empty' <<<"$candidate")"
if [[ -n "$sums_url" ]]; then
  sums="$(curl -fsSL --retry 3 "$sums_url")"
else
  echo "warning: $version has no SHA256SUMS; relying on GitHub asset digests." >&2
fi

hashes='{}'
while IFS=$'\t' read -r system url digest; do
  name="${url##*/}"
  hex=""
  if [[ "$digest" == sha256:* ]]; then
    hex="${digest#sha256:}"
  fi

  if [[ -n "$sums" ]]; then
    listed="$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1 }' <<<"$sums")"
    if [[ -z "$listed" ]]; then
      echo "$name is missing from SHA256SUMS." >&2
      exit 1
    fi
    if [[ -n "$hex" && "$listed" != "$hex" ]]; then
      echo "Digest mismatch for $name: GitHub=$hex SHA256SUMS=$listed" >&2
      exit 1
    fi
    hex="$listed"
  fi

  if [[ -n "$hex" ]]; then
    sri="$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$hex")"
  else
    echo "No published digest for $name; downloading to hash it." >&2
    sri="$(nix --extra-experimental-features nix-command store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"
  fi

  echo "  $system: $name"
  hashes="$(jq -c --arg k "$system" --arg v "$sri" '. + {($k): $v}' <<<"$hashes")"
done < <(jq -r '.files | to_entries[] | [.key, .value.url, (.value.digest // "")] | @tsv' <<<"$candidate")

tmp="$(mktemp "$sources.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
jq -n --argjson c "$candidate" --argjson h "$hashes" '
  {
    version: $c.version,
    tag: $c.tag,
    assets: ($c.files | with_entries(.value = {url: .value.url, hash: $h[.key]}))
  }
' >"$tmp"
mv "$tmp" "$sources"
trap - EXIT

echo "Pinned pi $version."
