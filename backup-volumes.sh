#!/usr/bin/env bash
#
# backup-volumes.sh — back up Docker volumes (and bind mounts) to compressed
# tarballs with rotation, using a throwaway container so data is consistent.
#
# Usage:
#   ./backup-volumes.sh                       # back up ALL volumes
#   ./backup-volumes.sh wp-content db-data    # back up named volumes only
#   ./backup-volumes.sh --dir /srv/docker-bak --keep 14 --pause wp,db
#
# Options:
#   --dir DIR      destination directory (default: ./backups)
#   --keep N       keep the N most recent tarballs per volume (default: 7)
#   --pause LIST   comma-separated containers to STOP during backup, started after
#   --list         list volumes and exit
#
# Notes:
# - Bind mounts (source paths) are supported too — the tarball name is derived
#   from the basename of the source path.
# - Backups run through a temporary alpine container (--rm), so no tools need
#   installing on the host beyond Docker itself.
# - The tarball excludes nothing by default; keep volumes lean (see prune-docker.sh).

set -euo pipefail

DIR="./backups"
KEEP=7
PAUSE=""
declare -a VOLUMES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)   DIR="$2"; shift 2 ;;
        --keep)  KEEP="$2"; shift 2 ;;
        --pause) PAUSE="$2"; shift 2 ;;
        --list)
            echo "=== Docker volumes ==="
            docker volume ls --format '{{.Name}}'
            echo "=== Bind mounts in use ==="
            docker ps -q | xargs -r docker inspect --format \
                '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} ({{.Destination}}){{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u
            exit 0 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) VOLUMES+=("$1"); shift ;;
    esac
done

mkdir -p "$DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Resolve target list: explicit names, else every volume.
if [[ ${#VOLUMES[@]} -eq 0 ]]; then
    mapfile -t VOLUMES < <(docker volume ls -q)
fi
[[ ${#VOLUMES[@]} -gt 0 ]] || { echo "No volumes found."; exit 1; }

pause_containers() {
    [[ -n "$PAUSE" ]] || return 0
    echo "Pausing: $PAUSE"
    IFS=',' read -ra C <<<"$PAUSE"
    docker stop "${C[@]}" >/dev/null
}
resume_containers() {
    [[ -n "$PAUSE" ]] || return 0
    IFS=',' read -ra C <<<"$PAUSE"
    docker start "${C[@]}" >/dev/null
    echo "Resumed: $PAUSE"
}
trap resume_containers EXIT
pause_containers

ok=0; failed=0
for vol in "${VOLUMES[@]}"; do
    name="$(basename "$vol")"                      # safe tarball stem
    out="$DIR/${name}-${STAMP}.tar.gz"
    echo "-> backing up [$vol] to $(basename "$out")"

    # Named volume or bind-mount path?
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        mount_arg="-v ${vol}:/data:ro"
    elif [[ -e "$vol" ]]; then
        mount_arg="-v ${vol}:/data:ro"
    else
        echo "   SKIP: no such volume or path: $vol"
        failed=$((failed + 1))
        continue
    fi

    if docker run --rm $mount_arg -v "$DIR":/backup alpine:3.20 \
            tar -czf "/backup/$(basename "$out")" -C /data . 2>/dev/null; then
        ok=$((ok + 1))
    else
        echo "   FAILED: $vol"
        failed=$((failed + 1))
        continue
    fi

    # Rotation: keep newest $KEEP tarballs for this volume.
    mapfile -t old < <(ls -1t "$DIR/${name}"-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))")
    for f in "${old[@]:-}"; do
        [[ -n "${f:-}" ]] && rm -f "$f" && echo "   rotated: $(basename "$f")"
    done
done

echo "Done: $ok backed up, $failed failed."
[[ $failed -eq 0 ]]
