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

resource "ibm_is_vpc" "vpc1" {
  name = "bank_vpc1"
}

resource "ibm_is_subnet" "subnet1" {
  name                     = "bank_subnet1"
  vpc                      = ibm_is_vpc.vpc1.id
  zone                     = "us_south-1"
  total_ipv4_address_count = 256
}

data "ibm_resource_group" "resource_group" {
  name = var.resource_group
}

resource "ibm_container_vpc_cluster" "cluster" {
  name              = var.cluster_name
  vpc_id            = ibm_is_vpc.vpc1.id
  kube_version      = var.kube_version
  flavor            = var.machine_type
  worker_count      = var.default_pool_size
  resource_group_id = data.ibm_resource_group.resource_group.id
  zones {
      subnet_id = ibm_is_subnet.subnet1.id
      name      = "us-south-1"
    }
}

data "ibm_resource_group" "group" {
  name = var.resource_group
}

resource "null_resource" "create_kubernetes_toolchain" {
  provisioner "local-exec" {
    command = "${path.cwd}/scripts/create-toolchain.sh"

    environment = {
      REGION                  =  var.region
      TOOLCHAIN_TEMPLATE_REPO = var.toolchain_template_repo
      APPLICATION_REPO        = var.application_repo
      RESOURCE_GROUP          = var.resource_group
      API_KEY                 = var.ibmcloud_api_key
      CLUSTER_NAME            = var.cluster_name
      CLUSTER_NAMESPACE       = var.cluster_namespace
      CONTAINER_REGISTRY_NAMESPACE = var.registry_namespace
      TOOLCHAIN_NAME          = var.toolchain_name
      PIPELINE_TYPE           = "tekton"
      BRANCH                  = var.branch
    }
  }
}
