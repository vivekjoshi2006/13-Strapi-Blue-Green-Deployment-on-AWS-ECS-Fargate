provider "aws" {
  region = "us-east-1"
}

# --- 1. NETWORK ---
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 2. SECURITY GROUPS ---
resource "aws_security_group" "alb_sg" {
  name   = "strapi-alb-sg-final-v3"
  vpc_id = data.aws_vpc.default.id
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

resource "aws_security_group" "ecs_sg" {
  name   = "strapi-ecs-sg-final-v3"
  vpc_id = data.aws_vpc.default.id
  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. LOAD BALANCER ---
resource "aws_lb" "main" {
  name               = "strapi-alb-final-v3"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "tg" {
  name        = "tg-strapi-final-v3"
  port        = 1337
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# --- 4. ECS CLUSTER & TASK (REMOVED CUSTOM ROLE TO BYPASS PASSROLE ERROR) ---
resource "aws_ecs_cluster" "main" {
  name = "strapi-cluster-final-v3"
}

resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task-final-v3"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  
  execution_role_arn       = "arn:aws:iam::811738710312:role/LabRole"
  task_role_arn            = "arn:aws:iam::811738710312:role/LabRole"

  container_definitions    = jsonencode([{
    name  = "strapi-container"
    image = "strapi/strapi:latest"
    portMappings = [{ containerPort = 1337, hostPort = 1337, protocol = "tcp" }]
  }])
}

resource "aws_ecs_service" "strapi" {
  name            = "strapi-service-final-v3"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.strapi.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "strapi-container"
    container_port   = 1337
  }
}

output "ALB_URL" { value = aws_lb.main.dns_name }