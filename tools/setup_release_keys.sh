#!/usr/bin/env bash
# One-time release key setup for Ufuq (Mac, Android, Windows). Run on YOUR Mac, from the repo root:
#
#   bash tools/setup_release_keys.sh
#
# It generates every signing key locally, stores them in ~/UfuqKeys (outside the repo) and sets the
# GitHub secrets and variables with your own `gh` login. Nothing is printed to the terminal except
# public keys. Run it once: re-running would create new keys, and Android refuses updates signed with
# a different key, so it stops if ~/UfuqKeys already exists.
#
# Needs: gh (logged in: `gh auth login`), python3, keytool (any JDK: `brew install openjdk`), curl.
set -euo pipefail

REPO="hystericmoon/ufuq"
KEYS="$HOME/UfuqKeys"
SPARKLE_VERSION="2.6.4"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"; }

[[ "$(uname)" == "Darwin" ]] || die "run this on your Mac (Sparkle's key tool is macOS-only)."
need gh "Install with: brew install gh, then gh auth login"
need python3 "Install Xcode command line tools: xcode-select --install"
need keytool "Install a JDK: brew install openjdk"
need curl ""
gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
[[ -e "$KEYS" ]] && die "$KEYS already exists. Keys were set up before; re-running would replace them."

mkdir -m 700 "$KEYS"
cd "$KEYS"
echo "Keys go to $KEYS"

# --- Mac: Sparkle EdDSA key -------------------------------------------------------------------
echo "1/3 Mac (Sparkle)…"
curl -fsSL -o sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
mkdir sparkle && tar -xf sparkle.tar.xz -C sparkle && rm sparkle.tar.xz
# generate_keys stores the private key in your login keychain (it may ask to allow access).
./sparkle/bin/generate_keys --account ufuq >/dev/null
SPARKLE_PUBLIC="$(./sparkle/bin/generate_keys --account ufuq -p)"
./sparkle/bin/generate_keys --account ufuq -x sparkle_private_key.txt
chmod 600 sparkle_private_key.txt
gh secret set SPARKLE_ED_PRIVATE_KEY --repo "$REPO" < sparkle_private_key.txt
gh variable set SPARKLE_PUBLIC_KEY --repo "$REPO" --body "$SPARKLE_PUBLIC"
echo "   public key: $SPARKLE_PUBLIC"

# --- Android: release keystore -----------------------------------------------------------------
echo "2/3 Android (release keystore)…"
STORE_PASS="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
keytool -genkeypair -v -keystore ufuq-release.jks -alias ufuq -keyalg RSA -keysize 4096 -validity 36500 \
  -storepass "$STORE_PASS" -keypass "$STORE_PASS" -dname "CN=Ufuq" >/dev/null 2>&1
chmod 600 ufuq-release.jks
printf '%s' "$STORE_PASS" > android_keystore_password.txt && chmod 600 android_keystore_password.txt
base64 -i ufuq-release.jks | gh secret set UFUQ_KEYSTORE_BASE64 --repo "$REPO"
printf '%s' "$STORE_PASS" | gh secret set UFUQ_KEYSTORE_PASSWORD --repo "$REPO"
printf '%s' "$STORE_PASS" | gh secret set UFUQ_KEY_PASSWORD --repo "$REPO"
gh secret set UFUQ_KEY_ALIAS --repo "$REPO" --body "ufuq"
echo "   keystore: $KEYS/ufuq-release.jks (alias ufuq)"

# --- Windows: Ed25519 update-signing key -------------------------------------------------------
echo "3/3 Windows (update signing)…"
python3 -m venv .venv >/dev/null && ./.venv/bin/pip install -q cryptography
./.venv/bin/python - <<'PY'
import base64, os
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization as s
k = Ed25519PrivateKey.generate()
priv = k.private_bytes(s.Encoding.Raw, s.PrivateFormat.Raw, s.NoEncryption())
pub = k.public_key().public_bytes(s.Encoding.Raw, s.PublicFormat.Raw)
fd = os.open("windows_update_private_key.txt", os.O_WRONLY | os.O_CREAT, 0o600)
os.write(fd, base64.b64encode(priv)); os.close(fd)
open("windows_update_public_key.txt", "w").write(base64.b64encode(pub).decode())
PY
rm -rf .venv
gh secret set UFUQ_UPDATE_PRIVATE_KEY --repo "$REPO" < windows_update_private_key.txt
gh variable set UFUQ_UPDATE_PUBLIC_KEY --repo "$REPO" --body "$(cat windows_update_public_key.txt)"
echo "   public key: $(cat windows_update_public_key.txt)"

cat <<EOF

Done. GitHub now has:
  secrets   SPARKLE_ED_PRIVATE_KEY, UFUQ_KEYSTORE_BASE64, UFUQ_KEYSTORE_PASSWORD, UFUQ_KEY_PASSWORD,
            UFUQ_KEY_ALIAS, UFUQ_UPDATE_PRIVATE_KEY
  variables SPARKLE_PUBLIC_KEY, UFUQ_UPDATE_PUBLIC_KEY

BACK UP $KEYS NOW (password manager or an encrypted drive), then keep it off cloud-synced folders.
If the Android keystore is lost, installed phones can never be updated again; users would have to
uninstall and reinstall. The Sparkle key is also in your login keychain (account "ufuq").
EOF
