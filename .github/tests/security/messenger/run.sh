#!/bin/bash
# Disposable Docker container only: uses real installed paths and Apache.
set -euo pipefail
if [[ ! -f /.dockerenv || $EUID -ne 0 ]]; then
    echo "Run only in the disposable Docker container documented in .github/tests/README.md" >&2
    exit 1
fi

suite_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$suite_dir/../../../.." && pwd)
fixture=/tmp/csf-messenger-test
mkdir -p "$fixture" /usr/local/csf/tpl /var/lib/csf/ssl/{certs,keys,ca} /etc/csf /etc/apache2/csf-messenger
cp "$repo_root"/tpl/apache.*.txt /usr/local/csf/tpl/
cp -a "$repo_root/etc/messenger" /etc/csf/
useradd --create-home --home-dir /home/csf-test csf-test
chmod 755 /home/csf-test
mkdir /home/csf-test/public_html
chmod 755 /home/csf-test/public_html
cat > /home/csf-test/public_html/index.php <<'PHP'
<?php header('Content-Type: text/plain'); echo "CSF-MESSENGER-PAGE\n";
PHP

# Harmless positive control for CGI routing; no system commands are executed.
cat > /usr/bin/csf-messenger-probe <<'CGI'
#!/bin/sh
printf 'Content-Type: text/plain\r\n\r\nCSF-CGI-PROBE\n'
CGI
chmod 755 /usr/bin/csf-messenger-probe

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "$fixture/key.pem" -out "$fixture/cert.pem" \
    -subj /CN=one.example.test \
    -addext subjectAltName=DNS:one.example.test,DNS:two.example.test > "$fixture/openssl.log" 2>&1
for name in one.example.test two.example.test; do
    cat >> "$fixture/sites.conf" <<EOF
<VirtualHost *:443>
    ServerName $name
    SSLCertificateFile $fixture/cert.pem
    SSLCertificateKeyFile $fixture/key.pem
</VirtualHost>
EOF
done

a2enmod ssl cgi rewrite headers > /dev/null
a2dissite 000-default > /dev/null
: > /etc/apache2/ports.conf
cat > /etc/apache2/conf-enabled/csf-test.conf <<'CONF'
ServerName one.example.test
<Directory /usr/bin>
    Require all granted
</Directory>
IncludeOptional /etc/apache2/csf-messenger/csf.messenger.conf
CONF
trap 'apache2ctl -k stop >/dev/null 2>&1 || true' EXIT

driver="$suite_dir/driver.pl"
generated=/etc/apache2/csf-messenger/csf.messenger.conf
request() {
    curl --silent --show-error --fail --noproxy '*' --retry 10 --retry-connrefused --retry-delay 1 \
        --cacert "$fixture/cert.pem" --resolve "$1:8443:127.0.0.1" "https://$1:8443$2"
}

# Recreate the v15.03 template with an unrelated administrator customization.
sed -i '/<FilesMatch/i\	ScriptAlias /local-bin /usr/bin' /usr/local/csf/tpl/apache.https.txt
sed -i '/<VirtualHost/a\	Header set X-CSF-Custom kept' /usr/local/csf/tpl/apache.https.txt
cp /usr/local/csf/tpl/apache.https.txt "$fixture/custom-template"
perl "$driver" legacy-control
[[ $(request one.example.test /local-bin/csf-messenger-probe) == CSF-CGI-PROBE ]]
echo "PASS: legacy positive control exposes the harmless CGI fixture"

perl "$driver"
apache2ctl -t
if grep -Eq '^[[:space:]]*ScriptAlias[[:space:]].*/usr/bin' "$generated"; then
    echo 'FAIL: generated configuration retains a system-binary CGI mapping' >&2
    exit 1
fi
[[ $(grep -c '<VirtualHost \*:8443>' "$generated") -eq 2 ]]
[[ $(grep -c 'Header set X-CSF-Custom kept' "$generated") -eq 2 ]]
for name in one.example.test two.example.test; do
    [[ $(request "$name" /) == CSF-MESSENGER-PAGE ]]
    [[ $(request "$name" /local-bin/csf-messenger-probe) == CSF-MESSENGER-PAGE ]]
done
cmp /usr/local/csf/tpl/apache.https.txt "$fixture/custom-template"
echo "PASS: upgrade removes CGI exposure for both TLS vhosts, preserves PHP pages and custom template bytes"

cp "$generated" "$fixture/generated"
perl "$driver"
cmp "$generated" "$fixture/generated"
echo "PASS: repeated regeneration is idempotent"

cp "$repo_root/tpl/apache.https.txt" /usr/local/csf/tpl/apache.https.txt
perl "$driver"
apache2ctl -t
for name in one.example.test two.example.test; do
    [[ $(request "$name" /local-bin/csf-messenger-probe) == CSF-MESSENGER-PAGE ]]
done
echo "PASS: fresh-install template preserves PHP pages without the CGI mapping"
