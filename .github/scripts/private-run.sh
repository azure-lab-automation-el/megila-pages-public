#!/usr/bin/env bash
# Public launcher: all application and QA stdout/stderr goes to an encrypted artifact.
set -u
mode=${1:-}
arg=${2:-}
case "$mode:$arg" in
  deploy:preview|deploy:production|audit:[0-9]) ;;
  *) echo 'Private job could not start (invalid mode).'; exit 2 ;;
esac
recipient='age13qzuzx5addzu9d2z3z58u8pjt3fe4y5j6qclpp867jx4fcca4d6q636uvh'
mkdir -p private-output
log="$(mktemp)"
chmod 600 "$log"
if ! curl -fsSL https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz -o /tmp/age.tar.gz >"$log" 2>&1 ||
   ! echo '7df45a6cc87d4da11cc03a539a7470c15b1041ab2b396af088fe9990f7c79d50  /tmp/age.tar.gz' | sha256sum -c - >>"$log" 2>&1 ||
   ! tar -xzf /tmp/age.tar.gz -C /tmp >>"$log" 2>&1; then
  rm -f "$log" /tmp/age.tar.gz
  echo 'Private job could not start.'
  exit 1
fi
(
  set -euo pipefail
  test -n "${MEGILA_AGE_SECRET_KEY:-}"
  printf '%s\n' "$MEGILA_AGE_SECRET_KEY" > /tmp/age-key.txt
  chmod 600 /tmp/age-key.txt
  /tmp/age/age -d -i /tmp/age-key.txt -o /tmp/private.tar.gz private.tar.gz.age
  mkdir private
  tar -xzf /tmp/private.tar.gz -C private
  rm -f /tmp/age-key.txt /tmp/private.tar.gz
  cd private
  if [ "$mode" = audit ]; then
    bash audit.sh "$arg"
  else
    export GITHUB_REF_NAME
    bash deploy.sh "$arg"
  fi
) >>"$log" 2>&1
rc=$?
printf '\nPrivate job exit code: %s\n' "$rc" >>"$log"
/tmp/age/age -r "$recipient" -o private-output/job.log.age "$log" >/dev/null 2>&1 || { rm -f "$log"; echo 'Private job log encryption failed.'; exit 1; }
rm -f "$log" /tmp/age-key.txt /tmp/private.tar.gz
if [ "$mode" = audit ] && [ -d private/qa/results ]; then
  tar -czf /tmp/qa-results.tar.gz -C private qa/results >/dev/null 2>&1 || { rm -rf private; echo 'Private result packaging failed.'; exit 1; }
  /tmp/age/age -r "$recipient" -o private-output/qa-results.tar.gz.age /tmp/qa-results.tar.gz >/dev/null 2>&1 || { rm -f /tmp/qa-results.tar.gz; rm -rf private; echo 'Private result encryption failed.'; exit 1; }
  rm -f /tmp/qa-results.tar.gz
fi
rm -rf private
printf 'Private job finished (exit %s).\n' "$rc"
exit "$rc"
