terraform {
  required_version = ">= 0.14.0"
  required_providers {
    ibm = {
      source  = "ibm-cloud/ibm"
      version = ">= 1.27.0"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "null" {
}

data "ibm_resource_group" "resource_group" {
  name = var.resource_group
}

resource "ibm_is_vpc" "vpc1" {
  name  = "bank-vpc-${formatdate("YYYYMMDDhhmm", timestamp())}"
}

resource "ibm_is_public_gateway" "vpc_gateway" {
  name = "bank-vpc-gateway-${formatdate("YYYYMMDDhhmm", timestamp())}"
  vpc  = ibm_is_vpc.vpc1.id
  zone = var.datacenter
}

resource "ibm_is_subnet" "subnet1" {
  name                     = "bank-subnet-${formatdate("YYYYMMDDhhmm", timestamp())}"
  vpc                      = ibm_is_vpc.vpc1.id
  zone                     = var.datacenter
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.vpc_gateway.id
}

resource "ibm_resource_instance" "cos_instance" {
  name     = "bank-cos-instance-${formatdate("YYYYMMDDhhmm", timestamp())}"
  resource_group_id = data.ibm_resource_group.resource_group.id
  service  = "cloud-object-storage"
  plan     = "standard"
  location = "global"
}

resource "ibm_cos_bucket" "cos_bucket" {
  bucket_name          = "bank-cos-bucket-${formatdate("YYYYMMDDhhmm", timestamp())}"
  resource_instance_id = ibm_resource_instance.cos_instance.id
  region_location      = var.region
  storage_class        = "standard"
}

resource "ibm_iam_service_id" "cos_serviceID" {
  name = "bank-cos-service-id"
}

resource "ibm_iam_service_api_key" "cos_service_api_key" {
  name           = "bank-cos-service-api-key"
  iam_service_id = ibm_iam_service_id.cos_serviceID.iam_id
}

resource "ibm_iam_service_policy" "cos_policy" {
  iam_service_id = ibm_iam_service_id.cos_serviceID.id
  roles          = ["Reader", "Writer"]

  resources {
    service              = "cloud-object-storage"
    resource_instance_id = ibm_resource_instance.cos_instance.id
  }
}

resource "ibm_container_vpc_cluster" "cluster" {
  name              = "bank_vpc_cluster-${formatdate("YYYYMMDDhhmm", timestamp())}"
  vpc_id            = ibm_is_vpc.vpc1.id
  kube_version      = var.kube_version
  flavor            = var.machine_type
  worker_count      = var.default_pool_size
  cos_instance_crn  = ibm_resource_instance.cos_instance.id
  resource_group_id = data.ibm_resource_group.resource_group.id
  zones {
      subnet_id = ibm_is_subnet.subnet1.id
      name      = var.datacenter
    }
}

resource "null_resource" "create_kubernetes_toolchain" {
  depends_on = [ibm_container_vpc_cluster.cluster]
  provisioner "local-exec" {
    command = "${path.cwd}/scripts/create-toolchain.sh"
    environment = {
      MOBILE_SIM              = "mobile-simulator-${formatdate("YYYYMMDDhhmm", timestamp())}"
      REGION                  = var.region
      TOOLCHAIN_TEMPLATE_REPO = "https://${var.region}.git.cloud.ibm.com/open-toolchain/compliance-ci-toolchain"
      APPLICATION_REPO        = "https://github.com/ChuckCox/example-bank-toolchain"
      RESOURCE_GROUP          = var.resource_group
      API_KEY                 = var.ibmcloud_api_key
      CLUSTER_NAME            = ibm_container_vpc_cluster.cluster.name
      CLUSTER_NAMESPACE       = "example-bank"
      CONTAINER_REGISTRY_NAMESPACE = var.registry_namespace
      TOOLCHAIN_NAME          = "example-bank-toolchain-${formatdate("YYYYMMDDhhmm", timestamp())}"
      PIPELINE_TYPE           = "tekton"
      PIPELINE_CONFIG_BRANCH  = "main"
      BRANCH                  = "master"
      APP_NAME                = "bank-app-${formatdate("YYYYMMDDhhmm", timestamp())}"
      COS_BUCKET_NAME         = ibm_cos_bucket.cos_bucket.bucket_name
      COS_URL                 = "s3.private.${var.region}.cloud-object-storage.appdomain.cloud"
      COS_API_KEY             = ibm_iam_service_api_key.cos_service_api_key.apikey
      SM_NAME                 = var.sm_name
      SM_SERVICE_NAME         = var.sm_service_name
      GITLAB_TOKEN            = var.gitlab_token
    }
  }
}
