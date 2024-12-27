# Secure AWS Infrastructure Setup Guide

## Table of Contents
- [1. AWS Secrets Manager Integration](#1-aws-secrets-manager-integration)
- [2. HTTPS and SSL Configuration](#2-https-and-ssl-configuration)
- [3. Backup Strategy](#3-backup-strategy)
- [4. Security Hardening](#4-security-hardening)
- [5. CI/CD Pipeline Setup](#5-cicd-pipeline-setup)

## 1. AWS Secrets Manager Integration

### Setup Steps:
1. Create secrets in AWS Secrets Manager:
```bash
aws secretsmanager create-secret \
    --name "/prod/db/credentials" \
    --description "Database credentials" \
    --secret-string '{"username":"admin","password":"your-secure-password"}'
```

2. Update `database.tf` to use Secrets Manager:
```hcl
data "aws_secretsmanager_secret" "db_credentials" {
  name = "/prod/db/credentials"
}

data "aws_secretsmanager_secret_version" "current" {
  secret_id = data.aws_secretsmanager_secret.db_credentials.id
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.current.secret_string)
}

resource "aws_db_instance" "main" {
  # ... other configurations ...
  username = local.db_creds.username
  password = local.db_creds.password
}
```

## 2. HTTPS and SSL Configuration

### Steps:
1. Request SSL Certificate:
```hcl
resource "aws_acm_certificate" "main" {
  domain_name       = "yourdomain.com"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn
}
```

2. Update ALB Listener:
```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
```

## 3. Backup Strategy

### Database Backups:
1. Enable automated backups:
```hcl
resource "aws_db_instance" "main" {
  # ... other configurations ...
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"
}
```

2. Create Read Replica for disaster recovery:
```hcl
resource "aws_db_instance" "replica" {
  instance_class       = "db.t3.micro"
  replicate_source_db  = aws_db_instance.main.id
  skip_final_snapshot  = true
}
```

### S3 Backup:
```hcl
resource "aws_s3_bucket" "backup" {
  bucket = "${var.environment}-backups"
  
  versioning {
    enabled = true
  }

  lifecycle_rule {
    enabled = true
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}
```

## 4. Security Hardening

### Network Security:
1. Create Network ACLs:
```hcl
resource "aws_network_acl" "main" {
  vpc_id = aws_vpc.main.id

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}
```

2. Enable VPC Flow Logs:
```hcl
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
```

### Instance Security:
1. Enable Systems Manager Session Manager for secure SSH access
2. Use IMDSv2 for EC2 instances:
```hcl
resource "aws_launch_template" "web" {
  # ... other configurations ...
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                = "required"
    http_put_response_hop_limit = 1
  }
}
```

## 5. CI/CD Pipeline Setup

### GitHub Actions Pipeline:
1. Create `.github/workflows/deploy.yml`:
```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v1
      
      - name: Terraform Init
        run: terraform init
      
      - name: Terraform Plan
        run: terraform plan
      
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve
```

2. Set up GitHub Secrets:
   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY
   - Other sensitive variables

### Application Deployment:
1. Create ECR repository for Docker images:
```hcl
resource "aws_ecr_repository" "app" {
  name = "${var.environment}-app"
}
```

2. Update Launch Template to pull from ECR:
```hcl
resource "aws_launch_template" "web" {
  # ... other configurations ...
  user_data = base64encode(<<-EOF
    #!/bin/bash
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}
    docker pull ${aws_ecr_repository.app.repository_url}:latest
    docker run -d -p 80:80 ${aws_ecr_repository.app.repository_url}:latest
  EOF
  )
}
```

## Best Practices

1. **Secret Management**:
   - Rotate secrets regularly
   - Use separate secrets for different environments
   - Implement least privilege access

2. **SSL/TLS**:
   - Use only TLS 1.2 or higher
   - Regularly rotate certificates
   - Enable HSTS

3. **Backups**:
   - Test backup restoration regularly
   - Maintain backup copies in different regions
   - Document recovery procedures

4. **Security**:
   - Enable AWS GuardDuty
   - Use AWS Security Hub
   - Implement AWS Config rules
   - Regular security audits

5. **CI/CD**:
   - Use infrastructure as code
   - Implement automated testing
   - Use separate environments for staging/production
   - Implement blue-green deployments