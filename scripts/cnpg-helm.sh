#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

COMMAND=""
CHART="cluster"
RELEASE="cnpg"
NAMESPACE="default"
VALUES_FILE=""
OUTPUT_FILE=""
CREATE_NAMESPACE=true
INCLUDE_CRDS=false
DRY_RUN=false
WAIT=false
TIMEOUT=""
HELM_ARGS=()
VALUE_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  scripts/cnpg-helm.sh <command> [options] [-- extra helm args]

Commands:
  install        Install a chart with helm upgrade --install
  update         Update an existing release with helm upgrade
  delete         Delete a release with helm uninstall
  test-yaml      Validate chart YAML with helm lint and helm template
  export         Render chart output to standard Kubernetes YAML

Options:
  -c, --chart NAME|PATH       Chart name under ./charts or a chart path. Default: cluster
  -r, --release NAME          Helm release name. Default: cnpg
  -n, --namespace NAME        Kubernetes namespace. Default: default
  -f, --values FILE           Values file to pass to helm
  -s, --set KEY=VALUE         Helm --set override. Can be used multiple times
      --set-string KEY=VALUE  Helm --set-string override
      --set-json KEY=JSON     Helm --set-json override
      --set-file KEY=PATH     Helm --set-file override
  -o, --output FILE           Output file for export. Default: ./rendered/<release>-<chart>.yaml
      --include-crds          Include CRDs when templating/exporting
      --no-create-namespace   Do not pass --create-namespace on install
      --dry-run               Pass --dry-run to install/update/delete
      --wait                  Wait for install/update/delete completion
      --timeout DURATION      Helm timeout, for example 10m
  -h, --help                  Show this help

Examples:
  scripts/cnpg-helm.sh install -c cluster -r pg-prod -n cnpg-database -f values.yaml
  scripts/cnpg-helm.sh update -c cluster -r pg-prod -n cnpg-database --set cluster.instances=5
  scripts/cnpg-helm.sh delete -r pg-prod -n cnpg-database
  scripts/cnpg-helm.sh test-yaml -c cluster -f values.yaml
  scripts/cnpg-helm.sh export -c cluster -r pg-prod -n cnpg-database -f values.yaml -o rendered/pg-prod.yaml
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

chart_path() {
  if [[ -d "${REPO_ROOT}/charts/${CHART}" ]]; then
    printf '%s\n' "${REPO_ROOT}/charts/${CHART}"
  elif [[ -d "${CHART}" ]]; then
    printf '%s\n' "${CHART}"
  else
    fail "chart not found: ${CHART}"
  fi
}

chart_name() {
  basename "$(chart_path)"
}

append_values_args() {
  if [[ -n "${VALUES_FILE}" ]]; then
    [[ -f "${VALUES_FILE}" ]] || fail "values file not found: ${VALUES_FILE}"
    ARGS+=("--values" "${VALUES_FILE}")
  fi

  if [[ "${#VALUE_ARGS[@]}" -gt 0 ]]; then
    ARGS+=("${VALUE_ARGS[@]}")
  fi
}

append_common_args() {
  ARGS+=("--namespace" "${NAMESPACE}")
  append_values_args

  if [[ -n "${TIMEOUT}" ]]; then
    ARGS+=("--timeout" "${TIMEOUT}")
  fi

  if [[ "${WAIT}" == true ]]; then
    ARGS+=("--wait")
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    ARGS+=("--dry-run")
  fi
}

append_template_args() {
  ARGS+=("--namespace" "${NAMESPACE}")
  append_values_args

  if [[ "${INCLUDE_CRDS}" == true ]]; then
    ARGS+=("--include-crds")
  fi
}

append_helm_args() {
  if [[ "${#HELM_ARGS[@]}" -gt 0 ]]; then
    ARGS+=("${HELM_ARGS[@]}")
  fi
}

run_install() {
  local chart
  local -a ARGS=()
  chart="$(chart_path)"
  append_common_args

  if [[ "${CREATE_NAMESPACE}" == true ]]; then
    ARGS+=("--create-namespace")
  fi

  append_helm_args
  helm upgrade --install "${RELEASE}" "${chart}" "${ARGS[@]}"
}

run_update() {
  local chart
  local -a ARGS=()
  chart="$(chart_path)"
  append_common_args
  append_helm_args
  helm upgrade "${RELEASE}" "${chart}" "${ARGS[@]}"
}

run_delete() {
  local -a ARGS=("--namespace" "${NAMESPACE}")

  if [[ "${DRY_RUN}" == true ]]; then
    ARGS+=("--dry-run")
  fi

  if [[ "${WAIT}" == true ]]; then
    ARGS+=("--wait")
  fi

  if [[ -n "${TIMEOUT}" ]]; then
    ARGS+=("--timeout" "${TIMEOUT}")
  fi

  append_helm_args
  helm uninstall "${RELEASE}" "${ARGS[@]}"
}

run_test_yaml() {
  local chart
  local template_out
  local -a ARGS=()
  local -a LINT_ARGS=()
  chart="$(chart_path)"
  append_template_args
  template_out="$(mktemp)"

  if [[ -n "${VALUES_FILE}" ]]; then
    LINT_ARGS+=("--values" "${VALUES_FILE}")
  fi
  if [[ "${#HELM_ARGS[@]}" -gt 0 ]]; then
    LINT_ARGS+=("${HELM_ARGS[@]}")
  fi
  append_helm_args

  trap 'rm -f "${template_out}"' RETURN
  helm lint "${chart}" "${LINT_ARGS[@]}"
  helm template "${RELEASE}" "${chart}" "${ARGS[@]}" >"${template_out}"

  if command -v kubectl >/dev/null 2>&1; then
    kubectl apply --dry-run=client --validate=false -f "${template_out}" >/dev/null
  else
    echo "kubectl not found; skipped client-side Kubernetes YAML validation" >&2
  fi

  echo "YAML build succeeded: ${chart}"
}

run_export() {
  local chart
  local -a ARGS=()
  chart="$(chart_path)"
  append_template_args

  if [[ -z "${OUTPUT_FILE}" ]]; then
    OUTPUT_FILE="${REPO_ROOT}/rendered/${RELEASE}-$(chart_name).yaml"
  fi

  mkdir -p "$(dirname "${OUTPUT_FILE}")"
  append_helm_args
  helm template "${RELEASE}" "${chart}" "${ARGS[@]}" >"${OUTPUT_FILE}"
  echo "Exported Kubernetes YAML to ${OUTPUT_FILE}"
}

need_value() {
  [[ $# -ge 2 && -n "$2" ]] || fail "missing value for $1"
}

parse_args() {
  [[ $# -gt 0 ]] || {
    usage
    exit 1
  }

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  COMMAND="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--chart)
        need_value "$@"
        CHART="$2"
        shift 2
        ;;
      -r|--release)
        need_value "$@"
        RELEASE="$2"
        shift 2
        ;;
      -n|--namespace)
        need_value "$@"
        NAMESPACE="$2"
        shift 2
        ;;
      -f|--values)
        need_value "$@"
        VALUES_FILE="$2"
        shift 2
        ;;
      -s|--set|--set-string|--set-json|--set-file)
        need_value "$@"
        VALUE_ARGS+=("$1" "$2")
        shift 2
        ;;
      -o|--output)
        need_value "$@"
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --include-crds)
        INCLUDE_CRDS=true
        shift
        ;;
      --no-create-namespace)
        CREATE_NAMESPACE=false
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --wait)
        WAIT=true
        shift
        ;;
      --timeout)
        need_value "$@"
        TIMEOUT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        HELM_ARGS+=("$@")
        break
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  require_cmd helm

  case "${COMMAND}" in
    install)
      run_install
      ;;
    update)
      run_update
      ;;
    delete|uninstall)
      run_delete
      ;;
    test-yaml|test|lint)
      run_test_yaml
      ;;
    export|render)
      run_export
      ;;
    *)
      fail "unknown command: ${COMMAND}"
      ;;
  esac
}

main "$@"
