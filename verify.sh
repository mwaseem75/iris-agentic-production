#!/usr/bin/env bash
# Install check: runs AgenticProd.Verify.Run() inside the container. No LLM call, nothing of yours is changed.
# Usage: ./verify.sh [--strict]   (--strict counts a skipped replay step as a failure)
set -u
cd "$(dirname "$0")" || exit 1
strict=0
[ "${1:-}" = "--strict" ] && strict=1

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed or not on PATH" >&2; exit 1; }
docker compose ps -q iris | grep -q . || { echo "ERROR: the iris container is not running; start it with ./install.sh" >&2; exit 1; }

out="$(printf 'Do ##class(AgenticProd.Verify).Run(%s)\nHalt\n' "$strict" | docker compose exec -T iris iris session iris -U IRISAPP 2>&1)"
printf '%s\n' "$out" | grep -E '^(AgenticProd verify|PASS|FAIL|SKIP|Verify )'
printf '%s\n' "$out" | grep -q '^Verify PASSED'
