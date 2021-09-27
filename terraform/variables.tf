variable "region" {
  type        = string
  description = "IBM Cloud region where your application will be deployed (to view your current targeted region `ibmcloud cr region`)"
  default     = "us-south"
}

variable "registry_namespace" {
  type        = string
  description = "Container registry namespace to save images (`ibmcloud cr namespaces`). NOTE: The namespace must already exist, or be a unique value."
}

variable "resource_group" {
  type        = string
  description = "Resource group where the resources will be created (`ibmcloud resource groups`)"
  default     = "default"
}

variable "default_pool_size" {
  type        = string
  description = "Number of worker nodes for the new Kubernetes cluster"
  default     = "3"
}

variable "datacenter" {
  type        = string
  description = "Zone from `ibmcloud ks zones --provider vpc-classic`"
  default     = "us-south-1"
}

variable "machine_type" {
  type        = string
  description = "Name of machine type from `ibmcloud ks flavors --zone <ZONE>`"
  default     = "bx2.4x16"
}

variable "kube_version" {
  type        = string
  description = "Version of Kubernetes to apply to the new Kubernetes cluster (Run: `ibmcloud ks versions` to see available versions)"
  default     = "4.7.23_openshift"
}

variable "ibmcloud_api_key" {
  type        = string
  description = "The IAM API Key for IBM Cloud access (https://cloud.ibm.com/iam/apikeys)"
}

