# Orbit DevOps Challenge Platform

A scalable DevOps challenge platform with ephemeral pods, embedded terminals, WebSocket routing, and multi-challenge support.

## 🏗️ Architecture Overview

<img width="1076" height="317" alt="image" src="https://github.com/user-attachments/assets/e544bc3e-cec9-4b83-9710-46fa3fd87ef7" />

## 🚀 Features

- **Ephemeral Challenge Pods**: Auto-scaling containers for isolated challenge environments
- **Embedded Terminals**: Real-time terminal access via WebSocket connections
- **Multi-Challenge Support**: 10+ DevOps/Cloud challenges with different difficulty levels
- **Team Collaboration**: 3 users per namespace with shared resources
- **Auto-Cleanup**: TTL-based pod deletion and resource management
- **Scalable Architecture**: Supports 50-100 concurrent users

## 🛠️ Tech Stack

| Component | Technology |
|-----------|------------|
| **Infrastructure** | GKE (private), Cloud NAT, Load Balancer, Container Registry |
| **Provisioning** | Terraform + Ansible |
| **Backend** | NESTJS typescript |
| **Frontend** | React + xterm.js |
| **Operator** | Go (Kubebuilder) |
| **Router** | WebSocket router (Go) |
| **Pods** | Ephemeral per-user challenge containers |

## 📁 Project Structure

```
orbit-competition-monorepo-v2/
├── infrastructure/           # Terraform & Ansible infrastructure code
│   ├── terraform/           # GCP infrastructure provisioning
│   └── ansible/             # Cluster configuration
├── operator/                # Go Kubernetes operator
│   ├── api/                 # CRD definitions
│   ├── controllers/         # Reconciliation logic
│   └── config/              # Deployment manifests
├── websocket-router/        # WebSocket routing service
│   ├── pkg/                 # Go packages
│   └── cmd/                 # Main application
├── backend/                 # FastAPI backend service
│   ├── app/                 # Application code
│   ├── tests/               # Unit & integration tests
│   └── requirements.txt     # Python dependencies
├── frontend/                # React frontend application
│   ├── src/                 # Source code
│   ├── public/              # Static assets
│   └── package.json         # Node dependencies
├── challenges/              # Challenge definitions & Docker images
│   ├── docker-basics/       # Individual challenge directories
│   ├── kubernetes-intro/
│   └── cloud-security/
├── k8s-manifests/          # Kubernetes deployment files
│   ├── base/               # Base configurations
│   └── overlays/           # Environment-specific overlays
├── scripts/                # Utility scripts
│   ├── deploy.sh           # Deployment automation
│   └── setup-dev.sh        # Development environment setup
└── docs/                   # Additional documentation
    ├── api.md              # API documentation
    ├── deployment.md       # Deployment guide
    └── development.md      # Development guide
```

## 🔧 Quick Start

### Prerequisites

- Docker & Docker Compose
- Node.js 18+
- Python 3.9+
- Go 1.20+
- kubectl & helm
- Terraform
- GCP account with billing enabled

### Local Development

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd orbit-competition-monorepo-v2
   ```

2. **Setup development environment**
   ```bash
   ./scripts/setup-dev.sh
   ```

3. **Start services locally**
   ```bash
   docker-compose up -d
   ```

4. **Access the platform**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000
   - WebSocket Router: ws://localhost:8080

### Production Deployment

1. **Provision infrastructure**
   ```bash
   cd infrastructure/terraform
   terraform init
   terraform apply
   ```

2. **Configure cluster**
   ```bash
   cd ../ansible
   ansible-playbook -i inventory/gcp.yaml site.yaml
   ```

3. **Deploy services**
   ```bash
   ./scripts/deploy.sh production
   ```

## 📈 Scaling & Performance

- **Max Concurrent Users**: 50 (optimized for 50 vCPU limit)
- **Challenge Pod CPU**: 0.5 CPU limit per pod (500m)
- **Pod Distribution**: 5 challenge pods per node (10 nodes total)
- **System Pod CPU**: Operator (300m), Backend (500m×2), Router (600m×2)
- **Pod TTL**: Configurable (default: 30 minutes)
- **Auto-scaling**: HPA for WebSocket router (2-4 replicas) and Backend (2-4 replicas)
- **Resource Limits**: CPU: 500m, Memory: 1Gi per challenge pod

## 🔒 Security

- Private GKE cluster with authorized networks
- Network policies for pod isolation
- JWT-based session authentication
- Cloud NAT for controlled outbound access
- Container image scanning

## 📊 Monitoring

- Prometheus metrics collection
- Grafana dashboards for visualization
- Resource usage tracking
- Session analytics

## 🧪 Testing

```bash
# Run all tests
make test

# Load testing
make load-test

# Security testing
make security-test
```

## 🚀 Roadmap

- [ ] Infrastructure provisioning (Days 2-5)
- [ ] Operator development (Days 6-14)
- [ ] WebSocket router (Days 10-16)
- [ ] Backend API (Days 12-18)
- [ ] Frontend development (Days 14-21)
- [ ] Challenge images (Days 16-24)
- [ ] Testing & QA (Days 22-26)
- [ ] Optimization (Days 27-28)
- [ ] Deployment (Days 29-30)

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.
