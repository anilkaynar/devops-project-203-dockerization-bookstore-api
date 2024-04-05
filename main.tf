terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~>6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "github" {
  token = var.github-token
}

variable "github-token" {
  default = "xxxxxxxxxxxxxxxxxx" 
}

variable "files" {
  default = ["bookstore-api.py", "docker-compose.yaml", "Dockerfile", "requirements.txt"]
}

variable "key-name" {
  default = "xxxxxxxxxxxxxxx"
}

resource "github_repository" "myrepo" {
  name       = "bookstore-api-repo"
  visibility = "private"
  auto_init  = true
}

resource "github_branch_default" "main" {
  branch     = "main"
  repository = github_repository.myrepo.name
}


resource "github_repository_file" "app-files" {
  for_each            = toset(var.files)
  content             = file(each.value)
  file                = each.value
  repository          = github_repository.myrepo.name
  branch              = "main"
  commit_message      = "managed by terraform"
  overwrite_on_create = true
}

resource "aws_security_group" "tf-docker-sec-gr" {
  name = "docker-sec-gr-203"
  tags = {
    "Name" = "docker-sec-gr-203"
  }
  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "tf-docker-instance" {
  ami                    = "ami-051f8a213df8bc089"
  instance_type          = "t2.micro"
  key_name               = var.key-name
  vpc_security_group_ids = [aws_security_group.tf-docker-sec-gr.id]
  tags = {
    "Name" = "Web Server of Bookstore"
  }
  user_data  = <<-EOF
          #!/bin/bash
          dnf update -y
          dnf install -y docker
          systemctl start docker
          systemctl enable docker
          usermod -a -G docker ec2-user
          newgrp docker
          curl -SL https://github.com/docker/compose/releases/download/v2.17.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
          chmod +x /usr/local/bin/docker-compose
          mkdir -p /home/ec2-user/bookstore-api
          TOKEN="${var.github-token}"
          FOLDER="https://$TOKEN@raw.githubusercontent.com/anilkaynar/bookstore-api-repo/main/"
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/app.py" -L "$FOLDER"bookstore-api.py
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/requirements.txt" -L "$FOLDER"requirements.txt
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/Dockerfile" -L "$FOLDER"Dockerfile
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/docker-compose.yml" -L "$FOLDER"docker-compose.yaml
          cd /home/ec2-user/bookstore-api
          docker build -t anilkaynar/bookstoreapi:latest .
          docker-compose up -d
  EOF
  depends_on = [github_repository.myrepo, github_repository_file.app-files]

}

output "website" {
  value = "http://${aws_instance.tf-docker-instance.public_dns}"
}