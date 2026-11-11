#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

bash -n install.sh
bash install.sh --help >/dev/null
command -v ruby >/dev/null && ruby -ryaml -e 'd=YAML.load_file("docker-compose.yml"); abort "missing efb" unless d.fetch("services").key?("efb")'
[[ "$(grep -c '^efb-telegram-master' requirements.txt)" -eq 1 ]]

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp install.sh Dockerfile docker-compose.yml requirements.txt "$tmp/"
(cd "$tmp" && bash install.sh docker init && bash install.sh docker init)
[[ -f "$tmp/.env" && -d "$tmp/data" ]]
grep -q '^EFB_CONFIG_DIR=./data$' "$tmp/.env"
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
  PATH="$tmp/fakebin:$PATH" bash install.sh docker backup "$tmp/snapshot.tar.gz"
)
[[ -s "$tmp/snapshot.tar.gz" ]]
tar -tzf "$tmp/snapshot.tar.gz" | grep -q 'profiles/default/session.txt'
grep -q 'compose --env-file .env run --rm --no-deps efb efb-wizard' "$FAKE_LOG"
grep -q 'compose --env-file .env stop efb' "$FAKE_LOG"
grep -q 'compose --env-file .env start efb' "$FAKE_LOG"
echo 'Smoke tests passed (Docker commands mocked; actual build validated by CI).'
