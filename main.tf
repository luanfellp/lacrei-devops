terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Região da AWS
provider "aws" {
  region = "us-east-1"
}

# Chave SSH
resource "aws_key_pair" "lacrei" {
  key_name   = "lacrei-devops-key"
  public_key = file("${path.module}/aws.pub")

  tags = {
    Name = "Lacrei DevOps Key"
  }
}

# 1. Security Group
resource "aws_security_group" "lacrei_sg" {
  name        = "lacrei-devops-sg"
  description = "Permite trafego web e acesso SSH restrito"

  # Libera HTTP (Para o desafio, usaremos a 80, mas você documentará o HTTPS/443 depois)
  ingress {
    description = "HTTP Web Traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Libera SSH - ATENÇÃO: Para o desafio, ideal é restringir ao IP do GitHub Actions ou seu IP
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Troque para o seu IP real depois, ex: "203.0.113.0/32"
  }

  # Egress liberado para baixar atualizações e imagens Docker
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Busca a AMI mais recente do Ubuntu 24.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 3. Script para instalar o Docker automaticamente na inicialização (User Data)
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

# 4. Staging EC2
resource "aws_instance" "staging" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro" # Free tier

  vpc_security_group_ids = [aws_security_group.lacrei_sg.id]

  # Adicione o nome da sua chave SSH (Key Pair) já criada na AWS
  key_name = aws_key_pair.lacrei.key_name

  user_data = local.install_docker

  tags = {
    Name        = "Lacrei-Staging"
    Environment = "Staging"
  }
}

# 5. Prod EC2
resource "aws_instance" "production" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro" # Free tier

  vpc_security_group_ids = [aws_security_group.lacrei_sg.id]

  # Adicione o nome da sua chave SSH (Key Pair) já criada na AWS
  key_name = aws_key_pair.lacrei.key_name

  user_data = local.install_docker

  tags = {
    Name        = "Lacrei-Production"
    Environment = "Production"
  }
}

# 6. Outputs para mostrar os IPs no terminal após a criação
output "ip_staging" {
  value       = aws_instance.staging.public_ip
  description = "IP Publico do ambiente de Staging"
}

output "ip_production" {
  value       = aws_instance.production.public_ip
  description = "IP Publico do ambiente de Producao"
}