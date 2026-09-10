# Node.js on AWS with Terraform

This project runs the adjacent `nodejs-demoapp` fork in Docker on private EC2
instances, behind a public Application Load Balancer. Dev and production share
Terraform files through relative symlinks and use separate remote state keys.

## The confirmed 502 cause

On 9 September 2026, read-only checks against the deployed dev environment found:

- The ECR `nodejs-demoapp:dev` image was **linux/arm64**. Its digest was
  `sha256:9faadc1345b1506d664d48f8e5d96e86e8b6577b6784b2099c1f1300b2e7c7b4`.
- The Auto Scaling group ran an **x86_64 t3.micro** instance.
- The target on port 3000 was `unhealthy` with `Target.FailedHealthChecks`.
- The public ALB returned HTTP 502, and EC2 console output showed repeated Docker
  network teardown/recreation consistent with a restarting container.

An ARM64-only image cannot execute on these x86_64 instances. Rebuild the image
for `linux/amd64`, publish it, and replace the instances. A Terraform-only change
or an EC2 reboot cannot repair the incompatible image. The new build helper
explicitly selects the architecture and tests the container before pushing it.

Dev now pins the verified linux/amd64 image digest in `env/dev.tfvars` so normal
re-applies use the repaired image. Production and new releases use the generated
image var-file below. Do not reuse the old ARM64 `:dev` image.

## Other fixes

- Added `providers.tf -> ../common/main.tf` in both environments. Symlinking
  individual files never loaded `common/main.tf`; the AWS region and provider
  constraints there were previously ignored.
- Pinned Auto Scaling 8.3.1, VPC 5.21.0 and AWS provider 5.100.x. Auto Scaling 8.3.1
  requires AWS provider **below 6.0**, so the former shared `>= 6.56` requirement
  was incompatible. Both environments include the provider lock file.
- Added a credential wrapper for the new AWS CLI `aws login` workflow, which the
  AWS 5.x provider does not understand directly. It passes temporary credentials
  through the child process environment, without writing or printing them.
- Bootstrap now installs required tools, retries ECR login/pull, propagates
  pipeline failures, logs failures, limits Docker log growth, and checks readiness.
  It avoids a full OS update during startup. Docker restarts the container on reboot.
- Explicitly sets Node's `PORT`. The target group and EC2 security group use
  `app_port`; Docker maps it to `container_port` (3000 by default).
- Uses `/healthz` and HTTP **200** for readiness. The application fork implements
  this route before optional sessions, templates and external APIs.
- Waits for VPC routing and the ALB listener before starting the ASG, and allows
  600 seconds for initial health checks. Private instances reach ECR and package
  repositories through NAT. Dev uses one NAT; production uses one per AZ.
- Rolls instances when the launch template changes, allowing 100–200% healthy
  capacity during replacement, including a one-instance dev deployment.
- Leaves desired capacity to Auto Scaling after creation. A `moved` block
  preserves the existing ASG when changing the module's internal resource address.
- Adds SSM access and requires IMDSv2. Application ingress remains restricted to
  the ALB security group. SSH remains optional and off by default.
- Sets Node keep-alive to 65 seconds and header timeout to 66 seconds, above the
  ALB's 60-second idle timeout. This addresses an additional possible source of
  intermittent 502s described in [AWS troubleshooting guidance](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html).
- Uses `npm ci`, runs Node directly as a non-root user, provides a Docker health
  check, and drains connections on SIGTERM.
- Fixes the application's monitoring endpoint to support cgroup v2 (AL2023 and
  modern Docker), with a cgroup v1 fallback. It previously returned HTTP 500.
- Adds real ASG launch/termination success/error notifications to SNS, alongside
  CPU, unhealthy-host and no-healthy-host CloudWatch alarms.
- Adds a load test, configuration checks, regression tests and deployment checks.

## Layout

Keep these directories next to each other:

```text
week3/
├── nodejs-demoapp/                # your wai-AI/nodejs-demoapp fork
│   ├── build/Dockerfile
│   └── src/                      # server, monitoring fix and regression tests
└── week3_task1/
    ├── README.md
    ├── artillery/load-test.yml
    ├── user_data/user_data.sh     # Terraform template, not a local installer
    ├── scripts/
    │   ├── build-image.sh
    │   ├── terraform.py
    │   └── smoke-test.sh
    ├── tests/test_bootstrap.py
    └── infrastructure/
        ├── common/               # shared resources, provider and tests
        ├── dev/                  # backend main.tf plus shared symlinks
        ├── production/           # backend main.tf plus shared symlinks
        └── env/                  # dev.tfvars and production.tfvars
```

Run Terraform from an environment directory, never from `common`. Resource
addresses already in state were retained to avoid unnecessary replacement.
`app` in Terraform and `dev-app-alb` in AWS continue to identify the existing ALB.

## Deploy dev

Prerequisites: Terraform >= 1.7 and < 2.0, current AWS CLI v2, Python 3,
Docker with Buildx, and access to the configured AWS account. Commands below
run from `week3_task1`. Set `AWS_PROFILE` if you use a named profile. Region
defaults to `eu-central-1`; keep tfvars and `AWS_REGION` consistent.

1. Select your working AWS profile and build the corrected fork. The `aws-learning`
   profile uses access keys, so do not run `aws login` for that profile. For a
   separate browser-login profile, authenticate it with `aws login --profile NAME`. The ECR repository already exists
   in the inspected account. For a fresh account, create `nodejs-demoapp` in ECR
   first. This command publishes the tested image to your account and writes
   `infrastructure/env/dev.image.local.tfvars` with its immutable digest:

   ```bash
   export AWS_PROFILE=aws-learning
   aws sts get-caller-identity
   export AWS_REGION=eu-central-1
   ./scripts/build-image.sh dev
   ```

   An alternative fork location can be passed as the second argument. The helper
   builds `linux/amd64` even on an Apple Silicon Mac. It does not rely on Docker's
   host architecture default.

2. Initialize the existing dev backend, then review a saved plan:

   ```bash
   python3 scripts/terraform.py dev init
   python3 scripts/terraform.py dev plan \
     -var-file=../env/dev.tfvars \
     -var-file=../env/dev.image.local.tfvars \
     -out=dev.tfplan
   ```

3. Apply that plan and wait for actual application health:

   ```bash
   python3 scripts/terraform.py dev apply dev.tfplan
   ./scripts/smoke-test.sh dev
   ```

   Open the URL printed by the smoke test, using **http://**. This assignment's
   listener is HTTP only. Terraform apply can finish before instance refresh is
   complete; the smoke test waits for the latest refresh and healthy targets.
   The old instances may serve errors while the repair rolls out.

4. Confirm the SNS subscription email to enable delivery. This is required by
   [Amazon SNS](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-sns-notifications.html).

Never apply the earlier diagnostic plan from this review: it used the old image
only to assess state migration and infrastructure changes. Generate a fresh plan
with the newly published image digest as shown above.

## Production

Run the same steps using `production` instead of `dev`, including
`./scripts/build-image.sh production` and both production var-files. Production
starts at two instances and scales up to four; dev starts at one and scales up
to two. Production uses one NAT per AZ, which adds AWS cost. These are separate
environments, not a complete production security architecture: configure a domain
and ACM HTTPS listener before using the demo for real user traffic.

New image releases must change the image digest in Terraform; pushing different
bytes under an unchanged mutable tag does not trigger instance refresh. Change
min/max capacity through Terraform; change desired capacity through Auto Scaling
after creation, because it is intentionally ignored by Terraform.

## Remote state

The existing bucket `week3-terraform-demo-test`, DynamoDB table `terraform-locks`,
region and environment state keys are preserved. Do not change the bucket/key
for an existing deployment without explicitly migrating its state.

For a **new account only**, choose a globally unique bucket name, create it in
the configured region, enable versioning/encryption, and create a DynamoDB lock
table before initializing Terraform. For example:

```bash
export TF_STATE_BUCKET=your-unique-state-bucket
aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1
aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$TF_STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws dynamodb create-table --region eu-central-1 --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
aws dynamodb wait table-exists --region eu-central-1 --table-name terraform-locks
python3 scripts/terraform.py dev init -backend-config="bucket=$TF_STATE_BUCKET"
```

DynamoDB locking is deprecated in newer Terraform releases but retained here for
compatibility with the existing backend. A coordinated migration to S3 native
locking can be done separately; it is not necessary to repair the 502.

## Validate locally

The Terraform tests mock AWS and do not create infrastructure or send emails:

```bash
terraform fmt -check -recursive infrastructure
terraform -chdir=infrastructure/dev init -backend=false
terraform -chdir=infrastructure/dev validate
terraform -chdir=infrastructure/dev test -var-file=../env/dev.tfvars
terraform -chdir=infrastructure/production init -backend=false
terraform -chdir=infrastructure/production validate
terraform -chdir=infrastructure/production test -var-file=../env/production.tfvars
python3 -m unittest discover -s tests -v
```

Application tests, from the fork's `src` directory with Node 22 installed:

```bash
npm ci --omit=dev --no-audit --no-fund
node --test tests/aws-runtime.test.mjs tests/container-memory.test.mjs
```

For a load test after successful deployment, install Artillery v2 and run:

```bash
URL=$(python3 scripts/terraform.py dev output -raw app_url)
artillery run --target "$URL" artillery/load-test.yml
```

The test checks HTTP responses and error rate. Homepage traffic does not guarantee
enough CPU load to trigger scaling; CPU target tracking uses a 50% target and
requires sustained load. Use only your own deployment as the test target.

## Diagnose a deployment

```bash
REGION=$(python3 scripts/terraform.py dev output -raw aws_region)
TG=$(python3 scripts/terraform.py dev output -raw target_group_arn)
ASG=$(python3 scripts/terraform.py dev output -raw asg_name)
aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG"
aws autoscaling describe-instance-refreshes --region "$REGION" --auto-scaling-group-name "$ASG"
aws autoscaling describe-scaling-activities --region "$REGION" --auto-scaling-group-name "$ASG" --max-records 10
```

For the updated instances, connect using EC2 → Connect → Session Manager, or
`aws ssm start-session --target INSTANCE_ID --region eu-central-1` with the Session
Manager plugin installed. Inspect:

```bash
sudo tail -n 150 /var/log/nodejs-demoapp-bootstrap.log
sudo tail -n 150 /var/log/cloud-init-output.log
sudo docker ps -a
sudo docker logs --tail 100 nodejs-demoapp
sudo docker inspect nodejs-demoapp --format '{{.State.Health.Status}}'
curl -i http://127.0.0.1:3000/healthz
```

SSH rules alone do not give private instances Internet-reachable addresses; use
SSM or an existing private network connection. The old instances lack the added
SSM role policy until the repair is deployed.

## Submission and cleanup

The fixed source remains in your local `wai-AI/nodejs-demoapp` fork. Review and
commit its Dockerfile, server, monitoring helper, tests and `.dockerignore`, and
include this IaC directory in your submission. Accidental nested clones were not
deleted or staged. The initial source repair did not deploy. In the subsequent
authorized live repair, the tested amd64 image was pushed to ECR and the dev launch
template/ASG were updated. No GitHub push was performed.

To remove an environment when you are finished, run the wrapper's `destroy`
command with the same two var-files. That deletes deployed resources and must
only be done when you intend to tear down that environment. ECR and the shared
state bucket/table are managed separately and are not destroyed by this project.
