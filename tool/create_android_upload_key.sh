#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keystore_path="$repository_root/android/upload-keystore.jks"
properties_path="$repository_root/android/key.properties"

if [[ -e "$keystore_path" || -e "$properties_path" ]]; then
  echo "Refusing to overwrite an existing Android upload key or key.properties." >&2
  exit 1
fi

read -r -s -p "Upload keystore password: " store_password
echo
read -r -s -p "Confirm password: " confirmation
echo
if [[ ${#store_password} -lt 16 || "$store_password" != "$confirmation" ]]; then
  echo "Use a matching password of at least 16 characters." >&2
  exit 1
fi

keytool -genkeypair -v \
  -keystore "$keystore_path" \
  -storetype JKS \
  -storepass "$store_password" \
  -keypass "$store_password" \
  -alias upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=Chetiwa Upload, O=Chetiwa, C=FR"

umask 077
{
  printf 'storePassword=%s\n' "$store_password"
  printf 'keyPassword=%s\n' "$store_password"
  printf 'keyAlias=upload\n'
  printf 'storeFile=../upload-keystore.jks\n'
} > "$properties_path"

echo "Android upload key created. Back up android/upload-keystore.jks and its password offline."
