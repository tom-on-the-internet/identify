module "infrastructure-production" {
  source                = "./infrastructure"
  host                  = "identify.tomontheinternet.com"
  root_domain           = "tomontheinternet.com"
  environment           = "production"
  application_directory = "${path.module}/"
  application_name      = "identify"
}
