###############################################################################
# 00c — ACTIVATE COST ALLOCATION TAGS
#
# Without this, every tag-filtered budget in the account silently matches nothing.
#
# A user-defined tag does not appear in billing data until it is explicitly
# activated. It is not enough to tag the resources — and the resources here ARE
# tagged correctly; `authoxi-prod-api` carries `Project=authoxi`, `Env=prod`,
# `ManagedBy=terraform`. But every key in the account read `Inactive`, so
# `authoxi-prod-total` and `agitome-prod-total` have both been reporting $0.00
# actual against a $20 limit since the day they were created.
#
# Two $20 budgets that can never fire, looking exactly like coverage. That is the
# third instance of this failure mode found in this account, after the
# data_transfer budget aimed at the wrong service and the VPC anti-budget
# permanently red from legitimate IPv4 spend. The pattern is consistent enough to
# state as a rule: A BUDGET THAT HAS NEVER REPORTED A NON-ZERO NUMBER IS NOT
# COVERAGE. Check what each one actually reads, not just that it exists.
#
# Two caveats that matter operationally:
#
#   * NOT RETROACTIVE. Activation applies to billing data going forward. Nothing
#     will explain August after the fact.
#   * SLOW. Up to 24 hours for a key to appear after resources are tagged, then
#     up to another 24 to activate. Per-app budgets stay blind for about two days
#     after this applies, so do not read $0.00 tomorrow as proof it failed.
###############################################################################

# The dimension the per-app budgets filter on. `Project` is the established key —
# authoxi and agitome both carry it, and their budgets already reference
# `user:Project$<name>`.
resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

# Company-level rollup. New with the geniusjnr cluster, where one company holds
# several products and "what does geniusjnr cost" is a question `Project` alone
# cannot answer.
#
# COMMENTED OUT UNTIL AWS SEES THE KEY. Activation fails with "Tag keys not
# found: Company" until at least one resource has carried the tag long enough for
# billing to ingest it — up to 24 hours after the resource is created, per the
# note at the top of this file. `clusters/` now tags `Company=geniusjnr`, so the
# key should appear within a day.
#
# Left commented rather than applied-and-failing on purpose: a resource that
# errors on every run blocks the entire stack, which is precisely the state the
# RDS engine_version pin had this stack in. A tripwire that cannot be applied is
# worse than one not yet written.
#
# TO RE-ENABLE: check `aws ce list-cost-allocation-tags --query
# "CostAllocationTags[?TagKey=='Company']"` returns a row, then uncomment.
#
# resource "aws_ce_cost_allocation_tag" "company" {
#   tag_key = "Company"
#   status  = "Active"
# }

# Separates prod from anything non-prod that appears later. Cheap to activate now;
# impossible to backfill when it is wanted.
resource "aws_ce_cost_allocation_tag" "env" {
  tag_key = "Env"
  status  = "Active"
}

# Answers "is this thing managed, or did somebody create it by hand" as a BILLING
# dimension. Untagged spend showing up under no `ManagedBy` value is the cheapest
# possible detector for the rule in AGENTS.md — resources created outside
# Terraform do not carry default_tags, so they stand out in Cost Explorer without
# anything having to scan for them.
resource "aws_ce_cost_allocation_tag" "managed_by" {
  tag_key = "ManagedBy"
  status  = "Active"
}
