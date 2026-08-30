#requires -Version 5.1
<#
.SYNOPSIS
  Einmalige GitOps-Einrichtung auf einem DigitalOcean-Cluster:
  nginx-Ingress + ArgoCD installieren, App-Secret anlegen, ArgoCD-Application anwenden.
  Danach laeuft alles automatisch: Push -> Pipeline -> ArgoCD -> Cluster.

.BEISPIELE
  # Cluster existiert & ist verbunden:
  .\setup-gitops.ps1

  # Cluster frisch erstellen und einrichten:
  .\setup-gitops.ps1 -ClusterName teko-doks -CreateCluster
#>
param(
  [string]$ClusterName  = "",
  [switch]$CreateCluster,
  [string]$Region       = "fra1",
  [string]$NodeSize     = "s-2vcpu-4gb",
  [int]   $NodeCount    = 2,
  [string]$AppNamespace = "user-mgmt",
  [switch]$Force
)
$ErrorActionPreference = "Stop"
function Need($c){ if(-not(Get-Command $c -ErrorAction SilentlyContinue)){ throw "Werkzeug '$c' fehlt auf dem PATH." } }
Need doctl; Need kubectl; Need helm

# 1) Cluster
if ($CreateCluster) {
  if ($ClusterName -eq "") { throw "-CreateCluster benoetigt -ClusterName." }
  Write-Host "==> Erstelle DOKS-Cluster '$ClusterName'..." -ForegroundColor Cyan
  doctl kubernetes cluster create $ClusterName --region $Region `
    --node-pool "name=worker-pool;size=$NodeSize;count=$NodeCount" --wait | Out-Host
} elseif ($ClusterName -ne "") {
  doctl kubernetes cluster kubeconfig save $ClusterName | Out-Host
}
Write-Host "==> Kontext: $(kubectl config current-context)" -ForegroundColor Yellow
kubectl get nodes | Out-Host
if (-not $Force) { if ((Read-Host "Auf DIESEM Cluster einrichten? (y/n)") -ne "y") { return } }

# 2) nginx Ingress-Controller
Write-Host "==> nginx Ingress-Controller..." -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null | Out-Null
helm repo update ingress-nginx 2>$null | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.publishService.enabled=true | Out-Host
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s | Out-Host

# 3) ArgoCD installieren
Write-Host "==> ArgoCD installieren..." -ForegroundColor Cyan
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - | Out-Host
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml | Out-Host
Write-Host "   Warte auf ArgoCD..." -ForegroundColor DarkGray
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s | Out-Host

# 4) App-Namespace + Secret (einmalig erzeugt, lokal gespeichert)
kubectl create namespace $AppNamespace --dry-run=client -o yaml | kubectl apply -f - | Out-Host
$secretFile = ".\do-secrets.json"
if (Test-Path $secretFile) {
  $s = Get-Content $secretFile -Raw | ConvertFrom-Json
} else {
  $jwt  = -join ((1..64) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
  $dbpw = -join ((1..24) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
  $s = [pscustomobject]@{ JWT_SECRET=$jwt; DB_PASSWORD=$dbpw }
  $s | ConvertTo-Json | Set-Content $secretFile -Encoding utf8
  Write-Host "   do-secrets.json erzeugt -> NICHT committen (.gitignore)!" -ForegroundColor Yellow
}
kubectl create secret generic app-secret -n $AppNamespace `
  --from-literal=SPRING_DATASOURCE_PASSWORD="$($s.DB_PASSWORD)" `
  --from-literal=JWT_SECRET="$($s.JWT_SECRET)" `
  --dry-run=client -o yaml | kubectl apply -f - | Out-Host

# 5) ArgoCD-Application anwenden
Write-Host "==> ArgoCD-Application anwenden..." -ForegroundColor Cyan
kubectl apply -f ".\application.yaml" | Out-Host

# 6) Zugang ausgeben
Write-Host "`n===================== FERTIG =====================" -ForegroundColor Green
$pw = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$pw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pw))
Write-Host "ArgoCD Login:  admin  /  $pw" -ForegroundColor Cyan
Write-Host "Dashboard:     kubectl port-forward svc/argocd-server -n argocd 8080:443   -> https://localhost:8080" -ForegroundColor Cyan
Write-Host "App-URL:       kubectl get svc ingress-nginx-controller -n ingress-nginx   (EXTERNAL-IP)" -ForegroundColor Cyan
Write-Host "=================================================`n" -ForegroundColor Green
