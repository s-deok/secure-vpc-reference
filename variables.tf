variable "aws_region" {
  description = "배포할 AWS 리전"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "사용할 AWS CLI profile 이름"
  type        = string
  default     = "cloudgoat"
}
