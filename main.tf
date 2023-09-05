provider "aws" {
  region = "eu-central-1"
  default_tags {
    tags = {
      Name = "infra-app"
      Terraform  = true
    }
  }
}

# VPC resources ->
resource "aws_vpc" "vpc" { cidr_block = var.cidr_block }
resource "aws_route_table" "private" { vpc_id = aws_vpc.vpc.id }
resource "aws_route_table" "public" { vpc_id = aws_vpc.vpc.id }
resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.vpc.id }
resource "aws_eip" "ip1" {
  domain = "vpc"
  depends_on = [ aws_internet_gateway.igw ]
  }
resource "aws_eip" "ip2" {
  domain = "vpc"
  depends_on = [ aws_internet_gateway.igw ]
}
resource "aws_subnet" "public_subnet1" {
  vpc_id = aws_vpc.vpc.id
  availability_zone = "${var.region}a"
  cidr_block = var.public-subnets[0]
  tags = { Name = "public1" }
}
resource "aws_subnet" "private_subnet1" {
  vpc_id = aws_vpc.vpc.id
  availability_zone = "${var.region}a"
  cidr_block = var.private-subnets[0]
  tags = { Name = "private1" }
}
resource "aws_subnet" "public_subnet2" {
  vpc_id = aws_vpc.vpc.id
  availability_zone = "${var.region}b"
  cidr_block = var.public-subnets[1]
  tags = { Name = "public2" }
}
resource "aws_subnet" "private_subnet2" {
  vpc_id = aws_vpc.vpc.id
  availability_zone = "${var.region}b"
  cidr_block = var.private-subnets[1]
  tags = { Name = "private2" }
}
resource "aws_nat_gateway" "private_gw1" {
  allocation_id = aws_eip.ip1.id
  subnet_id = aws_subnet.public_subnet1.id
}
resource "aws_nat_gateway" "private_gw2" {
  allocation_id = aws_eip.ip2.id
  subnet_id = aws_subnet.public_subnet2.id
}
resource "aws_route_table_association" "private1" {
  subnet_id = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private2" {
  subnet_id = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "public1" {
  subnet_id = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public2" {
  subnet_id = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route" "private" {
  route_table_id = aws_route_table.private.id
  nat_gateway_id = aws_nat_gateway.private_gw1.id
  destination_cidr_block = "0.0.0.0/0"
}
resource "aws_route" "public" {
  route_table_id = aws_route_table.public.id
  gateway_id = aws_internet_gateway.igw.id
  destination_cidr_block = "0.0.0.0/0"
}

# Instances ->
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"]
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
resource "aws_key_pair" "key" {
  key_name = "ssh"
  public_key = var.key
}
resource "aws_security_group" "ssh" {
  name = "ssh"
  vpc_id = aws_vpc.vpc.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "cicd" {
  name = "cicd"
  vpc_id = aws_vpc.vpc.id
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_instance" "bastion" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ssh.id]
  associate_public_ip_address = true
  subnet_id = aws_subnet.public_subnet1.id
  key_name = aws_key_pair.key.key_name
  tags = { Name = "Bastion-instance" }
}
resource "aws_instance" "ci-cd" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.cicd.id]
  subnet_id = aws_subnet.private_subnet1.id
  tags = { Name = "CI/CD-instance" }
}
resource "aws_db_subnet_group" "subnet-group" {
  name       = "rds-subnet"
  subnet_ids = [aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id]
}
resource "aws_db_instance" "rds" {
  db_subnet_group_name = aws_db_subnet_group.subnet-group.name
  allocated_storage    = 10
  identifier           = "rdsinstance"
  db_name              = "infradb"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = "infra"
  password             = "SecurePa$$w0rd"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}