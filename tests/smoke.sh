#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

bash -n install.sh
bash install.sh --help >/dev/null
command -v ruby >/dev/null && ruby -ryaml -e 'd=YAML.load_file("docker-compose.yml"); abort "missing efb" unless d.fetch("services").key?("efb")'
[[ "$(grep -c '^efb-telegram-master' requirements.txt)" -eq 1 ]]

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp install.sh Dockerfile docker-compose.yml requirements.txt requirements-extra.txt "$tmp/"
mkdir -p "$tmp/tools"
cp tools/validate_profile.py "$tmp/tools/"
(cd "$tmp" && bash install.sh docker init && bash install.sh docker init)
[[ -f "$tmp/.env" && -d "$tmp/data" ]]
grep -q '^EFB_CONFIG_DIR=./data$' "$tmp/.env"
grep -q '^EFB_PROFILE=default$' "$tmp/.env"
python3 -m py_compile tools/validate_profile.py
[[ "$(EFB_PROFILE=alpha bash install.sh native info)" == *"Service=efb-alpha Profile=alpha User=efb-alpha Home=/var/lib/efb-alpha Venv=/opt/efb-alpha/venv"* ]]
[[ "$(EFB_PROFILE=alpha EFB_VENV_DIR=/opt/efb-alpha/venv-v2 bash install.sh native info)" == *"Venv=/opt/efb-alpha/venv-v2"* ]]
if EFB_VENV_DIR=/tmp/venv bash install.sh native info >/dev/null 2>&1; then echo "Unsafe venv path accepted" >&2; exit 1; fi
[[ "$(bash install.sh native info)" == *"Service=efb Profile=default User=efb Home=/var/lib/efb Venv=/opt/efb/venv"* ]]
if EFB_PROFILE=BAD bash install.sh native info >/dev/null 2>&1; then echo "Invalid Profile accepted" >&2; exit 1; fi
if EFB_NOFILE=invalid bash install.sh --help >/dev/null 2>&1; then echo "Invalid NOFILE accepted" >&2; exit 1; fi
python3 -c 'import os,stat,sys; assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600' "$tmp/.env"

mkdir -p "$tmp/fakebin" "$tmp/data/profiles/default"
printf 'test-session-placeholder\n' > "$tmp/data/profiles/default/session.txt"
cat > "$tmp/fakebin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
if [[ "$*" == "compose --env-file .env ps --status running -q efb" ]]; then
  printf 'fake-container-id\n'
fi
FAKE_DOCKER
chmod +x "$tmp/fakebin/docker"
export FAKE_LOG="$tmp/fake-docker.log"
(
  cd "$tmp"
  PATH="$tmp/fakebin:$PATH" bash install.sh docker configure
  PATH="$tmp/fakebin:$PATH" bash install.sh docker up
  PATH="$tmp/fakebin:$PATH" bash install.sh docker update
  PATH="$tmp/fakebin:$PATH" bash install.sh docker doctor
  PATH="$tmp/fakebin:$PATH" bash install.sh docker backup "$tmp/snapshot.tar.gz"
  if PATH="$tmp/fakebin:$PATH" bash install.sh docker backup "$tmp/snapshot.tar.gz" >/dev/null 2>&1; then
    echo 'Overwriting an existing backup was allowed' >&2; exit 1
  fi
  if PATH="$tmp/fakebin:$PATH" bash install.sh docker backup "$tmp/data/snapshot.tar.gz" >/dev/null 2>&1; then
    echo 'Backup inside live data directory was allowed' >&2; exit 1
  fi
  python3 -c 'from pathlib import Path; p=Path(".env");p.write_text(p.read_text().replace("EFB_PROFILE=default","EFB_PROFILE=sssuck"))'
  PATH="$tmp/fakebin:$PATH" bash install.sh docker configure
)
[[ -s "$tmp/snapshot.tar.gz" ]]
tar -tzf "$tmp/snapshot.tar.gz" | grep -q 'profiles/default/session.txt'
grep -q 'compose --env-file .env run --rm --no-deps efb efb-wizard --profile default' "$FAKE_LOG"
grep -q 'compose --env-file .env run --rm --no-deps efb python /usr/local/lib/efb-install/validate_profile.py --profile default' "$FAKE_LOG"
grep -q 'compose --env-file .env run --rm --no-deps efb efb-wizard --profile sssuck' "$FAKE_LOG"
grep -q 'compose --env-file .env stop efb' "$FAKE_LOG"
grep -q 'compose --env-file .env start efb' "$FAKE_LOG"
echo 'Smoke tests passed (Docker commands mocked; actual build validated by CI).'
