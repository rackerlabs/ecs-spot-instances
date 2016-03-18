provider "aws" {
  region = "${var.region}"
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

/* ECS Cluster */

resource "aws_ecs_cluster" "ecs" {
  name = "ecs-spot-instances"
}

resource "aws_iam_role" "ecs" {
  name = "ecs-spot-instances"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ec2.amazonaws.com", "ecs.amazonaws.com"]
      }
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs" {
  name = "ecs-spot-instances"
  roles = ["${aws_iam_role.ecs.name}"]
}

resource "aws_iam_policy_attachment" "container_service" {
  name = "AmazonEC2ContainerServiceRole"
  roles = ["${aws_iam_role.ecs.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_iam_policy_attachment" "container_service_for_ec2" {
  name = "AmazonEC2ContainerServiceforEC2Role"
  roles = ["${aws_iam_role.ecs.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_security_group" "ec2" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name = "ecs-spot-instances-ec2"
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = {
    Name = "ecs-spot-instances-elb"
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/* On-Demand Instances */

resource "aws_launch_configuration" "on_demand" {
  image_id = "${var.image_id}"
  instance_type = "${var.instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs.name}"
  security_groups = ["${aws_security_group.ec2.id}"]
  associate_public_ip_address = true
  user_data = <<EOF
#!/bin/bash
echo "ECS_CLUSTER=${aws_ecs_cluster.ecs.name}" > /etc/ecs/ecs.config
EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "on_demand" {
  min_size = "${var.min_instances}"
  max_size = "${var.max_instances}"
  launch_configuration = "${aws_launch_configuration.on_demand.name}"
  vpc_zone_identifier = ["${aws_subnet.subnet.id}"]
  termination_policies = ["ClosestToNextInstanceHour"]
  enabled_metrics = ["GroupPendingInstances", "GroupTerminatingInstances"]

  lifecycle {
    create_before_destroy = true
  }
}

/* Spot Instances */

resource "aws_launch_configuration" "spot" {
  image_id = "${var.image_id}"
  instance_type = "${var.instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs.name}"
  security_groups = ["${aws_security_group.ec2.id}"]
  associate_public_ip_address = true
  spot_price = "${var.bid_price}"
  user_data = <<EOF
#!/bin/bash
echo "ECS_CLUSTER=${aws_ecs_cluster.ecs.name}" > /etc/ecs/ecs.config
EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "spot" {
  min_size = "${var.min_instances - var.min_instances}"
  max_size = "${var.max_instances - var.min_instances}"
  launch_configuration = "${aws_launch_configuration.spot.name}"
  vpc_zone_identifier = ["${aws_subnet.subnet.id}"]
  enabled_metrics = ["GroupPendingInstances", "GroupTerminatingInstances"]

  lifecycle {
    create_before_destroy = true
  }
}

/* Scaling Policies */

resource "aws_autoscaling_policy" "scale_up" {
  name = "ecs-spot-instances-scale_up"
  autoscaling_group_name = "${aws_autoscaling_group.on_demand.name}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  name = "ecs-spot-instances-scale_down"
  autoscaling_group_name = "${aws_autoscaling_group.on_demand.name}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 300
}

resource "aws_cloudwatch_metric_alarm" "spot_pending" {
  alarm_name = "ecs-spot-instances-spot_pending"
  namespace = "AWS/ECS"
  metric_name = "MemoryReservation"
  statistic = "Sum"
  period = "300"
  evaluation_periods = "1"
  threshold = "80"
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions {
    ClusterName = "${aws_ecs_cluster.ecs.name}"
  }

  alarm_actions = [
    "${aws_autoscaling_policy.scale_down.arn}"
  ]
}

/* Based on reservation, send scale up. */
/* When spot instances scale up, scale down on-demand instances. */
/* When spot instances scale down, scale up on-demand instances. */

/*

resource "aws_cloudwatch_metric_alarm" "spot_terminating" {
  alarm_name = "ecs-spot-instances-spot_terminating"
  namespace = "AWS/ECS"
  metric_name = "MemoryReservation"
  statistic = "Average"
  period = "300"
  evaluation_periods = "1"
  threshold = "60"
  comparison_operator = "LessThanOrEqualToThreshold"

  dimensions {
    ClusterName = "${aws_ecs_cluster.ecs.name}"
  }

  alarm_actions = [
    "${aws_autoscaling_policy.scale_down.arn}"
  ]
}*/
