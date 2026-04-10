#!/usr/bin/env sh
set -eu

NAMESPACE="task-manager"
ENV_FILE=".env.k8s"
SECRET_NAME="task-manager-secrets"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
MIGRATION_JOB_NAME="task-manager-migrate"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -e|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -s|--secret-name)
            SECRET_NAME="$2"
            shift 2
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

print_migration_diagnostics() {
    echo "Falha ao aguardar migration job $MIGRATION_JOB_NAME; coletando diagnostico..." >&2

    "$KUBECTL_BIN" describe job "$MIGRATION_JOB_NAME" -n "$NAMESPACE" || true

    migration_pod=$(
        "$KUBECTL_BIN" get pods -n "$NAMESPACE" -l "job-name=$MIGRATION_JOB_NAME" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
    )

    if [ -n "$migration_pod" ]; then
        echo "Logs do pod de migration: $migration_pod" >&2
        "$KUBECTL_BIN" logs -n "$NAMESPACE" "$migration_pod" --tail=200 || true
        "$KUBECTL_BIN" logs -n "$NAMESPACE" "$migration_pod" --previous --tail=200 || true
    else
        echo "Nenhum pod da migration encontrado para coleta de logs." >&2
    fi
}

print_deployment_diagnostics() {
    deployment_name=$1
    pod_label=$2

    echo "Falha ao aguardar rollout do deployment $deployment_name; coletando diagnostico..." >&2

    "$KUBECTL_BIN" describe deployment "$deployment_name" -n "$NAMESPACE" || true
    "$KUBECTL_BIN" describe pods -n "$NAMESPACE" -l "app=$pod_label" || true

    deployment_pods=$(
        "$KUBECTL_BIN" get pods -n "$NAMESPACE" -l "app=$pod_label" \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
    )

    if [ -z "$deployment_pods" ]; then
        echo "Nenhum pod encontrado para o deployment $deployment_name." >&2
        return
    fi

    for deployment_pod in $deployment_pods; do
        echo "Logs do pod $deployment_pod" >&2
        "$KUBECTL_BIN" logs -n "$NAMESPACE" "$deployment_pod" --all-containers=true --tail=200 || true
        "$KUBECTL_BIN" logs -n "$NAMESPACE" "$deployment_pod" --all-containers=true --previous --tail=200 || true
    done
}

wait_for_deployment_rollout() {
    deployment_name=$1
    pod_label=$2

    if ! "$KUBECTL_BIN" rollout status "deployment/$deployment_name" -n "$NAMESPACE"; then
        print_deployment_diagnostics "$deployment_name" "$pod_label"
        exit 1
    fi
}

NAMESPACE_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/namespace.yaml")
POSTGRES_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/postgres.yaml")
MIGRATION_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/migration.yaml")
APP_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/app.yaml")
GRAFANA_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/grafana.yaml")
PROMETHEUS_MANIFEST=$(kubectl_path "$ROOT_DIR/k8s/prometheus.yaml")

if ! command -v "$KUBECTL_BIN" >/dev/null 2>&1; then
    echo "Comando obrigatorio nao encontrado: $KUBECTL_BIN" >&2
    exit 1
fi

"$KUBECTL_BIN" apply -f "$NAMESPACE_MANIFEST"
KUBECTL_BIN="$KUBECTL_BIN" sh "$SCRIPT_DIR/apply-dev-secrets.sh" \
    --namespace "$NAMESPACE" \
    --secret-name "$SECRET_NAME" \
    --env-file "$ENV_FILE"

"$KUBECTL_BIN" apply -f "$POSTGRES_MANIFEST"
wait_for_deployment_rollout postgres postgres

"$KUBECTL_BIN" delete -f "$MIGRATION_MANIFEST" --ignore-not-found=true
"$KUBECTL_BIN" apply -f "$MIGRATION_MANIFEST"
if ! "$KUBECTL_BIN" wait --for=condition=complete --timeout=420s "job/$MIGRATION_JOB_NAME" -n "$NAMESPACE"; then
    print_migration_diagnostics
    exit 1
fi

"$KUBECTL_BIN" apply -f "$APP_MANIFEST"
wait_for_deployment_rollout task-manager-app task-manager-app

"$KUBECTL_BIN" apply -f "$GRAFANA_MANIFEST"
wait_for_deployment_rollout grafana grafana

"$KUBECTL_BIN" apply -f "$PROMETHEUS_MANIFEST"
wait_for_deployment_rollout prometheus prometheus

"$KUBECTL_BIN" get pods -n "$NAMESPACE"