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

SCRIPTDIR=$(readlink -f $(dirname $0))

# Commandline parameters:
#
# INDIR: root directory from which the input pcap.gz files are read.
# See the README.txt for the specification of this directory.
#
# OUTDIR: the directory to which the output pcap files are written.
# This directory will be created, if necessary.  WARNING: you usually
# DON'T want this to be the same as INDIR -- things will work if you,
# do, but cleaning up any problems will be more complicated

# Script parameters:
#
# CONCURRENCY is the number of concurrent filtering processes to use.
# If you have a system with fast CPUs and fast drives, you can increase
# this, but for my old system (with fairly sluggish disks) unzipping
# more than two pcap files at the same time saturates the bandwidth
# available to the file system.  If INDIR and OUTDIR are on SSDs and
# you have a fast multicore CPU, CONCURRENCY=8 is plausible.
#
# LOADTEST is the name of the directory where the load-test tools
# are installed.  The only element of load-test used by this script
# is pcap_weave.

CONCURRENCY=2

LOADTEST="$SCRIPTDIR"/load-test
WEAVE="$LOADTEST"/pcap_weave

# make sure that the scripts and executables we need are
# where we expect them to be
#
check_env() {
    if [ ! -x "$WEAVE" ]; then
	echo "ERROR: pcap_weave is missing from [$LOADTEST]"
	exit 1
    fi

    if [ ! -x "$SCRIPTDIR"/filter-scada.sh ]; then
	echo "ERROR: filter-scada.sh is missing from [$SCRIPTDIR]"
	exit 1
    fi

    if [ ! -x "$SCRIPTDIR"/find-flows ]; then
	echo "ERROR: find-flows is missing from [$SCRIPTDIR]"
	exit 1
    fi

    if [ -z "$(which tcprewrite)" ]; then
	echo "ERROR: tcprewrite is not installed/in your path"
	exit 1
    fi
}

create_filtered_pcaps() {
    local indir="$1"
    local outdir="$2"

    local dirs=$(cd "$indir" ; find . -type d \
	    | sed -e 's/^..//')
    local files=$(cd "$indir" ; find . -type f | grep pcap.gz$ \
	    | sed -e 's/^..//')

    local dir
    for dir in $dirs; do
	if [ ! -d "$outdir"/"$dir" ]; then
	    mkdir -p "$outdir"/"$dir"
	    if [ $? -ne 0 ]; then
		echo "ERROR: could not create directory [$outdir/$dir]"
		exit 1
	    fi
	fi
    done

    # This is a little complicated, but useful: in order to keep the system
    # busy, start working on $CONCURRENCY files (the "head") immediately in
    # the background, and then, every a file is finished (as detected by
    # the "wait -n"), start immediately working on one of the files in the
    # tail in the background as well.  When all the jobs have been started,
    # do one last "wait" to block until they're all complete.
    #
    local arr_files=($files)
    local head="${arr_files[@]:0:$CONCURRENCY}"
    local tail="${arr_files[@]:$CONCURRENCY}"
    local file

    for file in $head; do
	echo creating "$outdir"/"$file" "(head)"
	local outfile=$(echo $file | sed -e 's/.gz$//')
        "$SCRIPTDIR"/filter-scada.sh "$indir"/"$file" "$outdir"/"$outfile" &
    done

    for file in $tail; do
	wait -n
	echo creating "$outdir"/"$file"
	local outfile=$(echo $file | sed -e 's/.gz$//')
	"$SCRIPTDIR"/filter-scada.sh "$indir"/"$file" "$outdir"/"$outfile" &
    done

    wait
}

combine_pcaps() {
    local workdir="$1"

    # find the leaf directories that contain pcaps; we need to
    # combine the contents of each leaf into a single combo file
    #
    local dirs=$(cd "$workdir"; find . -type f \
	    | sed -e 's/^\.\///' \
	    | grep .pcap$ | sed -e 's/\/[^\/]*$//' | sort -u)

    local dir
    for dir in $dirs; do

	echo "Working in [$workdir/$dir]"
	# Remove derived files
	#
	rm -f "$workdir"/"$dir"/combo.pcap
	rm -f "$workdir"/"$dir"/eth_combo.pcap
	rm -f "$workdir"/"$dir"/flows_combo.pcap

	# NOTE: the pcap_weave commandline DEPENDS on there
	# not being ANY .pcap files in this directory except
	# the ones we want to weave together!
	#
	echo "    weaving pcaps..."
	$WEAVE -R -o "$workdir"/"$dir"/combo.pcap \
		"$workdir"/"$dir"/*.pcap
	if [ $? -ne 0 ]; then
	    echo "ERROR: weaving failed in [$dir]"
	    rm -f "$workdir"/"$dir"/combo.pcap
	    exit 1
	fi

	echo "    adding Ethernet headers..."
	tcprewrite --dlt=enet \
		--enet-dmac=0d:0e:0a:0d:0b:0e \
		--enet-smac=0f:0a:0c:0e:b0:0c \
		--infile="$workdir"/"$dir"/combo.pcap \
		--outfile="$workdir"/"$dir"/eth_combo.pcap
	if [ $? -ne 0 ]; then
	    echo "ERROR: tcprewrite failed to add headers in [$dir]"
	    rm -f "$workdir"/"$dir"/eth_combo.pcap
	    exit 1
	fi

	echo "    removing non-flow packets..."
	"$SCRIPTDIR"/find-flows \
		"$workdir"/"$dir"/eth_combo.pcap \
		"$workdir"/"$dir"/flows_combo.pcap
	if [ $? -ne 0 ]; then
	    echo "ERROR: find-flows failed to cull packets in [$dir]"
	    exit 1
	fi
    done
}

if [ $# -ne 2 ]; then
    echo "ERROR: usage: $0 INDIR OUTDIR"
    exit 1
fi

INDIR="$1"
OUTDIR="$2"

if [ ! -d "$INDIR" ]; then
    echo "ERROR: cannot read input directory [$INDIR]"
    exit 1
fi

if [ ! -d "$OUTDIR" ]; then
    mkdir -p "$OUTDIR"
    if [ $? -ne 0 ]; then
	echo "ERROR: could not create OUTDIR [$OUTDIR]"
	exit 1
    fi
fi

check_env
create_filtered_pcaps "$INDIR" "$OUTDIR"
combine_pcaps "$OUTDIR"
