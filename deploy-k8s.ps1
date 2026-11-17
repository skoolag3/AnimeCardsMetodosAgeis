param(
  [string]$EnvFile = '.env'
)

$ErrorActionPreference = 'Stop'
$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectl) {
  $dockerKubectl = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\kubectl.exe'
  if (-not (Test-Path $dockerKubectl)) { throw 'kubectl nao encontrado.' }
  $kubectl = $dockerKubectl
}

if (-not (Test-Path $EnvFile)) { throw "Arquivo $EnvFile nao encontrado. Copie .env.example e defina as senhas." }
$vars = @{}
Get-Content $EnvFile | ForEach-Object {
  if ($_ -match '^([A-Z_]+)=(.*)$') { $vars[$Matches[1]] = $Matches[2] }
}
foreach ($key in @('POSTGRES_PASSWORD', 'JWT_SECRET', 'GRAFANA_ADMIN_PASSWORD')) {
  if (-not $vars[$key] -or $vars[$key] -like 'troque-*') { throw "Defina $key em $EnvFile." }
}

& $kubectl config current-context | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Nenhum cluster Kubernetes configurado.' }

$rendered = (& $kubectl kustomize k8s) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao renderizar k8s/.' }
$docs = @($rendered -split '(?m)^---\s*$' | Where-Object { $_.Trim() })
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "animecards-k8s-$([guid]::NewGuid()).yaml"

function ApplyDocs([string[]]$selected) {
  ($selected -join "`n---`n") | Set-Content -LiteralPath $tempFile -Encoding utf8
  & $kubectl apply -f $tempFile
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar os manifests.' }
}

function KindOf([string]$doc) {
  if ($doc -match '(?m)^kind:\s*(\S+)') { return $Matches[1] }
  throw 'Manifest sem kind.'
}

function NameOf([string]$doc) {
  if ($doc -match '(?m)^metadata:\s*\r?\n\s+name:\s*(\S+)') { return $Matches[1] }
  throw 'Manifest sem metadata.name.'
}

try {
  ApplyDocs @($docs | Where-Object { (KindOf $_) -eq 'Namespace' })
  $dbUrl = "postgres://animecards:$($vars.POSTGRES_PASSWORD)@postgres:5432/animecards"
  & $kubectl -n animecards create secret generic animecards-secret `
    --from-literal="POSTGRES_PASSWORD=$($vars.POSTGRES_PASSWORD)" `
    --from-literal="JWT_SECRET=$($vars.JWT_SECRET)" `
    --from-literal="GRAFANA_ADMIN_PASSWORD=$($vars.GRAFANA_ADMIN_PASSWORD)" `
    --from-literal="DATABASE_URL=$dbUrl" `
    --from-literal="DIRECT_DATABASE_URL=$dbUrl" --dry-run=client -o yaml | & $kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar o Secret.' }

  ApplyDocs @($docs | Where-Object { (KindOf $_) -in @('ConfigMap', 'Service', 'StatefulSet') })
  & $kubectl -n animecards rollout status statefulset/postgres --timeout=300s
  if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL nao ficou pronto.' }

  ApplyDocs @($docs | Where-Object { (KindOf $_) -eq 'Job' })
  & $kubectl -n animecards wait --for=condition=complete job/animecards-migrate --timeout=300s
  if ($LASTEXITCODE -ne 0) { throw 'Migracao nao concluiu.' }

  foreach ($name in @('backend', 'frontend', 'prometheus', 'grafana', 'mailpit', 'cadvisor')) {
    ApplyDocs @($docs | Where-Object { (NameOf $_) -eq $name -and (KindOf $_) -in @('Deployment', 'DaemonSet') })
    $resource = if ($name -eq 'cadvisor') { 'daemonset/cadvisor' } else { "deployment/$name" }
    & $kubectl -n animecards rollout status $resource --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw "$resource nao ficou pronto." }
  }

  & $kubectl -n animecards get pods,svc,deploy,sts,ds,job
} finally {
  Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
}
