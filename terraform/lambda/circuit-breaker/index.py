"""Cost circuit breaker — disable a runaway CloudFront distribution.

This is the only cost control in the account that works while nobody is
reading email. Every other layer detects; this one acts.

It exists because of a measured failure, not a hypothetical one. In August 2026
the monthly budget alarmed at 100% and 120%, the daily anomaly budget alarmed,
and the Cost Anomaly Detector fired at a $3 threshold — all of them correctly,
all of them to one inbox, for three weeks, while a crawl ran up $273. Detection
was never the gap. Acting was.

SAFETY PROPERTIES, in the order they matter:

1. ALLOWLIST. The breaker can only disable distributions named in
   BREAKER_ALLOWED_DISTRIBUTIONS. The live products are deliberately absent, so
   a false positive can take down an abandoned marketing site and can never take
   down authoxi, agitome or uni. A breaker that could break production would
   have to be disarmed, and a disarmed breaker is not a breaker.

2. IDEMPOTENT. Disabling an already-disabled distribution is a no-op, so a
   flapping alarm cannot generate a storm of CloudFront API calls.

3. FAIL CLOSED, QUIETLY. Anything unparseable is ignored rather than raised.
   This function is subscribed to a general-purpose alerts topic that also
   carries budget notifications and RDS events; treating those as errors would
   fill the log with noise and mask a real failure.

4. ONE-WAY. It never re-enables anything. Coming back up is a human decision
   made with the cause understood, which means a `terraform apply` after the
   `enabled` lifecycle override is lifted.

NOTE ON TERRAFORM OWNERSHIP: disabling a distribution here is a change made
outside Terraform, which is normally forbidden in this workspace. The carve-out
is explicit and narrow, and mirrors the existing one for SSM secret values:
Terraform owns the distribution, this breaker owns the single `enabled` field,
and the distributions it may touch carry `lifecycle { ignore_changes = [enabled] }`
in ../existing/generated_cloudfront.tf so a later apply cannot silently re-enable
a distribution mid-incident.
"""

import json
import logging
import os

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

cloudfront = boto3.client("cloudfront")
sns = boto3.client("sns")
ssm = boto3.client("ssm")

ARMED = os.environ.get("BREAKER_ARMED", "false").lower() == "true"
NOTIFY_TOPIC = os.environ.get("BREAKER_NOTIFY_TOPIC_ARN", "")
ALLOWLIST_PARAM = os.environ.get("BREAKER_ALLOWLIST_PARAM", "")

# Static fallback, from the Lambda's environment. Used only if SSM is
# unreachable — see _allowlist().
ALLOWED_FALLBACK = {
    d.strip()
    for d in os.environ.get("BREAKER_ALLOWED_DISTRIBUTIONS", "").split(",")
    if d.strip()
}


def _allowlist():
    """The distributions this breaker may disable.

    Read from SSM at INVOCATION rather than baked in at deploy, because the
    authoritative list is derived from the CloudFront resources themselves in
    existing/cloudfront-alarms.tf. A distribution that is replaced gets a new
    ID; the alarms follow it automatically because they reference the resource,
    and this makes the breaker follow it too.

    Without this the breaker would refuse to act on exactly the distribution
    whose alarm just fired, log "not in the allowlist", and look healthy.
    Failing safe is not the same as working.

    Falls back to the environment if SSM cannot be read, so an SSM outage
    degrades the breaker to its last-deployed list rather than disarming it.
    """
    if not ALLOWLIST_PARAM:
        return ALLOWED_FALLBACK
    try:
        raw = ssm.get_parameter(Name=ALLOWLIST_PARAM)["Parameter"]["Value"]
        found = {d.strip() for d in raw.split(",") if d.strip()}
        if found:
            return found
        log.warning("Allowlist parameter %s is empty; using env fallback", ALLOWLIST_PARAM)
    except Exception:  # noqa: BLE001 - never let a lookup failure disarm the breaker
        log.exception("Could not read %s; using env fallback", ALLOWLIST_PARAM)
    return ALLOWED_FALLBACK


def handler(event, context):
    """Entry point. One SNS event may carry several records."""
    allowed = _allowlist()
    for record in event.get("Records", []):
        try:
            message = json.loads(record["Sns"]["Message"])
        except (KeyError, ValueError):
            # Not a CloudWatch alarm — a budget notification, an RDS event, or
            # this function's own notification coming back around the topic.
            # Expected traffic, not an error.
            continue

        if not isinstance(message, dict):
            continue

        if message.get("NewStateValue") != "ALARM":
            # OK and INSUFFICIENT_DATA transitions also arrive here.
            continue

        distribution_id = _distribution_from_alarm(message)
        if not distribution_id:
            continue

        alarm_name = message.get("AlarmName", "<unknown>")

        if distribution_id not in allowed:
            # The important log line. If a live product ever trips an alarm
            # wired to this topic, this is the record that it was seen and
            # deliberately not acted on.
            log.warning(
                "REFUSING to disable %s (alarm %s): not in the allowlist",
                distribution_id,
                alarm_name,
            )
            continue

        _trip(distribution_id, alarm_name)


def _distribution_from_alarm(message):
    """Pull DistributionId out of a CloudWatch alarm's trigger dimensions."""
    dimensions = message.get("Trigger", {}).get("Dimensions", [])
    for dimension in dimensions:
        # CloudWatch uses "name"/"value" here, lowercase, unlike most of the API.
        if dimension.get("name") == "DistributionId":
            return dimension.get("value")
    return None


def _trip(distribution_id, alarm_name):
    """Disable one distribution, if it is not already disabled."""
    try:
        current = cloudfront.get_distribution_config(Id=distribution_id)
    except cloudfront.exceptions.NoSuchDistribution:
        log.warning("Distribution %s no longer exists", distribution_id)
        return

    config = current["DistributionConfig"]
    etag = current["ETag"]

    if not config["Enabled"]:
        log.info("Distribution %s already disabled — nothing to do", distribution_id)
        return

    if not ARMED:
        log.warning(
            "WOULD DISABLE %s (alarm %s) but BREAKER_ARMED is false",
            distribution_id,
            alarm_name,
        )
        _notify(
            f"Cost breaker (OBSERVE ONLY): would have disabled CloudFront "
            f"{distribution_id}, triggered by {alarm_name}. Set BREAKER_ARMED=true to act."
        )
        return

    config["Enabled"] = False
    # IfMatch is mandatory and is CloudFront's optimistic-concurrency check: if
    # anything else changed the distribution since the read above, this fails
    # rather than clobbering it.
    cloudfront.update_distribution(
        Id=distribution_id, IfMatch=etag, DistributionConfig=config
    )

    log.info("DISABLED distribution %s, triggered by alarm %s", distribution_id, alarm_name)
    _notify(
        f"Cost breaker TRIPPED: CloudFront distribution {distribution_id} has been "
        f"DISABLED, triggered by alarm {alarm_name}.\n\n"
        f"The site behind it is now offline. This is deliberate — it was costing "
        f"money faster than the budget allows.\n\n"
        f"To restore: establish the cause first, then remove the `enabled` entry "
        f"from that distribution's lifecycle.ignore_changes in "
        f"personal/infra/existing/generated_cloudfront.tf and apply."
    )


def _notify(text):
    """Best-effort notification. Never let this fail the breaker itself."""
    if not NOTIFY_TOPIC:
        return
    try:
        sns.publish(TopicArn=NOTIFY_TOPIC, Subject="AWS cost circuit breaker", Message=text)
    except Exception:  # noqa: BLE001 - notification must never mask the action
        log.exception("Could not publish breaker notification")
