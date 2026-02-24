# --- 1. PROVIDER ---
provider "aws" {
  region = "us-east-1"
}

# --- 2. NETWORK DATA ---
data "aws_vpc" "selected" {
  default = true
}

data "aws_availability_zones" "available" {}

data "aws_subnet" "one_per_az" {
  for_each = toset(data.aws_availability_zones.available.names)
  vpc_id   = data.aws_vpc.selected.id
  availability_zone = each.value

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  subnet_ids = [for s in data.aws_subnet.one_per_az : s.id]
}

# --- 3. SECURITY GROUPS ---
resource "aws_security_group" "alb_sg_v3" {
  name        = "strapi-alb-sg-v3"
  vpc_id      = data.aws_vpc.selected.id

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

resource "aws_security_group" "ecs_sg_v3" {
  name        = "strapi-ecs-sg-v3"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg_v3.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. LOAD BALANCER & TARGET GROUPS ---
resource "aws_lb" "strapi_v3" {
  name               = "strapi-alb-v3"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg_v3.id]
  subnets            = local.subnet_ids
}

resource "aws_lb_target_group" "blue_v3" {
  name                 = "strapi-tg-blue-v3"
  port                 = 1337
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.selected.id
  deregistration_delay = 30 
}

resource "aws_lb_target_group" "green_v3" {
  name                 = "strapi-tg-green-v3"
  port                 = 1337
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.selected.id
  deregistration_delay = 30 
}

resource "aws_lb_listener" "http_v3" {
  load_balancer_arn = aws_lb.strapi_v3.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_v3.arn
  }
}

# --- 5. ECS CLUSTER & TASK DEFINITION ---
resource "aws_ecs_cluster" "main_v3" { 
  name = "strapi-cluster-v3" 
}

resource "aws_ecs_task_definition" "strapi_v3" {
  family                   = "strapi-task-v3"
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

# --- 6. ECS SERVICE (Changed to Standard Deployment for now) ---
resource "aws_ecs_service" "strapi_v3" {
  name            = "strapi-service-v3"
  cluster         = aws_ecs_cluster.main_v3.id
  task_definition = aws_ecs_task_definition.strapi_v3.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  deployment_controller { 
    type = "ECS" 
  }

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.ecs_sg_v3.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue_v3.arn
    container_name   = "strapi-container"
    container_port   = 1337
  }
}

# --- OUTPUTS ---
output "alb_dns_name" {
  value = aws_lb.strapi_v3.dns_name
}