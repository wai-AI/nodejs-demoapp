environment          = "dev"
aws_region           = "eu-central-1"
instance_type        = "t3.micro"
asg_min_size         = 1
asg_max_size         = 2
asg_desired_capacity = 1

alert_email = "trepitonpavlo@gmail.com"

# Verified linux/amd64 image. Keep this digest for normal re-applies.
# For a new release, scripts/build-image.sh writes an overriding dev.image.local.tfvars.
docker_image = "022784798189.dkr.ecr.eu-central-1.amazonaws.com/nodejs-demoapp@sha256:9c2c34d361c4bfd40bf2b8d414f9b532449ee958a475e906a1bae8d2736918a9"

# key_name         = "my-keypair"   # розкоментуй, якщо потрібен SSH-доступ
# ssh_allowed_cidr = "1.2.3.4/32"   # твій IP, якщо розкоментував key_name
