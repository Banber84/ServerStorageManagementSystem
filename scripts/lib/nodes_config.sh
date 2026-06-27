#!/usr/bin/env bash

ssms_sync_site_nodes() {
  local site_file="$1"
  local nodes_file="$2"
  local tmp
  [[ -f "$site_file" ]] || return 0
  [[ -f "$nodes_file" ]] || return 1

  tmp="$(mktemp)"
  awk -v nodes_file="$nodes_file" '
    function print_nodes(    line) {
      print "SSMS_NODES=\""
      while ((getline line < nodes_file) > 0) {
        if (line !~ /^[[:space:]]*#/ && line !~ /^[[:space:]]*$/) {
          print line
        }
      }
      close(nodes_file)
      print "\""
    }
    BEGIN { in_nodes = 0; replaced = 0 }
    !in_nodes && /^SSMS_NODES="/ {
      print_nodes()
      replaced = 1
      if ($0 == "SSMS_NODES=\"" || $0 ~ /^SSMS_NODES="[[:space:]]*$/) {
        in_nodes = 1
      }
      next
    }
    in_nodes {
      if ($0 ~ /^[[:space:]]*"[[:space:]]*$/) {
        in_nodes = 0
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        print ""
        print_nodes()
      }
    }
  ' "$site_file" > "$tmp"
  cat "$tmp" > "$site_file"
  rm -f "$tmp"
}
