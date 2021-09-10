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
  name = "bank-vpc1"
}

resource "ibm_is_subnet" "subnet1" {
  name                     = "bank-subnet1"
  vpc                      = ibm_is_vpc.vpc1.id
  zone                     = var.datacenter
  total_ipv4_address_count = 256
}

data "ibm_resource_group" "resource_group" {
  name = var.resource_group
}

resource "ibm_resource_instance" "cos_instance" {
  name     = "bank-cos-instance"
  service  = "cloud-object-storage"
  plan     = "standard"
  location = "global"
}

resource "ibm_container_vpc_cluster" "cluster" {
  name              = var.cluster_name
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

data "ibm_resource_group" "group" {
  name = var.resource_group
}

resource "null_resource" "create_kubernetes_toolchain" {
  provisioner "local-exec" {
    command = "${path.cwd}/scripts/create-toolchain.sh"

    environment = {
      REGION                  = var.region
      TOOLCHAIN_TEMPLATE_REPO = "https://github.com/open-toolchain/secure-kube-toolchain"
      APPLICATION_REPO        = "https://github.com/IBM/example-bank"
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
