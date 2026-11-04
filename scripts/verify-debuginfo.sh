#!/usr/bin/env bash
# Verify that the CPack-produced server debuginfo is available and non-empty.
# Fail before publishing; filename presence alone is not evidence of DWARF.
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <artifacts-directory> <version> <arch>" >&2
    exit 2
fi

artifacts_dir=$1
version=$2
arch=$3

shopt -s nullglob
server_debug=("${artifacts_dir}"/MariaDB-server-debuginfo-"${version}"-*."${arch}".rpm)
if [ "${#server_debug[@]}" -ne 1 ]; then
    echo "ERROR: expected one matching MariaDB-server-debuginfo RPM; found ${#server_debug[@]}" >&2
    exit 1
fi

for package in "${server_debug[@]}"; do
    name=$(rpm -qp --qf '%{NAME}' "$package")
    if [ "$name" != 'MariaDB-server-debuginfo' ]; then
        echo "ERROR: unexpected debuginfo RPM name: $name" >&2
        exit 1
    fi
    if ! rpm -qpl "$package" | grep -E '^/usr/lib/debug/.+\.debug$' > /dev/null; then
        echo "ERROR: $package does not contain any .debug ELF files" >&2
        exit 1
    fi
    echo "Validated debuginfo: $package"
done
