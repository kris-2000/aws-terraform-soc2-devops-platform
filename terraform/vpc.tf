# =============================================================================
# vpc.tf — VPC, Subnets, Security Groups
# Architecture: Public subnets (ALB) → Private subnets (EC2 + RDS)
# =============================================================================

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "dckap-main-vpc" }
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "dckap-igw" }
}

# ---------------------------------------------------------------------------
# Public Subnets (ALB lives here — needs 2 AZs for ALB requirement)
# ---------------------------------------------------------------------------
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "dckap-public-a", Tier = "Public" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "dckap-public-b", Tier = "Public" }
}

# ---------------------------------------------------------------------------
# Private Subnets (EC2 app server + RDS — no direct internet exposure)
# ---------------------------------------------------------------------------
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "dckap-private-a", Tier = "Private" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "dckap-private-b", Tier = "Private" }
}

# ---------------------------------------------------------------------------
# NAT Gateway (allows private subnets to reach internet for Docker pulls)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "dckap-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "dckap-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "dckap-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "dckap-private-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Security Groups — Strict Least-Privilege Rules
# ---------------------------------------------------------------------------

# ALB Security Group: only HTTPS (443) and HTTP (80) from internet
resource "aws_security_group" "alb_sg" {
  name        = "dckap-alb-sg"
  description = "Allow HTTPS/HTTP inbound to ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "dckap-alb-sg" }
}

# EC2 Security Group: port 8000 only from ALB (blocks direct public access)
resource "aws_security_group" "ec2_sg" {
  name        = "dckap-ec2-sg"
  description = "Allow app traffic only from ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # SSH via AWS Systems Manager (SSM) — no port 22 open to internet (SOC2)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "dckap-ec2-sg" }
}

# RDS Security Group: MySQL 3306 only from EC2 security group
resource "aws_security_group" "rds_sg" {
  name        = "dckap-rds-sg"
  description = "Allow MySQL only from EC2 security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from EC2 only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "dckap-rds-sg" }
}
