#!/usr/bin/env python

# This script takes one parameter, the file name of an ironic-conductor log file
# and calculates the total time spent performing commands over SSH
#
# It's goal: determine how much time was wasted by the ssh power driver
# results: about 5% of the total test run time

import re
import sys
import datetime

first_time = None
this_time = None
last_time = None
total_time = datetime.timedelta(0)

match_string = 'oslo_concurrency.processutils [-] Running cmd (SSH)'

def gen_time(ts):
    return datetime.datetime.strptime(ts[:-6], '%Y-%m-%d %H:%M:%S.%f')


with open(sys.argv[1]) as file:
    line = True
    while line:
        line = file.readline()
        chunk = re.split(' DEBUG ', line)
        # last line matched the fingerprint, calculate time delta
        if this_time:
            new_time = gen_time(chunk[0])
            delta = new_time - this_time
            this_time = None
            total_time += delta
            continue

        # line didn't split properly
        if len(chunk) < 2 or len(chunk[1]) < 50:
            continue
        # line doesn't match our fingerprint
        elif match_string != chunk[1][:51]:
            continue
        # we've got a winner, save the time
        this_time = gen_time(chunk[0])
        last_time = this_time
        if not first_time:
            first_time = this_time


print("TIME SPENT IN SSH: %s" % total_time)
print("TOTAL TIME IS: %s" % (last_time - first_time))
