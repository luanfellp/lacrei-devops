terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "lacrei" {
  key_name   = "lacrei-devops-key"
  public_key = file("${path.module}/aws.pub")

  tags = {
    Name = "Lacrei DevOps Key"
  }
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "lacrei_sg" {
  name        = "lacrei-devops-sg"
  description = "Permite trafego web e acesso SSH restrito"

  # O HTTPS termina no CloudFront. A EC2 recebe HTTP somente dele.
  ingress {
    description     = "HTTP somente via CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  # Necessário para o deploy atual via GitHub Actions.
  ingress {
    description = "SSH Acess"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

locals {
  install_docker = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
  EOF
}

resource "aws_instance" "staging" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.lacrei_sg.id]
  key_name               = aws_key_pair.lacrei.key_name
  user_data              = local.install_docker

  tags = {
    Name        = "Lacrei-Staging"
    Environment = "Staging"
  }
}

resource "aws_instance" "production" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.lacrei_sg.id]
  key_name               = aws_key_pair.lacrei.key_name
  user_data              = local.install_docker

  tags = {
    Name        = "Lacrei-Production"
    Environment = "Production"
  }
}

data "aws_acm_certificate" "lacrei" {
  domain      = "api.luanmoura.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "staging" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Lacrei DevOps - Staging"
  price_class     = "PriceClass_100"

  aliases = ["staging-api.luanmoura.com"]

  origin {
    domain_name = aws_instance.staging.public_dns
    origin_id   = "lacrei-staging-ec2"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lacrei-staging-ec2"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id
    compress        = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.lacrei.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_cloudfront_distribution" "production" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Lacrei DevOps - Production"
  price_class     = "PriceClass_100"

  aliases = ["api.luanmoura.com"]

  origin {
    domain_name = aws_instance.production.public_dns
    origin_id   = "lacrei-production-ec2"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lacrei-production-ec2"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id
    compress        = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.lacrei.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_cloudwatch_metric_alarm" "staging_cpu_high" {
  alarm_name          = "lacrei-staging-cpu-high"
  alarm_description   = "Alerta quando a CPU de Staging fica acima de 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.staging.id
  }

  tags = {
    Environment = "Staging"
  }
}

resource "aws_cloudwatch_metric_alarm" "production_cpu_high" {
  alarm_name          = "lacrei-production-cpu-high"
  alarm_description   = "Alerta quando a CPU de Prod fica acima de 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.production.id
  }

  tags = {
    Environment = "Production"
  }
}

output "ip_staging" {
  value       = aws_instance.staging.public_ip
  description = "IP Publico do ambiente de Staging"
}

output "ip_production" {
  value       = aws_instance.production.public_ip
  description = "IP Publico do ambiente de Producao"
}

output "cloudfront_staging_domain" {
  value = aws_cloudfront_distribution.staging.domain_name
}

output "cloudfront_production_domain" {
  value = aws_cloudfront_distribution.production.domain_name
}