plan:
	terraform plan -out terraform.plan terraform

apply:
	terraform apply terraform.plan
