#!/usr/bin/python

from pychart import *
from datetime import *
import sys, cStringIO
import MySQLdb
import json

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

def format_date_range(date_range):
    fmt = "%Y/%m/%d"
    return "date range %s - %s" % (format_date(date_range[0], fmt=fmt),
                                   format_date(date_range[1], fmt=fmt))

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

BARO_COL=1
TEMP_COL=4
HUM_COL=5
WIND_COL=6
MAXWIND_COL=7
RAIN_COL=8
MAXRAIN_COL=9

def read_data(params):

    #source format:
    # date(0) time(1) barometer(2) tempin(3) humin(4) tempout(5)
    # humout(6) windsamples(7) avgwindsp(8) winddir(9) highwindsp(10)
    # highwinddir(11) highrainrate(12) rainrate(13)

    # output format:
    # date-float(0) barometer(1) tempin(2) humin(3) tempout(4) humout(5)
    # wind(6) max_wind(7) rain(8) max_rain(9)

    data = []
    date_range = params["date_range"]
    d = date_range[0]
    while d <= date_range[1]:
        dstr = date.fromordinal(d).strftime("%Y-%m-%d")
        try:
            tdata = chart_data.read_csv("/srv/www/weather/data/" + dstr + ".wld", "\t")
            tdata = chart_data.transform(lambda x:
                                             [date_to_float(x[0], x[1]),
                                              x[2], x[3], x[4], x[5], x[6],
                                              x[8], x[10], x[13], x[12]],
                                         tdata)
            tdata = chart_data.filter(lambda x:
                                          x[TEMP_COL] < 120 and
                                      x[WIND_COL] < 200, tdata)
            data.extend(tdata)
        except:
            None
        d += 1

    data = sorted(data)
    dimen = params["dimen"]
    average = params["average"]
    if len(data) > dimen[0] and average:
        # refactor data down to horiz resolution
        ndata = []
        dx = (float(date_range[1]) + 1 - date_range[0]) / dimen[0]
        ex = data[0][0]
        n = 0
        for x in range(dimen[0]):
            y = None
            c = 0
            ex += dx
            while data[n][0] < ex:
                c += 1
                d = data[n]
                if y:
                    for i in [1,2,3,4,5,6,8]:
                        y[i] += d[i]
                    for i in [7,9]:
                        y[i] = max(y[i], d[i])
                else:
                    y = [ex - dx/2]
                    y.extend(d[1:])
                    
                n += 1
                if n >= len(data):
                    break
            if c:
                for i in [1,2,3,4,5,6,8]:
                    y[i] /= c
                ndata.append(y)
            if n >= len(data):
                break
        data = ndata

    return data

def data_date_range(data):
    if not len(data):
        return cur_range
    date_data = chart_data.extract_columns(data, 0)
    min_date = int(min(date_data)[0])
    max_date = int(max(date_data)[0]) + 1
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

def show_msg(msg):
    return text_box.T(text="/30" + msg, line_style=None)

def show_no_data(params):
    return show_msg("No %s data for %s" %
                    (params["mode"], format_date_range(params["date_range"])))

def show_wind(params, data):
    x_range = data_date_range(data)
    x_axis = get_date_axis(x_range)
    ar = area.T(size = params["dimen"],
                legend=legend.T(shadow=(2, -2, fill_style.gray50)),
                y_grid_interval=5, x_axis = x_axis, x_range = x_range,
                y_axis = axis.Y(format="%.1f", label="Wind (mph)",
                                tic_interval=5))
    ar.add_plot(line_plot.T(label="Max Wind", data=data, ycol=MAXWIND_COL,
                            line_style=line_style.red),
                line_plot.T(label="Avg Wind", data=data, ycol=WIND_COL,
                            line_style=line_style.blue))
    return ar

def show_temp(params, data):
    x_range = data_date_range(data)
    x_axis = get_date_axis(x_range)
    ar = area.T(size = params["dimen"], legend=None,
                y_grid_interval=5, x_axis=x_axis, x_range = x_range,
                y_axis = axis.Y(format="%.0f", label="Temp (F)", tic_interval=5))
    ar.add_plot(line_plot.T(label="Temp", data=data, ycol=TEMP_COL, 
                            line_style=line_style.blue))
    return ar

def build_params(fdate, tdate, dimen, average):
    if tdate < fdate:
        xdate = tdate
        tdate = fdate
        fdate = xdate

    params = {}
    params["date_range"] = (fdate, tdate)
    params["dimen"] = dimen
    params["average"] = int(average)
    return params

def napa(req, mode=None, from_date=None, to_date=None, average="0"):
    fh = cStringIO.StringIO()

    theme.use_color = True
    theme.default_font_size = 15
    theme.default_font_family = "Times"
    theme.reinitialize()

    can = canvas.init(fh, "png")

    if mode not in ("wind", "temp"):
        mode = "temp"

    fdate = parse_date(from_date)
    tdate = parse_date(to_date)

    if not fdate:
        v = show_msg("Invalid from_date: " + repr(from_date))
    elif not tdate:
        v = show_msg("Invalid to_date: " + repr(to_date))
    else:
        params = build_params(fdate, tdate, (600, 400), average)

        data = read_data(params)
        if not len(data):
            return show_no_data(params)

        if mode == "wind":
            v = show_wind(params, data)
        elif mode == "temp":
            v = show_temp(params, data)
        else:
            v = show_msg("Invalid mode: " + repr(mode))
    
    if not v:
        v = show_msg("Check you're errors...")
    v.draw(can)
    
    can.close()
    req.content_type = "image/png"

    return fh.getvalue()

def data(req, source=None, col=None):
    all_columns = [ "barometer", "temp_in", "humid_in", "temp_out", "high_temp_out", "low_temp_out", "humid_out", "wind_samples", "wind_speed", "wind_dir", "high_wind_speed", "high_wind_dir", "rain", "high_rain"]
    cols = []
    if col:
        for c in col.split(","):
            if c in all_columns:
                cols.append(c)
    if len(cols) == 0:
        cols = all_columns
    db=MySQLdb.connect("localhost","weather","69ftweather","weather")
    dbc = db.cursor()
    if source:
        srcid = int(source)
    else:
        srcid = 0
    stmt = 'select time_observed, ' + ",".join(cols) + ' from weather_samples where source_id = %(srcid)s'
    dbc.execute(stmt, vars())
    result = []
    row = dbc.fetchone()
    while row:
        data = [int(row[0].strftime("%s"))*1000]
        data.extend(row[1:])
        result.append(data)
        row = dbc.fetchone()
    req.content_type = "application/json"
    return json.dumps(result)

def index():
    return "in index"
