# docker-volume-backup

Back up, restore, and prune **Docker volumes** with plain bash scripts — no
agent, no extra tools on the host beyond Docker itself. Backups run through a
throwaway `alpine` container so files are read consistently.

## Scripts

| Script | What it does |
|--------|--------------|
| `backup-volumes.sh` | Tars each volume (or bind-mount path) to `backups/<name>-<stamp>.tar.gz`, keeps the newest `--keep N` (default 7), can stop containers during backup with `--pause wp,db` |
| `restore-volume.sh` | Restores a tarball into a volume: refuses when running containers have it mounted (override with `--force`), previews tarball contents, wipes then restores |
| `prune-docker.sh` | Dry-run disk reclamation report by default (`--apply` to execute; `--images`/`--volumes` for aggressive tiers) |

## Examples

```bash
# Nightly cron: back up everything, keep 14 days, pause WP stack during backup
0 2 * * * /opt/docker-volume-backup/backup-volumes.sh --dir /srv/docker-bak --keep 14 --pause wordpress,mariadb

# Restore
./restore-volume.sh wp-content /srv/docker-bak/wp-content-20261018-020000.tar.gz

# See what prune would reclaim, without touching anything
./prune-docker.sh
```

## Notes

- Bind-mount source paths work as backup targets too (tarball named from the basename).
- `--volumes` prune is destructive to unreferenced data — run `backup-volumes.sh` first.
- Tested logic with `bash -n`; restore flow is interactive by design.

## License

MIT — see `LICENSE`.
