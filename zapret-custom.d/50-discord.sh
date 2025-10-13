# This script creates iptables/nftables rules to send Discord voice-related UDP packets to nfqws
# NOTE: @ih requires nft 1.0.1+ and updated kernel version.
#
# - Discord IP Discovery (app-based voice connection) https://discord.com/developers/docs/topics/voice-connections#ip-discovery
#   - Match signature pattern: 0x00010046 (Type = 1, Length = 70)
#   - Conditions: UDP length = 82 bytes (8-byte header + 74-byte payload)
#
# Enabled only if a port range is set in `$NFQWS_PORTS_UDP_DISCORD` in zapret-config.sh.
# Otherwise, this script does nothing.
#
[ -z "$NFQWS_PORTS_UDP_DISCORD" ] && return

zapret_custom_firewall() { # $1 - 1 - run, 0 - stop
	local port_range=$(replace_char - : "$NFQWS_PORTS_UDP_DISCORD")
  local f="-p udp --dport $port_range -m u32 --u32"

  local dis_v4="0>>22&0x3C@4>>16=0x52&&0>>22&0x3C@8=0x00010046&&0>>22&0x3C@16=0&&0>>22&0x3C@76=0"
  local dis_v6="44>>16=0x52&&48=0x00010046&&56=0&&116=0"

  fw_nfqws_post "$1" "$f $dis_v4" "$f $dis_v6" 200
}

zapret_custom_firewall_nft() { # stop logic is not required
  local f="udp dport $NFQWS_PORTS_UDP_DISCORD udp length == 82 @ih,0,32 0x00010046 @ih,64,128 0x00000000000000000000000000000000 @ih,192,128 0x00000000000000000000000000000000 @ih,320,128 0x00000000000000000000000000000000 @ih,448,128 0x00000000000000000000000000000000"
  nft_fw_nfqws_post "$f" "$f" 200
}
