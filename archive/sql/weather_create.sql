
CREATE TABLE weather_sources (
       id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY,
       name VARCHAR(32) NOT NULL
);

CREATE TABLE weather_ranges (
       range_mins INTEGER NOT NULL PRIMARY KEY,
       min_query_secs INTEGER NOT NULL
);

# Query < 2 months = 30 min samples (1-2880 rows)
#  < 5 years = daily (60-1825 rows)
# otherwize weekly (60- rows)
INSERT INTO weather_ranges (range_mins, min_query_secs)
VALUES (30, 0), (1440, 5184000), (10080, 157680000), (43200, 788400000);
COMMIT;

CREATE TABLE weather_windmap (
       id INTEGER NOT NULL PRIMARY KEY,
       direction VARCHAR(4) NOT NULL
);

INSERT INTO weather_windmap (id, direction)
VALUES (0, "N"), (1, "NNE"), (2, "NE"), (3, "ENE"), (4, "E"), (5, "ESE"),
       (6, "SE"), (7, "SSE"), (8, "S"), (9, "SSW"), (10, "SW"), (11, "WSW"),
       (12, "W"), (13, "WNW"), (14, "NW"), (15, "NNW"), (16, "");
COMMIT;

CREATE TABLE weather_samples (
       source_id INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_samples_source_fk (source_id)
         REFERENCES weather_sources (id)
         ON UPDATE CASCADE ON DELETE RESTRICT,
       time_observed DATETIME NOT NULL,
       time_utc DATETIME NOT NULL,
       barometer FLOAT(5,2) NOT NULL,
       temp_in FLOAT(5,2) NOT NULL,
       humid_in INTEGER NOT NULL,
       temp_out FLOAT(5,2) NOT NULL,
       high_temp_out FLOAT(5,2) NOT NULL,
       low_temp_out FLOAT(5,2) NOT NULL,
       humid_out INTEGER NOT NULL,
       wind_samples INTEGER NOT NULL,
       wind_speed FLOAT(5,2) NOT NULL,
       wind_dir INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_samples_wind_fk (wind_dir)
         REFERENCES weather_windmap (id)
         ON UPDATE CASCADE ON DELETE RESTRICT,
       high_wind_speed FLOAT(5,2) NOT NULL,
       high_wind_dir INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_samples_high_wind_fk (high_wind_dir)
         REFERENCES weather_windmap (id)
         ON UPDATE CASCADE ON DELETE RESTRICT,
       rain FLOAT(5,2) NOT NULL,
       high_rain FLOAT(5,2) NOT NULL,
       CONSTRAINT PRIMARY KEY (source_id, time_utc)
);

CREATE TABLE weather_summary (
       source_id INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_summary_source_fk (source_id)
         REFERENCES weather_sources (id)
         ON UPDATE CASCADE ON DELETE RESTRICT,
       range_mins INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_summary_range_fk (range_mins)
     	 REFERENCES weather_ranges (range_mins)
         ON UPDATE RESTRICT ON DELETE CASCADE,
       time_utc DATETIME NOT NULL,
       barometer FLOAT(5,2) NOT NULL,
       temp_in FLOAT(5,2) NOT NULL,
       humid_in INTEGER NOT NULL,
       temp_out FLOAT(5,2) NOT NULL,
       high_temp_out FLOAT(5,2) NOT NULL,
       low_temp_out FLOAT(5,2) NOT NULL,
       humid_out INTEGER NOT NULL,
       wind_samples INTEGER NOT NULL,
       wind_speed FLOAT(5,2) NOT NULL,
       wind_dir INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_summary_wind_fk (wind_dir)
         REFERENCES weather_windmap (id)
         ON UPDATE CASCADE ON DELETE RESTRICT,
       high_wind_speed FLOAT(5,2) NOT NULL,
       high_wind_dir INTEGER NOT NULL,
       CONSTRAINT FOREIGN KEY weather_summary_high_wind_fk (high_wind_dir)
         REFERENCES weather_windmap (id)
         ON UPDATE CASCADE ON DELETE RESTRICT,
       rain FLOAT(5,2) NOT NULL,
       high_rain FLOAT(5,2) NOT NULL,
       num_samples INTEGER NOT NULL,
       CONSTRAINT PRIMARY KEY (source_id, range_mins, time_utc)
);

CREATE TABLE weather_log (
       id INTEGER NOT NULL AUTO_INCREMENT PRIMARY KEY,
       dt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
       	  ON UPDATE CURRENT_TIMESTAMP,
       msg VARCHAR(255) NOT NULL
);

