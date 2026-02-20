#!/usr/bin/env bash
#
# lib/utils.sh — Shared utilities for VPS management scripts
#
# Provides common functions for SSH execution, argument parsing,
# system architecture mapping, and target labeling.
#
# Usage: source this file from any script in the project root.
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/utils.sh"
#

# ── SSH URI builder ───────────────────────────────────────────
# Prints an SSH URI string (ssh://root@IP:PORT) to stdout.
# Only used in --ip mode. When using --host, use HOST_ALIAS directly.
#
# Arguments:
#   $1 — IP address
#   $2 — SSH port (e.g. 2222)
ssh_uri() {
  local ip="$1"
  local port="$2"

  echo "ssh://root@$ip:$port"
}

# ── SSH execution wrapper ────────────────────────────────────
# Runs a command on the remote server via SSH.
#
# Arguments:
#   $1        — SSH target (HOST_ALIAS or ssh://root@IP:PORT from ssh_uri)
#   $2+       — SSH options and/or command to run remotely
#
ssh_exec() {
  local target="$1"
  shift

  ssh "$target" "$@"
}

# ── System architecture mapping ──────────────────────────────
# Prints the Nix system triple for a given system flag.
#
# Arguments:
#   $1 — system flag: "x86" or "arm"
get_nix_system() {
  if [ "$1" = "arm" ]; then
    echo "aarch64-linux"
  else
    echo "x86_64-linux"
  fi
}

# Prints the flake host name for a given system flag.
#
# Arguments:
#   $1 — system flag: "x86" or "arm"
get_flake_host() {
  if [ "$1" = "arm" ]; then
    echo "vps-arm"
  else
    echo "vps-x86"
  fi
}

# ── First valid value helper ──────────────────────────────────
# Prints the first non-empty argument. Useful for building
# human-friendly labels from a list of candidates.
#
# Arguments:
#   $@ — candidate values (first non-empty wins)
first_valid() {
  for val in "$@"; do
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  done
}

# ── Connection argument validation ───────────────────────────
# Validates mutual exclusivity of --host and --ip.
# Designed to be called AFTER the argument loop has set HOST_ALIAS and IP.
#
# Arguments:
#   $1 — host alias value (from --host)
#   $2 — ip value (from --ip)
#   $3 — usage function name (called on error)
validate_connection_args() {
  local host_alias="$1"
  local ip="$2"
  local usage_fn="$3"

  if [ -n "$host_alias" ] && [ -n "$ip" ]; then
    echo "Error: Use either --host or --ip, not both."
    "$usage_fn"
    exit 1
  fi

  if [ -z "$host_alias" ] && [ -z "$ip" ]; then
    echo "Error: You must provide either --host or --ip."
    "$usage_fn"
    exit 1
  fi
}

# ── System argument validation ───────────────────────────────
# Validates that --system was provided with a valid value.
#
# Arguments:
#   $1 — system value to validate (e.g. "x86" or "arm")
#   $2 — usage function name (called on error)
validate_system_arg() {
  local system="$1"
  local usage_fn="$2"

  if [ -z "$system" ]; then
    echo "Error: --system is required (x86 or arm)."
    "$usage_fn"
    exit 1
  fi

  if [ "$system" != "x86" ] && [ "$system" != "arm" ]; then
    echo "Error: --system must be one of: x86, arm."
    "$usage_fn"
    exit 1
  fi
}
