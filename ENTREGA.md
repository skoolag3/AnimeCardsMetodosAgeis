# AnimeCards: Docker, Kubernetes e observabilidade

Este repositório contém uma cópia isolada do AnimeCards para a atividade de Métodos Ágeis. O frontend Next.js, backend NestJS e PostgreSQL rodam em containers. Prometheus coleta métricas da API e do cAdvisor; Grafana recebe dashboard e alerta provisionados por arquivos.

## Docker Compose

1. Copie `.env.example` para `.env` e substitua as três senhas.
2. Execute `docker compose up --build -d`.
3. Acesse a aplicação em `http://localhost:3000`, o Grafana em `http://localhost:3002`, o Prometheus em `http://localhost:9090` e a caixa de alertas em `http://localhost:8025`.
4. Confira `docker compose ps`, `curl http://localhost:3001/metrics` e `curl http://localhost:9090/api/v1/targets`.

O primeiro boot executa `prisma migrate deploy`. O PostgreSQL inicializa os papéis e a tabela de compatibilidade exigidos por migrações originalmente criadas no Supabase. A persistência de PostgreSQL, Prometheus e Grafana usa volumes nomeados. Recursos opcionais do aplicativo (Cloudinary, SMTP, Stripe, Google, IA) exigem credenciais próprias; o ambiente básico não as preenche.

## Kubernetes

O workflow `.github/workflows/images.yml` publica as imagens de frontend, backend e migração no GHCR em cada push à branch `main`. Depois de conferir que as três imagens estão acessíveis ao cluster:

1. Copie `k8s/secret.example.yaml` para um arquivo local fora do repositório e substitua as senhas e as URLs do banco.
2. Execute `kubectl apply -f k8s/namespace.yaml` e `kubectl apply -f <arquivo-secret-local>`.
3. Execute `kubectl apply -k k8s`.
4. Aguarde `kubectl -n animecards wait --for=condition=complete job/animecards-migrate --timeout=180s` e confira `kubectl -n animecards get pods,svc,deploy,sts,ds,job`.
5. Use `kubectl -n animecards port-forward svc/frontend 3000:3000`, `kubectl -n animecards port-forward svc/grafana 3002:3000` e `kubectl -n animecards port-forward svc/mailpit 8025:8025`.

O Secret de exemplo é apenas um molde. A URL do PostgreSQL precisa refletir a senha escolhida. Se o pacote GHCR estiver privado, crie um `imagePullSecret` e configure os Pods. O cAdvisor em Kubernetes depende de acesso ao host e pode exigir ajuste para o runtime do cluster; métricas da API continuam disponíveis sem ele.

## Validação local de 17/11/2026

O Docker Compose iniciou os sete serviços persistentes, aplicou as 42 migrações e respondeu HTTP 200 na aplicação, em `/api/health` e em `/metrics`. Prometheus mostrou os três alvos `up` e séries de CPU e memória por container. O dashboard e a regra de alerta foram carregados no Grafana. Um cluster `kind-animecards` foi criado e os manifests passaram por `kubectl apply -k k8s`, mas a máquina de 8 GB ficou sem memória suficiente para concluir simultaneamente os pulls dos Pods. O cluster local foi parado; a execução integral em Kubernetes e os respectivos prints ainda precisam ser refeitos em uma máquina com mais recursos.

## Prints da entrega

Após executar o ambiente, capture: dashboard `AnimeCards | Operacao` (incluindo disponibilidade, tráfego e containers); `Alerting > Alert rules`; um e-mail recebido no Mailpit; `docker compose ps`; `kubectl -n animecards get pods,svc,deploy,sts,ds,job`; e a tela de detalhes dos deployments. Salve em `evidencias/`. Nenhum print é fornecido como se o ambiente tivesse sido executado nesta máquina.
