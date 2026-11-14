#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
review_dir="$(mktemp -d /tmp/klip-phase3-checks.XXXXXX)"
trap 'rm -rf "$review_dir"' EXIT
sources=("${project_dir}"/Klip/**/*.swift)
sources=("${sources[@]:#*/KlipApp.swift}")
xcrun swiftc -parse-as-library -module-name KlipPhase3Checks -default-isolation MainActor \
    -o "${review_dir}/checks" "${sources[@]}" "${project_dir}/Tests/Phase3Checks.swift"
"${review_dir}/checks"
