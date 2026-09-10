environment          = "production"
aws_region           = "eu-central-1"
instance_type        = "t3.small"
asg_min_size         = 2
asg_max_size         = 4
asg_desired_capacity = 2

alert_email = "trepitonpavlo@gmail.com"

# docker_image is required. scripts/build-image.sh writes production.image.local.tfvars.
# Always pass that second var-file; the old :dev image is ARM64 and cannot run on t3.

# key_name         = "my-keypair"
# ssh_allowed_cidr = "1.2.3.4/32"
