# CNPG Helm Helper Script

Use `cnpg-helm.sh` to manage the charts in this repository with a consistent command line.

## Requirements

- `helm`
- `kubectl` for optional client-side validation in `test-yaml`

## Commands

### Install

Install a chart with `helm upgrade --install`.

```console
scripts/cnpg-helm.sh install -c cluster -r pg-prod -n cnpg-database -f values.yaml
```

### Update

Update an existing Helm release.

```console
scripts/cnpg-helm.sh update -c cluster -r pg-prod -n cnpg-database --set cluster.instances=5
```

### Delete

Delete an existing Helm release.

```console
scripts/cnpg-helm.sh delete -r pg-prod -n cnpg-database
```

### Test YAML

Run `helm lint`, render the chart with `helm template`, and validate the rendered YAML with `kubectl` when available.

```console
scripts/cnpg-helm.sh test-yaml -c cluster -r pg-prod -n cnpg-database -f values.yaml
```

### Export Kubernetes YAML

Render the Helm chart into standard Kubernetes manifests that can be reviewed or applied with `kubectl`.

```console
scripts/cnpg-helm.sh export -c cluster -r pg-prod -n cnpg-database -f values.yaml -o rendered/pg-prod.yaml
```

## Common Options

| Option | Description |
| --- | --- |
| `-c, --chart NAME\|PATH` | Chart name under `./charts` or a chart path. Defaults to `cluster`. |
| `-r, --release NAME` | Helm release name. Defaults to `cnpg`. |
| `-n, --namespace NAME` | Kubernetes namespace. Defaults to `default`. |
| `-f, --values FILE` | Values file to pass to Helm. |
| `-s, --set KEY=VALUE` | Helm `--set` override. Can be used multiple times. |
| `--set-string KEY=VALUE` | Helm `--set-string` override. |
| `--set-json KEY=JSON` | Helm `--set-json` override. |
| `--set-file KEY=PATH` | Helm `--set-file` override. |
| `-o, --output FILE` | Export output file. Defaults to `rendered/<release>-<chart>.yaml`. |
| `--include-crds` | Include CRDs when templating or exporting. |
| `--no-create-namespace` | Do not pass `--create-namespace` during install. |
| `--dry-run` | Pass `--dry-run` to install, update, or delete. |
| `--wait` | Wait for install, update, or delete completion. |
| `--timeout DURATION` | Helm timeout, for example `10m`. |

Pass extra Helm flags after `--`.

```console
scripts/cnpg-helm.sh install -c cluster -r pg-prod -n cnpg-database -- --debug
```
