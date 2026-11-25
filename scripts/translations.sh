#!/usr/bin/env bash
# Keeps translated documents in sync with their English source.
#
# Each translation starts with a marker that records the version of the source it was
# translated from, as the git blob hash of the source file:
#
#   <!-- translation-of: README.md sha:<git hash-object README.md> ... -->
#
# Usage:
#   scripts/translations.sh check          fail if any translation is behind its source (CI)
#   scripts/translations.sh sync [FILE...] after updating a translation, record the current
#                                          source version in its marker (all files by default)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

mode="${1:-check}"
shift || true

marker_re='^<!-- translation-of: ([^ ]+) sha:([^ ]+) '

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  mapfile -t files < <(git grep -l --untracked -e '^<!-- translation-of: ' -- '*.md')
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No translated documents found."
  exit 0
fi

status=0
for file in "${files[@]}"; do
  first_line="$(head -n 1 "$file")"
  if [[ ! "$first_line" =~ $marker_re ]]; then
    echo "error: $file does not start with a translation-of marker" >&2
    status=1
    continue
  fi
  source="${BASH_REMATCH[1]}"
  recorded="${BASH_REMATCH[2]}"
  current="$(git hash-object "$source")"

  case "$mode" in
    check)
      if [ "$recorded" = "$current" ]; then
        echo "ok: $file is up to date with $source"
      else
        message="$file is behind $source: update the translation, then run scripts/translations.sh sync $file"
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
          echo "::error file=$file,line=1::$message"
        else
          echo "error: $message" >&2
        fi
        status=1
      fi
      ;;
    sync)
      sed -i "1s/sha:[^ ]*/sha:$current/" "$file"
      echo "synced: $file -> $source@$current"
      ;;
    *)
      echo "usage: $0 check | sync [FILE...]" >&2
      exit 2
      ;;
  esac
done

exit "$status"
