# Orbit Challenge Platform - Infrastructure Pause Script (PowerShell)
# Pauses the infrastructure to save costs when not in use

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,
    
    [string]$Region = "us-central1",
    [string]$ClusterName = "orbit-challenge-cluster",
    [bool]$SaveState = $true,
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
Orbit Challenge Platform - Infrastructure Pause Script

USAGE:
    .\pause-infrastructure.ps1 -ProjectId <project-id> [OPTIONS]

PARAMETERS:
    -ProjectId     GCP Project ID (required)
    -Region        GCP Region [default: us-central1]
    -ClusterName   GKE Cluster name [default: orbit-challenge-cluster]
    -SaveState     Save current state before pause [default: true]
    -Force         Force pause without confirmation
    -Help          Show this help message

EXAMPLES:
    .\pause-infrastructure.ps1 -ProjectId "my-gcp-project"
    .\pause-infrastructure.ps1 -ProjectId "my-gcp-project" -Region "europe-west1" -Force

"@
}

if ($Help) {
    Show-Usage
    exit 0
}

# Confirmation prompt
if (-not $Force) {
    Write-Host ""
    Write-Warning "⚠️  INFRASTRUCTURE PAUSE CONFIRMATION ⚠️"
    Write-Host ""
    Write-Host "Project ID: $ProjectId"
    Write-Host "Region: $Region"
    Write-Host "Cluster: $ClusterName"
    Write-Host "Save State: $SaveState"
    Write-Host ""
    Write-Host "This will:"
    Write-Host "1. Scale down all non-essential workloads"
    Write-Host "2. Resize node pools to minimum (1 node per pool)"
    Write-Host "3. Save current deployment state (if enabled)"
    Write-Host "4. Significantly reduce your GCP costs"
    Write-Host ""
    
    $confirm = Read-Host "Are you sure you want to pause the infrastructure? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Info "Operation cancelled"
        exit 0
    }
}

Write-Info "Starting infrastructure pause process..."

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

# Create pause state directory
$PauseStateDir = "./pause-state/$(Get-Date -Format 'yyyyMMdd-HHmmss')"
if ($SaveState) {
    Write-Info "Creating state backup directory: $PauseStateDir"
    New-Item -ItemType Directory -Path $PauseStateDir -Force | Out-Null
}

# Function to save deployment state
function Save-DeploymentState {
    param(
        [string]$Namespace,
        [string]$Deployment
    )
    
    if ($SaveState) {
        Write-Info "Saving state for deployment $Deployment in namespace $Namespace"
        kubectl get deployment $Deployment -n $Namespace -o yaml > "$PauseStateDir\${Namespace}-${Deployment}.yaml"
        
        # Save replica count
        $replicas = kubectl get deployment $Deployment -n $Namespace -o jsonpath='{.spec.replicas}'
        $replicas | Out-File -FilePath "$PauseStateDir\${Namespace}-${Deployment}.replicas" -Encoding utf8
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

# 1. Save and scale down system deployments
Write-Info "📦 Scaling down system deployments..."

# Backend - scale to 1 replica (keep minimal functionality)
Save-DeploymentState -Namespace "orbit-system" -Deployment "orbit-backend"
Set-DeploymentScale -Namespace "orbit-system" -Deployment "orbit-backend" -Replicas 1

# WebSocket Router - scale to 1 replica
Save-DeploymentState -Namespace "orbit-system" -Deployment "websocket-router"
Set-DeploymentScale -Namespace "orbit-system" -Deployment "websocket-router" -Replicas 1

# Operator - keep running (essential for cluster management)
Write-Info "Keeping operator running (essential service)"

# 2. Save and terminate all challenge pods
Write-Info "🎯 Terminating all challenge pods..."
try {
    kubectl get namespace orbit-challenges | Out-Null
    
    # Save list of active challenge pods
    if ($SaveState) {
        kubectl get pods -n orbit-challenges -o yaml > "$PauseStateDir\challenge-pods.yaml"
        $podCount = (kubectl get pods -n orbit-challenges --no-headers | Measure-Object).Count
        $podCount | Out-File -FilePath "$PauseStateDir\challenge-pods.count" -Encoding utf8
    }
    
    # Delete all challenge pods
    kubectl delete pods --all -n orbit-challenges --grace-period=30
    Write-Success "All challenge pods terminated"
} catch {
    Write-Warning "Challenge namespace not found"
}

# 3. Scale down monitoring (if exists)
Write-Info "📊 Scaling down monitoring components..."
try {
    kubectl get namespace monitoring | Out-Null
    
    # Prometheus
    try {
        kubectl get deployment prometheus-server -n monitoring | Out-Null
        Save-DeploymentState -Namespace "monitoring" -Deployment "prometheus-server"
        Set-DeploymentScale -Namespace "monitoring" -Deployment "prometheus-server" -Replicas 0
    } catch {}
    
    # Grafana
    try {
        kubectl get deployment grafana -n monitoring | Out-Null
        Save-DeploymentState -Namespace "monitoring" -Deployment "grafana"
        Set-DeploymentScale -Namespace "monitoring" -Deployment "grafana" -Replicas 0
    } catch {}
} catch {}

# 4. Wait for pods to terminate
Write-Info "⏳ Waiting for pods to terminate..."
Start-Sleep -Seconds 30

# 5. Resize node pools to minimum
Write-Info "🔽 Resizing node pools to minimum..."

# System node pool - minimum 1 node
Write-Info "Resizing system node pool to 1 node..."
gcloud container clusters resize $ClusterName --node-pool="system-pool" --num-nodes=1 --region=$Region --quiet

# Challenge node pools - minimum 1 node each
Write-Info "Resizing challenge node pools to minimal configuration..."
for ($i = 1; $i -le 10; $i++) {
    gcloud container clusters resize $ClusterName --node-pool="challenge-pool-$i" --num-nodes=1 --region=$Region --quiet
}

# 6. Save pause metadata
if ($SaveState) {
    Write-Info "💾 Saving pause metadata..."
    $metadata = @{
        pause_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        project_id = $ProjectId
        region = $Region
        cluster_name = $ClusterName
        original_node_counts = @{
            system_pool = 2
            challenge_pools = 10
        }
        paused_by = $env:USERNAME
        pause_reason = "Cost optimization"
    } | ConvertTo-Json -Depth 3
    
    $metadata | Out-File -FilePath "$PauseStateDir\pause-metadata.json" -Encoding utf8
    Write-Success "State saved to: $PauseStateDir"
}

# 7. Show completion message
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗"
Write-Host "║                    INFRASTRUCTURE PAUSED                     ║"
Write-Host "╠══════════════════════════════════════════════════════════════╣"
Write-Host "║ Cluster: $ClusterName"
Write-Host "║ Region: $Region"
Write-Host "║ Pause Time: $(Get-Date)"
Write-Host "║"
Write-Host "║ COST SAVINGS ESTIMATE (per hour):"
Write-Host "║ • System Nodes: 1/2 nodes running (~50% savings)"
Write-Host "║ • Challenge Nodes: 10/10 nodes at minimum (~80% savings)"
Write-Host "║ • Application Pods: ~90% reduction"
Write-Host "║ • Estimated Total Savings: ~70-80% of running costs"
Write-Host "║"
Write-Host "║ MAINTAINED SERVICES:"
Write-Host "║ • 1x Backend replica (minimal API access)"
Write-Host "║ • 1x Router replica (basic functionality)"
Write-Host "║ • 1x Operator (cluster management)"
Write-Host "║"
Write-Host "║ TO RESUME: .\scripts\resume-infrastructure.ps1"
Write-Host "╚══════════════════════════════════════════════════════════════╝"
Write-Host ""

Write-Success "✅ Infrastructure successfully paused!"
Write-Info "💡 To resume full operations, run: .\scripts\resume-infrastructure.ps1 -ProjectId $ProjectId"

if ($SaveState) {
    Write-Info "📂 State backup location: $PauseStateDir"
}

exit 0
