output "alb_dns_name" {
  value       = aws_lb.app.dns_name
  description = "DNS name of the load balancer"
}

output "cluster_name" {
  value       = aws_ecs_cluster.main.name
  description = "ECS cluster name"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECR repository URL to push the container image to"
}
