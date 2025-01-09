locals {
  dockerlabels = jsonencode(merge([for mapping in var.port_mappings : (mapping.http_subdomain == null ? {
    "traefik.tcp.routers.${var.identifier}-${mapping.lb_port}.entrypoints"               = "p${mapping.lb_port}",
    "traefik.tcp.routers.${var.identifier}-${mapping.lb_port}.service"                   = "${var.identifier}-${mapping.lb_port}",
    "traefik.tcp.services.${var.identifier}-${mapping.lb_port}.loadbalancer.server.port" = "${tostring(mapping.instance_port)}"
    "traefik.tcp.routers.${var.identifier}-${mapping.lb_port}.rule"                      = "HostSNI(`*`)",
    "traefik.enable"                                                                     = "true",
    } : merge({
      "traefik.http.routers.${mapping.http_subdomain}.entrypoints"               = "webSecure",
      "traefik.http.routers.${mapping.http_subdomain}.service"                   = "${mapping.http_subdomain}",
      "traefik.http.services.${mapping.http_subdomain}.loadbalancer.server.port" = "${tostring(mapping.instance_port)}"
      "traefik.http.routers.${mapping.http_subdomain}.rule"                      = "Host(`${mapping.http_subdomain}.${var.challenge_cluster.chall_domain}`)"

      # HTTPS
      "traefik.enable"                                     = "true"
      "traefik.http.routers.${mapping.http_subdomain}.tls" = "true"

      # HTTP => HTTPS redirect
      "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme" = "https",
      "traefik.http.routers.${mapping.http_subdomain}-redir.rule"        = "Host(`${mapping.http_subdomain}.${var.challenge_cluster.chall_domain}`)"
      "traefik.http.routers.${mapping.http_subdomain}-redir.entrypoints" = "web"
      "traefik.http.routers.${mapping.http_subdomain}-redir.middlewares" = "redirect-to-https"

      "traefik.http.routers.${mapping.http_subdomain}.tls.domains.0.main" = "*.${var.challenge_cluster.chall_domain}"
      "traefik.http.routers.${mapping.http_subdomain}.tls.certResolver" : "mydnsresolver",
    },
    (var.rate_limit != 0) ? (
      (mapping.http_subdomain != null) ? {
        "traefik.http.middlewares.test-ratelimit-${mapping.http_subdomain}.ratelimit.average" = "${var.rate_limit}",
        "traefik.http.middlewares.test-ratelimit-${mapping.http_subdomain}.ratelimit.burst"   = "${var.rate_limit / 2}",
        "traefik.http.routers.${mapping.http_subdomain}.middlewares"                          = "test-ratelimit-${mapping.http_subdomain}"
        } : {
        "traefik.tcp.middlewares.test-inflightconn-${var.identifier}.inflightconn.amount" = "${var.rate_limit}",
        "traefik.http.routers.${var.identifier}-${mapping.lb_port}.middlewares"           = "test-inflightconn-${var.identifier}"
    }) : {}
  )) if mapping.lb_port != "0"]...))
}

data "template_file" "container_definitions" {
  template = file("ecs/container.json")

  vars = {
    container_name   = var.identifier
    image_label      = var.identifier
    portMappingsJSON = join(",", formatlist("{\"hostPort\": %d, \"protocol\": \"tcp\", \"containerPort\": %d}", [for mapping in var.port_mappings : mapping.instance_port], [for mapping in var.port_mappings : mapping.container_port]))
    privileged       = var.privileged
    aws_region       = var.challenge_cluster.region
    environmentJSON  = join(",", formatlist("{\"name\": \"%s\", \"value\": \"%s\"}", [for mapping in var.environment : mapping.name], [for mapping in var.environment : mapping.value]))
    dockerLabelsJSON = local.dockerlabels
    healthcheck_cmd  = var.skip_health_check ? "echo succ" : join(" && ", formatlist("nc -z localhost %s", [for mapping in var.port_mappings : mapping.container_port]))
    ecr_repository   = var.challenge_cluster.ecr_repository
  }
}

resource "aws_ecs_task_definition" "task_def" {
  family                   = var.identifier
  container_definitions    = data.template_file.container_definitions.rendered
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  memory                   = var.memory
  cpu                      = var.cpu > 0 ? var.cpu : null

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.subnet-id in [${var.challenge_cluster.hack_subnet_id}]"
  }

  tags = {
    event = var.challenge_cluster.event_tag
  }
}

resource "aws_ecs_service" "service" {
  name            = var.identifier
  cluster         = var.challenge_cluster.cluster_id
  task_definition = aws_ecs_task_definition.task_def.arn
  desired_count   = var.desired_count
  depends_on      = [var.challenge_cluster]

  tags = {
    event = var.challenge_cluster.event_tag
  }
}
