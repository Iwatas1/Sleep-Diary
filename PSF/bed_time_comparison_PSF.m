function [cmp,muse,garmin] = bed_time_comparison_PSF(SD,file_path)
% BED_TIME_COMPARISON_PSF  Sleep diary vs Garmin (sleep summary) vs Muse (largest ss file, W epochs removed)
%   PSF version of bed_time_comparison_T1D. Nights keyed on SID + StudyWeek + Date
%   (Date = morning the participant woke up). Muse nights are matched by DATE
%   (local wake-up date of the recording), not by N# position.
%   SD        : morning diary table from EMA_to_sleep_diary_morning (PSF), with
%               first_sleep_pst / get_out_of_bed_pst (PST) and *_local, time_zone
%   file_path : ...\PSF\PSF DATA
%   cmp       : all nights;  muse / garmin : nights flagged >30 min for that device
%   Output is NOT deidentified (full dates + unix timestamps; stays on CRSP).
%
%   Paths:  Garmin  <file_path>\Labfront Data\<SID>\SW#\<SID>_<hash>\garmin-connect-sleep-summary\*.csv
%           Muse    <PSF>\Muse\SID\<SID>\SW#\N#\*_ss*.csv
%   Older Muse ss files have no "timestamps" column: their unix time is rebuilt from
%   the file name (yyyy-MM-ddTHH_mm_ss±HH_mm) + "times". Those nights get
%   muse_has_unix = false and are left out of the MUSE device check (it would always pass).

file_path = char(file_path);
lab_root  = fullfile(file_path,'Labfront Data');
muse_root = fullfile(fileparts(file_path),'Muse','SID');

SD = SD(~isnan(SD.SID) & ~isnat(SD.Date),:);
SD = sortrows(SD,["SID","StudyWeek","Date"]);
tz_codes = ["PST","MST","CST","EST"];
tz_names = ["America/Los_Angeles","America/Denver","America/Chicago","America/New_York"];

final = table;
SID = unique(SD.SID);
for i = 1:numel(SID)
    s = char(string(SID(i)));
    SW = unique(SD.StudyWeek(SD.SID == SID(i)));
    for w = SW(:)'
        sw_name = ['SW' char(string(w))];
        T = SD(SD.SID == SID(i) & SD.StudyWeek == w,:);
        D = dateshift(T.Date,"start","day");
        h = height(T);
        zc = upper(strtrim(string(T.time_zone(1))));
        zone = "America/Los_Angeles";
        if any(tz_codes == zc), zone = tz_names(tz_codes == zc); end

        T.garmin_sleep_unix_ms = nan(h,1);   % Garmin: milliseconds since 1970 UTC
        T.garmin_wake_unix_ms  = nan(h,1);
        T.garmin_sleep_isoDate = strings(h,1);   % e.g. 2025-07-09T22:00:00.000-07:00
        T.muse_start_unix_s    = nan(h,1);   % Muse: seconds since 1970 UTC
        T.muse_end_unix_s      = nan(h,1);
        T.muse_start_time      = strings(h,1);   % raw text from ss "times" column
        T.muse_end_time        = strings(h,1);
        T.muse_has_unix        = false(h,1);
        T.muse_file            = strings(h,1);

        % ---- Garmin (sleep summary) ----
        sub = dir(fullfile(lab_root,s,sw_name,[s '_*']));
        sub = sub([sub.isdir]);
        lab_t = table;
        for d = 1:numel(sub)
            path_g = fullfile(sub(d).folder,sub(d).name,'garmin-connect-sleep-summary');
            files = dir(fullfile(path_g,'*.csv'));
            files = files(contains({files.name},s));
            for f = 1:numel(files)
                lab_t = [lab_t; import_sleep_summary(fullfile(path_g,files(f).name))]; %#ok<AGROW>
            end
        end
        if isempty(sub)
            fprintf("[GARMIN] SID %s %s: no Labfront folder\n", s, sw_name);
        elseif isempty(lab_t)
            fprintf("[GARMIN] SID %s %s: no sleep-summary csv\n", s, sw_name);
        else
            lab_t = lab_t(~isnan(lab_t.unixTimestampInMs) & ~isnat(lab_t.calendarDate),:);
            lab_t = sortrows(lab_t,"unixTimestampInMs");
            [~,keep] = unique(lab_t.calendarDate,"last");      % one summary per night: last row
            lab_t = lab_t(keep,:);
            wake_ms = lab_t.unixTimestampInMs + lab_t.durationInMs + fillmissing(lab_t.awakeDurationInMs,"constant",0);
            for j = 1:height(lab_t)
                r = D == lab_t.calendarDate(j);                  % calendarDate = wake-up morning
                if ~any(r), continue; end
                T{r,"garmin_sleep_unix_ms"} = lab_t.unixTimestampInMs(j);
                T{r,"garmin_wake_unix_ms"}  = wake_ms(j);
                T{r,"garmin_sleep_isoDate"} = lab_t.isoDate(j);
            end
        end

        % ---- Muse (all stages kept, incl. W; largest ss file per night) ----
        sw_path = fullfile(muse_root,s,sw_name);
        if ~isfolder(sw_path), fprintf("[MUSE] folder missing: %s\n", sw_path); end
        nights = dir(fullfile(sw_path,'N*'));
        nights = nights([nights.isdir]);
        for j = 1:numel(nights)
            n_path = fullfile(sw_path,nights(j).name);
            ss_d = dir(fullfile(n_path,'*_ss*.csv'));
            if isempty(ss_d), fprintf("[MUSE] no _ss file: %s\n", n_path); continue; end
            [~,big] = max([ss_d.bytes]);
            if numel(ss_d) > 1
                fprintf("[MUSE] %d ss files in %s -> using %s\n", numel(ss_d), n_path, ss_d(big).name);
            end
            t = readtable(fullfile(n_path,ss_d(big).name));
            if height(t) == 0 || ~ismember("times",t.Properties.VariableNames)
                fprintf("[MUSE] empty or no 'times' column: %s\n", ss_d(big).name); continue
            end
            tod = t.times;
            if isdatetime(tod), tod = timeofday(tod); end
            if ismember("timestamps",t.Properties.VariableNames) && any(t.timestamps > 0)
                unix_s = t.timestamps;  has_unix = true;
                unix_s(unix_s <= 0) = NaN;
            else
                % rebuild unix seconds from file-name start + elapsed clock time
                % (uses ALL rows so elapsed time starts at the first epoch, before W is removed)
                tok = regexp(ss_d(big).name,'^(\d{4}-\d{2}-\d{2})T(\d{2})_(\d{2})_(\d{2})([+-]\d{2})_(\d{2})','tokens','once');
                if isempty(tok), fprintf("[MUSE] no timestamps and bad file name: %s\n", ss_d(big).name); continue; end
                t0 = datetime(sprintf('%s %s:%s:%s %s:%s',tok{:}),'InputFormat','yyyy-MM-dd HH:mm:ss xxx','TimeZone','UTC');
                sec = tod_sec(tod);
                el  = sec - sec(1);
                el  = el + 86400*cumsum([0; diff(sec) < 0]);   % wrap past midnight
                unix_s = posixtime(t0) + el;  has_unix = false;
            end
            % bed/wake = first/last epoch that is NOT wake (W)
            keep = string(t.sleep_stage) ~= "W" & ~isnan(unix_s);
            if ~any(keep), fprintf("[MUSE] no sleep epochs (all W): %s\n", ss_d(big).name); continue; end
            unix_s = unix_s(keep);  tod = tod(keep);
            [~,i_s] = min(unix_s);
            [~,i_e] = max(unix_s);
            % night = local wake-up date of the recording
            wake_day = dateshift(to_local(unix_s(i_e),zone),"start","day");
            r = D == wake_day;
            if ~any(r)
                fprintf("[MUSE] SID %s %s %s: wake date %s not in diary dates\n", s, sw_name, nights(j).name, string(wake_day,"yyyy-MM-dd"));
                continue
            end
            T{r,"muse_start_unix_s"} = unix_s(i_s);
            T{r,"muse_end_unix_s"}   = unix_s(i_e);
            T{r,"muse_start_time"}   = tod_str(tod(i_s));
            T{r,"muse_end_time"}     = tod_str(tod(i_e));
            T{r,"muse_has_unix"}     = has_unix;
            T{r,"muse_file"}         = string(ss_d(big).name);
        end
        final = [final; T]; %#ok<AGROW>
    end
end

% Sleep diary: *_pst = Pacific, *_local = participant's clock
final.sleep_diary_sleep_pst   = final.first_sleep_pst;
final.sleep_diary_sleep_local = final.first_sleep_local;
final.sleep_diary_wake_pst    = final.get_out_of_bed_pst;
final.sleep_diary_wake_local  = final.get_out_of_bed_local;

columns = ["SID","time_zone","StudyWeek","Day","Date","DayofWeek","WeekdayWeekend","sleep_duration","sleep_duration_in_mins", ...
    "sleep_diary_sleep_pst","sleep_diary_sleep_local","sleep_diary_wake_pst","sleep_diary_wake_local", ...
    "garmin_sleep_unix_ms","garmin_wake_unix_ms","garmin_sleep_isoDate", ...
    "muse_start_unix_s","muse_end_unix_s","muse_start_time","muse_end_time","muse_has_unix","muse_file"];
columns = columns(ismember(columns,final.Properties.VariableNames));
new = final(:,columns);

%% ---- Convert raw unix timestamps to each subject's time zone and compare ----
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
    if ~isnan(new.garmin_sleep_unix_ms(r)), new.garmin_sleep_converted(r) = to_local(new.garmin_sleep_unix_ms(r)/1000, z); end
    if ~isnan(new.garmin_wake_unix_ms(r)),  new.garmin_wake_converted(r)  = to_local(new.garmin_wake_unix_ms(r)/1000, z);  end
    if ~isnan(new.muse_start_unix_s(r)),    new.muse_start_converted(r)   = to_local(new.muse_start_unix_s(r), z);         end
    if ~isnan(new.muse_end_unix_s(r)),      new.muse_end_converted(r)     = to_local(new.muse_end_unix_s(r), z);           end
end
fmt = "uuuu-MM-dd HH:mm:ss";
new.garmin_sleep_converted.Format = fmt;  new.garmin_wake_converted.Format = fmt;
new.muse_start_converted.Format   = fmt;  new.muse_end_converted.Format   = fmt;

% clock-time difference in minutes (wraps around midnight; Muse "times" has no date)
garmin_dev = clock_min(extractBetween(pad_iso(new.garmin_sleep_isoDate),12,19));
muse_s_dev = clock_min(new.muse_start_time);
muse_e_dev = clock_min(new.muse_end_time);
new.GARMIN_diff_min     = circ_diff(clock_min(string(new.garmin_sleep_converted,"HH:mm:ss")), garmin_dev);
new.MUSE_start_diff_min = circ_diff(clock_min(string(new.muse_start_converted,"HH:mm:ss")), muse_s_dev);
new.MUSE_end_diff_min   = circ_diff(clock_min(string(new.muse_end_converted,"HH:mm:ss")),   muse_e_dev);
% file-name-based Muse nights: unix was built from "times", so the check is not real
new.MUSE_start_diff_min(~new.muse_has_unix) = NaN;
new.MUSE_end_diff_min(~new.muse_has_unix)   = NaN;

g = abs(new.GARMIN_diff_min);
m = max(abs([new.MUSE_start_diff_min, new.MUSE_end_diff_min]), [], 2, "omitnan");
new.GARMIN_mismatch_30min = flag_over(g,30);
new.GARMIN_mismatch_1hr   = flag_over(g,60);
new.MUSE_mismatch_30min   = flag_over(m,30);
new.MUSE_mismatch_1hr     = flag_over(m,60);
fprintf("GARMIN: %d/%d nights >30 min, %d >1 h\n", sum(new.GARMIN_mismatch_30min==1), sum(~isnan(g)), sum(new.GARMIN_mismatch_1hr==1));
fprintf("MUSE:   %d/%d nights >30 min, %d >1 h (unix files only)\n", sum(new.MUSE_mismatch_30min==1), sum(~isnan(m)), sum(new.MUSE_mismatch_1hr==1));

%% ---- For 1-hr flagged nights: compare converted unix time with sleep diary ----
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
g_loc = max(abs([circ_diff(g_bed,d_bed_loc), circ_diff(g_wake,d_wake_loc)]),[],2,"omitnan");
g_pst = max(abs([circ_diff(g_bed,d_bed_pst), circ_diff(g_wake,d_wake_pst)]),[],2,"omitnan");
m_loc = max(abs([circ_diff(m_bed,d_bed_loc), circ_diff(m_wake,d_wake_loc)]),[],2,"omitnan");
m_pst = max(abs([circ_diff(m_bed,d_bed_pst), circ_diff(m_wake,d_wake_pst)]),[],2,"omitnan");
% every night with device data (used for the RA check; calc_clock still uses the 1-hr rule)
new.GARMIN_vs_diary_local_all_min = g_loc;
new.GARMIN_vs_diary_pst_all_min   = g_pst;
new.GARMIN_diary_closer_all       = closer(g_loc,g_pst);
new.MUSE_vs_diary_local_all_min   = m_loc;
new.MUSE_vs_diary_pst_all_min     = m_pst;
new.MUSE_diary_closer_all         = closer(m_loc,m_pst);
g_loc(~gf) = NaN;  g_pst(~gf) = NaN;  m_loc(~mf) = NaN;  m_pst(~mf) = NaN;

new.GARMIN_vs_diary_local_min = g_loc;
new.GARMIN_vs_diary_pst_min   = g_pst;
new.GARMIN_diary_local_30min  = flag_over(g_loc,30);
new.GARMIN_diary_local_1hr    = flag_over(g_loc,60);
new.GARMIN_diary_closer       = closer(g_loc,g_pst);
new.MUSE_vs_diary_local_min   = m_loc;
new.MUSE_vs_diary_pst_min     = m_pst;
new.MUSE_diary_local_30min    = flag_over(m_loc,30);
new.MUSE_diary_local_1hr      = flag_over(m_loc,60);
new.MUSE_diary_closer         = closer(m_loc,m_pst);
fprintf("GARMIN flagged nights: diary_local closer %d, diary_pst closer %d\n", sum(new.GARMIN_diary_closer=="local"), sum(new.GARMIN_diary_closer=="pst"));
fprintf("MUSE flagged nights:   diary_local closer %d, diary_pst closer %d\n", sum(new.MUSE_diary_closer=="local"), sum(new.MUSE_diary_closer=="pst"));

% order: ID info -> sleep diary -> Garmin -> Muse -> flags/comparisons
v       = string(new.Properties.VariableNames);
c_diary = v(startsWith(v,"sleep_diary_"));
c_gar   = v(startsWith(v,"garmin_"));
c_muse  = v(startsWith(v,"muse_"));
c_flag  = v(startsWith(v,["GARMIN_","MUSE_"]));
front   = ["SID","time_zone","StudyWeek"];
front   = front(ismember(front,v));
other   = setdiff(v,[front c_diary c_gar c_muse c_flag],"stable");
new = new(:,[front other c_diary c_gar c_muse c_flag]);
muse   = new(new.MUSE_mismatch_30min==1   | new.MUSE_mismatch_1hr==1,:);
garmin = new(new.GARMIN_mismatch_30min==1 | new.GARMIN_mismatch_1hr==1,:);
cmp = new;
end

%% ===================== Local functions =====================
function d = to_local(unix_s, zone)
% unix seconds -> wall clock in ZONE, returned without a time zone
d = datetime(unix_s,"ConvertFrom","posixtime","TimeZone",zone);
d.TimeZone = "";
end

function s = tod_sec(tod)
% "times" column (duration / text) -> seconds after midnight
if isduration(tod), s = seconds(tod); else, s = clock_min(string(tod))*60; end
end

function s = tod_str(x)
% one "times" value -> "HH:mm:ss" text
if isduration(x), x.Format = "hh:mm:ss"; end
s = string(x);
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

function out = import_sleep_summary(filename)
% Import Labfront garmin-connect-sleep-summary CSV (header = 7 lines, data from line 8)
opts = detectImportOptions(filename,"NumHeaderLines",6,"Delimiter",",");
opts.VariableNamesLine = 7;
opts.DataLines = [8 Inf];
opts = setvartype(opts,["timezoneOffsetInMs","unixTimestampInMs","durationInMs","awakeDurationInMs"],"double");
opts = setvartype(opts,"calendarDate","datetime");
opts = setvaropts(opts,"calendarDate","InputFormat","uuuu-MM-dd");
opts = setvartype(opts,"isoDate","string");
out = readtable(filename,opts);
out = out(:,["calendarDate","timezoneOffsetInMs","unixTimestampInMs","isoDate","durationInMs","awakeDurationInMs"]);
end
