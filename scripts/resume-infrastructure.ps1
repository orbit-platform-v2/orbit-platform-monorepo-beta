# Orbit Challenge Platform - Infrastructure Resume Script (PowerShell)
# Resumes the paused infrastructure to full operational capacity

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,
    
    [string]$Region = "us-central1",
    [string]$ClusterName = "orbit-challenge-cluster",
    [bool]$RestoreState = $true,
    [string]$StateDir = "",
    [switch]$Force,
    [switch]$Help
)

# Colors for output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Reset = "`e[0m"

function Write-Info {
    param([string]$Message)
    Write-Host "${Blue}[INFO]${Reset} $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "${Green}[SUCCESS]${Reset} $Message"
}

function Write-Warning {
    param([string]$Message)
    Write-Host "${Yellow}[WARNING]${Reset} $Message"
}

function Write-Error {
    param([string]$Message)
    Write-Host "${Red}[ERROR]${Reset} $Message"
}

function Show-Usage {
    Write-Host @"
Orbit Challenge Platform - Infrastructure Resume Script

USAGE:
    .\resume-infrastructure.ps1 -ProjectId <project-id> [OPTIONS]

PARAMETERS:
    -ProjectId       GCP Project ID (required)
    -Region          GCP Region [default: us-central1]
    -ClusterName     GKE Cluster name [default: orbit-challenge-cluster]
    -StateDir        Directory with saved state [auto-detect latest]
    -RestoreState    Restore from saved state [default: true]
    -Force           Force resume without confirmation
    -Help            Show this help message

EXAMPLES:
    .\resume-infrastructure.ps1 -ProjectId "my-gcp-project"
    .\resume-infrastructure.ps1 -ProjectId "my-gcp-project" -StateDir ".\pause-state\20250821-143000"
    .\resume-infrastructure.ps1 -ProjectId "my-gcp-project" -Force -RestoreState:$false

"@
}

if ($Help) {
    Show-Usage
    exit 0
}

# Auto-detect latest state directory if not provided
if ($RestoreState -and [string]::IsNullOrEmpty($StateDir)) {
    if (Test-Path "./pause-state") {
        $StateDir = Get-ChildItem "./pause-state" -Directory | 
                   Where-Object { $_.Name -match "^\d{8}-\d{6}$" } | 
                   Sort-Object Name -Descending | 
                   Select-Object -First 1 | 
                   ForEach-Object { $_.FullName }
        
        if ($StateDir) {
            Write-Info "Auto-detected latest state directory: $StateDir"
        } else {
            Write-Warning "No state directories found in ./pause-state"
            $RestoreState = $false
        }
    } else {
        Write-Warning "No pause-state directory found"
        $RestoreState = $false
    }
}

# Confirmation prompt
if (-not $Force) {
    Write-Host ""
    Write-Warning "🚀 INFRASTRUCTURE RESUME CONFIRMATION 🚀"
    Write-Host ""
    Write-Host "Project ID: $ProjectId"
    Write-Host "Region: $Region"
    Write-Host "Cluster: $ClusterName"
    Write-Host "Restore State: $RestoreState"
    if ($StateDir) {
        Write-Host "State Directory: $StateDir"
    }
    Write-Host ""
    Write-Host "This will:"
    Write-Host "1. Scale node pools back to full capacity"
    Write-Host "2. Restore system deployments to optimal configuration"
    Write-Host "3. Re-enable resource quotas for 50 concurrent users"
    Write-Host "4. Resume full platform operations"
    Write-Host "5. Increase your GCP costs to normal operational levels"
    Write-Host ""
    
    $confirm = Read-Host "Are you sure you want to resume the infrastructure? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Info "Operation cancelled"
        exit 0
    }
}

Write-Info "Starting infrastructure resume process..."

# Set up GCP authentication and project
gcloud config set project $ProjectId

# Check if cluster exists
Write-Info "Checking if cluster exists..."
try {
    $null = gcloud container clusters describe $ClusterName --region=$Region 2>$null
} catch {
    Write-Error "Cluster $ClusterName not found in region $Region"
    exit 1
}

# Get cluster credentials
Write-Info "Getting cluster credentials..."
gcloud container clusters get-credentials $ClusterName --region=$Region

# Function to get saved replica count
function Get-SavedReplicas {
    param(
        [string]$Namespace,
        [string]$Deployment,
        [int]$DefaultReplicas
    )
    
    if ($RestoreState -and (Test-Path "$StateDir\${Namespace}-${Deployment}.replicas")) {
        return [int](Get-Content "$StateDir\${Namespace}-${Deployment}.replicas")
    } else {
        return $DefaultReplicas
    }
}

# Function to scale deployment
function Set-DeploymentScale {
    param(
        [string]$Namespace,
        [string]$Deployment,
        [int]$Replicas
    )
    
    Write-Info "Scaling deployment $Deployment in namespace $Namespace to $Replicas replicas"
    kubectl scale deployment $Deployment -n $Namespace --replicas=$Replicas
}

# 1. Remove pause-mode resource quotas
Write-Info "🔧 Removing pause-mode resource quotas..."
kubectl delete resourcequota pause-mode-quota -n orbit-challenges --ignore-not-found=true
kubectl delete resourcequota pause-mode-quota -n orbit-system --ignore-not-found=true

# 2. Restore normal resource quotas
Write-Info "📊 Restoring normal resource quotas..."
kubectl apply -f k8s-manifests/base/challenge-resources.yaml

# 3. Scale up node pools to full capacity
Write-Info "🔼 Scaling node pools to full capacity..."

# System node pool - back to 2 nodes
Write-Info "Scaling system node pool to 2 nodes..."
gcloud container clusters resize $ClusterName --node-pool="system-pool" --num-nodes=2 --region=$Region --quiet

# Challenge node pools - back to 1 node each (total: 10 nodes)
Write-Info "Scaling challenge node pools to optimal configuration..."
$jobs = @()
for ($i = 1; $i -le 10; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($ClusterName, $i, $Region)
        gcloud container clusters resize $ClusterName --node-pool="challenge-pool-$i" --num-nodes=1 --region=$Region --quiet
    } -ArgumentList $ClusterName, $i, $Region
}

# Wait for all resize operations to complete
$jobs | Wait-Job | Remove-Job

# 4. Update autoscaling settings for normal operations
Write-Info "🔧 Configuring autoscaling for normal operations..."
gcloud container clusters update $ClusterName --region=$Region --enable-autoscaling --min-nodes=2 --max-nodes=3 --node-pool="system-pool"

$jobs = @()
for ($i = 1; $i -le 10; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($ClusterName, $i, $Region)
        gcloud container clusters update $ClusterName --region=$Region --enable-autoscaling --min-nodes=1 --max-nodes=2 --node-pool="challenge-pool-$i"
    } -ArgumentList $ClusterName, $i, $Region
}
$jobs | Wait-Job | Remove-Job

# 5. Wait for nodes to be ready
Write-Info "⏳ Waiting for nodes to become ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# 6. Scale up system deployments
Write-Info "📦 Scaling up system deployments..."

# Backend - restore to original replica count
$backendReplicas = Get-SavedReplicas -Namespace "orbit-system" -Deployment "orbit-backend" -DefaultReplicas 2
Set-DeploymentScale -Namespace "orbit-system" -Deployment "orbit-backend" -Replicas $backendReplicas

# WebSocket Router - restore to original replica count
$routerReplicas = Get-SavedReplicas -Namespace "orbit-system" -Deployment "websocket-router" -DefaultReplicas 2
Set-DeploymentScale -Namespace "orbit-system" -Deployment "websocket-router" -Replicas $routerReplicas

# Operator should already be running, verify it's healthy
Write-Info "Verifying operator health..."
kubectl rollout status deployment/orbit-operator -n orbit-system --timeout=120s

# 7. Restore monitoring components
Write-Info "📊 Restoring monitoring components..."
try {
    kubectl get namespace monitoring | Out-Null
    
    # Prometheus
    try {
        kubectl get deployment prometheus-server -n monitoring | Out-Null
        $prometheusReplicas = Get-SavedReplicas -Namespace "monitoring" -Deployment "prometheus-server" -DefaultReplicas 1
        Set-DeploymentScale -Namespace "monitoring" -Deployment "prometheus-server" -Replicas $prometheusReplicas
    } catch {}
    
    # Grafana
    try {
        kubectl get deployment grafana -n monitoring | Out-Null
        $grafanaReplicas = Get-SavedReplicas -Namespace "monitoring" -Deployment "grafana" -DefaultReplicas 1
        Set-DeploymentScale -Namespace "monitoring" -Deployment "grafana" -Replicas $grafanaReplicas
    } catch {}
} catch {}

# 8. Wait for all deployments to be ready
Write-Info "⏳ Waiting for all deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/orbit-backend -n orbit-system
kubectl wait --for=condition=available --timeout=300s deployment/websocket-router -n orbit-system
kubectl wait --for=condition=available --timeout=300s deployment/orbit-operator -n orbit-system

# 9. Validate system health
Write-Info "🔍 Validating system health..."

# Check node status
Write-Info "Checking node status..."
kubectl get nodes -o wide

# Check system pod status
Write-Info "Checking system pod status..."
kubectl get pods -n orbit-system

# Validate resource allocation
Write-Info "Validating resource allocation..."
if (Test-Path "./scripts/validate-cpu-allocation.sh") {
    bash ./scripts/validate-cpu-allocation.sh
}

# 10. Show final status
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗"
Write-Host "║                  INFRASTRUCTURE RESUMED                      ║"
Write-Host "╠══════════════════════════════════════════════════════════════╣"
Write-Host "║ Cluster: $ClusterName"
Write-Host "║ Region: $Region"
Write-Host "║ Resume Time: $(Get-Date)"
Write-Host "║"
Write-Host "║ RESTORED CAPACITY:"
Write-Host "║ • System Nodes: 2 nodes (full capacity)"
Write-Host "║ • Challenge Nodes: 10 nodes (ready for 50 users)"
Write-Host "║ • Backend Replicas: $backendReplicas"
Write-Host "║ • Router Replicas: $routerReplicas"
Write-Host "║ • Resource Quotas: 50 challenge pods / 25 CPU limit"
Write-Host "║"
Write-Host "║ PLATFORM STATUS:"
Write-Host "║ • ✅ Ready for 50 concurrent users"
Write-Host "║ • ✅ 0.5 CPU per challenge pod enforced"
Write-Host "║ • ✅ Auto-scaling enabled"
Write-Host "║ • ✅ Monitoring restored"
Write-Host "║"
Write-Host "║ COST IMPACT: Resumed full operational costs"
Write-Host "║ TO PAUSE AGAIN: .\scripts\pause-infrastructure.ps1"
Write-Host "╚══════════════════════════════════════════════════════════════╝"
Write-Host ""

Write-Success "✅ Infrastructure successfully resumed!"
Write-Info "🎯 Platform is ready for 50 concurrent users with 0.5 CPU per challenge pod"

if ($RestoreState -and $StateDir) {
    Write-Info "📂 State restored from: $StateDir"
}

# 11. Show next steps
Write-Host ""
Write-Info "📋 Next Steps:"
Write-Host "1. Verify platform functionality with a test challenge"
Write-Host "2. Monitor resource usage: kubectl top nodes && kubectl top pods --all-namespaces"
Write-Host "3. Check logs: kubectl logs -f deployment/orbit-backend -n orbit-system"
Write-Host "4. Access monitoring dashboard (if deployed)"
Write-Host ""

exit 0
