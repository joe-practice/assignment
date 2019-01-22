locals {
    availability_zones = ["us-west-2a", "us-west-2b"]
}

provider "aws" {
    region = "${var.region}"
}

resource "aws_key_pair" "key" {
    key_name = "my_key"
    public_key = "${file("my_key.pub")}"
}

resource "aws_ecr_repository" "assignment" {
    name = "python_app"
}

module "networking" {
    source = "./modules/networking"
    environment = "assignment"
    vpc_cidr = "10.0.0.0/16"
    public_subnets_cidr = ["10.0.1.0/24"]
    private_subnets_cidr = ["10.0.10.0/24"]
    region = "${var.region}"
    availability_zones = "${local.availability_zones}"
    key_name = "my_key"
}

module "ecs" {
    source              = "./modules/ecs"
    environment         = "assignment"
    vpc_id              = "${module.networking.vpc_id}"
    availability_zones  = "${local.availability_zones}"
    repository_name     = "python_app/assignment"
    subnets_ids         = ["${module.networking.private_subnets_id}"]
    public_subnet_ids   = ["${module.networking.public_subnets_id}"]
    security_groups_ids = [
        "${module.networking.security_groups_ids}"
    ]
}
