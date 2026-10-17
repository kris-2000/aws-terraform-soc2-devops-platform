# aws-terraform-soc2-devops-platform

[![DevOps Pipeline](https://github.com/kris-2000/aws-terraform-soc2-devops-platform/actions/workflows/devops-pipeline.yml/badge.svg)](https://github.com/kris-2000/aws-terraform-soc2-devops-platform/actions)
[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=kris-2000_aws-terraform-soc2-devops-platform&metric=alert_status)](https://sonarcloud.io/project/overview?id=kris-2000_aws-terraform-soc2-devops-platform)

Enterprise-grade AWS infrastructure platform demonstrating **SOC2, GDPR, and PCI-DSS compliant** DevOps engineering.

Built as a portfolio project for the **DCKAP Junior DevOps Engineer** role, this repository wraps a **Django/Python Hospital Management System** in a complete production-grade AWS + Terraform + Docker + Kubernetes + GitHub Actions + SonarQube stack.

---

## Architecture

```
Route 53 → CloudFront + WAF → ALB → EC2 (Docker) → RDS MySQL
                                          ↓
                                    S3 (Encrypted Backups)
                                          ↓
                                    CloudWatch (Alarms + Logs)
```

## Tech Stack

| Category | Technology |
|----------|----------|
| **Cloud** | AWS (VPC, EC2, RDS, S3, CloudFront, WAF, Route 53, CloudWatch, IAM) |
| **IaC** | Terraform 1.6+ |
| **Containers** | Docker (multi-stage, non-root, health-checked) |
| **Orchestration** | Kubernetes (Deployment + Service + Ingress) |
| **CI/CD** | GitHub Actions + Jenkins |
| **Security Scan** | SonarQube Cloud + Bandit + ShellCheck |
| **Language** | Python 3.12 |
| **Database** | MySQL 8.0 on RDS (encrypted) |
| **Compliance** | SOC2, GDPR, PCI-DSS controls implemented |

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/kris-2000/aws-terraform-soc2-devops-platform
cd aws-terraform-soc2-devops-platform

# 2. Run compliance audit (requires AWS credentials)
python3 scripts/soc2_gdpr_audit.py

# 3. Run app locally with Docker
docker build -t hospital-app ./app
docker run -p 8000:8000 hospital-app
curl http://localhost:8000/health

# 4. Deploy infrastructure (WARNING: costs money if not in free tier)
cd terraform
terraform init
terraform plan -var="db_password=YourSecurePass!"
```

## GitHub Secrets Required

| Secret | Description |
|--------|------------|
| `SONAR_TOKEN` | SonarCloud authentication token |
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `DB_PASSWORD` | RDS MySQL master password |

## Compliance

See [docs/RUNBOOK_SOC2_GDPR.md](docs/RUNBOOK_SOC2_GDPR.md) for full SOC2/GDPR control mapping.

## Author

**Krishnaprasad June** — [github.com/kris-2000](https://github.com/kris-2000)
