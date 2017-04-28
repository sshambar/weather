create table weather_samples (
       source_id integer not null,
       time_observed datetime not null,
       barometer float(5,2) not null,
       temp_in float(5,2) not null,
       humid_in integer not null,
       temp_out float(5,2) not null,
       high_temp_out float(5,2) not null,
       low_temp_out float(5,2) not null,
       humid_out integer not null,
       wind_samples integer not null,
       wind_speed float(5,2) not null,
       wind_dir varchar(4) not null,
       high_wind_speed float(5,2) not null,
       high_wind_dir varchar(4) not null,
       rain float(5,2) not null,
       high_rain float(5,2) not null,
       constraint primary key (source_id, time_observed)
);
