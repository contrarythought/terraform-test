provider "aws" {
    region = "us-east-1"
}

resource "aws_launch_template" "my_instance" {
    image_id = "ami-084568db4383264d4"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.instance.id]

    user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "Hello, World" > index.html
    nohup busybox httpd -f -p ${var.server_port} &
    EOF
    )  

    lifecycle {
        create_before_destroy = true
    } 
}

resource "aws_autoscaling_group" "my_asg" {
    launch_template {
      id = aws_launch_template.my_instance.id
      version = "$Latest"
    }
    vpc_zone_identifier = data.aws_subnets.default.ids
    target_group_arns = [aws_lb_target_group.my_target_group.arn]
    health_check_type = "ELB"

    min_size = 2
    max_size = 10

    tag {
        key = "Name"
        value = "terraform-asg-example"
        propagate_at_launch = true
    }
}

resource "aws_security_group" "instance" {
    name = "terraform-example-instance"
    
    ingress {
        from_port = var.server_port
        to_port = var.server_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb" "example_lb" {
    name = "terraform-asg-example"
    load_balancer_type = "application"
    subnets = data.aws_subnets.default.ids
    security_groups = [ aws_security_group.alb.id ]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example_lb.arn
    port = 80
    protocol = "HTTP"

    default_action {
        type = "fixed-response"

        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code = 404
        }   
    }
}

resource "aws_lb_target_group" "my_target_group" {
    name = "terraform-asg-example"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
        path = "/"
        protocol = "HTTP"
        matcher = "200"
        interval = 15
        timeout = 3 
        healthy_threshold = 2
        unhealthy_threshold = 2
    }   
}

resource "aws_security_group" "alb" {
    name = "terraform-alb-example"

    # allow inbound HTTP requests
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # allow outbound requests
    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority = 100

    condition {
        path_pattern {
          values = ["*"]
        }
    }

    action {
      type = "forward"
      target_group_arn = aws_lb_target_group.my_target_group.arn
    }
}

variable "server_port" {
    description = "the port the server will use for HTTP requests"
    type = number
    default = 8080
}

output "alb_dns_name" {
    value = aws_lb.example_lb.dns_name
    description = "the domain name of the load balancer"
}

data "aws_vpc" "default" {
    default = true  
}

data "aws_subnets" "default" {
    filter {
        name = "vpc-id"
        values = [ data.aws_vpc.default.id ]
    }
}