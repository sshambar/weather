#!/usr/bin/python

from pychart import *
from datetime import *
import sys, os

def parse_date(s):
    try:
        if not s:
            d = date.today()
        elif len(s.split('-')) == 3:
            parts = s.split('-')
            d = date(int(parts[0]), int(parts[1]), int(parts[2]))
        else:
            d = date.fromordinal(int(s))
        return d.toordinal()
    except:
        return None

def read_data(fname):
    return chart_data.read_csv(fname, "\t")

def write_data(data, fdate, tdate):

    d = fdate
    while d <= tdate:
        dstr = date.fromordinal(d).strftime("%Y-%m-%d")
        year, month, day = dstr.split("-")
        fstr = "%d-%d-%d" % (int(year), int(month), int(day))
        fdata = chart_data.filter(lambda x: x[0] == fstr, data)
        if not len(fdata):
            d += 1
            continue
        fname = "/srv/www/weather/data/" + dstr + ".wld"
        print "writing " + fname
        fd = open(fname, "w")
        for v in fdata:
            fd.write("\t".join(str(x) for x in v))
            fd.write("\n")
        fd.close
        d += 1

def main(argv):

    if len(argv) < 4:
        print "Usage: %s <filename> <from-date> <to-date>" % argv[0]
        sys.exit(1)
    fname = argv[1]
    if not fname:
        print "Missing filename"
        sys.exit(1)
    fdate = parse_date(argv[2])
    if not fdate:
        print "Invalid from_date: " + repr(argv[2])
        sys.exit(1)
    tdate = parse_date(argv[3])
    if not tdate:
        print "Invalid to_date: " + repr(argv[3])
        sys.exit(1)

    data = read_data(fname)
    write_data(data, fdate, tdate)

if __name__ == "__main__":
    main(sys.argv)
