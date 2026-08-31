variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "app_name" {
  type        = string
  description = "Application name"
  default     = "rdicidr"
}

variable "environment" {
  type        = string
  description = "Deployment environment (devel or stage) — interpolated into all named resources so devel/stage never collide"

  validation {
    condition     = contains(["devel", "stage"], var.environment)
    error_message = "environment must be \"devel\" or \"stage\"."
  }
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID that owns the ECR repository"
  default     = "208211371137"
}

variable "container_image_tag" {
  type        = string
  description = "Tag of the image to deploy from the ECR repository"
  default     = "latest"
}

variable "container_port" {
  type        = number
  description = "Port the container listens on"
  default     = 80
}

variable "health_check_path" {
  type        = string
  description = "Health check endpoint path"
  default     = "/health"
}

variable "desired_count" {
  type        = number
  description = "Number of ECS tasks to run"
  default     = 2
}
