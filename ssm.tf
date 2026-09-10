# ── SSM용 IAM Role ───────────────────────────────────
# Session Manager로 접속하려면 인스턴스에 이 role이 붙어있어야
# 한다. AWS 관리형 정책 AmazonSSMManagedInstanceCore가 필요한
# 최소 권한을 담고 있다.
resource "aws_iam_role" "ssm_role" {
  name = "vpc-lab-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "vpc-lab-ssm-profile"
  role = aws_iam_role.ssm_role.name
}
