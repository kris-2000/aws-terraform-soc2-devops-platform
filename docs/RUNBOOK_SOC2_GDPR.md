# RUNBOOK — SOC2 / GDPR Operations Guide
**Project:** `aws-terraform-soc2-devops-platform`  
**Owner:** Krishnaprasad June  
**Last Updated:** October 2026  

---

## 1. Architecture & Traffic Flow

```
Internet
   │
   ▼
[Route 53] ── A alias record ──► [CloudFront CDN]
                                       │
                                  (OAC + HTTPS)
                                       │
                                  [AWS WAF v2]
                            (SQLi + CommonRuleSet)
                                       │
                                       ▼
                            [Application Load Balancer]
                             (Public Subnets: 10.0.1.0/24
                                         & 10.0.2.0/24)
                                       │
                              Port 8000 only from ALB SG
                                       │
                                       ▼
                          [EC2 Ubuntu — Docker Container]
                           (Private Subnet: 10.0.10.0/24)
                            hospital-app:latest running
                                       │
                              Port 3306 only from EC2 SG
                                       │
                                       ▼
                          [RDS MySQL 8.0 — Encrypted]
                           (Private Subnet: 10.0.11.0/24)
                              storage_encrypted = true
                           backup_retention = 7 days
                                       │
                                       ▼
                          [S3 Bucket — Encrypted Backups]
                            AES256 | All public access blocked
```

| Layer | AWS Service | Purpose |
|-------|------------|--------|
| DNS | Route 53 | Domain resolution + health checks |
| CDN | CloudFront | Static asset caching, HTTPS enforcement, OAC |
| Protection | AWS WAF v2 | Block SQLi, XSS, common OWASP threats |
| Load Balancing | ALB | HTTP→HTTPS redirect, health-check routing |
| Compute | EC2 (t3.micro) | Runs Docker container in private subnet |
| Database | RDS MySQL 8.0 | Encrypted at rest, 7-day automated backups |
| Storage | S3 | Static files + encrypted RDS backup dumps |
| Observability | CloudWatch | CPU/5XX alarms → SNS email notifications |
| Secrets | IAM + SSM | Least-privilege roles, no hardcoded credentials |

---

## 2. Troubleshooting Playbook

### Problem: 502 Bad Gateway from ALB

```bash
# Step 1: Check if container is running on EC2
docker ps --filter "name=hospital-app"
docker logs --tail 100 hospital-app

# Step 2: Test health endpoint locally on EC2
curl -v http://localhost:8000/health

# Step 3: Check systemd/docker daemon
journalctl -u docker --since "10 minutes ago"

# Step 4: Check listening ports
ss -tulpn | grep 8000

# Step 5: Check ALB target group health from AWS CLI
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --region ap-south-1

# Step 6: Check CloudWatch logs
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_ELB_5XX_Count \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum \
  --region ap-south-1
```

### Problem: High CPU Alarm Triggered

```bash
# Check top processes on EC2
top -b -n1 | head -20
ps aux --sort=-%cpu | head -10

# Check Docker container resource usage
docker stats --no-stream

# Check CloudWatch alarm state
aws cloudwatch describe-alarms \
  --alarm-names "dckap-ec2-high-cpu" \
  --region ap-south-1

# Check if container is OOM-killed
docker inspect hospital-app | grep -i oom
journalctl -k | grep -i "out of memory"
```

### Problem: Cannot Connect to RDS

```bash
# Check security group rules (must only allow EC2 SG on 3306)
aws ec2 describe-security-groups \
  --group-ids <RDS_SG_ID> \
  --region ap-south-1

# Test DNS resolution of RDS endpoint from EC2
dig <rds-endpoint.ap-south-1.rds.amazonaws.com>

# Test TCP connectivity from EC2 to RDS port
nc -zv <RDS_ENDPOINT> 3306

# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier dckap-hospital-db \
  --region ap-south-1 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint}'
```

### Problem: DNS Not Resolving

```bash
# Check Route 53 record
dig devops.example.com
nslookup devops.example.com 8.8.8.8

# Check CloudFront distribution status
aws cloudfront list-distributions \
  --query 'DistributionList.Items[].{Domain:DomainName,Status:Status}'
```

---

## 3. SOC2 / GDPR Controls Implemented

| Control | Implementation | Standard |
|---------|---------------|----------|
| **Encryption at Rest** | RDS `storage_encrypted=true` (AES-256), S3 AES256 SSE, EC2 root volume encrypted | SOC2 CC6.1, GDPR Art.32 |
| **Encryption in Transit** | CloudFront enforces HTTPS, `redirect-to-https`, ALB HTTP→HTTPS 301 redirect | SOC2 CC6.1, PCI-DSS 4.1 |
| **Network Isolation** | EC2 and RDS in private subnets; no direct public access | SOC2 CC6.6, GDPR Art.25 |
| **Least Privilege IAM** | EC2 IAM role allows only CloudWatch Logs + S3 backup bucket (no wildcard `*`) | SOC2 CC6.3, GDPR Art.25 |
| **No SSH Exposure** | Port 22 not open; access via AWS Systems Manager Session Manager | SOC2 CC6.6 |
| **WAF Protection** | AWS WAF v2 with SQLi + CommonRuleSet blocks OWASP Top 10 threats | SOC2 CC7.2, PCI-DSS 6.6 |
| **Non-Root Containers** | Dockerfile: `USER appuser` (non-root); K8s: `runAsNonRoot=true` | SOC2 CC8.1, CIS Benchmark |
| **Automated Backups** | RDS 7-day backup retention + daily `mysqldump` → S3 AES256 | SOC2 A1.2, GDPR Art.32 |
| **Audit Logging** | CloudWatch Logs (30-day retention) for app + RDS general/error/slowquery logs | SOC2 CC7.2, GDPR Art.30 |
| **Alerting & Monitoring** | CloudWatch alarms for CPU > 80% and ALB 5XX > 5 → SNS email | SOC2 CC7.4 |
| **Compliance Scanning** | `soc2_gdpr_audit.py` scans S3 encryption, SG exposure, RDS encryption in CI/CD | SOC2 CC4.1 |
| **Code Security Gate** | SonarQube Cloud scans Python, Dockerfile, K8s YAML, Terraform IaC on every push | SOC2 CC8.1 |

---

## 4. Daily Operational Checklist

- [ ] Run `scripts/linux_health_backup.sh` (automated via cron at 2 AM)
- [ ] Check CloudWatch dashboard for CPU/5XX anomalies
- [ ] Review SonarQube quality gate on latest commit
- [ ] Verify S3 backup bucket has today's `db_backup_*.sql.gz` file
- [ ] Run `scripts/soc2_gdpr_audit.py` and confirm exit code 0

---

## 5. Disaster Recovery

| Scenario | RTO | RPO | Steps |
|----------|-----|-----|-------|
| EC2 instance failure | < 10 min | 0 | Terraform re-apply creates new EC2; Docker auto-starts via user_data |
| RDS failure | < 30 min | < 24 hrs | Restore from automated snapshot in RDS console |
| S3 data loss | < 5 min | 0 | Enable S3 versioning (recommended for production) |
| Region failure | < 2 hrs | < 24 hrs | Terraform apply in secondary region (ap-southeast-1) |
