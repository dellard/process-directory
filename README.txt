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

This README describes how to set up and use the process-directory.sh
script, which extracts possible SCADA data from a directory of gzip'd
pcap files.  (process-directory.sh can be modified to extract other
kinds of data as well, if desired -- see filter-scada.sh)

## Prerequisites

These instructions were tested on Ubuntu 18.04.3, although this
software should be portable to other Linux systems.

### General software prereqs

sudo apt install build-essential python3 python-dpkt tcpreplay

### Installing load-test

A tarball for the part of load-test used by this script is included.
Note that this version of load-test has minor edits to increase the
number of files supported, so please use the included version instead
of the version from github.

You can install load-test wherever you like, but process-directory.sh
assumes that it's installed in the the load-test subdirectory of the
directory where process-directory.sh is.  If you decide to install it
elsewhere, edit process-directory.sh to change the value of LOADTEST
to be wherever you installed it.

To install load-test, untar load-test.tgz in the desired location, cd
into the load-test directory, and type make.  The build process leaves
the executables in the same directory.  Please let me know if there
are any problems.

### Data prerequisites

Before running the script, you must already have a copy of whatever
pcap.gz files you want to examine, arranged in the following manner:

  - There should be one parent directory for all of the directories
    you want to process.
    
  - Each leaf subdirectory should contain pcap.gz files that can be
    merged together chronologically.  For example, if you have a data
    set with one pcap file per hour and want to analyze the data in
    24-hour chunks, you would put the 24 pcap files for each chunk
    into a separate directory.

  - If you do NOT want to merge the output for each input files, then
    you MUST put each input file in a separate directory.

  - The directory structure may have additional levels and contain
    non-pcap.gz files.

For example, if you have hourly traces from two sources X and Y,
on two dates 20210527 and 20210528, and you want to group them by
day but not site, then you might use a directory structure like:

    traces
      /X
        /20210527
          /00.pcap.gz
          ..
          /23.pcap.gz
        /20210528
          /00.pcap.gz
          ..
          /23.pcap.gz
      /Y
        /20210527
          /00.pcap.gz
          ..
          /23.pcap.gz
        /20210528
          /00.pcap.gz
          ..
          /23.pcap.gz

Note that many trace data sets, including the CAIDA passive traces,
are already arranged in a similar manner and can be processed by this
script without any modification.

The script places its output in a directory also specified on the
commandline.  If necessary, it will create the given directory.  In
this document, we'll call this directory OUTDIR.  Note that it is
permitted for INDIR and OUTDIR to be the same directory, but this is
usually a bad idea.

The script will duplicate the structure of INDIR in OUTDIR.  Then, for
each pcap.gz file in INDIR, it will create a corresponding pcap file
in OUTDIR that contains the packets that remain after the filter
(defined in filter-scada.sh) is applied.  Note that this is a pcap
file, not a pcap.gz file.

For each directory that contains pcap.gz files in INDIR, it will also
weave together all the created pcap files in that directory in OUTDIR,
to create a single pcap that spans the entire hour (instead of the
minute-long pcap files in INDIR) and then do two operations on the
result: first, it uses tcprewrite to add Ethernet headers to the file
(because some of our tools assume that there are Ethernet headers),
and then it uses find-flows to remove any extraneous packets.

The files created in each directory are:

  - combo.pcap - all of the pcap files, woven together in time order

  - eth_combo.pcap - combo.pcap, with Ethernet headers added

  - flows_combo.pcap - the output of find-flows on eth_combo.pcap

find-flows uses heuristics to determine whether packets are likely to
be part of "interesting" flows, or whether they appear to be spurious
and/or IBR.  For example, if we only see a very small number of
packets for a given 5-tuple, then find-flows will discard all packets
with that 5-tuple because we aren't interested in very small flows.
This heuristic might not be useful to other researchers; find-flows
can be modified to meet different requirements, or its output can
simply be ignored.

## Running process-directory.sh

./process-directory.sh INDIR OUTDIR

This may take a long time to run, depending on the volume of traces
you have, and how fast your system is.  On our test system (which is
not particularly fast) the filter pass runs at 1-2 gzip'd GB/minute,
so if you have TBs of data it can take days.

Note that in the process-directory.sh script there is a variable names
CONCURRENCY that specifies the number of concurrent filter processes
to run -- for a machine with a relatively slow I/O subsystem, the
default concurrency of 2 is enough.  If you have a fast I/O subsystem
then you can try higher levels, which might help.
