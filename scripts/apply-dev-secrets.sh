#!/usr/bin/env sh
set -eu

NAMESPACE="task-manager"
SECRET_NAME="task-manager-secrets"
ENV_FILE=".env.k8s"
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
        -e|--env-file)
            ENV_FILE="$2"
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
NAMESPACE_MANIFEST="$ROOT_DIR/k8s/namespace.yaml"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Comando obrigatorio nao encontrado: $1" >&2
        exit 1
    fi
}

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

trim_value() {
    value=$1
    value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    case "$value" in
        \"*\")
            value=$(printf '%s' "$value" | sed 's/^"//; s/"$//')
            ;;
        \'*\')
            value=$(printf '%s' "$value" | sed "s/^'//; s/'$//")
            ;;
    esac

    printf '%s' "$value"
}

read_env_value() {
    key=$1

    awk -F= -v key="$key" '
        /^[[:space:]]*#/ { next }
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub("^[^=]*=", "", $0)
            print $0
            exit
        }
    ' "$ENV_FILE"
}

require_command awk
require_command sed
require_command "$KUBECTL_BIN"

if [ ! -f "$ENV_FILE" ]; then
    echo "Arquivo de variaveis nao encontrado: $ENV_FILE" >&2
    exit 1
fi

ENV_FILE_KUBECTL=$(kubectl_path "$ENV_FILE")
NAMESPACE_MANIFEST_KUBECTL=$(kubectl_path "$NAMESPACE_MANIFEST")

missing_keys=""
for key in \
    DATABASE_URL \
    SECRET_KEY \
    ALGORITHM \
    ACCESS_TOKEN_EXPIRE_MINUTES \
    POSTGRES_DB \
    POSTGRES_USER \
    POSTGRES_PASSWORD
do
    value=$(read_env_value "$key")
    value=$(trim_value "$value")

    if [ -z "$value" ]; then
        missing_keys="$missing_keys $key"
    fi
done

if [ -n "$missing_keys" ]; then
    echo "Chaves obrigatorias ausentes no arquivo $ENV_FILE:$missing_keys" >&2
    exit 1
fi

if ! "$KUBECTL_BIN" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    if [ -f "$NAMESPACE_MANIFEST" ]; then
        "$KUBECTL_BIN" apply -f "$NAMESPACE_MANIFEST_KUBECTL"
    else
        "$KUBECTL_BIN" create namespace "$NAMESPACE"
    fi
fi

"$KUBECTL_BIN" create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-env-file "$ENV_FILE_KUBECTL" \
    --dry-run=client \
    -o yaml | "$KUBECTL_BIN" apply -f -

echo "Secret $SECRET_NAME aplicado no namespace $NAMESPACE usando $ENV_FILE"