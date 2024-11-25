terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "eu-west-1"  # Ireland region
}

# Variables
variable "instance_type" {
  description = "Instance type for EC2 instances"
  type        = string
  default     = "t2.micro"  # Free Tier eligible instance type
}

variable "environment" {
  description = "Environment type"
  type        = string
  default     = "Development"
}

variable "key_name" {
  description = "Key pair name"
  type        = string
  default     = "Sidkey"
}

# Data to fetch the latest Amazon Linux 2 AMI in eu-west-1 region
data "aws_ami" "ami_lookup" {
  most_recent = true
  owners      = ["amazon"]  # Amazon's official AMIs
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]  # Amazon Linux 2 AMI
  }
}

# Data for availability zones
data "aws_availability_zones" "available" {}

# VPC
resource "aws_vpc" "hitt_vpc" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "Custom_HITTVPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "hitt_igw" {
  vpc_id = aws_vpc.hitt_vpc.id
  tags = {
    Name = "HITTInternetGateway"
  }
}

# Public Subnet
resource "aws_subnet" "hitt_public_subnet" {
  vpc_id                  = aws_vpc.hitt_vpc.id
  cidr_block              = "10.0.0.0/25"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "HITTPublicSubnet"
  }
}

# Private Subnet
resource "aws_subnet" "hitt_private_subnet" {
  vpc_id                  = aws_vpc.hitt_vpc.id
  cidr_block              = "10.0.0.128/26"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "HITTPrivateSubnet"
  }
}

# Public Route Table
resource "aws_route_table" "hitt_public_rt" {
  vpc_id = aws_vpc.hitt_vpc.id
  tags = {
    Name = "HITTPublicRouteTable"
  }
}

# Public Route
resource "aws_route" "hitt_public_route" {
  route_table_id         = aws_route_table.hitt_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hitt_igw.id
}

# Public Subnet Association
resource "aws_route_table_association" "hitt_public_assoc" {
  subnet_id      = aws_subnet.hitt_public_subnet.id
  route_table_id = aws_route_table.hitt_public_rt.id
}

# NAT Gateway
resource "aws_eip" "hitt_eip" {
  vpc = true
  tags = {
    Name = "HITTElasticIP"
  }
}

resource "aws_nat_gateway" "hitt_nat" {
  allocation_id = aws_eip.hitt_eip.id
  subnet_id     = aws_subnet.hitt_public_subnet.id
  tags = {
    Name = "HITTNatGateway"
  }
}

# Private Route Table
resource "aws_route_table" "hitt_private_rt" {
  vpc_id = aws_vpc.hitt_vpc.id
  tags = {
    Name = "HITTPrivateRouteTable"
  }
}

# Private Route
resource "aws_route" "hitt_private_route" {
  route_table_id         = aws_route_table.hitt_private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.hitt_nat.id
}

# Private Subnet Association
resource "aws_route_table_association" "hitt_private_assoc" {
  subnet_id      = aws_subnet.hitt_private_subnet.id
  route_table_id = aws_route_table.hitt_private_rt.id
}

# Security Groups
resource "aws_security_group" "hitt_public_sg" {
  vpc_id = aws_vpc.hitt_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "HITTPublicSecurityGroup"
  }
}

resource "aws_security_group" "hitt_jumpbox_sg" {
  vpc_id = aws_vpc.hitt_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "HITTJumpBoxSecurityGroup"
  }
}

resource "aws_security_group" "hitt_private_sg" {
  vpc_id = aws_vpc.hitt_vpc.id
  ingress {
    from_port                = 22
    to_port                  = 22
    protocol                 = "tcp"
    security_groups          = [aws_security_group.hitt_jumpbox_sg.id]
  }
  tags = {
    Name = "HITTPrivateSecurityGroup"
  }
}

# EC2 Instances
resource "aws_instance" "hitt_public_ec2" {
  ami             = data.aws_ami.ami_lookup.id
  instance_type   = var.instance_type
  subnet_id       = aws_subnet.hitt_public_subnet.id
  key_name        = var.key_name
  security_groups = [aws_security_group.hitt_public_sg.id]
  depends_on      = [aws_security_group.hitt_public_sg]
  tags = {
    Name = "HITTpublicEC2"
  }
}

resource "aws_instance" "hitt_jumpbox" {
  ami             = data.aws_ami.ami_lookup.id
  instance_type   = var.instance_type
  subnet_id       = aws_subnet.hitt_public_subnet.id
  key_name        = var.key_name
  security_groups = [aws_security_group.hitt_jumpbox_sg.id]
  depends_on      = [aws_security_group.hitt_jumpbox_sg]
  tags = {
    Name = "HITTJumpBox"
  }
}

resource "aws_instance" "hitt_private_ec2" {
  ami             = data.aws_ami.ami_lookup.id
  instance_type   = var.instance_type
  subnet_id       = aws_subnet.hitt_private_subnet.id
  key_name        = var.key_name
  security_groups = [aws_security_group.hitt_private_sg.id]
  depends_on      = [aws_security_group.hitt_private_sg]
  tags = {
    Name = "HITTprivateEC2"
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.hitt_vpc.id
}

output "public_subnet_id" {
  value = aws_subnet.hitt_public_subnet.id
}

output "private_subnet_id" {
  value = aws_subnet.hitt_private_subnet.id
}

output "public_ec2_id" {
  value = aws_instance.hitt_public_ec2.id
}

output "jumpbox_ec2_id" {
  value = aws_instance.hitt_jumpbox.id
}

output "private_ec2_id" {
  value = aws_instance.hitt_private_ec2.id
}
