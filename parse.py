#!/usr/bin/env python

import sys, fileinput
import MySQLdb, datetime
import json

def json2():
    db=MySQLdb.connect("localhost","weather","69ftweather","weather")
    dbc = db.cursor()
    srcid = 0
    dbc.execute('''select time_observed, barometer, temp_in, humid_in, temp_out, high_temp_out, low_temp_out, humid_out, wind_samples, wind_speed, wind_dir, high_wind_speed, high_wind_dir, rain, high_rain from weather_samples where source_id = %(srcid)s''', vars())
    result = []
    row = dbc.fetchone()
    while row:
        data = {}
        data['wind'] = row[1]
        result.append(data)
        row = dbc.fetchone()
        if len(result) > 5:
            break;
    print json.dumps(result)

def main():
    db=MySQLdb.connect("localhost","weather","69ftweather","weather")
    dbc = db.cursor()
    srcid = int(0)
    cnt = 0
    for line in fileinput.input():
        cnt += 1
        # skip header
        if cnt < 3:
            continue
        try:
            (date, time, ampm, tempout, hitempout, lowtempout, humout, dew,
             wind, winddir, windrun, hiwind, hiwinddir, chill, heatindx,
             thwindx, bar, rain, rainrate, heatdd, cooldd, tempin, humin,
             indew, inheat, inemc, inden, windsamp, windtx, issrecept,
             arcint) = line.split()
        except:
            print "line ", cnt, sys.exc_info()
            break
        (month, day, year) = date.split('/')
        year = 2000 + int(year)
        (hour, minute) = time.split(':')
        hour = int(hour)
        if hour == 12:
            if ampm == 'a':
                hour = 0
        elif ampm == 'p':
            hour += 12
        if tempout == '---':
            continue # skip when outside data missing
        if windsamp == '---':
            windsamp = 0
        if winddir == '---':
            winddir = ''
        if hiwinddir == '---':
            hiwinddir = ''
        dstr = datetime.datetime(year, int(month), int(day), hour, int(minute))
        (tempout, hitempout, lowtempout, humout, wind, hiwind, bar, rain,
         rainrate, tempin, humin, windsamp) = \
         (float(tempout), float(hitempout), float(lowtempout), int(humout),
          float(wind), float(hiwind), float(bar), float(rain), float(rainrate),
          float(tempin), int(humin), int(windsamp))
        dbc.execute('''insert into weather_samples (source_id, time_observed, barometer, temp_in, humid_in, temp_out, high_temp_out, low_temp_out, humid_out, wind_samples, wind_speed, wind_dir, high_wind_speed, high_wind_dir, rain, high_rain) values(%(srcid)s,%(dstr)s,%(bar)s,%(tempin)s,%(humin)s,%(tempout)s,%(hitempout)s,%(lowtempout)s,%(humout)s,%(windsamp)s,%(wind)s,%(winddir)s,%(hiwind)s,%(hiwinddir)s,%(rain)s,%(rainrate)s)''', vars())
        db.commit()
    print "Imported ", cnt, " items"

if __name__ == "__main__":
    json2()

