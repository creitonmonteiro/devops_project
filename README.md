# DevOps Project

## GitHub Actions secrets

O workflow [.github/workflows/kubernetes-deploy.yaml](.github/workflows/kubernetes-deploy.yaml) separa valores fixos de ambiente e segredos obrigatorios.

Secrets obrigatorios no GitHub Actions:
- `SECRET_KEY`: chave usada pela aplicacao para assinar tokens.
- `POSTGRES_PASSWORD`: senha do usuario PostgreSQL usado pelo app e pela migration.

Valores fixos mantidos no workflow:
- Namespace `task-manager` e secret Kubernetes `task-manager-secrets`.
- Host e porta do banco `postgres-service:5432`.
- Banco `taskmanager`, usuario `taskmanager`, algoritmo `HS256` e expiracao `30`.

Durante o deploy, o workflow monta o arquivo `.env.k8s` em runtime e aplica o secret Kubernetes a partir dele.
