variable "environment" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Environment variables to be set"
}

variable "port_mappings" {
  type = list(object({
    container_port = number
    instance_port  = number
    lb_port        = optional(number)
    http_subdomain = optional(string)
  }))
  default = []
}

variable "identifier" {
  type        = string
  description = "Identifier to be used for ECR image tag and task. MUST BE THE NAME OF THE FOLDER THE DOCKERFILE IS IN"
}

variable "rate_limit" {
  type        = number
  default     = 10
  description = "Rate limit in requests per second"
}

variable "memory" {
  type        = number
  default     = 256
  description = "Memory (in Megabytes) to allocate to the deployed challenge container"
}

variable "cpu" {
  type        = number
  description = "Max cpu for the task (1024 = 1vcpu)"
  default     = 0
}

variable "skip_health_check" {
  type        = bool
  default     = true
  description = "Whether or not to skip the health check for the container"
}

variable "privileged" {
  type        = bool
  default     = false
  description = "Whether the container should run as privileged or not"
}

variable "desired_count" {
  type        = number
  default     = 1
  description = "Number of tasks"
}


variable "challenge_cluster" {
  type = object({
    chall_domain   = string,
    region         = string,
    hack_subnet_id = string,
    cluster_id     = string,
    ecr_repository = string,
    event_tag      = string,
  })
  description = "Subnets this task can be placed in. Should be [aws_subnet.challenge_subnet_1.id, aws_subnet.challenge_subnet_2.id] for hackable services"
}
