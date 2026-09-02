.PHONY: help init plan apply check

help:
	@echo "  make plan    — what would change"
	@echo "  make apply   — create/update the company clusters"
	@echo "  make check   — fmt + validate"
	@echo ""
	@echo "  Adding a company: add a key to `companies` in variables.tf, then apply."
	@echo "  Clusters are free; only Container Insights would make the count cost money."

init:
	terraform init -input=false

plan: init
	terraform plan -input=false

apply: init
	terraform apply -input=false

check:
	terraform fmt -check -diff
	terraform validate
