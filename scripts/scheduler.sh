#!/bin/bash

# Orbit Challenge Platform - Automated Scheduler
# Automatically pause and resume infrastructure based on schedule

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="orbit-challenge-cluster"
ACTION=""
SCHEDULE_FILE="./config/schedule.yaml"
DRY_RUN=false
TIMEZONE="UTC"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated Scheduler for Orbit Challenge Platform Infrastructure

OPTIONS:
    -p, --project-id     GCP Project ID (required)
    -r, --region         GCP Region [default: us-central1]
    -c, --cluster-name   GKE Cluster name [default: orbit-challenge-cluster]
    -a, --action         Action: check, pause, resume, setup-cron [required]
    -s, --schedule       Schedule file [default: ./config/schedule.yaml]
    -t, --timezone       Timezone [default: UTC]
    -d, --dry-run        Show what would be done without executing
    -h, --help           Show this help message

ACTIONS:
    check       Check if action should be performed based on schedule
    pause       Force pause infrastructure
    resume      Force resume infrastructure
    setup-cron  Set up cron jobs for automated scheduling

EXAMPLES:
    $0 --project-id my-gcp-project --action check
    $0 --project-id my-gcp-project --action setup-cron
    $0 --project-id my-gcp-project --action pause --dry-run

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -s|--schedule)
            SCHEDULE_FILE="$2"
            shift 2
            ;;
        -t|--timezone)
            TIMEZONE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" || -z "$ACTION" ]]; then
    log_error "Project ID and action are required"
    usage
    exit 1
fi

# Create default schedule file if it doesn't exist
create_default_schedule() {
    local dir=$(dirname "$SCHEDULE_FILE")
    mkdir -p "$dir"
    
    cat > "$SCHEDULE_FILE" <<EOF
# Orbit Challenge Platform - Infrastructure Schedule
# Define when to pause and resume infrastructure

schedule:
  timezone: "UTC"
  
  # Work hours (infrastructure should be running)
  work_hours:
    monday:
      start: "08:00"
      end: "18:00"
    tuesday:
      start: "08:00"
      end: "18:00"
    wednesday:
      start: "08:00"
      end: "18:00"
    thursday:
      start: "08:00"
      end: "18:00"
    friday:
      start: "08:00"
      end: "18:00"
    saturday:
      start: "10:00"
      end: "16:00"
    sunday:
      enabled: false  # No work on Sunday
  
  # Special dates (override default schedule)
  special_dates:
    "2025-12-25":  # Christmas
      enabled: false
    "2025-01-01":  # New Year
      enabled: false
    "2025-07-04":  # July 4th
      enabled: false
  
  # Maintenance windows (force pause)
  maintenance:
    - date: "every sunday"
      time: "02:00-04:00"
      description: "Weekly maintenance"
  
  # Cost optimization rules
  cost_rules:
    max_daily_cost: 20.00
    pause_threshold_hours: 2  # Pause if idle for 2+ hours
    auto_pause_enabled: true
    auto_resume_enabled: true

# Notification settings
notifications:
  email: "admin@company.com"
  slack_webhook: ""
  teams_webhook: ""
  
  events:
    - infrastructure_paused
    - infrastructure_resumed
    - cost_threshold_exceeded
    - maintenance_started

EOF
    
    log_success "Created default schedule file: $SCHEDULE_FILE"
}

# Parse schedule file
parse_schedule() {
    if [[ ! -f "$SCHEDULE_FILE" ]]; then
        log_warning "Schedule file not found, creating default: $SCHEDULE_FILE"
        create_default_schedule
    fi
    
    log_info "Parsing schedule from: $SCHEDULE_FILE"
    # This would parse YAML, for now we'll use a simple approach
    # In production, use yq or python to parse YAML properly
}

# Check if infrastructure should be running based on schedule
should_be_running() {
    local current_day=$(date +%A | tr '[:upper:]' '[:lower:]')
    local current_time=$(date +%H:%M)
    local current_date=$(date +%Y-%m-%d)
    
    log_info "Checking schedule for $current_day at $current_time ($current_date)"
    
    # Simple schedule check (would be more sophisticated with YAML parsing)
    case $current_day in
        monday|tuesday|wednesday|thursday|friday)
            if [[ "$current_time" > "08:00" && "$current_time" < "18:00" ]]; then
                return 0  # Should be running
            fi
            ;;
        saturday)
            if [[ "$current_time" > "10:00" && "$current_time" < "16:00" ]]; then
                return 0  # Should be running
            fi
            ;;
        sunday)
            return 1  # Should be paused
            ;;
    esac
    
    return 1  # Default to paused
}

# Get current infrastructure status
get_current_status() {
    log_info "Getting current infrastructure status..."
    
    # Check if cluster exists
    if ! gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        echo "not_found"
        return
    fi
    
    # Get cluster credentials
    gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" --quiet
    
    # Check if system pods are running at full capacity
    local backend_replicas=$(kubectl get deployment orbit-backend -n orbit-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    local router_replicas=$(kubectl get deployment websocket-router -n orbit-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$backend_replicas" -ge "2" && "$router_replicas" -ge "2" ]]; then
        echo "running"
    else
        echo "paused"
    fi
}

# Perform action based on schedule check
check_and_act() {
    local current_status=$(get_current_status)
    local should_run=$(should_be_running && echo "running" || echo "paused")
    
    log_info "Current status: $current_status"
    log_info "Should be: $should_run"
    
    if [[ "$current_status" == "not_found" ]]; then
        log_error "Cluster not found: $CLUSTER_NAME"
        return 1
    fi
    
    if [[ "$current_status" != "$should_run" ]]; then
        case $should_run in
            "running")
                log_info "Infrastructure should be running but is paused - resuming..."
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would resume infrastructure"
                else
                    resume_infrastructure
                fi
                ;;
            "paused")
                log_info "Infrastructure should be paused but is running - pausing..."
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would pause infrastructure"
                else
                    pause_infrastructure
                fi
                ;;
        esac
    else
        log_success "Infrastructure is in correct state: $current_status"
    fi
}

# Pause infrastructure
pause_infrastructure() {
    log_info "Pausing infrastructure..."
    
    if [[ -f "./scripts/pause-infrastructure.sh" ]]; then
        chmod +x ./scripts/pause-infrastructure.sh
        ./scripts/pause-infrastructure.sh \
            --project-id "$PROJECT_ID" \
            --region "$REGION" \
            --cluster-name "$CLUSTER_NAME" \
            --force
    else
        log_error "Pause script not found: ./scripts/pause-infrastructure.sh"
        return 1
    fi
}

# Resume infrastructure
resume_infrastructure() {
    log_info "Resuming infrastructure..."
    
    if [[ -f "./scripts/resume-infrastructure.sh" ]]; then
        chmod +x ./scripts/resume-infrastructure.sh
        ./scripts/resume-infrastructure.sh \
            --project-id "$PROJECT_ID" \
            --region "$REGION" \
            --cluster-name "$CLUSTER_NAME" \
            --force
    else
        log_error "Resume script not found: ./scripts/resume-infrastructure.sh"
        return 1
    fi
}

# Set up cron jobs
setup_cron() {
    log_info "Setting up cron jobs for automated scheduling..."
    
    local script_path=$(realpath "$0")
    local project_root=$(dirname "$(dirname "$script_path")")
    
    # Check if running on GitHub Actions or similar CI
    if [[ -n "$GITHUB_ACTIONS" || -n "$CI" ]]; then
        log_info "Setting up GitHub Actions workflow schedule..."
        create_github_schedule
        return
    fi
    
    # Create cron entry
    local cron_entry="*/15 * * * * cd $project_root && $script_path --project-id $PROJECT_ID --action check --region $REGION --cluster-name $CLUSTER_NAME >> /var/log/orbit-scheduler.log 2>&1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would add cron entry:"
        echo "$cron_entry"
    else
        # Add to crontab
        (crontab -l 2>/dev/null | grep -v "orbit-scheduler" ; echo "$cron_entry") | crontab -
        log_success "Cron job added - infrastructure will be checked every 15 minutes"
        
        # Create log file
        sudo touch /var/log/orbit-scheduler.log
        sudo chmod 666 /var/log/orbit-scheduler.log
        
        log_info "Logs will be written to: /var/log/orbit-scheduler.log"
    fi
}

# Create GitHub Actions schedule
create_github_schedule() {
    local workflow_file=".github/workflows/scheduler.yml"
    
    cat > "$workflow_file" <<EOF
name: Infrastructure Scheduler

on:
  schedule:
    # Check every 15 minutes during business hours
    - cron: '*/15 8-18 * * 1-5'  # Mon-Fri 8AM-6PM UTC
    - cron: '*/15 10-16 * * 6'   # Saturday 10AM-4PM UTC
    # Maintenance check every Sunday at 2 AM
    - cron: '0 2 * * 0'
  workflow_dispatch:
    inputs:
      action:
        description: 'Action to perform'
        required: true
        default: 'check'
        type: choice
        options:
          - check
          - pause
          - resume

jobs:
  schedule-check:
    runs-on: ubuntu-latest
    if: github.event_name == 'schedule' || github.event.inputs.action == 'check'
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: \${{ secrets.GCP_SA_KEY }}

      - name: Setup Google Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Run Scheduler Check
        run: |
          chmod +x scripts/scheduler.sh
          ./scripts/scheduler.sh \\
            --project-id "\${{ secrets.GCP_PROJECT_ID }}" \\
            --region "\${{ env.GCP_REGION }}" \\
            --cluster-name "\${{ env.CLUSTER_NAME }}" \\
            --action check

  manual-action:
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.action != 'check'
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: \${{ secrets.GCP_SA_KEY }}

      - name: Setup Google Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Execute Action
        run: |
          chmod +x scripts/scheduler.sh
          ./scripts/scheduler.sh \\
            --project-id "\${{ secrets.GCP_PROJECT_ID }}" \\
            --region "\${{ env.GCP_REGION }}" \\
            --cluster-name "\${{ env.CLUSTER_NAME }}" \\
            --action "\${{ github.event.inputs.action }}"

env:
  GCP_REGION: 'us-central1'
  CLUSTER_NAME: 'orbit-challenge-cluster'
EOF
    
    log_success "Created GitHub Actions scheduler: $workflow_file"
}

# Show status and recommendations
show_status() {
    local current_status=$(get_current_status)
    local should_run=$(should_be_running && echo "running" || echo "paused")
    
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 INFRASTRUCTURE SCHEDULER                     ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Project: $PROJECT_ID"
    echo "║ Cluster: $CLUSTER_NAME"
    echo "║ Current Time: $(date)"
    echo "║ Timezone: $TIMEZONE"
    echo "║"
    echo "║ STATUS:"
    echo "║ • Current State: $current_status"
    echo "║ • Should Be: $should_run"
    if [[ "$current_status" == "$should_run" ]]; then
        echo "║ • Status: ✅ Correct"
    else
        echo "║ • Status: ⚠️ Needs Action"
    fi
    echo "║"
    echo "║ SCHEDULE FILE: $SCHEDULE_FILE"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
}

# Main execution
main() {
    log_info "🕐 Orbit Challenge Platform - Automated Scheduler"
    
    # Parse schedule
    parse_schedule
    
    case $ACTION in
        "check")
            show_status
            check_and_act
            ;;
        "pause")
            pause_infrastructure
            ;;
        "resume")
            resume_infrastructure
            ;;
        "setup-cron")
            setup_cron
            ;;
        *)
            log_error "Unknown action: $ACTION"
            usage
            exit 1
            ;;
    esac
    
    log_success "Scheduler action completed: $ACTION"
}

# Run main function
main

exit 0
