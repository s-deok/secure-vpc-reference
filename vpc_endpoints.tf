# ── SSM용 VPC Endpoint (Interface 타입) ──────────────
# Private EC2가 인터넷(NAT)을 거치지 않고도 Session Manager와
# 통신할 수 있게 해주는 사설 경로. SSM은 세 개의 서로 다른
# 서비스를 함께 써야 완전히 동작한다:
#   - ssm: Session Manager 제어 채널
#   - ssmmessages: 실제 세션 데이터(터미널 입출력) 전송
#   - ec2messages: 인스턴스가 SSM에 상태를 보고하는 채널
#
# 끝판왕 퀴즈 Q5에서 배운 대로, Interface Endpoint는 지정한
# subnet(AZ)에만 ENI가 생기므로, 여기서는 AZ-a, AZ-b의 private
# subnet을 모두 지정해서 두 AZ 다 커버한다.

resource "aws_security_group" "vpce_sg" {
  name        = "vpc-lab-endpoint-sg"
  description = "Allow HTTPS from within VPC to SSM endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vpc-lab-endpoint-sg"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-ssm"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-ssmmessages"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-ec2messages"
  }
}
