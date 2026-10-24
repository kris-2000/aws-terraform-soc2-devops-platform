# =============================================================================
# compute_db.tf — EC2 (Docker App Server) + RDS MySQL (Encrypted)
# =============================================================================

# ---------------------------------------------------------------------------
# EC2 — Ubuntu App Server in Private Subnet
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # SOC2: Encrypt root volume at rest
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # User data: install Docker and start the hospital app container
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Update system and install Docker
    apt-get update -y
    apt-get install -y docker.io awscli
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    # Pull and run the Hospital Management container
    docker pull ${var.docker_image}
    docker run -d \
      --name hospital-app \
      --restart unless-stopped \
      -p 8000:8000 \
      -e PORT=8000 \
      ${var.docker_image}

    echo "Hospital app container started successfully" >> /var/log/user-data.log
  EOF

  tags = { Name = "dckap-app-server" }
}

# Target group attachment
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server.id
  port             = 8000
}

# ---------------------------------------------------------------------------
# RDS MySQL — Encrypted, Multi-AZ ready, 7-day Backup Retention
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "mysql" {
  name       = "dckap-mysql-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = { Name = "dckap-mysql-subnet-group" }
}

resource "aws_db_instance" "mysql_rds" {
  identifier            = "dckap-hospital-db"
  engine                = "mysql"
  engine_version        = "8.0"
  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 100 # auto-scaling up to 100GB

  db_name  = "hospital_db"
  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # SOC2 / GDPR / PCI-DSS: Mandatory encryption at rest
  storage_encrypted = true

  # Automated backups for 7 days (SOC2 backup policy)
  backup_retention_period = 7
  backup_window           = "02:00-03:00" # 2-3 AM UTC
  maintenance_window      = "mon:04:00-mon:05:00"

  # Snapshot on delete (never lose prod data)
  skip_final_snapshot       = false
  final_snapshot_identifier = "dckap-hospital-final-snapshot"

  # Enable CloudWatch logs for audit (SOC2 logging requirement)
  enabled_cloudwatch_logs_exports = ["general", "error", "slowquery"]

  deletion_protection = false # set true in production
  tags                = { Name = "dckap-hospital-db" }
}
