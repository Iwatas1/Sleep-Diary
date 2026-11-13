function [new,bad,modify_t,wide] = EMA_to_sleep_diary_morning(EMA_morning,forget_morning,T_study,file_path)
% EMA_TO_SLEEP_DIARY_MORNING (K08)  Morning sleep diary with the final RA fixes.
%
%   new      long table, Day 1 removed, full datetimes (also saved to Sleep_diary\morning.mat)
%   bad      matching debug table (unchanged from before)
%   modify_t automatic + 12 h rule modifications
%   wide     one row per SID x StudyWeek, Days 2-8 (deidentified)
%
%   .xlsx outputs (all deidentified: no dates or timestamps):
%     Sleep_diary\Sleep_diary_morning_long.xlsx
%     Sleep_diary\Sleep_diary_morning_wide.xlsx
%     Sleep_diary\Sleep_diary_morning_modification_details.xlsx
%     Sleep_diary\Sleep_diary_morning_RA_fix_log.xlsx   (from apply_RA_fix_K08)
%     K08 master data.xlsx, sheet "Sleep Diary Morning"

% ---- add the "forgot morning diary" entries -------------------------------
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
EMA_morning.date = datetime(EMA_morning.started_at/1000,"convertfrom","posixtime","Format","dd-MMM-yyyy","Timezone","local");
EMA_morning.get_out_of_bed_pst = datetime(string(EMA_morning.date)+ " " + extractAfter(string(EMA_morning.get_out_of_bed_pst)," "));
EMA_morning.first_sleep_pst = datetime(string(EMA_morning.date - day(1))+ " " + extractAfter(string(EMA_morning.first_sleep_pst)," "));
EMA_morning.sleep_duration = EMA_morning.get_out_of_bed_pst - EMA_morning.first_sleep_pst - minutes(EMA_morning.fall_asleep_minutes) - minutes(EMA_morning.minutes_up_night);
EMA_morning.user = double(EMA_morning.user);
EMA_morning = renamevars(EMA_morning,"user","SID");
copy = EMA_morning;

% ---- match diaries to study days (latest submission wins on duplicates) ---
SID = unique(T_study.SID);
cols = string(copy.Properties.VariableNames(2:end));
sleep_diary_long = table;
bad = table;
for i = 1:length(SID)
    tt = T_study(T_study.SID == SID(i),:);
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
                        if isempty(rep_t.where_EMA_morning{k})      % "forgot" entry when a full diary exists
                            delete_ind(end+1) = k; %#ok<AGROW>
                            sd(sd.started_at == rep_t.started_at(k),:) = [];
                        end
                    end
                    rep_t(delete_ind,:) = [];
                    while height(rep_t) > 1                         % keep the latest submission
                        timestamp = rep_t.started_at;
                        timestamp(timestamp == max(timestamp)) = [];
                        rep_t(ismember(rep_t.started_at,timestamp),:) = [];
                        sd(ismember(sd.started_at,timestamp),:) = [];
                        if isscalar(unique(rep_t.started_at))
                            rep_t = rep_t(1,:);
                            sd(sd.started_at == unique(rep_t.started_at),:) = [];
                            sd(end+1,:) = rep_t; %#ok<AGROW>
                        end
                    end
                end
            end
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols);
            t_1 = t;
            sd = sortrows(sd,"started_at","ascend");
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols);
        end
        sleep_diary_long = [sleep_diary_long ; t]; %#ok<AGROW>
        bad = [bad;t_1]; %#ok<AGROW>
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

% ---- automatic fixes (unchanged) ------------------------------------------
copy = sleep_diary_long;
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

% ---- Day 1 has no night before it: removed before anything else -----------
copy(copy.Day == 1,:) = [];

% ---- final RA fixes (SleepDiaryDataCheck) ---------------------------------
[copy,~] = apply_RA_fix_K08(copy,file_path);

% 12 h rule (from final.mlx): if sleep duration is still >= 12 h, push bed time +1 day
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
writetable(deidentify_output(modify_t),fullfile(file_path,'Sleep_diary','Sleep_diary_morning_modification_details.xlsx'),'WriteMode','replacefile');

% ---- device comparison (Garmin / Muse) ---------------------------------------
% K08: everyone treated as Pacific (blank time zone = PST), so local = PST and all
% timing stays PST. Pilot SIDs (moved between zones) are left out.
PILOT = [];      % <-- set the pilot SIDs to exclude locally
dev = copy(~ismember(copy.SID,PILOT),:);
dev.time_zone            = repmat("PST",height(dev),1);
dev.first_sleep_local    = dev.first_sleep_pst;
dev.get_out_of_bed_local = dev.get_out_of_bed_pst;
[cmp,muse_off,garmin_off] = bed_time_comparison_K08(dev,file_path);

% ---- weekly summaries -----------------------------------------------------
midnight = dateshift(copy.Date,'start','day');                 % midnight of the diary morning
copy.minutes_away_from_midnight_to_sleep_time = minutes(copy.first_sleep_pst - midnight);
new = table;
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        tt = t(t.StudyWeek == sw(j),:);
        ttt = tt;
        ttt(isnan(ttt.sleep_duration),:) = [];
        bed_time = timeofday(ttt.first_sleep_pst);
        bed_time(hours(bed_time)<18) = bed_time(hours(bed_time)<18) + hours(24);
        tt{~isnan(tt.sleep_duration),"ave_bedtime"} = mean(bed_time);
        tt{hours(tt.ave_bedtime)>24,"ave_bedtime"} = tt{hours(tt.ave_bedtime)>24,"ave_bedtime"} - hours(24);
        tt{~isnan(tt.sleep_duration),"ave_waketime"} = mean(timeofday(ttt.get_out_of_bed_pst));
        tt{~isnan(tt.sleep_duration),"ave_sleep_duration_in_mins"} = mean(ttt.sleep_duration_in_mins);
        tt{~isnan(tt.sleep_duration),"std_sleep_duration_in_mins"} = std(ttt.sleep_duration_in_mins);
        tt{~isnan(tt.sleep_duration),"z_score_sleep_duration_in_mins"} = round((ttt.sleep_duration_in_mins - mean(ttt.sleep_duration_in_mins))/std(ttt.sleep_duration_in_mins),2);
        tt{~isnan(tt.sleep_duration), "ave_sleep_duration"} = mean(ttt.sleep_duration);
        tt{isnan(tt.sleep_duration),"ave_bedtime"} = nan;
        tt{isnan(tt.sleep_duration),"ave_waketime"} = nan;
        tt{isnan(tt.sleep_duration),"ave_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration),"std_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration),"z_score_sleep_duration_in_mins"} = nan;
        tt{isnan(tt.sleep_duration), "ave_sleep_duration"} = nan;
        new = [new;tt]; %#ok<AGROW>
    end
end
new.residual_from_ave_sleep_duration = new.sleep_duration_in_mins - new.ave_sleep_duration_in_mins;
new{:,"bed_midpoint"} = mean(new{:,["get_out_of_bed_pst","first_sleep_pst"]},2);
new.minutes_away_from_midnight_to_mid_point = minutes(new.bed_midpoint - dateshift(new.Date,'start','day'));

% ---- outputs --------------------------------------------------------------
save(fullfile(file_path,'Sleep_diary','morning.mat'),'new');          % analyst only: full datetimes
new_out = deidentify_output(new);
xl = fullfile(file_path,'Sleep_diary','Sleep_diary_morning_long.xlsx');
writetable(new_out,xl,'WriteMode','replacefile');
% device comparison sheets (raw, full dates + unix; stays on CRSP)
writetable(cmp,       xl,'Sheet','sleep_comparison');
writetable(muse_off,  xl,'Sheet','MUSE_off');
writetable(garmin_off,xl,'Sheet','GARMIN_off');
writetable(new_out,fullfile(file_path,'K08 master data.xlsx'),'Sheet','Sleep Diary Morning','WriteMode','overwritesheet');

wide = table;
SIDw = unique(new_out.SID);
for i = 1:length(SIDw)
    t = new_out(new_out.SID == SIDw(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        row = table;
        tw = t(t.StudyWeek == sw(j),:);
        for k = 2:8
            td = tw(tw.Day == k,:);
            td.Properties.VariableNames = cellstr(string(td.Properties.VariableNames) + "_" + k);
            row = [row,td]; %#ok<AGROW>
        end
        wide = [wide;row]; %#ok<AGROW>
    end
end
writetable(wide,fullfile(file_path,'Sleep_diary','Sleep_diary_morning_wide.xlsx'),'WriteMode','replacefile');
end
