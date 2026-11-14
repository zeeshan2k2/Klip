#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
review_dir="$(mktemp -d /tmp/klip-phase4-checks.XXXXXX)"
trap 'rm -rf "$review_dir"' EXIT
sources=("${project_dir}"/Klip/**/*.swift)
sources=("${sources[@]:#*/KlipApp.swift}")
xcrun swiftc -parse-as-library -module-name KlipPhase4Checks -default-isolation MainActor \
    -o "${review_dir}/checks" "${sources[@]}" "${project_dir}/Tests/Phase4Checks.swift"
"${review_dir}/checks"
