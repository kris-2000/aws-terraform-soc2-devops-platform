# Automated AWS Infrastructure & CI/CD Platform (Demo / SOC 2-Inspired Controls)

[![DevOps Pipeline](https://github.com/kris-2000/aws-terraform-soc2-devops-platform/actions/workflows/devops-pipeline.yml/badge.svg)](https://github.com/kris-2000/aws-terraform-soc2-devops-platform/actions)
[![Terraform 1.6+](https://img.shields.io/badge/Terraform-1.6%2B-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Security Scanned](https://img.shields.io/badge/Security-tfsec%20%7C%20Checkov%20%7C%20Bandit-success)](https://github.com/kris-2000/aws-terraform-soc2-devops-platform/actions)

This repository is a demo/reference implementation of an AWS cloud platform with a CI/CD pipeline and security-hardened infrastructure patterns. It is designed to illustrate common DevSecOps and cloud security controls, including network isolation, encrypted storage, WAF protection, least-privilege IAM, CloudWatch monitoring, and backup automation.

Important: This project is not a SOC 2 certification, attestation, or an audited production control environment. It is a learning/demo implementation inspired by SOC 2 control themes and AWS best practices.

---

## Architecture Overview

The platform provisions a multi-tier AWS architecture with public edge components and private application/database workloads.

```mermaid
flowchart TD
    U[Users] --> R53[Route 53]
    R53 --> CF[CloudFront]
    CF --> WAF[AWS WAF]
    WAF --> ALB[Application Load Balancer]
    ALB --> EC2[EC2 App Server in Private Subnet]
    EC2 --> RDS[RDS MySQL in Private Subnet]
    EC2 --> CW[CloudWatch Logs & Alarms]
    EC2 --> S3[S3 Encrypted Backups]
    PIPELINE[GitHub Actions / Jenkins] -.-> EC2
```

---

## Security Controls Included

| Control Area | Example Implementation |
| --- | --- |
| Network isolation | VPC with public/private subnets, ALB in public tier, app and DB in private subnets |
| Encryption at rest | RDS storage encryption, S3 SSE-S3 / AES256, EC2 root volume encryption |
| Encryption in transit | ALB redirect to HTTPS, CloudFront redirect-to-HTTPS |
| WAF protection | AWS managed SQLi and common rule sets |
| Least privilege IAM | EC2 role scoped to CloudWatch logs and S3 backup access |
| Monitoring | CloudWatch metric alarms for CPU and ALB errors |
| Backup automation | Bash backup script uploads encrypted database dumps to S3 |
| DevSecOps pipeline | flake8, bandit, shellcheck, terraform fmt/validate, tfsec, checkov |

---

## AWS Resources Provisioned

- VPC, subnets, routing, NAT gateway
- Security groups with least-privilege ingress/egress
- EC2 Ubuntu app server in a private subnet
- RDS MySQL 8.0 with encrypted storage
- S3 bucket with public access block and SSE
- CloudFront distribution with OAC and WAF
- ALB + target group + health checks
- CloudWatch log groups and alarms
- SNS topic for alerting

---

## CloudWatch Monitoring

This repo includes CloudWatch resources for operational visibility:

- Log groups for application logs and RDS logs
- Metric alarms for:
  - EC2 CPU utilization >= 80%
  - ALB 5xx errors > 5 in a given period
  - RDS CPU utilization >= 75%
- SNS topic notifications for alarm events

The implementation is a good example of how to centralize environment telemetry and operational alerts in AWS, but you still need to configure the actual runtime log shipping and alert subscriptions for a production environment.

---

## DevSecOps CI/CD Pipeline

The GitHub Actions workflow runs linting, security scans, Docker build validation, and Terraform validation/plan.

Stages:

1. Lint and security validation
   - flake8
   - bandit
   - shellcheck
   - terraform fmt/validate
   - tfsec
   - checkov
2. SonarQube scan
3. Docker build and health probe
4. Terraform plan (dry-run only)

---

## Local Quickstart

### 1. Run locally

```bash
git clone https://github.com/kris-2000/aws-terraform-soc2-devops-platform.git
cd aws-terraform-soc2-devops-platform
python app/app.py
```

Open:

- http://localhost:8000/
- http://localhost:8000/health
- http://localhost:8000/patients

### 2. Run with Docker

```bash
docker build -t hospital-app app/
docker run -d --name hospital-service -p 8000:8000 hospital-app
curl http://localhost:8000/health
```

### 3. Validate Terraform

```bash
cd terraform
terraform init -backend=false
terraform validate
```

---

## Repository Structure

```text
aws-terraform-soc2-devops-platform/
├── app/
│   ├── app.py
│   ├── Dockerfile
│   └── requirements.txt
├── terraform/
│   ├── main.tf
│   ├── vpc.tf
│   ├── edge_alb_waf.tf
│   ├── compute_db.tf
│   └── iam_cloudwatch.tf
├── k8s/
│   └── deployment-ingress.yaml
├── scripts/
│   ├── linux_health_backup.sh
│   └── soc2_gdpr_audit.py
├── .github/workflows/
│   └── devops-pipeline.yml
├── docs/
│   └── RUNBOOK_SOC2_GDPR.md
├── Jenkinsfile
├── README.md
└── .gitignore
```

---

## Demo Notes

This repo is intended to be a practical reference and portfolio project rather than a regulated production control implementation. It demonstrates how to combine AWS, Terraform, Docker, Kubernetes, CI/CD, and monitoring patterns in a single environment.

This is a strong educational baseline, but actual production compliance work must include:

- real security review and threat modeling
- identity and access review
- secrets management and rotation
- actual certificate and DNS configuration
- workload-specific authn/authz
- logging agent configuration and retention policies
- independent audit and compliance validation

---

## Author

KRISHNA PRASAD S

GitHub: @kris-2000

