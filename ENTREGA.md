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

1. Tenha um cluster configurado em `kubectl`. Para teste local, use `kind create cluster --name animecards`.
2. Copie `.env.example` para `.env` e defina as três senhas.
3. Execute `./deploy-k8s.ps1` no PowerShell para criar o Secret, aplicar os serviços em etapas e aguardar cada rollout. Em um cluster com recursos suficientes, também é possível criar o Secret a partir de `k8s/secret.example.yaml` e usar `kubectl apply -k k8s`.
4. Confira `kubectl -n animecards get pods,svc,deploy,sts,ds,job`.
5. Use `kubectl -n animecards port-forward svc/frontend 3000:3000`, `kubectl -n animecards port-forward svc/grafana 3002:3000` e `kubectl -n animecards port-forward svc/mailpit 8025:8025`.

O Secret de exemplo é apenas um molde. A URL do PostgreSQL precisa refletir a senha escolhida. Se o pacote GHCR estiver privado, crie um `imagePullSecret` e configure os Pods. O cAdvisor em Kubernetes depende de acesso ao host e pode exigir ajuste para o runtime do cluster; métricas da API continuam disponíveis sem ele.

## Validação local de 17/11/2026

O Docker Compose iniciou os sete serviços persistentes, aplicou as 42 migrações e respondeu HTTP 200 na aplicação, em `/api/health` e em `/metrics`. Prometheus mostrou os três alvos `up` e séries de CPU e memória por container. O dashboard e a regra de alerta foram carregados no Grafana. Ao parar o backend, Prometheus registrou `up = 0` e o Mailpit recebeu o e-mail `[FIRING:1] Backend indisponivel`; o backend foi restaurado.

Um cluster local `kind-animecards` foi criado. A implantação em etapas concluiu o Job de migração e deixou backend, frontend, PostgreSQL, Prometheus, Grafana, Mailpit e cAdvisor prontos (`1/1`). Por `port-forward`, a aplicação, `/api/health`, Prometheus e Grafana responderam HTTP 200. Os três alvos do Prometheus ficaram `up`, com séries de memória por container. O script `deploy-k8s.ps1` reproduz a ordem usada nessa validação. O alerta também foi provocado no Kubernetes: a regra ficou em `Firing`, o Mailpit recebeu a mensagem e o backend foi restaurado com HTTP 200.

## Prints da entrega

As capturas de tela da execução local estão em `evidencias/`: `grafana-dashboard-k8s.png`, `grafana-alertas-k8s.png`, `grafana-alerta-disparado-k8s.png`, `mailpit-alerta-k8s.png`, `k8s-cluster.png` e `k8s-deployment-backend.png`. As duas imagens Kubernetes apresentam a saída real dos comandos `kubectl` indicados na própria imagem, renderizada para leitura. O documento `Relatorio_Entrega_AnimeCards.docx` inclui as principais capturas. O Compose foi validado anteriormente, mas não estava em execução simultânea com o cluster no momento dos prints.
