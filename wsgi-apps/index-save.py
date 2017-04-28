#!/usr/bin/python

from pychart import *
from datetime import *
import sys, cStringIO

def date_to_float(day, time):
    year, month, day = map(int, day.split("-"))
    hour, minute = map(int, time.split(":"))
    d = datetime(year, month, day, hour, minute)
    return d.toordinal() + (d.hour * 60.0 + d.minute) / 1440

def format_date(float_date, detail=0, fmt=None):
    int_date = int(float_date)
    float_date = (float_date - int_date) * 1440
    d = date.fromordinal(int_date)
    t = time(int(float_date/60), int(float_date%60))
    dt = datetime.combine(d, t)
    if fmt:
        return dt.strftime(fmt)
    if detail:
        return "/a60{}" + dt.strftime("%Y//%m//%d\n%H:%M")
    else:
        return "/a60{}" + dt.strftime("%Y//%m//%d")

def format_detail_date(float_date):
    return format_date(float_date, detail=1)

def date_range(fdate, tdate):
    fmt = "%Y/%m/%d"
    return "date range %s - %s" % (format_date(fdate, fmt=fmt),
                                   format_date(tdate, fmt=fmt))

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

def read_data(fdate, tdate):

    data = []
    d = fdate
    while d <= tdate:
        dstr = date.fromordinal(d).strftime("%Y-%m-%d")
        try:
            data.extend(chart_data.read_csv("/srv/www/weather/data/" + dstr + ".wld", "\t"))
        except:
            None
        d += 1
    data = chart_data.transform(lambda x: [date_to_float(x[0], x[1]), x[2], x[3], x[4], x[5], x[6], x[7], x[8], x[9], x[10], x[11], x[12], x[13]], data)
    return sorted(data)

def get_date_range(cur_range, data):
    if not len(data):
        return cur_range
    date_data = chart_data.extract_columns(data, 0)
    min_date = int(min(date_data)[0])
    max_date = int(max(date_data)[0]) + 1
    if cur_range:
        min_date = min((min_date, cur_range[0]))
        max_date = max((max_date, cur_range[1]))
    return (min_date, max_date)

def get_date_axis(date_range):
    drange = date_range[1] - date_range[0]
    fmt = format_date
    if drange < 2:
        dtic = 0.25
        fmt = format_detail_date
    elif drange < 7:
        dtic = 1
    else:
        dtic = drange / 6
    return axis.X(format=fmt, label="Time", tic_interval=dtic)

def napa(req, mode=None, from_date=None, to_date=None):
    fh = cStringIO.StringIO()

    theme.use_color = True
    theme.reinitialize()

    #format: date	time	barometer	tempin	humin	tempout
    # humout	windsamples	avgwindsp	winddir	highwindsp
    # highwinddir	highrainrate	rainrate

    fdate = parse_date(from_date)
    if not fdate:
        return "Invalid from_date: " + repr(from_date)
    tdate = parse_date(to_date)
    if not tdate:
        return "Invalid to_date: " + repr(to_date)
    if tdate < fdate:
        xdate = tdate
        tdate = fdate
        fdate = xdate
    data = read_data(fdate, tdate)

    can = canvas.init(fh, "png")
    width = 600
    size = (width, 400)

    if mode == "wind":
        wind_data = chart_data.extract_columns(data, 0, 7)
        wind_data = chart_data.filter(lambda x: x[1] < 200, wind_data)
        if not len(wind_data):
            return "No wind data for %s" % date_range(fdate, tdate)
        max_wind_data = chart_data.extract_columns(data, 0, 9)
        max_wind_data = chart_data.filter(lambda x: x[1] < 200, max_wind_data)
        x_range = get_date_range(None, wind_data)
        x_range = get_date_range(x_range, max_wind_data)
        x_axis = get_date_axis(x_range)
        ar = area.T(size = size, legend=legend.T(shadow=(2,-2,fill_style.gray50)),
                    y_grid_interval=5, x_axis = x_axis, x_range = x_range,
                    y_axis = axis.Y(format="%.1f", label="Wind (mph)", tic_interval=5))
        if len(max_wind_data):
            ar.add_plot(line_plot.T(label="Avg Wind", data=wind_data, line_style=line_style.blue),
                        line_plot.T(label="Max Wind", data=max_wind_data, line_style=line_style.red))
        else:
            ar.add_plot(line_plot.T(label="Avg Wind", data=wind_data, line_style=line_style.blue))
    elif mode == "temp":
        temp_data = chart_data.extract_columns(data, 0, 4)
        if not len(temp_data):
            return "No temp data for %s" % date_range(fdate, tdate)
        temp_data = chart_data.filter(lambda x: x[1] < 120, temp_data)
        x_range = get_date_range(None, temp_data)
        x_axis = get_date_axis(x_range)
        ar = area.T(size = size, legend=None,
                    y_grid_interval=5, x_axis=x_axis, x_range = x_range,
                    y_axis = axis.Y(format="%.0f", label="Temp (F)", tic_interval=5))
        ar.add_plot(line_plot.T(label="Temp", data=temp_data, line_style=line_style.blue))
    else:
        return "Invalid mode: " + repr(mode)
    
    ar.draw(can)
    
    can.close()
    req.content_type = "image/png"

    return fh.getvalue()

def index():
    return "in index"
