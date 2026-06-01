#!/bin/bash
# Stub bootstrap for module validation only. References the standard template
# vars the module injects, so templatefile() resolves during `terraform validate`.
set -euxo pipefail
echo "region=${aws_region} app=${name_prefix} env=${env} shared=${shared_env}"
echo "repo=${git_repo_url}@${git_ref} domain=${domain} email=${caddy_email}"
echo "bucket=${backup_bucket} mount=${data_mount}"
