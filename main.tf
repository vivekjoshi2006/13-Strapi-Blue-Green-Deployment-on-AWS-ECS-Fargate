provider "aws" {
  region = "us-east-1"
}

# --- 1. NETWORK DATA ---
data "aws_vpc" "selected" {
  default = true
}

data "aws_availability_zones" "available" {}

data "aws_subnet" "one_per_az" {
  for_each          = toset(data.aws_availability_zones.available.names)
  vpc_id            = data.aws_vpc.selected.id
  availability_zone = each.value

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  subnet_ids = [for s in data.aws_subnet.one_per_az : s.id]
}

# --- 2. SECURITY GROUPS ---
resource "aws_security_group" "alb_sg_final" {
  name   = "strapi-alb-sg-final-deploy"
  vpc_id = data.aws_vpc.selected.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg_final" {
  name   = "strapi-ecs-sg-final-deploy"
  vpc_id = data.aws_vpc.selected.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg_final.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. ALB & TWO TARGET GROUPS ---
resource "aws_lb" "strapi" {
  name               = "strapi-alb-final-deploy"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_final.id]
  subnets            = local.subnet_ids
}

resource "aws_lb_target_group" "blue" {
  name        = "strapi-tg-blue-final-deploy"
  port        = 1337
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.selected.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_target_group" "green" {
  name        = "strapi-tg-green-final-deploy"
  port        = 1337
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.selected.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.strapi.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# --- 4. ECS CLUSTER & TASK ---
resource "aws_ecs_cluster" "main" {
  name = "strapi-cluster-final-deploy"
}

resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task-final-deploy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = "arn:aws:iam::811738710312:role/strapi-ecs-execution-role"
  task_role_arn            = "arn:aws:iam::811738710312:role/strapi-ecs-execution-role"

  container_definitions = jsonencode([{
    name  = "strapi-container"
    image = "strapi/strapi:latest"
    portMappings = [{
      containerPort = 1337
      hostPort      = 1337
      protocol      = "tcp"
    }]
  }])
}

# --- 5. ECS SERVICE ---
resource "aws_ecs_service" "strapi" {
  name            = "strapi-service-final-deploy"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.strapi.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.ecs_sg_final.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "strapi-container"
    container_port   = 1337
  }
}

output "alb_dns_name" {
  value = aws_lb.strapi.dns_name
}