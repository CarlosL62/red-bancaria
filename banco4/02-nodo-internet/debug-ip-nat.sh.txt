#!/bin/sh
# ==============================================================================
# Cisco-like "debug ip nat" for Linux (nftables / conntrack)
# Emulates: debug ip nat / debug ip nat detailed
# ==============================================================================

echo "NAT: debugging enabled (emulating Cisco IOS debug ip nat)"
echo "Type Ctrl+C to stop debugging (no debug all)"

conntrack -E -o timestamp 2>/dev/null | awk '
{
    line = $0
    split(line, words)
    
    # 1. Parse timestamp
    raw_ts = words[1]
    gsub(/[^0-9.]/, "", raw_ts)
    split(raw_ts, pts, ".")
    sec = pts[1] + 0
    ms = substr(pts[2], 1, 3)
    if (ms == "") ms = "000"
    ts = strftime("*%b %d %H:%M:%S", sec) "." ms ":"

    # 2. Parse event type
    event = ""
    if (line ~ /\[NEW\]/) event = "NEW"
    else if (line ~ /\[UPDATE\]/) event = "UPDATE"
    else if (line ~ /\[DESTROY\]/) event = "DESTROY"
    if (event == "") next

    # 3. Parse protocol
    proto = "ip"
    if (line ~ / tcp /) proto = "tcp"
    else if (line ~ / udp /) proto = "udp"
    else if (line ~ / icmp /) proto = "icmp"

    # 4. Extract parameters for Original and Reply directions
    src_cnt = 0; dst_cnt = 0; sp_cnt = 0; dp_cnt = 0; id_cnt = 0
    delete src; delete dst; delete sport; delete dport; delete id

    for (i = 2; i <= length(words); i++) {
        split(words[i], kv, "=")
        k = kv[1]; v = kv[2]
        if (k == "src") src[++src_cnt] = v
        else if (k == "dst") dst[++dst_cnt] = v
        else if (k == "sport") sport[++sp_cnt] = v
        else if (k == "dport") dport[++dp_cnt] = v
        else if (k == "id") id[++id_cnt] = v
    }

    orig_s = src[1]; orig_d = dst[1]
    reply_s = src[2]; reply_d = dst[2]
    
    if (orig_s == "" || reply_s == "") next

    pkt_id = (proto == "icmp" ? id[1] : (sport[1] ? sport[1] : (dport[1] ? dport[1] : id[1])))
    if (pkt_id == "") pkt_id = "0"

    # Detect if NAT was applied
    is_snat = (orig_s != reply_d)
    is_dnat = (orig_d != reply_s)

    # If neither SNAT nor DNAT occurred, skip (not a NAT packet)
    if (!is_snat && !is_dnat) next

    if (event == "DESTROY") {
        # Expiring format: *Sep 10 11:02:11.316: NAT: expiring <trans_ip> (<orig_ip>) <proto> <port> (<port>)
        trans_ip = is_snat ? reply_d : reply_s
        orig_ip = is_snat ? orig_s : orig_d
        printf "%s NAT: expiring %s (%s) %s %s (%s)\n", ts, trans_ip, orig_ip, proto, pkt_id, pkt_id
        fflush()
        next
    }

    if (event == "NEW") {
        if (is_snat) {
            # Outbound SNAT initial packet: s=orig_src->trans_src, d=dst [id]
            printf "%s NAT*: s=%s->%s, d=%s [%s]\n", ts, orig_s, reply_d, orig_d, pkt_id
        } else if (is_dnat) {
            # Inbound DNAT initial packet: s=src, d=orig_dst->trans_dst [id]
            printf "%s NAT*: s=%s, d=%s->%s [%s]\n", ts, orig_s, orig_d, reply_s, pkt_id
        }
    } else if (event == "UPDATE") {
        if (is_snat) {
            # Return packet for SNAT: s=dst, d=trans_src->orig_src [id]
            printf "%s NAT*: s=%s, d=%s->%s [%s]\n", ts, reply_s, reply_d, orig_s, pkt_id
        } else if (is_dnat) {
            # Return packet for DNAT: s=trans_dst->orig_dst, d=src [id]
            printf "%s NAT*: s=%s->%s, d=%s [%s]\n", ts, reply_s, orig_d, orig_s, pkt_id
        }
    }
    fflush()
}
'
