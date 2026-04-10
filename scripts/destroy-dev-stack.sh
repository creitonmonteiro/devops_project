#!/usr/bin/env sh
set -eu

NAMESPACE="task-manager"
SECRET_NAME="task-manager-secrets"
REMOVE_NAMESPACE=0
REMOVE_SECRET=0
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -s|--secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --remove-namespace)
            REMOVE_NAMESPACE=1
            shift
            ;;
        --remove-secret)
            REMOVE_SECRET=1
            shift
            ;;
        *)
            echo "Argumento invalido: $1" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

kubectl_path() {
    target_path=$1

    case "$KUBECTL_BIN" in
        *.exe|*.EXE)
            if command -v wslpath >/dev/null 2>&1; then
                wslpath -w "$target_path"
                return
            fi
            ;;
    esac

    printf '%s' "$target_path"
}

POSTGRES_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/postgres.yaml")
MIGRATION_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/migration.yaml")
APP_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/app.yaml")
GRAFANA_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/grafana.yaml")
PROMETHEUS_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/prometheus.yaml")

if ! command -v "$KUBECTL_BIN" >/dev/null 2>&1; then
    echo "Comando obrigatorio nao encontrado: $KUBECTL_BIN" >&2
    exit 1
fi

if ! "$KUBECTL_BIN" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace $NAMESPACE nao encontrado; nada para remover"
    exit 0
fi

"$KUBECTL_BIN" delete -f "$PROMETHEUS_MANIFEST" --ignore-not-found=true
"$KUBECTL_BIN" delete -f "$GRAFANA_MANIFEST" --ignore-not-found=true
"$KUBECTL_BIN" delete -f "$APP_MANIFEST" --ignore-not-found=true
"$KUBECTL_BIN" delete -f "$MIGRATION_MANIFEST" --ignore-not-found=true
"$KUBECTL_BIN" delete -f "$POSTGRES_MANIFEST" --ignore-not-found=true

if [ "$REMOVE_SECRET" -eq 1 ]; then
    "$KUBECTL_BIN" delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found=true
fi

if [ "$REMOVE_NAMESPACE" -eq 1 ]; then
    "$KUBECTL_BIN" delete namespace "$NAMESPACE" --ignore-not-found=true
else
    "$KUBECTL_BIN" get all -n "$NAMESPACE"
fi