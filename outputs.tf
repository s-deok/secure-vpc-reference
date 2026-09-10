output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_a.id
}

output "private_subnet_id" {
  value = aws_subnet.private_a.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "nat_gateway_a_id" {
  value = aws_nat_gateway.nat_a.id
}

output "nat_gateway_b_id" {
  value = aws_nat_gateway.nat_b.id
}

output "public_ec2_id" {
  description = "Session Manager 접속 대상 - Public EC2 Instance ID"
  value       = aws_instance.public_ec2.id
}

output "public_ec2_public_ip" {
  value = aws_instance.public_ec2.public_ip
}

output "private_ec2_id" {
  description = "Session Manager 접속 대상 - Private EC2 Instance ID"
  value       = aws_instance.private_ec2.id
}

output "private_ec2_private_ip" {
  value = aws_instance.private_ec2.private_ip
}
