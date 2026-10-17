#!/usr/bin/env python3
"""
soc2_gdpr_audit.py
Python Boto3 compliance scanner.
Fails with exit code 1 if any SOC2/GDPR/PCI-DSS controls are violated.

Checks:
  - S3: All buckets must have AES256 or aws:kms encryption
  - Security Groups: No 0.0.0.0/0 on port 22 (SSH) or 3306 (MySQL)
  - RDS: All instances must have storage_encrypted = True
"""

import sys
import boto3
from botocore.exceptions import ClientError

# Use Mumbai region by default (change to match your deployment)
REGION = "ap-south-1"

s3  = boto3.client("s3")
ec2 = boto3.client("ec2", region_name=REGION)
rds = boto3.client("rds", region_name=REGION)

violations: list[str] = []
passed:     list[str] = []


def check_s3_encryption() -> None:
    """Ensure every S3 bucket has server-side encryption enabled."""
    print("\n[CHECK] S3 Bucket Encryption")
    buckets = s3.list_buckets().get("Buckets", [])
    for bucket in buckets:
        name = bucket["Name"]
        try:
            enc = s3.get_bucket_encryption(Bucket=name)
            rules = enc["ServerSideEncryptionConfiguration"]["Rules"]
            algo = rules[0]["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"]
            if algo in ("AES256", "aws:kms"):
                passed.append(f"  PASS  S3 bucket '{name}' encrypted with {algo}")
            else:
                violations.append(f"  FAIL  S3 bucket '{name}' uses unsupported algo: {algo}")
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code == "ServerSideEncryptionConfigurationNotFoundError":
                violations.append(f"  FAIL  S3 bucket '{name}' has NO encryption configured")
            else:
                violations.append(f"  FAIL  S3 bucket '{name}' — unexpected error: {exc}")


def check_security_groups() -> None:
    """Ensure no security group exposes SSH (22) or MySQL (3306) to the world."""
    print("\n[CHECK] Security Group Open Ports")
    BLOCKED_PORTS = {22: "SSH", 3306: "MySQL"}
    sgs = ec2.describe_security_groups()["SecurityGroups"]
    for sg in sgs:
        sg_name = sg.get("GroupName", sg["GroupId"])
        for rule in sg.get("IpPermissions", []):
            from_port = rule.get("FromPort", 0)
            to_port   = rule.get("ToPort", 0)
            for cidr_range in rule.get("IpRanges", []):
                cidr = cidr_range.get("CidrIp", "")
                if cidr == "0.0.0.0/0":
                    for port, svc in BLOCKED_PORTS.items():
                        if from_port <= port <= to_port:
                            violations.append(
                                f"  FAIL  SG '{sg_name}' allows {svc} (port {port}) "
                                f"from 0.0.0.0/0 — PUBLIC EXPOSURE!"
                            )
            # Also check IPv6
            for ipv6_range in rule.get("Ipv6Ranges", []):
                if ipv6_range.get("CidrIpv6") == "::/0":
                    for port, svc in BLOCKED_PORTS.items():
                        if from_port <= port <= to_port:
                            violations.append(
                                f"  FAIL  SG '{sg_name}' allows {svc} (port {port}) "
                                f"from ::/0 — IPv6 PUBLIC EXPOSURE!"
                            )
        passed.append(f"  PASS  SG '{sg_name}' — no dangerous public port exposure")


def check_rds_encryption() -> None:
    """Ensure every RDS instance has storage encryption enabled."""
    print("\n[CHECK] RDS Storage Encryption")
    instances = rds.describe_db_instances()["DBInstances"]
    if not instances:
        passed.append("  PASS  No RDS instances found")
        return
    for db in instances:
        db_id = db["DBInstanceIdentifier"]
        if db.get("StorageEncrypted"):
            passed.append(f"  PASS  RDS '{db_id}' has storage encryption enabled")
        else:
            violations.append(f"  FAIL  RDS '{db_id}' does NOT have storage encryption — GDPR VIOLATION!")


def main() -> None:
    print("============================================================")
    print(" SOC2 / GDPR / PCI-DSS Compliance Audit")
    print(f" Region: {REGION}")
    print("============================================================")

    check_s3_encryption()
    check_security_groups()
    check_rds_encryption()

    print("\n===== AUDIT RESULTS =====")
    for msg in passed:
        print(msg)

    if violations:
        print("\n===== VIOLATIONS FOUND =====")
        for v in violations:
            print(v)
        print(f"\n[AUDIT FAILED] {len(violations)} violation(s) found. Fix before deployment!")
        sys.exit(1)
    else:
        print(f"\n[AUDIT PASSED] All {len(passed)} checks passed. Ready for SOC2 review.")
        sys.exit(0)


if __name__ == "__main__":
    main()
