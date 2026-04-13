# DevOps Project

Projeto Devops para executar a aplicação Task Manager em Kubernetes, com automação de deploy/destruição, migrações de banco, observabilidade com Prometheus e Grafana, e teste de carga com k6.

## Objetivo

Este repositório concentra os manifests e scripts de operação do ambiente:

- Provisionar namespace e recursos da stack.
- Aplicar secrets de ambiente para app, banco e migration.
- Subir PostgreSQL, rodar migration e publicar a aplicação.
- Habilitar monitoramento com Prometheus e dashboard no Grafana.
- Executar deploy automático via GitHub Actions em runner self-hosted.

## Estrutura do repositório

Os manifests Kubernetes estão divididos em arquivos separados por responsabilidade — namespace, banco de dados, migração, aplicação e observabilidade — para permitir que cada componente seja aplicado, atualizado ou removido de forma independente sem afetar os demais. Isso facilita a leitura, o versionamento granular e a automação orquestrada pelos scripts, que aplicam os manifests em ordem de dependência respeitando o ciclo de vida da stack.

```text
.
|-- k8s/
|   |-- namespace.yaml
|   |-- postgres.yaml
|   |-- migration.yaml
|   |-- app.yaml
|   |-- grafana.yaml
|   `-- prometheus.yaml
|-- scripts/
|   |-- apply-dev-secrets.sh
|   |-- apply-dev-stack.sh
|   |-- destroy-dev-stack.sh
|   `-- loadtest.js
|-- .github/workflows/
|   `-- kubernetes-deploy.yaml
|-- .env.k8s.example
`-- README.md
```

## Arquitetura da stack

1. O namespace `task-manager` é criado.
2. O secret `task-manager-secrets` é aplicado a partir de `.env.k8s`.
3. O deployment PostgreSQL sobe com service interno `postgres-service:5432`.
4. O job `task-manager-migrate` executa `alembic upgrade head`.
5. O deployment da aplicação `task-manager-app` sobe com 4 réplicas e probes HTTP em `/health`.
6. O Prometheus sobe com configuração de scrape e node-exporter no mesmo pod, usando o PVC `prometheus-pvc` para persistência da TSDB.
7. O Grafana sobe com datasource e dashboard provisionados via ConfigMap.

## Pre-requisitos

- Cluster Kubernetes acessível via contexto local do kubectl.
- kubectl instalado e funcional.
- Shell POSIX para scripts (`sh`/Git Bash).
- (Opcional) Minikube para ambiente local.
- (Opcional) k6 para teste de carga.

### Observacao para Windows

Se estiver usando Git Bash com cluster local no Windows, pode ser necessário executar os scripts com:

```bash
KUBECTL_BIN=kubectl.exe sh scripts/apply-dev-stack.sh
```

Isso evita divergência entre binário/contexto do kubectl quando ha mistura de ambientes.

## Configuracao de ambiente

1. Copie o exemplo e ajuste os valores:

```bash
cp .env.k8s.example .env.k8s
```

2. Campos obrigatorios em `.env.k8s`:

- `DATABASE_URL`
- `SECRET_KEY`
- `ALGORITHM`
- `ACCESS_TOKEN_EXPIRE_MINUTES`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`

Exemplo de URL:

```text
postgresql+psycopg://taskmanager:senha@postgres-service:5432/taskmanager
```

## Deploy local

### 1) Aplicar apenas secrets

```bash
sh scripts/apply-dev-secrets.sh \
	--namespace task-manager \
	--secret-name task-manager-secrets \
	--env-file .env.k8s
```

### 2) Subir stack completa

```bash
sh scripts/apply-dev-stack.sh \
	--namespace task-manager \
	--secret-name task-manager-secrets \
	--env-file .env.k8s
```

O script aplica os manifests na ordem:

1. Namespace
2. Secrets
3. PostgreSQL
4. Migration
5. App
6. Grafana
7. Prometheus

Se migration ou rollout falhar, o script coleta diagnóstico automaticamente com `describe` e `logs`.

## Destruicao da stack

Remove workloads e services mantendo namespace e secret:

```bash
sh scripts/destroy-dev-stack.sh
```

Remover tambem secret:

```bash
sh scripts/destroy-dev-stack.sh --remove-secret
```

Remover namespace inteiro:

```bash
sh scripts/destroy-dev-stack.sh --remove-namespace
```

## Acesso aos servicos

Como os tipos de Service variam por ambiente, valide com:

```bash
kubectl get svc -n task-manager
```

Para Minikube, atalho comum:

```bash
minikube service task-manager-app-service -n task-manager --url
minikube service grafana -n task-manager --url
```

No driver Docker do Minikube no Windows, mantenha o terminal aberto durante o uso da URL tunelada.

## Observabilidade

O stack de observabilidade combina Prometheus para coleta e armazenamento de métricas e Grafana para visualização operacional do ambiente. No estado atual, o Prometheus faz scrape de si mesmo e do `node_exporter`, armazenando métricas de disponibilidade, volume de séries na TSDB, quantidade de amostras coletadas por scrape, taxa de ingestão de amostras, uso de memória do processo Prometheus e métricas de infraestrutura do nó, como uso de CPU, memória RAM e espaço livre em disco; essas informações são apresentadas no Grafana em painéis stat e séries temporais já provisionados automaticamente para acompanhamento rápido da saúde do monitoramento e do host.

### Prometheus

- Manifesto: `k8s/prometheus.yaml`
- Service interno: `prometheus-service:9090`
- Scrapes ativos:
	- `prometheus` (self)
	- `node_exporter` (127.0.0.1:9100)

### Grafana

- Manifesto: `k8s/grafana.yaml`
- Login padrao:
	- usuario: `admin`
	- senha: `admin123`
- Datasource Prometheus e dashboard principal sao provisionados automaticamente por ConfigMap.

## Teste de carga com k6

O script de teste executa dois cenários em paralelo durante 5 minutos cada: `create_users` usa executor `constant-arrival-rate` com taxa constante de 10 requisições por segundo distribuídas entre 10 VUs pré-alocadas (máximo 20) para simular criação concorrente de usuários, enquanto `get_users` usa executor `constant-vus` com 4 VUs constantes para leitura da listagem. Ambos executam checks de validação (status HTTP e estrutura de resposta) e coletam métricas padrão do k6: taxa de sucesso/erro, latência (p50, p95, p99), taxa de throughput e resultados detalhados de cada check, permitindo avaliar capacidade, performance e confiabilidade da API sob carga simulada.

Script: `scripts/loadtest.js`

Execucao:

```bash
k6 run scripts/loadtest.js
```

Definir endpoint alvo:

```bash
BASE_URL=http://127.0.0.1:8000 k6 run scripts/loadtest.js
```

## CI/CD com GitHub Actions

Workflow: `.github/workflows/kubernetes-deploy.yaml`

Dispara em push para `main`/`master` e manualmente (`workflow_dispatch`).

### Runner esperado

- `self-hosted`
- `windows`
- `minikube`

### Secrets exigidos

Opcao A (preferencial):

- `ENV_K8S` contendo o conteudo completo de `.env.k8s`

Opcao B (fallback no workflow):

- `SECRET_KEY`
- `POSTGRES_PASSWORD`

Com a opcao B, o workflow monta `.env.k8s` em runtime usando valores fixos de namespace, usuario, banco e algoritmo definidos no proprio pipeline.

## Troubleshooting rapido

1. App nao conecta no banco:
	 Verifique se o deployment `postgres` existe e se o service `postgres-service` esta no namespace correto.
2. Migration falha:
	 Confirme se todos os campos de secret foram aplicados, especialmente `DATABASE_URL`, `SECRET_KEY`, `ALGORITHM` e `ACCESS_TOKEN_EXPIRE_MINUTES`.
3. Prometheus em crash:
	 Confira se a chave esta escrita como `evaluation_interval` no ConfigMap.
4. Grafana sem datasource:
	 Confirme se o ConfigMap de datasource foi aplicado com `kind` correto e se o pod montou os volumes de provisioning.

## Comandos úteis de operação

```bash
kubectl get all -n task-manager
kubectl get jobs,pods,svc,deploy -n task-manager
kubectl logs -n task-manager deploy/task-manager-app --tail=200
kubectl logs -n task-manager job/task-manager-migrate --tail=200
kubectl describe pod -n task-manager <pod-name>
```

## Segurança

- Não use credenciais padrão fora de ambiente local.
- Não versione `.env.k8s` com valores reais de produção.
- Troque senha do Grafana e segredos da aplicação antes de expor o ambiente.
