function [cmp,muse,garmin] = bed_time_comparison_T1D(SD,file_path)
% BED_TIME_COMPARISON_T1D  Sleep diary vs Garmin (sleep summary) vs Muse (largest ss file)
%   SD        : morning sleep diary table (the "new" table from EMA_to_sleep_diary_morning)
%   file_path : ...\T1D\DATA
%   cmp       : all nights;  muse / garmin : nights flagged >30 min for that device
%   Output is NOT deidentified (full dates + unix timestamps; stays on CRSP).

file_path = char(file_path);
muse_root = fullfile(fileparts(file_path),'Muse','RawData','SleepWakeStudy');

T_study = select_studysheet(file_path);
SID = unique(T_study.SID);
[study_cog,study_sd] = expand_study(T_study);

sleep = study_cog(study_cog.Sleep_Wake_condition == 1,:);
sleep(:,"AMPM") =[];
wake = study_cog(and(study_cog.Sleep_Wake_condition == 0,study_cog.AMPM == "AM"),:);
wake(:,"AMPM") = [];
SD = sortrows(SD,"Date","ascend");
SD = sortrows(SD,"SID","ascend");
SD_sleep = SD(SD.Sleep_Wake_condition == 1, :);
SD_wake = SD(SD.Sleep_Wake_condition == 0, :);

condition = ["Sleep","Wake"];
final = table;
for i = 1:length(SID)
    for ii = 1:2
                path = [muse_root '\' char(condition(ii)) '\' char(string(SID(i))) '\'];
        path_base = [char(file_path) '\Labfront\' char(string(SID(i))) '\'];
        c_file = string({dir(path_base).name});
        path_c = '';
        if ii == 1
            if ~isempty(c_file(contains(c_file,"SC")))
                path_c = [path_base char(c_file(contains(c_file,"SC"))) '\'];
            end
            T = SD_sleep(SD_sleep.SID == SID(i),:);
        else
            if ~isempty(c_file(contains(c_file,"WC")))
                path_c = [path_base char(c_file(contains(c_file,"WC"))) '\'];
            end
            T = SD_wake(SD_wake.SID == SID(i),:);
        end

        h = height(T);
        T.garmin_sleep_unix_ms = nan(h,1);   % Garmin: milliseconds since 1970 UTC
        T.garmin_wake_unix_ms  = nan(h,1);
        T.garmin_sleep_isoDate = strings(h,1);   % e.g. 2025-07-09T22:00:00.000-07:00
        T.muse_start_unix_s    = nan(h,1);   % Muse: seconds since 1970 UTC
        T.muse_end_unix_s      = nan(h,1);
        T.muse_start_time      = strings(h,1);   % raw text from ss "times" column
        T.muse_end_time        = strings(h,1);

        % ---- Garmin (sleep summary) ----
        layer = string.empty;
        if ~isempty(path_c)
            layer = string({dir(path_c).name});
            layer(~contains(layer,string(SID(i)))) = [];
        end
        if ~isempty(layer)
            path_g = [path_c char(layer(1)) '\garmin-connect-sleep-summary\'];
            files = string({dir(fullfile(path_g,'*.csv')).name});
            files(~contains(files,string(SID(i)))) = [];
            if isempty(files)
                fprintf("[GARMIN] no sleep-summary csv: %s\n", path_g);
            else
                lab_t = table;
                for f = 1:numel(files)
                    lab_t = [lab_t; import_sleep_summary([path_g char(files(f))])]; %#ok<AGROW>
                end
                lab_t = lab_t(~isnan(lab_t.unixTimestampInMs) & ~isnat(lab_t.calendarDate),:);
                % one summary per night: keep the last row per calendarDate
                lab_t = sortrows(lab_t,"unixTimestampInMs");
                [~,keep] = unique(lab_t.calendarDate,"last");
                lab_t = lab_t(keep,:);
                % wake = sleep start + time asleep + time awake
                wake_ms = lab_t.unixTimestampInMs + lab_t.durationInMs + fillmissing(lab_t.awakeDurationInMs,"constant",0);

                % calendarDate = the morning the subject woke up, same as T.Date
                for j = 1:height(lab_t)
                    r = dateshift(T.Date,"start","day") == lab_t.calendarDate(j);
                    if ~any(r), continue; end
                    T{r,"garmin_sleep_unix_ms"} = lab_t.unixTimestampInMs(j);
                    T{r,"garmin_wake_unix_ms"}  = wake_ms(j);
                    T{r,"garmin_sleep_isoDate"} = lab_t.isoDate(j);   % raw text, device local time
                end
            end
        end

        % ---- Muse (all stages kept, incl. W) ----
        if ~isfolder(path), fprintf("[MUSE] folder missing: %s\n", path); end
        nights = string({dir(path).name});
        nights(~contains(nights,"N")) = [];
        for j = 1:length(nights)
            n_path = [path char(nights(j)) '\'];
            ss_d = dir(fullfile(n_path,'*_ss*.csv'));
            if isempty(ss_d), fprintf("[MUSE] no _ss file: %s\n", n_path); continue; end
            [~,big] = max([ss_d.bytes]);              % use the largest ss file (most sleep data)
            if numel(ss_d) > 1
                fprintf("[MUSE] %d ss files in %s -> using %s\n", numel(ss_d), n_path, ss_d(big).name);
            end
            ss = string(ss_d(big).name);
            t = readtable([n_path char(ss)]);
            t(t.timestamps == 0 | isnan(t.timestamps),:) = [];
            if height(t) == 0, continue; end
            [~,i_s] = min(t.timestamps);
            [~,i_e] = max(t.timestamps);
            T{j+1,"muse_start_unix_s"} = t.timestamps(i_s);
            T{j+1,"muse_end_unix_s"}   = t.timestamps(i_e);
            % value in the ss file's "times" column on those same rows
            if ismember("times",t.Properties.VariableNames)
                T{j+1,"muse_start_time"} = string(t.times(i_s));
                T{j+1,"muse_end_time"}   = string(t.times(i_e));
            else
                fprintf("[MUSE] no 'times' column in %s (columns: %s)\n", ss(1), ...
                    strjoin(string(t.Properties.VariableNames),", "));
            end
        end
        final = [final;T];
    end
end
clear T t ss n_path lab_t wake_ms

% Sleep diary: bed_time/wake_time = PST, *_local = subject local
final.sleep_diary_sleep_pst   = final.bed_time;
final.sleep_diary_sleep_local = final.bed_time_local;
final.sleep_diary_wake_pst    = final.wake_time;
final.sleep_diary_wake_local  = final.wake_time_local;

columns = string(study_cog.Properties.VariableNames);
columns(matches(columns,["StudyWeek","Day","Sex_1","AMPM"])) = [];
columns = [columns "time_zone" "sleep_duration" "sleep_duration_in_mins" ...
    "sleep_diary_sleep_pst" "sleep_diary_sleep_local" "sleep_diary_wake_pst" "sleep_diary_wake_local" ...
    "garmin_sleep_unix_ms" "garmin_wake_unix_ms" "garmin_sleep_isoDate" "muse_start_unix_s" "muse_end_unix_s" "muse_start_time" "muse_end_time"];
columns = columns(ismember(columns,final.Properties.VariableNames));
new = final(:,columns);

%% ---- Convert raw unix timestamps to each subject's time zone and compare ----
% Our conversion: unix -> subject zone (time_zone column, same codes as T1D_timezones.xlsx)
% Device conversion: Garmin isoDate clock time, Muse ss "times" column
tz_codes = ["PST","MST","CST","EST"];
tz_names = ["America/Los_Angeles","America/Denver","America/Chicago","America/New_York"];
tz_new = repmat("America/Los_Angeles",height(new),1);
for k = 1:numel(tz_codes)
    tz_new(upper(strtrim(string(new.time_zone))) == tz_codes(k)) = tz_names(k);
end

n = height(new);
new.garmin_sleep_converted = NaT(n,1);
new.garmin_wake_converted  = NaT(n,1);
new.muse_start_converted   = NaT(n,1);
new.muse_end_converted     = NaT(n,1);
for r = 1:n
    z = tz_new(r);
    if ~isnan(new.garmin_sleep_unix_ms(r))
        new.garmin_sleep_converted(r) = to_local(new.garmin_sleep_unix_ms(r)/1000, z);
    end
    if ~isnan(new.garmin_wake_unix_ms(r))
        new.garmin_wake_converted(r)  = to_local(new.garmin_wake_unix_ms(r)/1000, z);
    end
    if ~isnan(new.muse_start_unix_s(r))
        new.muse_start_converted(r)   = to_local(new.muse_start_unix_s(r), z);
    end
    if ~isnan(new.muse_end_unix_s(r))
        new.muse_end_converted(r)     = to_local(new.muse_end_unix_s(r), z);
    end
end
fmt = "uuuu-MM-dd HH:mm:ss";
new.garmin_sleep_converted.Format = fmt;  new.garmin_wake_converted.Format = fmt;
new.muse_start_converted.Format   = fmt;  new.muse_end_converted.Format   = fmt;

% clock-time difference in minutes (wraps around midnight; Muse "times" has no date)
garmin_dev  = clock_min(extractBetween(pad_iso(new.garmin_sleep_isoDate),12,19));
muse_s_dev  = clock_min(new.muse_start_time);
muse_e_dev  = clock_min(new.muse_end_time);
new.GARMIN_diff_min     = circ_diff(clock_min(string(new.garmin_sleep_converted,"HH:mm:ss")), garmin_dev);
new.MUSE_start_diff_min = circ_diff(clock_min(string(new.muse_start_converted,"HH:mm:ss")), muse_s_dev);
new.MUSE_end_diff_min   = circ_diff(clock_min(string(new.muse_end_converted,"HH:mm:ss")),   muse_e_dev);

% flags (NaN when there is nothing to compare). A >1 h row is also 1 in _30min.
g = abs(new.GARMIN_diff_min);

m = max(abs([new.MUSE_start_diff_min, new.MUSE_end_diff_min]), [], 2, "omitnan");
new.GARMIN_mismatch_30min = double(g > 30);  new.GARMIN_mismatch_30min(isnan(g)) = NaN;
new.GARMIN_mismatch_1hr   = double(g > 60);  new.GARMIN_mismatch_1hr(isnan(g))   = NaN;
new.MUSE_mismatch_30min   = double(m > 30);  new.MUSE_mismatch_30min(isnan(m))   = NaN;
new.MUSE_mismatch_1hr     = double(m > 60);  new.MUSE_mismatch_1hr(isnan(m))     = NaN;

fprintf("GARMIN: %d/%d nights >30 min, %d >1 h\n", sum(new.GARMIN_mismatch_30min==1), sum(~isnan(g)), sum(new.GARMIN_mismatch_1hr==1));
fprintf("MUSE:   %d/%d nights >30 min, %d >1 h\n", sum(new.MUSE_mismatch_30min==1),   sum(~isnan(m)), sum(new.MUSE_mismatch_1hr==1));
%% ---- For 1-hr flagged nights: compare converted unix time with sleep diary ----
% converted (subject zone) vs diary local and diary PST, clock-time difference in minutes
d_bed_loc  = clock_min(string(new.sleep_diary_sleep_local,"HH:mm:ss"));
d_wake_loc = clock_min(string(new.sleep_diary_wake_local,"HH:mm:ss"));
d_bed_pst  = clock_min(string(new.sleep_diary_sleep_pst,"HH:mm:ss"));
d_wake_pst = clock_min(string(new.sleep_diary_wake_pst,"HH:mm:ss"));
g_bed  = clock_min(string(new.garmin_sleep_converted,"HH:mm:ss"));
g_wake = clock_min(string(new.garmin_wake_converted,"HH:mm:ss"));
m_bed  = clock_min(string(new.muse_start_converted,"HH:mm:ss"));
m_wake = clock_min(string(new.muse_end_converted,"HH:mm:ss"));

gf = new.GARMIN_mismatch_1hr == 1;
mf = new.MUSE_mismatch_1hr == 1;

% worst of bed/wake difference, only on flagged rows (NaN elsewhere)
g_loc = max(abs([circ_diff(g_bed,d_bed_loc), circ_diff(g_wake,d_wake_loc)]),[],2,"omitnan");
g_pst = max(abs([circ_diff(g_bed,d_bed_pst), circ_diff(g_wake,d_wake_pst)]),[],2,"omitnan");
m_loc = max(abs([circ_diff(m_bed,d_bed_loc), circ_diff(m_wake,d_wake_loc)]),[],2,"omitnan");
m_pst = max(abs([circ_diff(m_bed,d_bed_pst), circ_diff(m_wake,d_wake_pst)]),[],2,"omitnan");
g_loc(~gf) = NaN;  g_pst(~gf) = NaN;  m_loc(~mf) = NaN;  m_pst(~mf) = NaN;

new.GARMIN_vs_diary_local_min   = g_loc;
new.GARMIN_vs_diary_pst_min     = g_pst;
new.GARMIN_diary_local_30min    = flag_over(g_loc,30);
new.GARMIN_diary_local_1hr      = flag_over(g_loc,60);
new.GARMIN_diary_closer         = closer(g_loc,g_pst);

new.MUSE_vs_diary_local_min     = m_loc;
new.MUSE_vs_diary_pst_min       = m_pst;
new.MUSE_diary_local_30min      = flag_over(m_loc,30);
new.MUSE_diary_local_1hr        = flag_over(m_loc,60);
new.MUSE_diary_closer           = closer(m_loc,m_pst);

fprintf("GARMIN flagged nights: diary_local closer %d, diary_pst closer %d\n", ...
    sum(new.GARMIN_diary_closer=="local"), sum(new.GARMIN_diary_closer=="pst"));
fprintf("MUSE flagged nights:   diary_local closer %d, diary_pst closer %d\n", ...
    sum(new.MUSE_diary_closer=="local"), sum(new.MUSE_diary_closer=="pst"));



new = movevars(new,"time_zone","After","SID");
% drop unneeded columns
new(:,intersect(["Blurghbo","Burst_Day_","AgebydaysSinceBurst__day_","Ethnicity", ...
    "DayofWeek_code","WeekdayWeekend_coded"],new.Properties.VariableNames)) = [];

% order: ID info -> sleep diary -> Garmin -> Muse -> flags/comparisons
v       = string(new.Properties.VariableNames);
c_diary = v(startsWith(v,"sleep_diary_"));
c_gar   = v(startsWith(v,"garmin_"));
c_muse  = v(startsWith(v,"muse_"));
c_flag  = v(startsWith(v,["GARMIN_","MUSE_"]));
front   = ["SID","time_zone"];
other   = setdiff(v,[front c_diary c_gar c_muse c_flag],"stable");
new = new(:,[front other c_diary c_gar c_muse c_flag]);
muse   = new(new.MUSE_mismatch_30min==1   | new.MUSE_mismatch_1hr==1,:);
garmin = new(new.GARMIN_mismatch_30min==1 | new.GARMIN_mismatch_1hr==1,:);
cmp = new;
end

function d = to_local(unix_s, zone)
% unix seconds -> wall clock in ZONE, returned without a time zone
d = datetime(unix_s,"ConvertFrom","posixtime","TimeZone",zone);
d.TimeZone = "";
end

function m = clock_min(s)
% "HH:mm:ss" (or "HH:mm") text -> minutes after midnight; NaN if empty/missing
s = strtrim(string(s));
m = nan(size(s));
ok = find(~ismissing(s) & strlength(s) >= 5);
for k = ok(:)'
    v = sscanf(char(s(k)),'%d:%d:%d');
    if numel(v) == 2, v(3) = 0; end
    if numel(v) == 3, m(k) = v(1)*60 + v(2) + v(3)/60; end
end
end

function s = pad_iso(s)
% make short/missing isoDate strings safe for extractBetween(…,12,19)
s = string(s);
s(ismissing(s) | strlength(s) < 19) = "                   ";
end


function f = flag_over(x, lim)
% 1 if |x| > lim, 0 if not, NaN if x is NaN
f = double(x > lim);  f(isnan(x)) = NaN;
end

function c = closer(loc, pst)
% which diary column is closer to the converted device time: "local", "pst", "tie" or ""
c = strings(size(loc));
ok = ~isnan(loc) & ~isnan(pst);
c(ok & loc < pst) = "local";
c(ok & pst < loc) = "pst";
c(ok & pst == loc) = "tie";
end

function d = circ_diff(a, b)
% a - b in minutes, wrapped to [-720, 720)
d = mod(a - b + 720, 1440) - 720;
end

function y = select_studysheet(file_path)
ss_path = append(file_path,"\StudySheet");
file_names = string({dir(ss_path).name});
ss = file_names(contains(file_names,["Sheet","Study"]));
ss(~contains(ss,[".csv",".xlsx"])) = [];
ss(contains(ss,["~","blurgh"])) = [];
if isscalar(ss)
    ind = 1;
    y = readtable(append(ss_path,"\",ss(ind)));
else
    num_pat = extract(ss,digitsPattern);
    ds = datetime(append(num_pat(:,:,2),"-",num_pat(:,:,3),"-",num_pat(:,:,4)),"inputformat","MM-dd-uuuu");
    ind = find(ds == max(ds));
    y = readtable(append(ss_path,"\",ss(ind)));
    ss(ind) = [];
    for i = 1:length(ss)
        movefile(append(ss_path,"\",ss(i)),append(ss_path,"\","ARCHIVE"));
    end
end
y(isnat(y.Date),:) = [];
end

function [y,z] = expand_study(T_study)
copy = T_study;
SID = unique(copy.SID);
new_study = vertcat(copy,copy);
new_study = sortrows(new_study,"Date","ascend");
new_study = sortrows(new_study,"SID","ascend");
new_study{:,"AMPM"} = "AM";
T = new_study;
swc = unique(T.Sleep_Wake_condition);
swc(isnan(swc)) = [];
for i = 1:length(SID)
    for j = 1:length(swc)
        t = T(and(T.SID == SID(i),T.Sleep_Wake_condition == swc(j)),:);
        if swc(j) == 1
            t{1,"AMPM"} = "PM";
            t{end,"Date"} = t{end,"Date"} + days(1);
            t{end,"Burst_Day_"} = t{end,"Burst_Day_"} + days(1);
        else
            t{end,"AMPM"} = "PM";
        end
        T(and(T.SID == SID(i),T.Sleep_Wake_condition == swc(j)),:) = t;
    end
end
copy = T;
[a,b] = weekday(copy.Date,'long');
copy.DayofWeek_code = a;
copy.DayofWeek = b;
copy{or(copy.DayofWeek_code == 1,copy.DayofWeek_code == 7),"WeekdayWeekend_coded"} = 1;
copy{copy.WeekdayWeekend_coded == 1,"WeekdayWeekend"} = {'Weekend'};
copy{copy.WeekdayWeekend_coded == 0,"WeekdayWeekend"} = {'Weekday'};
copy.AgebydaysSinceBurst__day_ = days(copy.Date - copy.Blurghbo);
copy(isnat(copy.Date),:) = [];
y = copy;
T = y;
SID = unique(new_study.SID);
expand = table;
for i = 1:length(SID)
    sid_t = table;
    t = T(T.SID == SID(i),:);
    sc = t(t.Sleep_Wake_condition == 1,:);
    wc = t(t.Sleep_Wake_condition == 0,:);
    sc_d = [min(sc.Date) - days(1); sc.Date];
    wc_d = [min(wc.Date) - days(1); unique(wc.Date)];
    new_dates = repelem(sort([sc_d;wc_d],'ascend'),2);
    h = length(new_dates);
    sid_t.SID = repelem(SID(i),h,1);
    sid_t.Date = new_dates;
    sid_t.Sex = repelem(unique(t.Sex),h,1);
    sid_t.Age = zeros(h,1);
    if sum(~isnat(unique(t.Blurghbo))) ~= 0
        sid_t.Blurghbo = repelem(datetime(unique(t.Blurghbo),'Format','dd-MMM-y'),h,1);
    else
        sid_t.Blurghbo = NaT(h,1);
    end
    sid_t.Burst_Day_ = sid_t.Date;
    sid_t.AgebydaysSinceBurst__day_ = nan(h,1);
    sid_t.Ethnicity = repelem(unique(t.Ethnicity),h,1);
    sid_t.AMPM = repmat(["AM";"PM"],h/2,1);
    sid_t{ismember(sid_t.Date,sc_d),"Sleep_Wake_condition"} = 1;
    expand = vertcat(expand,sid_t);
end
ampm = expand.AMPM;
expand(:,"AMPM") = [];
expand.Age = floor(years(expand.Date-expand.Blurghbo));
expand.AgebydaysSinceBurst__day_ = days(expand.Date-expand.Blurghbo);
[a,b] = weekday(expand.Date,'long');
expand.DayofWeek_code = a;
expand.WeekdayWeekend_coded = zeros(height(expand),1);
expand{or(expand.DayofWeek_code == 1, expand.DayofWeek_code == 7),"WeekdayWeekend_coded"} = 1;
expand.DayofWeek = b;
expand{expand.WeekdayWeekend_coded == 1,"WeekdayWeekend"} = {'Weekend'};
expand{expand.WeekdayWeekend_coded == 0,"WeekdayWeekend"} = {'Weekday'};
expand.Blurghbo = datetime(expand.Blurghbo,"Format","dd-MMM-yyyy");
expand.AMPM = ampm;
z = expand;
end

function out = import_sleep_summary(filename)
% Import Labfront garmin-connect-sleep-summary CSV (header = 7 lines, data from line 8)
opts = detectImportOptions(filename,"NumHeaderLines",6,"Delimiter",",");
opts.VariableNamesLine = 7;
opts.DataLines = [8 Inf];
opts = setvartype(opts,["timezoneOffsetInMs","unixTimestampInMs","durationInMs", ...
    "awakeDurationInMs","overallSleepScore"],"double");
opts = setvartype(opts,"calendarDate","datetime");
opts = setvaropts(opts,"calendarDate","InputFormat","uuuu-MM-dd");
opts = setvartype(opts,"isoDate","string");
out = readtable(filename,opts);
out = out(:,["calendarDate","timezoneOffsetInMs","unixTimestampInMs","isoDate", ...
    "durationInMs","awakeDurationInMs","overallSleepScore"]);
end

function out = importfile(filename, dataLines)
% Import Labfront garmin-connect-sleep-stage CSV
if nargin < 2
    dataLines = [8, Inf];
end
opts = delimitedTextImportOptions("NumVariables", 6);
opts.DataLines = dataLines;
opts.Delimiter = ",";
opts.VariableNames = ["sleepSummaryId", "timezoneOffsetInMs", "unixTimestampInMs", "isoDate", "durationInMs", "type"];
opts.VariableTypes = ["categorical", "double", "double", "string", "double", "categorical"];
opts.ExtraColumnsRule = "ignore";
opts.EmptyLineRule = "read";
opts = setvaropts(opts, "isoDate", "WhitespaceRule", "preserve");
opts = setvaropts(opts, ["sleepSummaryId", "isoDate", "type"], "EmptyFieldRule", "auto");
out = readtable(filename, opts);
end