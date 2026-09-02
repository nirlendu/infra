# personal/infra/cloudflare
#
# Requires CLOUDFLARE_API_TOKEN in the environment (see README).

ZONE ?=

# Keep in sync with zones.tf. Duplicated deliberately: `make purge` must work
# from a clean checkout without a terraform init / state read.
ZONE_ID_maxinterview := e2450d7f14fdcf30e34212613f7eaa16
ZONE_ID_nirlendu     := 50d402d707b43a6717ee06aaf1d79f81
ZONE_ID_superwomn    := b04e6e45e899cf5c6b349964fdc86643
ZONE_ID_suprhealthe  := 68de4bb68b0882c0dbc4db705cfc3fc1
ZONE_ID_geniusjnr    := 04215cd92c731147fe3cf48f016efc5a
ZONE_ID_supertravelr := 26402352e1cd08e18793200675137760

.PHONY: help plan apply purge check

help:
	@echo "make plan                    - terraform plan"
	@echo "make apply                   - terraform apply"
	@echo "make purge ZONE=geniusjnr    - purge that zone's edge cache (run after a deploy)"
	@echo "make check                   - show live cache status for every managed host"
	@echo ""
	@echo "Zones: maxinterview nirlendu superwomn suprhealthe geniusjnr supertravelr"

plan:
	terraform plan -input=false

apply:
	terraform apply -input=false

# Purge after deploying an `active` zone. The 300s edge TTL means a deploy goes
# live within 5 minutes unaided; this makes it immediate.
#
# NOTE: this clears the Cloudflare EDGE only. Browsers hold their own copy for
# browser_ttl (300s) and are not reachable by a purge.
purge:
	@test -n "$(ZONE)" || { echo "ERROR: pass ZONE=<name>, e.g. make purge ZONE=geniusjnr"; exit 1; }
	@test -n "$(ZONE_ID_$(ZONE))" || { echo "ERROR: unknown zone '$(ZONE)'"; exit 1; }
	@test -n "$$CLOUDFLARE_API_TOKEN" || { echo "ERROR: CLOUDFLARE_API_TOKEN not set"; exit 1; }
	@echo "purging $(ZONE) ($(ZONE_ID_$(ZONE)))..."
	@curl -sS -X POST \
	  "https://api.cloudflare.com/client/v4/zones/$(ZONE_ID_$(ZONE))/purge_cache" \
	  -H "Authorization: Bearer $$CLOUDFLARE_API_TOKEN" \
	  -H 'Content-Type: application/json' \
	  --data '{"purge_everything":true}' \
	  | python3 -c "import json,sys; d=json.load(sys.stdin); print('  purged' if d.get('success') else '  FAILED: '+json.dumps(d.get('errors')))"

# Quick health read. `HIT`/`REVALIDATED` = the edge is doing its job.
# `DYNAMIC` = HTML is passing through to origin and billing at CloudFront.
check:
	@for h in maxinterview.com code.maxinterview.com nirlendu.com superwomn.com \
	          suprhealthe.com geniusjnr.com supertravelr.com visa.supertravelr.com; do \
	  s=$$(curl -sS -o /dev/null -D - --max-time 20 "https://$$h/" 2>/dev/null \
	       | grep -i '^cf-cache-status' | awk '{print $$2}' | tr -d '\r'); \
	  printf "  %-26s %s\n" "$$h" "$${s:-none}"; \
	done
