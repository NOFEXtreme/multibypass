# This script starts an extra nfqws daemon and sends traffic into its own NFQUEUE
# matching iptables/nftables rules using IP set (CIDR list) and ports.
#
# TCP is disabled by default, UDP is enabled by default.
#
# Enabled only if `NFQWS_CUSTOM_GAMES=1` is set in zapret-config.sh.
# If `NFQWS_GAMES_CIDR`, `NFQWS_GAMES_ASN` and `$NFQWS_GAMES_ASN_DIR/custom.cidr` are empty/missing, the script does nothing.
#
# It builds an IPv4 list and applies it as:
#  - iptables: ipset `$NFQWS_GAMES_IPSET_NAME`
#  - nftables: nft set  `$NFQWS_GAMES_IPSET_NAME`
#
# IP list sources (combined):
#  `NFQWS_GAMES_CIDR` - space separated list of IPv4 CIDR and/or plain IPv4. Plain IPv4 is converted to /32.
#     Example: NFQWS_GAMES_CIDR="1.1.1.1 8.8.8.0/24"
#
#  `$NFQWS_GAMES_ASN_DIR/custom.cidr` (optional) - additional user list file.
#     Same format: IPv4 CIDR and/or plain IPv4 (plain IPv4 -> /32).
#
#  `NFQWS_GAMES_ASN` - comma-separated ASN numbers to fetch and cache.
#     Examples:
#       NFQWS_GAMES_ASN="13335,32934"
#       NFQWS_GAMES_ASN="AS13335,AS32934"
#
#     Default points to RIPE Stat announced-prefixes:
#       NFQWS_GAMES_ASN_URL="https://stat.ripe.net/data/announced-prefixes/data.json?resource="
#     Fetch URL is formed as: "${NFQWS_GAMES_ASN_URL}AS<NUM>"
#
#     Cache dir:
#       NFQWS_GAMES_ASN_DIR="/jffs/scripts/multibypass/zapret-asn-lists"
#     Cached files:
#       $NFQWS_GAMES_ASN_DIR/AS<NUM>.cidr
#     Cache is refreshed on run if older than 7 days.
#
# Notes:
#  - IPv4 only (no IPv6).
#  - You can override other parameters from the script in your config if needed.
#
[ "$NFQWS_CUSTOM_GAMES" = "1" ] || return 0

# can override in config :
NFQWS_GAMES_PORTS_TCP=${NFQWS_GAMES_PORTS_TCP:-}
NFQWS_GAMES_PORTS_UDP=${NFQWS_GAMES_PORTS_UDP:-1024-65535}
NFQWS_GAMES_TCP_PKT_OUT=${NFQWS_GAMES_TCP_PKT_OUT:-}
NFQWS_GAMES_UDP_PKT_OUT=${NFQWS_GAMES_UDP_PKT_OUT:-2}
NFQWS_GAMES_TCP_PKT_IN=${NFQWS_GAMES_TCP_PKT_IN:-}
NFQWS_GAMES_UDP_PKT_IN=${NFQWS_GAMES_UDP_PKT_IN:-}
NFQWS_GAMES_IPSET_SIZE=${NFQWS_GAMES_IPSET_SIZE:-65536}
NFQWS_GAMES_IPSET_OPT="${NFQWS_GAMES_IPSET_OPT:-hash:net hashsize 32768 maxelem $NFQWS_GAMES_IPSET_SIZE}"
NFQWS_GAMES_CIDR="${NFQWS_GAMES_CIDR:-}"
NFQWS_GAMES_ASN="${NFQWS_GAMES_ASN:-}"
NFQWS_GAMES_ASN_DIR="${NFQWS_GAMES_ASN_DIR:-/jffs/scripts/multibypass/zapret-asn-lists}"
NFQWS_GAMES_ASN_URL="${NFQWS_GAMES_ASN_URL:-https://stat.ripe.net/data/announced-prefixes/data.json?resource=}"
NFQWS_GAMES_OPT="${NFQWS_GAMES_OPT:-
--filter-udp=$NFQWS_GAMES_PORTS_UDP
--filter-l7=unknown
--dpi-desync=fake
--dpi-desync-fake-unknown-udp=$ZAPRET_BASE/files/fake/quic_initial_www_google_com.bin
--dpi-desync-repeats=6
--dpi-desync-any-protocol
}"

[ -z "$NFQWS_GAMES_CIDR" ] && [ -z "$NFQWS_GAMES_ASN" ] && [ ! -s "$NFQWS_GAMES_ASN_DIR/custom.cidr" ] && return 0

# CIDR regex (IPv4/prefix)
IP_RE='([1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\.(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])){3}'
IP_RE_PREFIX='(3[0-2]|[12][0-9]|[89])'
CIDR_REGEX="$IP_RE/$IP_RE_PREFIX"

alloc_dnum DNUM_NFQWS_GAMES
alloc_qnum QNUM_NFQWS_GAMES
NFQWS_GAMES_IPSET_NAME=zapret-custom-games

games_get_cidr()
{
  local a n asn file tmp

  mkdir -p "$NFQWS_GAMES_ASN_DIR" 2>/dev/null

  { [ -n "$NFQWS_GAMES_CIDR" ] && printf '%s\n' "$NFQWS_GAMES_CIDR"
    [ -s "$NFQWS_GAMES_ASN_DIR/custom.cidr" ] && cat "$NFQWS_GAMES_ASN_DIR/custom.cidr"
  } | grep -oE "$CIDR_REGEX|$IP_RE" | sed -E '/\//!s|$|/32|'

  [ -n "$NFQWS_GAMES_ASN" ] && {
    for a in $(echo "$NFQWS_GAMES_ASN" | tr ',' ' '); do
      n="${a#[Aa][Ss]}"
      echo "$n" | grep -Eq '^[0-9]+$' || { echo "NFQWS_CUSTOM_GAMES: skip invalid '$a'" >&2; continue; }

      asn="AS$n"
      file="$NFQWS_GAMES_ASN_DIR/$asn.cidr"

      if [ ! -s "$file" ] || [ -n "$(find "$file" -mtime +7 -print 2>/dev/null)" ]; then
        tmp="$file.tmp.$$"

        curl --retry 3 --connect-timeout 3 --speed-limit 1 --speed-time 30 -sSfL \
          -w "%{stderr}Downloaded ${asn}: %{size_download} bytes in %{time_total}s\n%{stdout}" \
          "${NFQWS_GAMES_ASN_URL}${asn}" \
          | grep -oE "$CIDR_REGEX" \
          | sort -u -t '.' -k1,1n -k2,2n -k3,3n -k4,4n >"$tmp"

        [ -s "$tmp" ] || {
          echo "NFQWS_CUSTOM_GAMES: fetch/parse failed or empty list for $asn" >&2
          rm -f "$tmp"
          continue
        }
        mv -f "$tmp" "$file"
      fi

      cat "$file"
    done
  }
}

zapret_custom_daemons()
{
	# $1 - 1 - run, 0 - stop

	local opt="--qnum=$QNUM_NFQWS_GAMES $NFQWS_GAMES_OPT"
	do_nfqws $1 $DNUM_NFQWS_GAMES "$opt"
}

zapret_custom_firewall()
{
	# $1 - 1 - run, 0 - stop

	local f4
	local NFQWS_GAMES_PORTS_TCP=$(replace_char - : $NFQWS_GAMES_PORTS_TCP)
	local NFQWS_GAMES_PORTS_UDP=$(replace_char - : $NFQWS_GAMES_PORTS_UDP)

	[ "$1" = 1 -a "$DISABLE_IPV4" != 1 ] && {
		ipset create $NFQWS_GAMES_IPSET_NAME $NFQWS_GAMES_IPSET_OPT family inet 2>/dev/null
		ipset flush $NFQWS_GAMES_IPSET_NAME
		games_get_cidr | sort -u | sed "s|^|add $NFQWS_GAMES_IPSET_NAME |" | ipset -! restore
	}

	[ -n "$NFQWS_GAMES_PORTS_TCP" ] && {
		[ -n "$NFQWS_GAMES_TCP_PKT_OUT" -a "$NFQWS_GAMES_TCP_PKT_OUT" != 0 ] && {
			f4="-p tcp -m multiport --dports $NFQWS_GAMES_PORTS_TCP $ipt_connbytes 1:$NFQWS_GAMES_TCP_PKT_OUT -m set --match-set"
			f4="$f4 $NFQWS_GAMES_IPSET_NAME dst"
			fw_nfqws_post $1 "$f4" "" $QNUM_NFQWS_GAMES
		}
		[ -n "$NFQWS_GAMES_TCP_PKT_IN" -a "$NFQWS_GAMES_TCP_PKT_IN" != 0 ] && {
			f4="-p tcp -m multiport --sports $NFQWS_GAMES_PORTS_TCP $ipt_connbytes 1:$NFQWS_GAMES_TCP_PKT_IN -m set --match-set"
			f4="$f4 $NFQWS_GAMES_IPSET_NAME src"
			fw_nfqws_pre $1 "$f4" "" $QNUM_NFQWS_GAMES
		}
	}
	[ -n "$NFQWS_GAMES_PORTS_UDP" ] && {
		[ -n "$NFQWS_GAMES_UDP_PKT_OUT" -a "$NFQWS_GAMES_UDP_PKT_OUT" != 0 ] && {
			f4="-p udp -m multiport --dports $NFQWS_GAMES_PORTS_UDP $ipt_connbytes 1:$NFQWS_GAMES_UDP_PKT_OUT -m set --match-set"
			f4="$f4 $NFQWS_GAMES_IPSET_NAME dst"
			fw_nfqws_post $1 "$f4" "" $QNUM_NFQWS_GAMES
		}
		[ -n "$NFQWS_GAMES_UDP_PKT_IN" -a "$NFQWS_GAMES_UDP_PKT_IN" != 0 ] && {
			f4="-p udp -m multiport --sports $NFQWS_GAMES_PORTS_UDP $ipt_connbytes 1:$NFQWS_GAMES_UDP_PKT_IN -m set --match-set"
			f4="$f4 $NFQWS_GAMES_IPSET_NAME src"
			fw_nfqws_pre $1 "$f4" "" $QNUM_NFQWS_GAMES
		}
	}

	[ "$1" = 1 ] || {
		ipset destroy $NFQWS_GAMES_IPSET_NAME 2>/dev/null
	}
}

zapret_custom_firewall_nft()
{
	local f4

	[ "$DISABLE_IPV4" != 1 ] && {
		nft_create_set $NFQWS_GAMES_IPSET_NAME "type ipv4_addr; size $NFQWS_GAMES_IPSET_SIZE; auto-merge; flags interval;"
		nft_flush_set $NFQWS_GAMES_IPSET_NAME
	  games_get_cidr | sort -u | sed "s|^|add element inet $ZAPRET_NFT_TABLE $NFQWS_GAMES_IPSET_NAME { |; s|$| }|" | nft -f -
	}

	[ -n "$NFQWS_GAMES_PORTS_TCP" ] && {
		[ -n "$NFQWS_GAMES_TCP_PKT_OUT" -a "$NFQWS_GAMES_TCP_PKT_OUT" != 0 ] && {
			f4="tcp dport {$NFQWS_GAMES_PORTS_TCP} $(nft_first_packets $NFQWS_GAMES_TCP_PKT_OUT)"
			f4="$f4 ip daddr @$NFQWS_GAMES_IPSET_NAME"
			nft_fw_nfqws_post "$f4" "" $QNUM_NFQWS_GAMES
		}
		[ -n "$NFQWS_GAMES_TCP_PKT_IN" -a "$NFQWS_GAMES_TCP_PKT_IN" != 0 ] && {
			f4="tcp sport {$NFQWS_GAMES_PORTS_TCP} $(nft_first_packets $NFQWS_GAMES_TCP_PKT_IN)"
			f4="$f4 ip saddr @$NFQWS_GAMES_IPSET_NAME"
			nft_fw_nfqws_pre "$f4" "" $QNUM_NFQWS_GAMES
		}
	}
	[ -n "$NFQWS_GAMES_PORTS_UDP" ] && {
		[ -n "$NFQWS_GAMES_UDP_PKT_OUT" -a "$NFQWS_GAMES_UDP_PKT_OUT" != 0 ] && {
			f4="udp dport {$NFQWS_GAMES_PORTS_UDP} $(nft_first_packets $NFQWS_GAMES_UDP_PKT_OUT)"
			f4="$f4 ip daddr @$NFQWS_GAMES_IPSET_NAME"
			nft_fw_nfqws_post "$f4" "" $QNUM_NFQWS_GAMES
		}
		[ -n "$NFQWS_GAMES_UDP_PKT_IN" -a "$NFQWS_GAMES_UDP_PKT_IN" != 0 ] && {
			f4="udp sport {$NFQWS_GAMES_PORTS_UDP} $(nft_first_packets $NFQWS_GAMES_UDP_PKT_IN)"
			f4="$f4 ip saddr @$NFQWS_GAMES_IPSET_NAME"
			nft_fw_nfqws_pre "$f4" "" $QNUM_NFQWS_GAMES
		}
	}
}

zapret_custom_firewall_nft_flush()
{
	# this function is called after all nft fw rules are deleted
	# however sets are not deleted. it's desired to clear sets here.
	nft_del_set $NFQWS_GAMES_IPSET_NAME 2>/dev/null
}
