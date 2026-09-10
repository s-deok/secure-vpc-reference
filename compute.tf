resource "aws_security_group" "lab_sg" {
  name        = "lab-sg"
  description = "VPC lab verification SG (no SSH inbound)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "ICMP for connectivity test (VPC internal only)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lab-sg"
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  # 표준 AL2023 네이밍은 "al2023-ami-2023.x..." 형태이고,
  # Minimal 에디션은 "al2023-ami-minimal-2023.x..." 형태다.
  # "ami-2023"로 명시해야 minimal이 걸리지 않는다.
  # (오늘 실습에서 실제로 겪은 함정: 느슨한 필터 "al2023-ami-*"는
  # minimal도 함께 매치되고, SSM Agent가 없는 minimal이 "가장
  # 최근"으로 뽑혀서 SSM 접속이 통째로 실패했다.)
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }
}

# SSM Agent가 al2023에 내장되어 있어도, 서비스가 disabled 상태로
# 시작될 수 있는 케이스를 대비해 부팅 시 명시적으로 활성화/시작한다.
locals {
  ssm_user_data = <<-EOF
    #!/bin/bash
    systemctl enable amazon-ssm-agent || dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl restart amazon-ssm-agent
  EOF
}

resource "aws_instance" "public_ec2" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.lab_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  associate_public_ip_address = true
  user_data                   = local.ssm_user_data

  tags = {
    Name = "public-ec2"
  }
}

resource "aws_instance" "private_ec2" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.lab_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  user_data              = local.ssm_user_data

  tags = {
    Name = "private-ec2"
  }
}
