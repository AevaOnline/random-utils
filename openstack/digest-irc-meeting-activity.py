#!/usr/bin/env python

from collections import defaultdict

monday = [i.strip() for i in file('1700.txt', 'r').readlines()]
tuesday = [i.strip() for i in file('0500.txt', 'r').readlines()]

meetings = {
        "Monday": monday,
        "Tuesday": tuesday
        }

cores = ['devananda', 'nobodycam', 'jroll', 'lucasagomes', 'rloo',  'dtantsur', 'shrews', 'yuriyz', 'rameshg87', 'haomeng']

print("TOTAL MEETINGS")
print("  Monday: %s" % len(monday))
print("  Tuesday: %s" % len(tuesday))

print("TOTAL LINES BY DAY")
for day in meetings.keys():
    by_day = 0
    for f in meetings[day]:
        lines = len(file(f + ".log.txt", 'r').readlines())
        print("    %s - %s - %s" % (f, day, lines))
        by_day += lines
    print("  %s: %s" % (day, by_day))

print("UNIQUE PARTICIPANTS")
for day in meetings.keys():
    by_day = set()
    for f in meetings[day]:
        participants = defaultdict(int)
        for line in file(f + ".log.txt", 'r').readlines():
            line = line.lower()
            try:
                person = line[1 + line.index('<') : line.index('>')]
                filtered = filter(person.startswith, cores)
                if filtered:
                    person = filtered[0]
                participants[person] += 1
            except ValueError:
                continue
        print("    %s - %s - %s - %s" % (f, day, len(participants), len([p for p in participants if p in cores])))
        by_day = set(participants.keys() + list(by_day))
    print("  %s: total: %s - cores: %s" % (day, len(by_day), len([p for p in by_day if p in cores])))
    
