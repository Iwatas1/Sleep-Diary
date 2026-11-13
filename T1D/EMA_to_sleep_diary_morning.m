function [new_out,modify_t] = EMA_to_sleep_diary_morning(EMA_morning,forget_morning,study_sd,file_path)
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
EMA_morning.wake_time = datetime(EMA_morning.get_out_of_bed / 1000, "convertfrom","posixtime","Format","dd-MMM-uuuu HH:mm","TimeZone","local");
EMA_morning.bed_time = datetime(EMA_morning.first_sleep / 1000, "convertfrom","posixtime","Format","dd-MMM-uuuu HH:mm","TimeZone","local");
EMA_morning.date = datetime(EMA_morning.started_at/1000,"convertfrom","posixtime","Format","dd-MMM-yyyy","Timezone","local");
EMA_morning.wake_time = datetime(string(EMA_morning.date)+ " " + extractAfter(string(EMA_morning.wake_time)," "));
EMA_morning.bed_time = datetime(string(EMA_morning.date - day(1))+ " " + extractAfter(string(EMA_morning.bed_time)," "));
EMA_morning.fall_asleep_minutes(isnan(EMA_morning.fall_asleep_minutes)) = 0;
EMA_morning.minutes_up_night(isnan(EMA_morning.minutes_up_night)) = 0;
EMA_morning.sleep_duration = EMA_morning.wake_time - EMA_morning.bed_time - minutes(EMA_morning.fall_asleep_minutes) - minutes(EMA_morning.minutes_up_night);
EMA_morning.user = double(EMA_morning.user);
EMA_morning = renamevars(EMA_morning,"user","SID");
copy = EMA_morning;
SID = unique(study_sd.SID);
cols = string(copy.Properties.VariableNames(2:end));
T = study_sd(study_sd.AMPM == "AM",:);
sleep_diary_long = table;
bad = table;
for i = 1:length(SID)
    tt = T(T.SID == SID(i),:); %StudySheet filtered by SID
    swc = unique(tt.Sleep_Wake_condition);
    for ii = 1:length(swc)
        t = tt(tt.Sleep_Wake_condition == swc(ii),:); %StudySheet filtered by SID and Sleep Wake condition 
        t_1 = table;
        sd = copy(and(copy.SID == SID(i),ismember(string(copy.date),string(t.Date))),:);%EMA_morning filtered by SID, Sleep Wake condition, and dates
        sd = sortrows(sd,"started_at","ascend");
        try
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols); %if height of filtered StudySheet and filtered EMA_morning, filtered EMA_morning is mapped to the according dates
            t_1 = t;
        catch
            %when the subject completed twice or zotcare glitch and duplicate data
            unique_dates = unique(string(sd.date));
            for j = 1:length(unique_dates) %looping for unique dates
                if height(sd(string(sd.date) == unique_dates(j),:)) > 1
                    rep_t = sd(string(sd.date) == unique_dates(j),:); %table for the day that has more than one input
                    delete_ind = [];
                    %filtering duplicated table that has no imput (all nans in the row)
                    for k = 1:height(rep_t)
                        if isempty(rep_t.where_EMA_morning{k})
                            timestamp = rep_t.started_at(k);
                            delete_ind(end+1) = k;
                            sd(sd.started_at == timestamp,:) = [];%deletes the row that has all nan in a row
                        end 
                    end
                    rep_t(delete_ind,:) = []; %if there is more than 1 row of actual inputs (non nans), it enters to while loop
                    while height(rep_t) > 1
                        timestamp = rep_t.started_at;
                        timestamp(timestamp == max(timestamp)) = []; 
                        rep_t(ismember(rep_t.started_at,timestamp),:) = []; %filters out all the rows that are not the latest
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
for i = width(study_sd)+1:width(missing_t)
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
% (clock-hour rules below then work on their own clock; see add_local_time_T1D)
[copy,~] = add_local_time_T1D(copy,file_path);
modify_t = table;
[copy,modify_t] = fix_sleep_inputs(copy,modify_t,study_sd,"");
early_bed = and(hour(copy.bed_time) <= 19, hour(copy.bed_time) > 4);
late_wake = or(hour(copy.wake_time) > 10,hour(copy.wake_time) < 4);
E = copy(or(and(early_bed,late_wake),copy.sleep_duration_in_mins > 720),:);
new_wake = E.bed_time + days(1);
new_bed = E.wake_time - days(1);
E.wake_time = new_wake;
E.bed_time = new_bed;
E.sleep_duration = new_wake - new_bed - minutes(E.fall_asleep_minutes) - minutes(E.minutes_up_night);
E.sleep_duration_in_mins = minutes(E.sleep_duration);
[E,modify_t] = fix_sleep_inputs(E,modify_t,study_sd,"switched the wake and bed time then ");
copy(or(and(early_bed,late_wake),copy.sleep_duration_in_mins > 720),:) = E;
t = copy(copy.sleep_duration_in_mins > 60*24,:);
new_bed = t.wake_time - hours(36);
new_wake = t.bed_time + hours(12);
t.bed_time = new_bed;
t.wake_time = new_wake;
t.sleep_duration = new_wake - new_bed -minutes(t.fall_asleep_minutes) - minutes(t.minutes_up_night);
t.sleep_duration_in_mins = minutes(t.sleep_duration);
copy(copy.sleep_duration_in_mins > 60*24,:) = t;

% ---- after the fixes: keep local, derive Pacific ---------------------------
% bed_time / wake_time become Pacific (PST) again so the rest of the code and the
% mlx work unchanged; *_local hold the participant's own clock time
copy.bed_time_local  = copy.bed_time;
copy.wake_time_local = copy.wake_time;
known = ~isnan(copy.offset_h);
copy.bed_time(known)  = copy.bed_time(known)  - hours(copy.offset_h(known));
copy.wake_time(known) = copy.wake_time(known) - hours(copy.offset_h(known));
copy.bed_time_local(~known)  = NaT;              % no time zone -> local unknown
copy.wake_time_local(~known) = NaT;
writetable(deidentify_output(modify_t),append(file_path,'\Sleep_diary\Sleep_diary_morning_modification_details.xlsx'),'WriteMode','replacefile');

% ---- device comparison (Garmin / Muse) before the averages -------------------
% decides, per night, which diary clock the midpoint/averages use
[cmp,muse_off,garmin_off] = bed_time_comparison_T1D(copy,file_path);
g_c = string(cmp.GARMIN_diary_closer);  m_c = string(cmp.MUSE_diary_closer);
has_any = g_c ~= "" | m_c ~= "";
all_pst = has_any & (g_c == "pst" | g_c == "") & (m_c == "pst" | m_c == "");
pst_keys = cmp(all_pst,["SID","Date","Sleep_Wake_condition"]);
copy.calc_clock = repmat("local",height(copy),1);
copy.calc_clock(ismember(copy(:,["SID","Date","Sleep_Wake_condition"]),pst_keys)) = "pst";
% bed/wake used for midpoint and averages: local, or PST where all devices say pst
copy.bed_calc  = copy.bed_time_local;   copy.wake_calc = copy.wake_time_local;
use_pst = copy.calc_clock == "pst";
copy.bed_calc(use_pst)  = copy.bed_time(use_pst);
copy.wake_calc(use_pst) = copy.wake_time(use_pst);
fprintf('Sleep diary: %d night(s) use PST for midpoint/averages\n', sum(use_pst));

new = table;
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    swc = unique(t.Sleep_Wake_condition);
    for j = 1:length(swc)
        tt = t(t.Sleep_Wake_condition == swc(j),:);
        ttt = tt;
        ttt(isnan(ttt.sleep_duration),:) = [];
        tt{~isnan(tt.sleep_duration),"ave_sleep_duration_in_mins"} = mean(ttt.sleep_duration_in_mins);
        tt{~isnan(tt.sleep_duration), "ave_sleep_duration"} = mean(ttt.sleep_duration);
        bed_l = timeofday(ttt.bed_calc);                               % local (or PST where flagged)
        bed_l(hours(bed_l)<18) = bed_l(hours(bed_l)<18) + hours(24);
        tt{~isnan(tt.sleep_duration),"ave_bedtime_local"} = mean(bed_l);
        tt{hours(tt.ave_bedtime_local)>24,"ave_bedtime_local"} = tt{hours(tt.ave_bedtime_local)>24,"ave_bedtime_local"} - hours(24);
        tt{~isnan(tt.sleep_duration),"ave_waketime_local"} = mean(timeofday(ttt.wake_calc));
        tt{isnan(tt.sleep_duration),"ave_bedtime_local"} = nan;
        tt{isnan(tt.sleep_duration),"ave_waketime_local"} = nan;
        tt{isnan(tt.sleep_duration),"ave_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration), "ave_sleep_duration"} = nan;
        new = [new;tt];
    end
end
new.sleep_duration_residual = new.sleep_duration_in_mins - new.ave_sleep_duration_in_mins;
new.bed_midpoint_local = new.bed_calc + (new.wake_calc - new.bed_calc)/2;   % local (or PST where flagged)
new(:,["bed_calc","wake_calc"]) = [];
new(:,["first_sleep","get_out_of_bed"]) = [];

% ---- outputs --------------------------------------------------------------
% .mat (analyst only) and the returned table keep full datetimes; bed_time /
% wake_time / bed_midpoint / ave_bedtime / ave_waketime are Pacific (PST),
% the *_local columns are the participant's own clock time;
% .xlsx outputs are deidentified: Date -> yyyy-MM, bed/wake/midpoint -> HH:mm,
% Unix timestamps, birth date, burst day and age-in-days removed
save(append(file_path,'\Sleep_diary\Sleep_diary_morning_long.mat'),"new");
new_out = deidentify_output(new);
pst = intersect(["bed_time","wake_time"],string(new_out.Properties.VariableNames),'stable');
new_out = renamevars(new_out,pst,pst + "_PST");                    % make the clock explicit in the xlsx
new_out(:,intersect(["phone_tz_check","offset_h"],string(new_out.Properties.VariableNames))) = [];   % kept in the timezone check file only
writetable(new_out,append(file_path,'\Sleep_diary\Sleep_diary_morning_long.xlsx'),'WriteMode','replacefile');

% ---- device comparison sheets (raw, not deidentified; stays on CRSP) ---------
xl = append(file_path,'\Sleep_diary\Sleep_diary_morning_long.xlsx');
writetable(cmp,       xl,'Sheet','sleep_comparison');
writetable(muse_off,  xl,'Sheet','MUSE_off');
writetable(garmin_off,xl,'Sheet','GARMIN_off');
writetable(new_out,append(file_path,'\T1D master data.xlsx'),'Sheet','Sleep Diary Morning','WriteMode','overwritesheet');
end