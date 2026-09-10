# Backend спільний для всіх середовищ бакет/таблиця, але ключ (key)
# унікальний для кожного середовища - тому state dev і production
# ніколи не перетинаються.
#
# ВАЖЛИВО: бакет і DynamoDB-таблицю треба створити ЗАЗДАЛЕГІДЬ вручну
# (Terraform не може створити backend для самого себе). Дивись README.md
# у корені проєкту - там наведені готові AWS CLI команди для bootstrap.

terraform {
  backend "s3" {
    bucket         = "week3-terraform-demo-test" # TODO
    key            = "week3-task1/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
