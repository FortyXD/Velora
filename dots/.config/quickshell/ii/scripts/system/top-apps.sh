#!/usr/bin/env bash
# The user's processes with CPU use (top, sampled over half a second) and proportional memory (PSS).
# PSS splits shared pages between processes, so per-app sums don't count shared libraries many times.
# Output: "N <cpu count>", then "pid<TAB>cpu %<TAB>pss kB<TAB>command" per process.
export LC_ALL=C
echo "N $(nproc)"
{
    grep -H '^Pss:' /proc/[0-9]*/smaps_rollup 2>/dev/null \
        | sed -E 's#^/proc/([0-9]+)/smaps_rollup:Pss: +([0-9]+) kB#P \1 \2#'
    top -b -n 2 -d 0.5 -w 512 -u "$USER" \
        | awk '/^top -/ { frame++ } frame == 2 && $1 ~ /^[0-9]+$/ { cmd = $12; for (i = 13; i <= NF; i++) cmd = cmd " " $i; print "T", $1, $9, cmd }'
} | awk '
    $1 == "P" { pss[$2] = $3; next }
    $1 == "T" { cmd = $4; for (i = 5; i <= NF; i++) cmd = cmd " " $i; printf "%s\t%s\t%s\t%s\n", $2, $3, ($2 in pss ? pss[$2] : 0), cmd }'
