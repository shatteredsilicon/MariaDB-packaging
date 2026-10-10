#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
spec_file="$script_dir/../SPECS/MariaDB.spec"

usage() {
  cat >&2 <<'USAGE'
Usage: prep-mariadb.sh <branch|tag> <upstream-ref> <package-version>

Examples:
  prep-mariadb.sh branch 10.4.35 10.4.34.1
  prep-mariadb.sh tag mariadb-10.4.34 10.4.34
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

read_spec_global() {
  local macro_name="$1"
  awk -v macro_name="$macro_name" '
    $1 == "%global" && $2 == macro_name { print $3; found=1; exit }
    END { if (!found) exit 1 }
  ' "$spec_file"
}

download() {
  local url="$1"
  local output="$2"

  echo "Downloading: $url"
  wget --tries=3 --timeout=30 --no-verbose -O "$output" "$url"
  test -s "$output" || fail "downloaded file is empty: $output"
}

source_kind="${1:-}"
source_ref="${2:-}"
package_version="${3:-}"

if [[ -z "$source_kind" || -z "$source_ref" || -z "$package_version" ]]; then
  usage
  exit 2
fi

[[ -f "$spec_file" ]] || fail "spec file not found: $spec_file"
[[ "$source_kind" == "branch" || "$source_kind" == "tag" ]] || \
  fail "source kind must be 'branch' or 'tag': $source_kind"
[[ "$source_ref" =~ ^[A-Za-z0-9._/-]+$ ]] || \
  fail "upstream ref contains unsupported characters: $source_ref"
[[ "$source_ref" != /* && "$source_ref" != */ && "$source_ref" != *//* && "$source_ref" != *..* ]] || \
  fail "upstream ref has an unsafe path form: $source_ref"
[[ "$package_version" =~ ^[0-9]+([.][0-9]+){2,3}$ ]] || \
  fail "package version must look like 10.4.34 or 10.4.34.1: $package_version"

libmariadb_commit="$(read_spec_global libmariadb_commit)" || \
  fail "unable to read libmariadb_commit from $spec_file"
wolfssl_commit="$(read_spec_global wolfssl_commit)" || \
  fail "unable to read wolfssl_commit from $spec_file"

case "$source_kind" in
  branch)
    ref_namespace="heads"
    ;;
  tag)
    ref_namespace="tags"
    ;;
esac

source_archive="mariadb-server-mariadb-${package_version}.tar.gz"
connector_archive="mariadb-connector-c-${libmariadb_commit}.tar.gz"
wolfssl_archive="wolfssl-${wolfssl_commit}.tar.gz"

cd "$script_dir"
rm -f -- \
  mariadb-server-mariadb-*.tar.gz \
  mariadb-connector-c-*.tar.gz \
  wolfssl-*.tar.gz

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

upstream_download="$tmp_dir/mariadb-server.tar.gz"
extract_dir="$tmp_dir/extract"
mkdir -p -- "$extract_dir"

download \
  "https://github.com/shatteredsilicon/mariadb-server/archive/refs/${ref_namespace}/${source_ref}.tar.gz" \
  "$upstream_download"

tar -tzf "$upstream_download" >/dev/null || fail "invalid MariaDB source archive"
tar -xzf "$upstream_download" -C "$extract_dir"

mapfile -t source_roots < <(
  find "$extract_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
)
if [[ "${#source_roots[@]}" -ne 1 ]]; then
  fail "expected exactly one top-level source directory; found ${#source_roots[@]}"
fi

normalized_root="mariadb-server-mariadb-${package_version}"
if [[ "${source_roots[0]}" != "$normalized_root" ]]; then
  mv -- "$extract_dir/${source_roots[0]}" "$extract_dir/$normalized_root"
fi

tar -C "$extract_dir" -czf "$source_archive" "$normalized_root"

download \
  "https://github.com/MariaDB/mariadb-connector-c/archive/${libmariadb_commit}/${connector_archive}" \
  "$connector_archive"

download \
  "https://github.com/wolfSSL/wolfssl/archive/${wolfssl_commit}/${wolfssl_archive}" \
  "$wolfssl_archive"

printf 'Prepared MariaDB sources:\n'
printf '  source kind: %s\n' "$source_kind"
printf '  source ref:  %s\n' "$source_ref"
printf '  RPM version: %s\n' "$package_version"
printf '  Source0:     %s\n' "$source_archive"
printf '  Source1:     %s\n' "$connector_archive"
printf '  Source2:     %s\n' "$wolfssl_archive"
