provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

#####################
# API setup - BEGIN #
#####################
resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage_api" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}
###################
# API setup - END #
###################

module "staged_binary" {
  source      = "../../modules/file_storage_bucket"
  bucket_name = "${var.name}-binary-staging-storage-bucket"
  project_id  = var.project_id
  location    = var.region
  files = [
    {
      source      = var.war_filepath
      object_name = "ROOT.war"
    }
  ]
  depends_on = [google_project_service.storage_api]
}

data "template_file" "startup_script" {
  template = file("${path.module}/tomcat.sh.tpl")
  vars = {
    STAGED_BINARY   = module.staged_binary.gs_urls[0]
    DATADOG_API_KEY = datadog_api_key.agent_key.key
  }
}

module "vpc_with_nat" {
  source       = "../../modules/vpc_with_nat"
  project_id   = var.project_id
  network_name = var.name

  iap_ssh_tag                   = "iap-ssh"
  enable_default_firewall_rules = true
  router_region                 = var.region

  depends_on = [google_project_service.compute_api]
}

module "tomcat_cluster" {
  source     = "../../modules/http_accessible_mig"
  project_id = var.project_id
  region     = var.region
  mig_name   = var.name
  network    = module.vpc_with_nat.network_self_link

  startup_script    = data.template_file.startup_script.rendered
  tags              = ["iap-ssh"]
  health_check_path = "/healthz/"
  http_port         = 8080

  autoscaling_cpu_percent = 0.75

  depends_on = [google_project_service.compute_api]
}