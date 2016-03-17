provider "aws" {
  region = "us-east-1"
}

/* VPC */

resource "aws_vpc" "vpc" {
  cidr_block = "${var.cidr_block}"
  tags {
    Name = "ecs-spot-instances"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id = "${aws_vpc.vpc.id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${cidrsubnet(var.cidr_block, 8, 0)}"
  tags {
    name = "ecs-spot-instances"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags {
    Name = "ecs-spot-instances"
  }
}

resource "aws_route" "igw" {
  gateway_id = "${aws_internet_gateway.igw.id}"
  route_table_id = "${aws_vpc.vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
}
