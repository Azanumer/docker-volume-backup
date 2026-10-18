#!/usr/bin/env bash
#
# prune-docker.sh — safe disk reclamation for a Docker host.
#
# Shows what WOULD be removed first (dry-run by default), then prunes:
#   1. Stopped containers, unused networks, dangling images, build cache
#   2. Optionally: ALL unused images (--images) and unused volumes (--volumes)
#
# Usage:
#   ./prune-docker.sh            # dry-run: report only
#   ./prune-docker.sh --apply    # actually prune (safe tier)
#   ./prune-docker.sh --apply --images --volumes   # aggressive
#
# DANGER: --volumes deletes data in volumes not referenced by any container
# (even stopped ones). Back up first (see backup-volumes.sh).

set -euo pipefail

APPLY=0; IMAGES=0; VOLUMES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)   APPLY=1; shift ;;
        --images)  IMAGES=1; shift ;;
        --volumes) VOLUMES=1; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

run() {  # run CMD or echo it in dry-run
    if [[ $APPLY -eq 1 ]]; then "$@"; else echo "  [dry-run] $*"; fi
}

echo "=== Docker disk usage ==="
docker system df

echo
echo "=== Plan ==="
echo "  - prune stopped containers, unused networks, dangling images, build cache"
[[ $IMAGES -eq 1  ]] && echo "  - prune ALL unused images (aggressive)"
[[ $VOLUMES -eq 1 ]] && echo "  - prune ALL unused volumes (DESTRUCTIVE — back up first)"
[[ $APPLY -eq 0   ]] && { echo; echo "Dry-run only. Re-run with --apply to execute."; exit 0; }

read -r -p "Execute the plan above? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "=== Pruning ==="
run docker container prune -f
run docker network prune -f
run docker image prune -f
run docker builder prune -f
[[ $IMAGES -eq 1  ]] && run docker image prune -a -f
[[ $VOLUMES -eq 1 ]] && run docker volume prune -f

echo
echo "=== After ==="
docker system df
