resource "aws_ecr_repository" "python_app" {
  name = "${var.repository_name}"
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

data "template_file" "python_app_task" {
    template = "${file("${path.module}/tasks/python_app_task_definition.json")}"

    vars {
        image           = "${aws_ecr_repository.python_app.repository_url}"
    }
}

resource "aws_ecs_task_definition" "python_app" {
  family                   = "${var.environment}_python_app"
  container_definitions    = "${data.template_file.python_app_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "${aws_iam_role.ecs_execution_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_execution_role.arn}"
}

resource "aws_alb_target_group" "alb_target_group" {
  name     = "${var.environment}-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
  target_type = "ip"

    lifecycle {
        create_before_destroy = true
  
    }
}

resource "aws_security_group" "python_app_inbound_sg" {
  name        = "${var.environment}-python-app-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
  vpc_id      = "${var.vpc_id}"

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8
        to_port     = 0
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    tags {
        Name = "${var.environment}-python-app-inbound-sg"
    }
}

resource "aws_alb" "alb_python_app" {
    name            = "${var.environment}-alb-python-app"
    subnets         = ["${var.public_subnet_ids}"]
    security_groups = ["${var.security_groups_ids}", "${aws_security_group.python_app_inbound_sg.id}"]

    tags {
        Name        = "${var.environment}-alb-python-app"
        Environment = "${var.environment}"
    }
}

resource "aws_alb_listener" "python_app" {
    load_balancer_arn = "${aws_alb.alb_python_app.arn}"
    port              = "80"
    protocol          = "HTTP"
    depends_on        = ["aws_alb_target_group.alb_target_group"]

    default_action {
        target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
        type             = "forward"
    }
}

data "aws_iam_policy_document" "ecs_service_role" {
    statement {
        effect = "Allow"
        actions = ["sts:AssumeRole"]
        principals {
            type = "Service"
            identifiers = ["ecs.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "ecs_role" {
    name               = "ecs_role"
    assume_role_policy = "${data.aws_iam_policy_document.ecs_service_role.json}"
}

data "aws_iam_policy_document" "ecs_service_policy" {
    statement {
        effect = "Allow"
        resources = ["*"]
        actions = [
            "elasticloadbalancing:Describe*",
            "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
            "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
            "ec2:Describe*",
            "ec2:AuthorizeSecurityGroupIngress"
        ]
    }
}

resource "aws_iam_role_policy" "ecs_service_role_policy" {
    name   = "ecs_service_role_policy"
    policy = "${file("${path.module}/policies/ecs-service-role.json")}"
    role   = "${aws_iam_role.ecs_role.id}"
}

resource "aws_iam_role" "ecs_execution_role" {
    name               = "ecs_task_execution_role"
    assume_role_policy = "${file("${path.module}/policies/ecs-task-execution-role.json")}"
}

resource "aws_iam_role_policy" "ecs_execution_role_policy" {
    name   = "ecs_execution_role_policy"
    policy = "${file("${path.module}/policies/ecs-execution-role-policy.json")}"
    role   = "${aws_iam_role.ecs_execution_role.id}"
}

resource "aws_security_group" "ecs_service" {
    vpc_id      = "${var.vpc_id}"
    name        = "${var.environment}-ecs-service-sg"
    description = "Allow egress from container"

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8
        to_port     = 0
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags {
        Name        = "${var.environment}-ecs-service-sg"
        Environment = "${var.environment}"
    }
}

data "aws_ecs_task_definition" "python_app" {
    task_definition = "${aws_ecs_task_definition.python_app.family}"
}

resource "aws_ecs_service" "python_app" {
    name            = "${var.environment}-python_app"
    task_definition = "${aws_ecs_task_definition.python_app.family}:${max("${aws_ecs_task_definition.python_app.revision}", "${data.aws_ecs_task_definition.python_app.revision}")}"
    desired_count   = 1
    launch_type     = "FARGATE"
    cluster =       "${aws_ecs_cluster.cluster.id}"
    depends_on      = ["aws_iam_role_policy.ecs_service_role_policy"]

    network_configuration {
        security_groups = ["${var.security_groups_ids}", "${aws_security_group.ecs_service.id}"]
        subnets         = ["${var.subnets_ids}"]
    }

    load_balancer {
        target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
        container_name   = "python_app"
        container_port   = "80"
    }

    depends_on = ["aws_alb_target_group.alb_target_group"]
}
