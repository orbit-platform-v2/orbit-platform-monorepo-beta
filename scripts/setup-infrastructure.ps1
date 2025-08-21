# Orbit Challenge Platform Infrastructure Setup Script (PowerShell)
# This script sets up the complete infrastructure for the platform on Windows

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,
    
    [string]$Environment = "dev",
    [string]$Region = "us-central1",
    [string]$ClusterName = "orbit-challenge-cluster",
    [switch]$DryRun,
    [switch]$SkipTerraform,
    [switch]$SkipAnsible,
    [switch]$Help
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$TerraformDir = Join-Path $ProjectRoot "infrastructure\terraform"
$AnsibleDir = Join-Path $ProjectRoot "infrastructure\ansible"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Usage {
    @"
Orbit Challenge Platform Infrastructure Setup Script

USAGE:
    .\setup-infrastructure.ps1 -ProjectId <project-id> [OPTIONS]

PARAMETERS:
    -ProjectId          GCP Project ID (required)
    -Environment        Environment (dev, staging, prod) [default: dev]
    -Region            GCP Region [default: us-central1]
    -ClusterName       GKE Cluster name [default: orbit-challenge-cluster]
    -DryRun            Show what would be done without executing
    -SkipTerraform     Skip Terraform deployment
    -SkipAnsible       Skip Ansible configuration
    -Help              Show this help message

EXAMPLES:
    .\setup-infrastructure.ps1 -ProjectId "my-gcp-project"
    .\setup-infrastructure.ps1 -ProjectId "my-gcp-project" -Environment "prod" -Region "us-west1"
    .\setup-infrastructure.ps1 -ProjectId "my-gcp-project" -DryRun

PREREQUISITES:
    - gcloud CLI authenticated and configured
    - Terraform >= 1.0 installed
    - Python 3.x with pip
    - Git for Windows (includes bash)
    - PowerShell 5.1 or later

"@
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check gcloud
    try {
        $null = Get-Command gcloud -ErrorAction Stop
        $authList = gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>$null
        if (-not $authList) {
            Write-Error "gcloud is not authenticated. Run 'gcloud auth login'"
            exit 1
        }
    }
    catch {
        Write-Error "gcloud CLI is not installed or not in PATH"
        exit 1
    }
    
    # Check terraform
    try {
        $null = Get-Command terraform -ErrorAction Stop
    }
    catch {
        Write-Error "Terraform is not installed or not in PATH"
        exit 1
    }
    
    # Check python
    try {
        $null = Get-Command python -ErrorAction Stop
    }
    catch {
        Write-Warning "Python is not installed. Ansible may not work properly."
    }
    
    Write-Success "Prerequisites check completed"
}

function Test-Inputs {
    if (-not $ProjectId) {
        Write-Error "Project ID is required. Use -ProjectId parameter."
        Show-Usage
        exit 1
    }
    
    if ($Environment -notin @("dev", "staging", "prod")) {
        Write-Error "Environment must be one of: dev, staging, prod"
        exit 1
    }
    
    Write-Info "Validating GCP project access..."
    try {
        $null = gcloud projects describe $ProjectId 2>$null
    }
    catch {
        Write-Error "Cannot access project $ProjectId. Check project ID and permissions."
        exit 1
    }
    
    Write-Success "Input validation completed"
}

function Set-TerraformInfrastructure {
    if ($SkipTerraform) {
        Write-Warning "Skipping Terraform deployment"
        return
    }
    
    Write-Info "Setting up Terraform..."
    
    Push-Location $TerraformDir
    
    try {
        # Initialize Terraform
        Write-Info "Initializing Terraform..."
        terraform init
        
        # Create terraform.tfvars if it doesn't exist
        $tfVarsPath = Join-Path $TerraformDir "terraform.tfvars"
        if (-not (Test-Path $tfVarsPath)) {
            Write-Info "Creating terraform.tfvars from example..."
            $exampleContent = Get-Content (Join-Path $TerraformDir "terraform.tfvars.example")
            $updatedContent = $exampleContent -replace 'your-gcp-project-id', $ProjectId
            $updatedContent = $updatedContent -replace 'us-central1', $Region
            $updatedContent = $updatedContent -replace 'orbit-challenge-cluster', $ClusterName
            $updatedContent = $updatedContent -replace 'dev', $Environment
            $updatedContent | Set-Content $tfVarsPath
            
            Write-Warning "Please review and update terraform.tfvars with your specific values"
        }
        
        # Plan
        Write-Info "Planning Terraform deployment..."
        terraform plan -var="project_id=$ProjectId" -var="region=$Region" -var="cluster_name=$ClusterName" -var="environment=$Environment"
        
        if ($DryRun) {
            Write-Info "Dry run mode - skipping Terraform apply"
            return
        }
        
        # Apply
        Write-Info "Applying Terraform configuration..."
        terraform apply -var="project_id=$ProjectId" -var="region=$Region" -var="cluster_name=$ClusterName" -var="environment=$Environment" -auto-approve
        
        Write-Success "Terraform deployment completed"
    }
    finally {
        Pop-Location
    }
}

function Set-AnsibleConfiguration {
    if ($SkipAnsible) {
        Write-Warning "Skipping Ansible configuration"
        return
    }
    
    Write-Info "Setting up Ansible..."
    
    # Check if WSL is available for running Ansible
    $useWSL = $false
    try {
        $null = Get-Command wsl -ErrorAction Stop
        $wslOutput = wsl --list --quiet 2>$null
        if ($wslOutput) {
            $useWSL = $true
            Write-Info "Using WSL for Ansible execution"
        }
    }
    catch {
        Write-Warning "WSL not available. Trying to run Ansible natively on Windows."
    }
    
    if ($DryRun) {
        Write-Info "Dry run mode - skipping Ansible playbook execution"
        return
    }
    
    Push-Location $AnsibleDir
    
    try {
        if ($useWSL) {
            # Run Ansible in WSL
            $wslAnsibleDir = $AnsibleDir -replace '\\', '/' -replace 'C:', '/mnt/c'
            wsl bash -c "cd '$wslAnsibleDir' && ansible-galaxy install -r requirements.yml"
            wsl bash -c "cd '$wslAnsibleDir' && ansible-playbook -i inventory/gcp.yaml site.yaml -e project_id='$ProjectId' -e region='$Region' -e cluster_name='$ClusterName' -e environment='$Environment'"
        }
        else {
            # Try to run Ansible natively
            Write-Info "Installing Ansible requirements..."
            ansible-galaxy install -r requirements.yml
            
            Write-Info "Running Ansible playbook..."
            ansible-playbook -i inventory/gcp.yaml site.yaml -e project_id="$ProjectId" -e region="$Region" -e cluster_name="$ClusterName" -e environment="$Environment"
        }
        
        Write-Success "Ansible configuration completed"
    }
    catch {
        Write-Error "Ansible execution failed: $_"
        Write-Info "You may need to run the Ansible playbook manually from WSL or a Linux environment"
    }
    finally {
        Pop-Location
    }
}

function Test-Deployment {
    if ($DryRun) {
        Write-Info "Dry run mode - skipping deployment verification"
        return
    }
    
    Write-Info "Verifying deployment..."
    
    # Configure kubectl
    Write-Info "Configuring kubectl..."
    gcloud container clusters get-credentials $ClusterName --region $Region --project $ProjectId
    
    # Check cluster status
    Write-Info "Checking cluster status..."
    kubectl get nodes
    
    # Check namespaces
    Write-Info "Checking namespaces..."
    kubectl get namespaces | Select-String "orbit"
    
    # Check system pods
    Write-Info "Checking system pods..."
    kubectl get pods -n kube-system
    
    Write-Success "Deployment verification completed"
}

function Main {
    if ($Help) {
        Show-Usage
        exit 0
    }
    
    Write-Info "Starting Orbit Challenge Platform Infrastructure Setup"
    Write-Info "Environment: $Environment"
    Write-Info "Project ID: $ProjectId"
    Write-Info "Region: $Region"
    Write-Info "Cluster Name: $ClusterName"
    
    if ($DryRun) {
        Write-Warning "DRY RUN MODE - No changes will be made"
    }
    
    Test-Prerequisites
    Test-Inputs
    Set-TerraformInfrastructure
    Set-AnsibleConfiguration
    Test-Deployment
    
    Write-Success "Infrastructure setup completed successfully!"
    
    @"

🎉 Orbit Challenge Platform Infrastructure is ready!

Next steps:
1. Review the created resources in GCP Console
2. Deploy the Orbit Operator: kubectl apply -f k8s-manifests/operator/
3. Deploy the WebSocket Router: kubectl apply -f k8s-manifests/websocket-router/
4. Deploy the Backend API: kubectl apply -f k8s-manifests/backend/
5. Deploy the Frontend: kubectl apply -f k8s-manifests/frontend/

Useful commands:
- kubectl get nodes
- kubectl get namespaces
- kubectl get pods -A
- kubectl logs -n orbit-system -l app=orbit-operator

Access your cluster:
gcloud container clusters get-credentials $ClusterName --region $Region --project $ProjectId

"@
}

# Run main function
Main
