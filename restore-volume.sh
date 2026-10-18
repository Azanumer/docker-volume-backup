#!/usr/bin/env bash
#
# restore-volume.sh — restore a Docker volume from a backup-volumes.sh tarball.
#
# Usage:
#   ./restore-volume.sh <volume-name> <backup.tar.gz>
#   ./restore-volume.sh wp-content ./backups/wp-content-20261018-101200.tar.gz
#
# Behaviour:
# - Creates the volume if it does not exist.
# - Refuses to restore into a volume that is currently mounted by a RUNNING
#   container (use --force to override; stop containers first).
# - Existing contents are wiped before restore (the tarball is authoritative).
# - Prints the tarball's top-level listing before restoring for a sanity check.

set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; shift; fi

VOL="${1:-}"; TARBALL="${2:-}"
[[ -n "$VOL" && -n "$TARBALL" ]] || { echo "Usage: $0 [--force] <volume> <tarball>"; exit 1; }
[[ -f "$TARBALL" ]] || { echo "Tarball not found: $TARBALL" >&2; exit 1; }

docker volume inspect "$VOL" >/dev/null 2>&1 || docker volume create "$VOL" >/dev/null

if [[ $FORCE -eq 0 ]]; then
    in_use="$(docker ps -q | xargs -r docker inspect --format \
        '{{range .Mounts}}{{if eq .Name "'"$VOL"'"}}{{.Name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u)"
    if [[ -n "$in_use" ]]; then
        echo "ERROR: volume '$VOL' is mounted by running containers. Stop them first or use --force." >&2
        exit 1
    fi
fi

echo "=== tarball contents (top level) ==="
tar -tzf "$TARBALL" | cut -d/ -f1-2 | sort -u | head -20
echo
read -r -p "Wipe volume '$VOL' and restore from $(basename "$TARBALL")? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

docker run --rm -v "${VOL}:/data" -v "$(dirname "$(realpath "$TARBALL")"):/backup:ro" alpine:3.20 \
    sh -c "rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null; tar -xzf /backup/$(basename "$TARBALL") -C /data"

echo "Restored '$VOL' from $(basename "$TARBALL")."
