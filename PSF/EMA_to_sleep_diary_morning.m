function [new,modify_t] = EMA_to_sleep_diary_morning(EMA_morning,forget_morning,T_study,file_path)
col_names = string(forget_morning.Properties.VariableNames);
for i = 1:height(forget_morning)
    for j = 1:length(col_names)
        if j == 1
            EMA_morning{end+1,col_names(j)} = forget_morning{i,col_names(j)};
        else
            EMA_morning{end,col_names(j)} = forget_morning{i,col_names(j)};
        end
    end
end
EMA_morning.get_out_of_bed_pst = datetime(EMA_morning.get_out_of_bed / 1000, "convertfrom","posixtime","Format","dd-MMM-uuuu HH:mm","TimeZone","local");
EMA_morning.first_sleep_pst = datetime(EMA_morning.first_sleep / 1000, "convertfrom","posixtime","Format","dd-MMM-uuuu HH:mm","TimeZone","local");
EMA_morning.minutes_up_night(isnan(EMA_morning.minutes_up_night)) = 0;
modify_t = table;
EMA_morning.date = datetime(EMA_morning.started_at/1000,"convertfrom","posixtime","Format","dd-MMM-yyyy","Timezone","local");
EMA_morning.get_out_of_bed_pst = datetime(string(EMA_morning.date)+ " " + extractAfter(string(EMA_morning.get_out_of_bed_pst)," "));
EMA_morning.first_sleep_pst = datetime(string(EMA_morning.date - day(1))+ " " + extractAfter(string(EMA_morning.first_sleep_pst)," "));
EMA_morning.sleep_duration = EMA_morning.get_out_of_bed_pst - EMA_morning.first_sleep_pst - minutes(EMA_morning.fall_asleep_minutes) - minutes(EMA_morning.minutes_up_night);
EMA_morning.user = double(EMA_morning.user);
EMA_morning = renamevars(EMA_morning,"user","SID");
copy = EMA_morning;
SID = unique(T_study.SID);
cols = string(copy.Properties.VariableNames(2:end));
T = T_study;
sleep_diary_long = table;
bad = table;
for i = 1:length(SID)
    tt = T(T.SID == SID(i),:);
    sw = unique(tt.StudyWeek);
    for ii = 1:length(sw)
        t = tt(tt.StudyWeek == sw(ii),:);
        t_1 = table;
        sd = copy(and(copy.SID == SID(i),ismember(string(copy.date),string(t.Date))),:);
        sd = sortrows(sd,"started_at","ascend");
        try
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols);
            t_1 = t;
        catch
            unique_dates = unique(string(sd.date));
            for j = 1:length(unique_dates)
                if height(sd(string(sd.date) == unique_dates(j),:)) > 1
                    rep_t = sd(string(sd.date) == unique_dates(j),:);
                    delete_ind = [];
                    for k = 1:height(rep_t)
                        if isempty(rep_t.where_EMA_morning{k})
                            timestamp = rep_t.started_at(k);
                            delete_ind(end+1) = k;
                            sd(sd.started_at == timestamp,:) = [];
                        end 
                    end
                    rep_t(delete_ind,:) = [];
                    while height(rep_t) > 1
                        timestamp = rep_t.started_at;
                        timestamp(timestamp == max(timestamp)) = [];
                        rep_t(ismember(rep_t.started_at,timestamp),:) = [];
                        sd(ismember(sd.started_at,timestamp),:) = [];
                        if isscalar(unique(rep_t.started_at))
                            rep_t = rep_t(1,:);
                            sd(sd.started_at == unique(rep_t.started_at),:) = [];
                            sd(end+1,:) = rep_t;
                        end
    
    
                    end
    
                end
            end
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols);
            t_1 = t;
            sd = sortrows(sd,"started_at","ascend");
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols);
        end
        sleep_diary_long = [sleep_diary_long ; t];
        bad = [bad;t_1];
    end

end

missing_t = sleep_diary_long(isnat(sleep_diary_long.date),:);
for i = width(T_study)+1:width(missing_t)
    d_type = class(missing_t{1,i});
    if d_type == "double" || d_type == "duration"
        missing_t{:,i} = nan(height(missing_t),1);
    end
end
sleep_diary_long(isnat(sleep_diary_long.date),:) = missing_t;
sleep_diary_long(:,"date") = [];
sleep_diary_long.sleep_duration_in_mins = minutes(sleep_diary_long.sleep_duration);
copy = sleep_diary_long;

% ---- convert bed/wake to the participant's local time BEFORE the fixes ------
% (clock-hour rules below then work on their own clock; see add_local_time_PSF)
copy = add_local_time_PSF(copy,file_path);
modify_t = table;
[copy,modify_t] = fix_sleep_inputs(copy,modify_t,T_study,"");
early_bed = and(hour(copy.first_sleep_pst) <= 19, hour(copy.first_sleep_pst) > 4);
late_wake = or(hour(copy.get_out_of_bed_pst) > 10,hour(copy.get_out_of_bed_pst) < 4);
E = copy(or(and(early_bed,late_wake),copy.sleep_duration_in_mins > 720),:);
new_wake = E.first_sleep_pst + days(1);
new_bed = E.get_out_of_bed_pst - days(1);
E.get_out_of_bed_pst = new_wake;
E.first_sleep_pst = new_bed;
E.sleep_duration = new_wake - new_bed - minutes(E.fall_asleep_minutes) - minutes(E.minutes_up_night);
E.sleep_duration_in_mins = minutes(E.sleep_duration);
[E,modify_t] = fix_sleep_inputs(E,modify_t,T_study,"switched the wake and bed time then ");
copy(or(and(early_bed,late_wake),copy.sleep_duration_in_mins > 720),:) = E;
t = copy(copy.sleep_duration_in_mins > 60*24,:);
new_bed = t.get_out_of_bed_pst - hours(36);
new_wake = t.first_sleep_pst + hours(12);
t.first_sleep_pst = new_bed;
t.get_out_of_bed_pst = new_wake;
t.sleep_duration = new_wake - new_bed -minutes(t.fall_asleep_minutes) - minutes(t.minutes_up_night);
t.sleep_duration_in_mins = minutes(t.sleep_duration);
copy(copy.sleep_duration_in_mins > 60*24,:) = t;

% ---- back to Pacific (PST) before the RA fix --------------------------------
% RA workbook times are Pacific, so the RA fix and 12 h rule run on PST
known = ~isnan(copy.offset_h);
copy.first_sleep_pst(known)    = copy.first_sleep_pst(known)    - hours(copy.offset_h(known));
copy.get_out_of_bed_pst(known) = copy.get_out_of_bed_pst(known) - hours(copy.offset_h(known));

% ---- RA manual check (SleepDiaryDataCheck folder) -------------------------
% Overwrite bed/wake times with the RA-revised values (only rows the RA
% changed) and recalculate sleep duration. Log: Sleep_diary\Sleep_diary_morning_RA_fix_log.xlsx
[copy,ra_log] = apply_RA_fix(copy,file_path);

% 12 h rule (carried over from just_sleep_diary.mlx): if sleep duration is
% still >= 12 h after the RA fix, push bed time forward by 1 day.
long_sleep = copy.sleep_duration_in_mins >= 12*60;
if any(long_sleep)
    B = copy(long_sleep,1:width(T_study));
    B.modification_details = repelem("after RA fix: sleep duration >= 12 hrs, added 1 day on bed time",height(B),1);
    modify_t = [modify_t ; B];
    copy.first_sleep_pst(long_sleep) = copy.first_sleep_pst(long_sleep) + days(1);
    copy.sleep_duration(long_sleep) = copy.get_out_of_bed_pst(long_sleep) - copy.first_sleep_pst(long_sleep) ...
        - minutes(copy.fall_asleep_minutes(long_sleep)) - minutes(copy.minutes_up_night(long_sleep));
    copy.sleep_duration_in_mins(long_sleep) = minutes(copy.sleep_duration(long_sleep));
end
if any(copy.sleep_duration_in_mins < 0)
    warning('EMA_to_sleep_diary_morning: %d row(s) have negative sleep duration after all fixes. See modification details.', ...
        sum(copy.sleep_duration_in_mins < 0));
end
% ---- local clock columns (PST + offset) -------------------------------------
known = ~isnan(copy.offset_h);
copy.first_sleep_local    = NaT(height(copy),1);
copy.get_out_of_bed_local = NaT(height(copy),1);
copy.first_sleep_local(known)    = copy.first_sleep_pst(known)    + hours(copy.offset_h(known));
copy.get_out_of_bed_local(known) = copy.get_out_of_bed_pst(known) + hours(copy.offset_h(known));

% ---- device comparison (Garmin / Muse) before the averages -------------------
% decides, per night, which diary clock the midpoint/averages use
[cmp,muse_off,garmin_off] = bed_time_comparison_PSF(copy,file_path);
g_c = string(cmp.GARMIN_diary_closer);  m_c = string(cmp.MUSE_diary_closer);
has_any = g_c ~= "" | m_c ~= "";
all_pst = has_any & (g_c == "pst" | g_c == "") & (m_c == "pst" | m_c == "");
keys = ["SID","StudyWeek","Date"];
copy.calc_clock = repmat("local",height(copy),1);
copy.calc_clock(ismember(copy(:,keys),cmp(all_pst,keys))) = "pst";
% bed/wake used for midpoint and averages: local, or PST where all devices say pst
copy.bed_calc  = copy.first_sleep_local;   copy.wake_calc = copy.get_out_of_bed_local;
use_pst = copy.calc_clock == "pst" | ~known;
copy.bed_calc(use_pst)  = copy.first_sleep_pst(use_pst);
copy.wake_calc(use_pst) = copy.get_out_of_bed_pst(use_pst);
fprintf('Sleep diary: %d night(s) use PST for midpoint/averages\n', sum(copy.calc_clock == "pst"));

% ---- RA time zone check (flag only, nothing is changed) ----------------------
% RA values are treated as PST. On a non-PST SID, if a device whose own clock is fine
% (mismatch_1hr == 0) is closer to diary PST than diary local, the RA most likely
% typed the participant's LOCAL time -> RA_entered_local = 1
cmp = outerjoin(cmp,copy(:,[keys "calc_clock"]),"Keys",keys,"MergeKeys",true,"Type","left");
cmp.RA_changed = strings(height(cmp),1);
cmp.RA_status  = strings(height(cmp),1);
if ~isempty(ra_log)
    [hit,loc] = ismember(cmp(:,["SID","StudyWeek","Day"]),ra_log(:,["SID","StudyWeek","Day"]));
    cmp.RA_changed(hit) = ra_log.changed(loc(hit));
    cmp.RA_status(hit)  = ra_log.status(loc(hit));
end
non_pst = upper(strtrim(string(cmp.time_zone))) ~= "PST";
g_says_pst = cmp.GARMIN_diary_closer_all == "pst" & cmp.GARMIN_mismatch_1hr == 0;
m_says_pst = cmp.MUSE_diary_closer_all   == "pst" & cmp.MUSE_mismatch_1hr   == 0;
g_says_loc = cmp.GARMIN_diary_closer_all == "local" & cmp.GARMIN_mismatch_1hr == 0;
m_says_loc = cmp.MUSE_diary_closer_all   == "local" & cmp.MUSE_mismatch_1hr   == 0;
ra_row = cmp.RA_changed ~= "";
cmp.RA_entered_local = nan(height(cmp),1);
cmp.RA_entered_local(ra_row & non_pst & (g_says_loc | m_says_loc)) = 0;
cmp.RA_entered_local(ra_row & non_pst & (g_says_pst | m_says_pst)) = 1;
ra_tz = cmp(ra_row & non_pst,:);
fprintf('RA check (non-PST SIDs): %d RA-revised night(s); %d look LOCAL (missed the time zone), %d look PST, %d no usable device\n', ...
    height(ra_tz), sum(ra_tz.RA_entered_local == 1), sum(ra_tz.RA_entered_local == 0), sum(isnan(ra_tz.RA_entered_local)));

% Files kept on CRSP may have dates; set DEID = true only for copies sent outside the lab
DEID = false;
if DEID, deid = @deidentify_output; else, deid = @(x) x; end
writetable(deid(modify_t),append(file_path,'\Sleep_diary\Sleep_diary_morning_modification_details.xlsx'),'WriteMode','replacefile')
copy.date = datetime(copy.started_at/1000,"convertfrom","posixtime","Format","dd-MMM-yyyy","Timezone","local");
copy.minutes_away_from_midnight_to_sleep_time = minutes(copy.bed_calc - datetime(string(copy.date)+ " " + string(timeofday(datetime("00:00:00","inputformat","HH:mm:ss")))));
new = table;
for j = 1:length(SID)
    t = copy(copy.SID == SID(j),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        tt = t(t.StudyWeek == sw(j),:);
        ttt = tt;
        ttt(isnan(ttt.sleep_duration),:) = [];
        bed_time = timeofday(ttt.bed_calc);                             % local (or PST where flagged)
        bed_time(hours(bed_time)<18) = bed_time(hours(bed_time)<18) + hours(24);
        tt{~isnan(tt.sleep_duration),"ave_bedtime_local"} = mean(bed_time);
        tt{hours(tt.ave_bedtime_local)>24,"ave_bedtime_local"} = tt{hours(tt.ave_bedtime_local)>24,"ave_bedtime_local"} - hours(24);
        tt{~isnan(tt.sleep_duration),"ave_waketime_local"} = mean(timeofday(ttt.wake_calc));
        tt{~isnan(tt.sleep_duration),"ave_sleep_duration_in_mins"} = mean(ttt.sleep_duration_in_mins);
        tt{~isnan(tt.sleep_duration),"std_sleep_duration_in_mins"} = std(ttt.sleep_duration_in_mins);
        tt{~isnan(tt.sleep_duration),"z_score_sleep_duration_in_mins"} = round((ttt.sleep_duration_in_mins - mean(ttt.sleep_duration_in_mins))/std(ttt.sleep_duration_in_mins),2);
        tt{~isnan(tt.sleep_duration), "ave_sleep_duration"} = mean(ttt.sleep_duration);
        tt{isnan(tt.sleep_duration),"ave_bedtime_local"} = nan;
        tt{isnan(tt.sleep_duration),"ave_waketime_local"} = nan;
        tt{isnan(tt.sleep_duration),"ave_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration),"std_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration),"z_score_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration), "ave_sleep_duration"} = nan;
        new = [new;tt];
    end
end
new.residual_from_ave_sleep_duration = new.sleep_duration_in_mins - new.ave_sleep_duration_in_mins;
new.bed_midpoint_local = new.bed_calc + (new.wake_calc - new.bed_calc)/2;   % local (or PST where flagged)
new.minutes_away_from_midnight_to_mid_point = minutes(new.bed_midpoint_local - datetime(string(new.date)+ " " + string(timeofday(datetime("00:00:00","inputformat","HH:mm:ss")))));
new(:,["date","bed_calc","wake_calc"]) = [];
new(new.Day == 1,:) = [];
% xlsx outputs: full dates on CRSP; deidentified only if DEID = true
new_out = deid(new);
new_out(:,intersect("offset_h",string(new_out.Properties.VariableNames))) = [];
xl = append(file_path,'\Sleep_diary\Sleep_diary_morning_long.xlsx');
writetable(new_out,xl,'WriteMode','replacefile');
% ---- device comparison sheets (raw; stays on CRSP) ---------------------------
writetable(cmp,       xl,'Sheet','sleep_comparison');
writetable(muse_off,  xl,'Sheet','MUSE_off');
writetable(garmin_off,xl,'Sheet','GARMIN_off');
writetable(ra_tz,     xl,'Sheet','RA_timezone_check');
writetable(new_out,append(file_path,'\PSF master data.xlsx'),'Sheet','Sleep Diary Morning','WriteMode','overwritesheet');
% .mat keeps full datetimes (Date stays a real date)
drop_cols = intersect(["Blughbo","Blurghbo","Burst_Day_"],string(new.Properties.VariableNames));
new(:,drop_cols) = [];
save(append(file_path,'\Sleep_diary\Sleep_diary_morning_long.mat'),"new");
copy = new_out;
copy(copy.Day == 1,:) = [];
wide = table;
SID = unique(copy.SID);
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        row = table;
        tw = t(t.StudyWeek == sw(j),:);
        for k = 2:5
            td = tw(tw.Day == k,:);
            col_name = string(td.Properties.VariableNames);
            for l = 1:length(col_name)
                col_name(l) = append(col_name(l),"_",string(k));
            end
            td = renamevars(td,td.Properties.VariableNames,col_name);
            row = [row,td];
        end
        wide = [wide;row];
    end
end
writetable(wide,append(file_path,'\Sleep_diary\Sleep_diary_morning_wide.xlsx'),'WriteMode','replacefile');
end