# This script starts an extra nfqws daemon for plain RTMP and sends RTMP
# handshake packets into its own NFQUEUE.
#
# RTMP plain TCP handshake:
#   C0 = 0x03
#   C1:
#     4 bytes time
#     4 bytes zero
#
# Match signature:
#   payload[0]    == 0x03
#   payload[5..8] == 0x00000000
#
# Enabled only if `NFQWS_CUSTOM_RTMP=1` is set in zapret-config.sh.
#
[ "$NFQWS_CUSTOM_RTMP" = "1" ] || return 0

# can override in config :
NFQWS_RTMP_PORTS_TCP=${NFQWS_RTMP_PORTS_TCP:-1935}
NFQWS_RTMP_PKT_OUT=${NFQWS_RTMP_PKT_OUT:-3}
NFQWS_RTMP_OPT="${NFQWS_RTMP_OPT:-
--filter-tcp=*
--ip-id=seq
--dpi-desync-skip-nosni=0
--dpi-desync=multisplit
--dpi-desync-split-pos=3
--dpi-desync-split-seqovl=740
--dpi-desync-split-seqovl-pattern=$ZAPRET_BASE/files/fake/stun.bin
--dpi-desync-any-protocol
}"

alloc_dnum DNUM_NFQWS_RTMP
alloc_qnum QNUM_NFQWS_RTMP

zapret_custom_daemons()
{
	# $1 - 1 - run, 0 - stop

	local opt="--qnum=$QNUM_NFQWS_RTMP $NFQWS_RTMP_OPT"
	do_nfqws $1 $DNUM_NFQWS_RTMP "$opt"
}

zapret_custom_firewall()
{
	# $1 - 1 - run, 0 - stop

	local ports_ipt=$(replace_char - : "$NFQWS_RTMP_PORTS_TCP")
	local f="-p tcp -m multiport --dports $ports_ipt $ipt_connbytes 1:$NFQWS_RTMP_PKT_OUT -m u32 --u32"

	# IPv4 only:
	# - no fragments
	# - first TCP payload byte is 0x03
	# - TCP payload bytes 5..8 are 0x00000000
	local rtmp_v4="4&0x3FFF=0&&0>>22&0x3C@12>>26&0x3C@0>>24=0x03&&0>>22&0x3C@12>>26&0x3C@5=0x00000000"

	fw_nfqws_post "$1" "$f $rtmp_v4" "" "$QNUM_NFQWS_RTMP"
}

zapret_custom_firewall_nft()
{
	local f="tcp dport {$NFQWS_RTMP_PORTS_TCP} $(nft_first_packets $NFQWS_RTMP_PKT_OUT) @ih,0,8 0x03 @ih,40,32 0x00000000"
	nft_fw_nfqws_post "$f" "" "$QNUM_NFQWS_RTMP"
}
