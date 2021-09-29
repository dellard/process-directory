#!/usr/bin/env bash
#
# FRESNEL: fresnel_dista
#
# Copyright © 2019-2021 - Raytheon BBN Technologies Corp.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# DISTRIBUTION STATEMENT A.
# Approved for public release: distribution unlimited.
#
# This material is based upon work supported by the Defense Advanced
# Research Projects Agency under Contract No. W911NF-19-C-0042.
# Any opinions, findings and conclusions or recommendations expressed
# in this material are those of the author(s) and do not necessarily
# reflect the views of the Defense Advanced Research Project Agency.
#
# FRESNEL: end

# Define the tcpdump filter you want to use to match all of the packets
# you want to extract from the data files.
#
# Right now, this is our best guess of what the kinds of SCADA we're
# interested in looks like.
#
create_filter() {

    # The E-104 protocol is spec'd to use tcp:2404
    local E104="tcp and port 2404"

    # The TC57 extension to E-104 uses tcp:19998
    local TC57="tcp and port 19998"

    # SynchroPhasor uses tcp:4712 or udp:4713
    local SYNC="(tcp and port 4712) or (udp and port 4713)"

    # IEC 61850 (aka 61x50) uses tcp:102
    # NOTE: this is not well-defined in the docs I have; it
    # could be wrong
    local I61X50="tcp and port 102"

    # OPC is a gateway protocol, which is used to create a
    # VPN-like functionality some kinds # of SCADA traffic
    local OPC="(tcp and port 21379) or (port 4840)"

    # Paste them all together...
    #
    local filter="($E104) or ($TC57) or ($SYNC) or ($I61X50) or ($OPC)"

    echo $filter
}

apply_filter() {
    local pcapgz="$1"
    local outfile="$2"
    local filter=$(create_filter)
    local tmpfile="tmp_in.$$.pcap"

    # if the outfile already exists, then do nothing
    #
    if [ ! -f "$outfile" ]; then
	gunzip -c "$pcapgz" > "$tmpfile"
	if [ $? -ne 0 ]; then
	    echo "ERROR: could not unzip [$pcapgz] into [$tmpfile]"
	    rm -f "$tmpfile"
	    exit 1
	fi

	tcpdump -r "$tmpfile" -w "$outfile" "$filter"
	if [ $? -ne 0 ]; then
	    echo "ERROR: could not tcpdump [$tmpfile] into [$outfile]"
	    rm -f "$outfile" "$tmpfile"
	    exit 1
	fi

	rm -f "$tmpfile"
    fi
}

usage() {
    echo "Usage: $0 IN.pcap.gz OUT.pcap"
}

filter_scada() {
    local infile="$1"
    local outfile="$2"

    if [ ! -r "$infile" ]; then
	echo "ERROR: input file [$infile] does not exist"
	exit 1
    fi

    if [ $(basename "$infile") = $(basename -s .pcap.gz "$infile") ]; then
	echo "ERROR: input file [$infile] must be a .pcap.gz file"
	exit 1
    fi

    if [ ! -d $(dirname "$outfile") ]; then
	echo "ERROR: directory for output file [$outfile] does not exist"
	exit 1
    fi

    if [ $(basename "$outfile") = $(basename -s .pcap "$outfile") ]; then
	echo "ERROR: output file [$outfile] must be a .pcap file"
	exit 1
    fi

    apply_filter "$infile" "$outfile"
}

if [ $# -ne 2 ]; then
    echo "ERROR: bad usage"
    usage
    exit 1
fi

filter_scada "$1" "$2"
