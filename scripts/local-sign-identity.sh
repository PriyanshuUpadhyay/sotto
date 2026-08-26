#!/usr/bin/env bash
# Prints the code-signing identity for local builds, or "-" for ad-hoc.
#
# A stable self-signed identity keeps the cdhash constant across rebuilds, so
# macOS Accessibility / Input Monitoring grants survive. Ad-hoc signing gives a
# fresh cdhash every build and re-prompts for those permissions each time.
#
# To create the cert (one-time, ~30 sec):
#   Keychain Access -> Certificate Assistant -> Create a Certificate...
#     Name: sotto-local
#     Identity Type: Self Signed Root
#     Certificate Type: Code Signing
#
# Both the Makefile and bin/acceptance read the identity from here so a local
# build, a test run, and an acceptance run always sign the same way.
set -uo pipefail

/usr/bin/security find-identity -p codesigning -v 2>/dev/null \
  | grep -F -e '"sotto-local"' -e '"voiceink-fork-local"' \
  | head -1 \
  | awk '{ print $2 }' \
  | grep -E '^[A-F0-9]+$' \
  || echo "-"
