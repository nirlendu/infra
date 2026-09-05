# infra

Account-wide AWS and Cloudflare resources that every app in this account consumes: the shared VPC,
account-level cost guardrails (budgets, billing alarm, anomaly detector, SNS alerts), per-service
anti-budgets that fire on the first dollar of a cost-killer like NAT Gateway or ALB, and an opt-in
IAM policy that denies the worst offenders outright.

Terraform owns every resource here. Nothing in this account is created, changed or deleted by hand —
see `COST-GUARDRAILS.md` for the layer map.

## Run

```sh
cd terraform      # or: clusters/ (per-company), cloudflare/ (edge), existing/ (imported)

terraform init
terraform plan    # always read the plan
terraform apply
```

A secret's *value* is the one thing set out of band, so it never enters Terraform state:

```sh
aws ssm put-parameter --name /path --type SecureString --value "…" --overwrite
```
