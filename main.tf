provider "aws" {
  region = "us-east-1"
}

# --- 1. NETWORK DATA ---
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- 2. SECURITY GROUPS ---
resource "aws_security_group" "alb_sg" {
  name        = "strapi-alb-sg-v-final"
  vpc_id      = data.aws_vpc.default.id
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "strapi-ecs-sg-v-final"
  vpc_id      = data.aws_vpc.default.id
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

# --- 3. LOAD BALANCER & TARGET GROUPS ---
resource "aws_lb" "main" {
  name               = "strapi-alb-v-final"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "blue" {
  name        = "tg-blue-v-final"
  port        = 1337
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id
  health_check { path = "/" }
}

resource "aws_lb_target_group" "green" {
  name        = "tg-green-v-final"
  port        = 1337
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id
  health_check { path = "/" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# --- 4. ECS CLUSTER & TASK DEFINITION ---
resource "aws_ecs_cluster" "main" {
  name = "strapi-cluster-v-final"
}

resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task-v-final"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
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

# --- 5. ECS SERVICE (Corrected load_balancer block) ---
resource "aws_ecs_service" "strapi" {
  name            = "strapi-service-v-final"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.strapi.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "strapi-container"
    container_port   = 1337
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

# --- 6. CODEDEPLOY APPLICATION & GROUP ---
resource "aws_codedeploy_app" "strapi" {
  compute_platform = "ECS"
  name             = "StrapiApp-v-final"
}

resource "aws_codedeploy_deployment_group" "strapi" {
  app_name               = aws_codedeploy_app.strapi.name
  deployment_group_name  = "StrapiGroup-v-final"
  service_role_arn       = "arn:aws:iam::811738710312:role/strapi-ecs-execution-role"
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 1
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.strapi.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }
      target_group {
        name = aws_lb_target_group.blue.name
      }
      target_group {
        name = aws_lb_target_group.green.name
      }
    }
  }
}

output "ALB_DNS" {
  value = aws_lb.main.dns_name
}