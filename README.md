# ZTE Router CLI

A single-file Bash CLI for inspecting and safely operating a ZTE cellular
router/modem through its local web UI API.

The maintained executable is [`zte.sh`](./zte.sh). The repository does not
contain a router password, session cookie, SIM identity, WAN address, or
client data.

## What it supports

### Read-only views

```text
status          Basic signal, network, carrier and WAN status
full            Broad raw router information
report          Formatted status, usage and connected-client report
radio           LTE/5G radio, cell and carrier-aggregation information
wifi-info       Wi-Fi state, SSIDs and LAN information
network-info    Dial, WAN, DNS and IP information
system          Firmware, thermal, power and restart settings
devices         Wi-Fi and wired clients
sms             SMS counters and storage totals
query CMD       Read a comma-separated router command list
speed [seconds] Live throughput monitor
watch [seconds] Live status monitor
ui              Web UI route map discovered from the router firmware
capabilities    CLI/API capability map
debug           Login diagnostics without printing cookies
```

### Guarded writes and restart actions

Writes prompt for confirmation unless `--yes` is supplied. `--dry-run` never
contacts the router.

```text
mode auto|5g|5g-sa|4g|4g-only|3g
wifi 2.4|5
wifi-on / wifi-off
wifi-ssid BAND SSID [PASSWORD]
connection auto|manual
connect / disconnect
reset-data
sim-slot SLOT
cell-lock PCI EARFCN RAT
nr-band-lock MASK
nr5g-band-lock MASK
unlock-cells
reboot / restart
shutdown
factory-reset [0|1]
form GOFORM_ID key=value...
```

The `form` command exposes known UI write endpoints and is useful when a
firmware-specific setting is not yet wrapped by a named command. Unknown form
IDs require `--unsafe`.

## Requirements

- Bash 4 or newer
- `curl`
- `jq`
- `sha256sum`
- `awk`
- `mktemp`
- `base64` and `tr` for `wifi-ssid`

On Debian or Ubuntu:

```bash
sudo apt install bash curl jq coreutils gawk
```

No package installation is required by the script itself.

## Install or clone

```bash
git clone <your-repository-url> zte-router-cli
cd zte-router-cli
chmod 755 zte.sh
./zte.sh help
```

The default router address is `192.168.5.1` and the default transport is
HTTP, matching the device UI inspected for this project. Override them when
needed:

```bash
./zte.sh --ip 192.168.8.1 --scheme https status --redact
```

Prefer HTTPS if the router has HTTPS enabled. HTTP exposes the login request
and session to anyone able to observe the local network.

## Credential handling

The router's web UI does not necessarily submit the human-readable password
directly. Depending on firmware, it may Base64-encode it or apply a
firmware-specific SHA-256 transformation involving a dynamic value. This CLI
expects the **exact value sent in the browser's login request**, not a guessed
hash of the human password.

That value is credential-equivalent: anyone who obtains it may be able to log
into the router. Treat it like a password.

### Fetch the value from the web UI

Use the router's own UI so the browser performs the correct firmware-specific
transformation:

1. Connect to the router and open its UI, for example `http://192.168.5.1/`.
2. Open browser Developer Tools and select **Network**.
3. Enable **Preserve log** if available.
4. Log in normally.
5. Find the POST request named `goform_set_cmd_process` whose form data
   contains `goformId=LOGIN`.
6. Inspect **Payload**, **Form Data**, or **Request** fields and locate the
   `password` value.
7. Copy only that exact `password` value. Do not copy cookies, the plaintext
   password, or the complete request into this repository.

For this router family, the value may be a long hexadecimal string. Do not
assume that a plain SHA-256 of the human password is sufficient: some firmware
versions include a dynamic login value. The browser request is the reliable
source.

### Save it in the automatically detected file

The script looks for this file automatically:

```text
$XDG_CONFIG_HOME/zte/hash
```

or, when `XDG_CONFIG_HOME` is not set:

```text
~/.config/zte/hash
```

Create it without placing the value in shell history or the process list:

```bash
install -d -m 700 "${XDG_CONFIG_HOME:-$HOME/.config}/zte"
umask 077
read -r -s -p 'Paste the browser password value: ' ZTE_HASH
printf '\n'
printf '%s\n' "$ZTE_HASH" > "${XDG_CONFIG_HOME:-$HOME/.config}/zte/hash"
unset ZTE_HASH
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/zte/hash"
```

The file must contain one value on one line. Verify its permissions:

```bash
stat -c '%A %a %n' "${XDG_CONFIG_HOME:-$HOME/.config}/zte/hash"
```

Expected permissions are `-rw-------` or mode `600`.

### Use a different file

```bash
./zte.sh --hash-file "$HOME/.secrets/zte-mu300.hash" status --redact
```

Or configure it for the current shell:

```bash
export ZTE_HASH_FILE="$HOME/.secrets/zte-mu300.hash"
./zte.sh report --redact
```

An environment variable also works, but it may be visible to processes or
shell diagnostics, so the protected file is preferred:

```bash
export ZTE_HASH='paste-the-value-only-in-a-private-shell'
./zte.sh status --redact
unset ZTE_HASH
```

### Verify the setup

Run a read-only command first:

```bash
./zte.sh status --redact
```

If the router rejects the login, repeat the browser capture and copy the
request's `password` field exactly. Do not add quotes, whitespace, or a
`password=` prefix to the file.

## Common examples

Use redaction when output may be saved, pasted into an issue, or shown to
someone else:

```bash
./zte.sh status --json --redact
./zte.sh report --redact
./zte.sh radio --json --redact
./zte.sh devices --json --redact
```

Explore the UI paths and the API groups without changing router state:

```bash
./zte.sh ui
./zte.sh ui --json
./zte.sh capabilities --json
```

Monitor the connection:

```bash
./zte.sh speed 1
./zte.sh watch 5
```

Always preview a write before applying it:

```bash
./zte.sh mode 5g --dry-run
./zte.sh wifi 5 --dry-run
./zte.sh reboot --dry-run
```

Apply a normal guarded write:

```bash
./zte.sh mode 5g
```

For automation, explicitly acknowledge the write:

```bash
./zte.sh mode 5g --yes
./zte.sh connect --yes
```

### Restart, shutdown and reset

These operations can interrupt every connected client:

```bash
./zte.sh reboot
./zte.sh restart --yes
./zte.sh shutdown --yes
```

Factory reset is intentionally harder to invoke. The `0` form keeps user
data when supported; `1` requests deletion of user data:

```bash
./zte.sh factory-reset 0 --dry-run
./zte.sh factory-reset 0 --confirm-factory-reset --yes
```

Do not run the real factory-reset command unless you have a recovery plan and
know the router's firmware behavior.

## UI coverage discovered on the current device

The `ui` command reports the menu paths found in the router's current web UI.
The inspected firmware exposed these areas:

- Home dashboard
- Dial, network selection, APN and internet settings
- Wi-Fi and connected stations
- Password, PIN, LAN/DHCP, restore and other device settings
- Network information and diagnostics
- Performance mode and access license
- USB internet protocol, USB port and Samba
- Indicator light, SIM slot and online authentication
- Traffic alerts and OTA update
- SMS list and SMS settings

The API catalog also contains radio diagnostics, thermal values, power-on
settings, cell locks, NR band locks, traffic counters, Wi-Fi controls, and
restart/shutdown forms. Firmware availability varies, so unsupported fields
may be empty and unsupported forms may be rejected by the router.

## Safety notes

- The script uses a private temporary cookie jar and removes it on exit.
- `debug` deliberately does not print the cookie jar.
- The hash is read from the environment, a protected file, or a hidden prompt;
  it is not stored in `zte.sh`.
- Write commands obtain the router's current challenge and calculate the
  authenticated `AD` value before submitting the form.
- Write commands require confirmation by default.
- `--dry-run` does not log in and does not contact the router.
- `--redact` removes IMEI, IMSI, ICCID, phone number, MAC, WAN and client
  address fields from JSON reports.
- Wi-Fi band switching uses the router UI's `switchWiFiChip` behavior, which
  sends `GuestEnable=0` and may disable guest Wi-Fi.
- `form --unsafe` can send firmware-specific write forms. Use it only when
  you understand the endpoint and parameters.
- HTTP is used by default because that is what the inspected router exposed.
  Use HTTPS when available.

## Testing and development

Run the local checks from the repository root:

```bash
bash -n zte.sh
./zte.sh help
./zte.sh version
./zte.sh ui --json | jq -e 'type == "array"'
./zte.sh capabilities --json | jq -e 'has("known_write_forms")'
./zte.sh mode 5g --dry-run --json | jq -e '.dry_run == true'
./zte.sh reboot --dry-run --json | jq -e '.dry_run == true'
```

If ShellCheck is installed:

```bash
shellcheck zte.sh
```

Read-only live smoke test:

```bash
./zte.sh status --json --redact | jq -e 'type == "object"'
```

Do not use a live router to test write commands. Use `--dry-run` first and
only apply a write when its side effects are understood.

## Keeping the repository GitHub-safe

Before publishing or opening a pull request:

```bash
git status --short
git diff --check
git grep -n -E 'password=|ZTE_HASH=|goformId=LOGIN' -- ':!README.md' || true
```

Never commit:

- the hash file
- plaintext router passwords
- browser cookies or exported DevTools requests
- reports containing SIM, WAN, MAC or client identity data
- `.env` files containing router credentials

The included `.gitignore` covers the usual local secret and output names, but
review `git diff` before every commit. A `.gitignore` rule is not a substitute
for checking tracked files.

## License

No license has been selected for this repository yet. Add the license that
matches your intended distribution before publishing it as a reusable project.
