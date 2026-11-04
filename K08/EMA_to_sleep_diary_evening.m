function [a,b,c] = EMA_to_sleep_diary_evening(EMA_evening,forget_evening,T_study,file_path)
% EMA_TO_SLEEP_DIARY_EVENING (K08)  Evening sleep diary: long, wide and modification tables.
%
%   a = long table (Day 8 removed), b = modification details, c = wide table.
%   The returned long table keeps full datetimes and is also saved to
%   Sleep_diary\Sleep_diary_evening_long.mat (used by just_sleep_diary.mlx).
%   .xlsx outputs (all deidentified: no dates or timestamps):
%     Sleep_diary\Sleep_diary_evening_long.xlsx
%     Sleep_diary\Sleep_diary_evening_wide.xlsx
%     Sleep_diary\Sleep_diary_evening_modification_details.xlsx
%     K08 master data.xlsx, sheet "Sleep Diary Evening"

% ---- add the "forgot evening diary" entries -------------------------------
col_names = string(forget_evening.Properties.VariableNames);
for i = 1:height(forget_evening)
    for j = 1:length(col_names)
        if j == 1
            EMA_evening{end+1,col_names(j)} = forget_evening{i,col_names(j)};
        else
            EMA_evening{end,col_names(j)} = forget_evening{i,col_names(j)};
        end
    end
    EMA_evening{end,~ismember(col_names,string(EMA_evening.Properties.VariableNames))} = nan;
end
copy = EMA_evening;
copy.date = datetime(copy.started_at/1000,"convertfrom","posixtime","Format","dd-MMM-uuuu","Timezone","America/Los_Angeles");
copy = renamevars(copy,"user","SID");
copy.SID = double(copy.SID);
copy.nap_start_time = datetime(copy.nap_start/1000,'ConvertFrom','posixtime','Format','dd-MMM-uuuu HH:mm:ss.SSS','TimeZone','America/Los_Angeles');
copy.nap_end_time = datetime(copy.nap_end/1000,'ConvertFrom','posixtime','Format','dd-MMM-uuuu HH:mm:ss.SSS','TimeZone','America/Los_Angeles');
copy.nap_duration = copy.nap_end_time - copy.nap_start_time;
copy{isnan(copy.nap_start),["nap_end_time","nap_start_time"]} = NaT;
copy{copy.nap_duration == 0,["nap_end","nap_start","nap_duration"]} = nan;

% ---- match diaries to study days (latest submission wins on duplicates) ---
SID = unique(T_study.SID);
cols = string(copy.Properties.VariableNames(2:end));
sleep_diary_long = table;
for i = 1:length(SID)
    tt = T_study(T_study.SID == SID(i),:);
    sw = unique(tt.StudyWeek);
    for ii = 1:length(sw)
        t = tt(tt.StudyWeek == sw(ii),:);
        sd = copy(and(copy.SID == SID(i),ismember(string(copy.date),string(t.Date))),:);
        sd = sortrows(sd,"started_at","ascend");
        try
            t(ismember(string(t.Date),string(sd.date)),cols) = sd(:,cols);
        catch
            unique_dates = unique(string(sd.date));
            for j = 1:length(unique_dates)
                if height(sd(string(sd.date) == unique_dates(j),:)) > 1
                    rep_t = sd(string(sd.date) == unique_dates(j),:);
                    delete_ind = [];
                    for k = 1:height(rep_t)
                        if isempty(rep_t.where_EMA_evening{k})      % "forgot" entry when a full diary exists
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
        end
        sleep_diary_long = [sleep_diary_long ; t]; %#ok<AGROW>
    end
end

% days with no diary: numbers/durations -> NaN
missing_t = sleep_diary_long(isnat(sleep_diary_long.date),:);
for i = width(T_study)+1:width(missing_t)
    d_type = class(missing_t{1,i});
    if d_type == "double" || d_type == "duration"
        missing_t{:,i} = nan(height(missing_t),1);
    end
end
sleep_diary_long(isnat(sleep_diary_long.date),:) = missing_t;
sleep_diary_long(:,"date") = [];
sleep_diary_long.nap_in_min = minutes(sleep_diary_long.nap_duration);

% K08: rows with impact_mood == 0 -> columns that are all 0 for those rows become NaN
sub = sleep_diary_long(sleep_diary_long.impact_mood == 0,:);
for i = 1:width(sub)
    col = sub{:,i};
    try
        if all(col == 0)
            sub{:,i} = nan;
        end
    catch
    end
end
sleep_diary_long(sleep_diary_long.impact_mood == 0,:) = sub;

% Day 8 is the last evening (no next night) -> removed
sleep_diary_long(sleep_diary_long.Day == 8,:) = [];

% ---- fix negative nap durations (AM/PM mix-ups) ---------------------------
% start after 18:00 -> start - 12 h ; end before 06:00 -> end + 12 h
modify_t = table;
negative = sleep_diary_long.nap_in_min < 0;
fix_start = negative & hour(sleep_diary_long.nap_start_time) > 18;
sleep_diary_long.nap_start_time(fix_start) = sleep_diary_long.nap_start_time(fix_start) - hours(12);
modify_t = [modify_t ; mod_rows(sleep_diary_long(fix_start,:),T_study,"nap_start_time","-12 hours on nap_start_time")];
recalc = minutes(sleep_diary_long.nap_end_time - sleep_diary_long.nap_start_time);
fix_end = negative & recalc < 0 & hour(sleep_diary_long.nap_end_time) < 6;
sleep_diary_long.nap_end_time(fix_end) = sleep_diary_long.nap_end_time(fix_end) + hours(12);
modify_t = [modify_t ; mod_rows(sleep_diary_long(fix_end,:),T_study,"nap_end_time","+12 hours on nap_end_time")];
sleep_diary_long.nap_duration = sleep_diary_long.nap_end_time - sleep_diary_long.nap_start_time;
sleep_diary_long.nap_in_min = minutes(sleep_diary_long.nap_duration);
still_negative = sleep_diary_long.nap_in_min < 0;
if any(still_negative)
    warning('EMA_to_sleep_diary_evening: %d nap(s) still have a negative duration after the AM/PM fix (listed in modification details).',sum(still_negative));
    modify_t = [modify_t ; mod_rows(sleep_diary_long(still_negative,:),T_study,"nap_duration","still negative - check by hand")];
end

% ---- wide: one row per SID x StudyWeek ------------------------------------
sleep_diary_wide = table;
for i = 1:length(SID)
    t = sleep_diary_long(sleep_diary_long.SID == SID(i),:);
    w = unique(t.StudyWeek);
    for j = 1:length(w)
        t_w = t(t.StudyWeek == w(j),:);
        if height(t_w) ~= 0
            row_n = table;
            row_n{end+1,"SID"} = SID(i);
            row_n{end,"StudyWeek"} = w(j);
            for k = 1:height(t_w)
                new_r = t_w(k,width(T_study)+1:end);
                new_r.Properties.VariableNames = cellstr(string(new_r.Properties.VariableNames) + "_PM_" + k);
                row_n = horzcat(row_n,new_r); %#ok<AGROW>
            end
            sleep_diary_wide = vertcat(sleep_diary_wide,row_n); %#ok<AGROW>
        end
    end
end

% ---- outputs --------------------------------------------------------------
a = sleep_diary_long;
b = modify_t;
c = sleep_diary_wide;
SD_path = fullfile(file_path,'Sleep_diary');
if ~isfolder(SD_path), mkdir(SD_path); end
save(fullfile(SD_path,'Sleep_diary_evening_long.mat'),'a');           % analyst only: full datetimes
long_out = deidentify_output(a);
writetable(long_out,fullfile(SD_path,'Sleep_diary_evening_long.xlsx'),'WriteMode','replacefile');
writetable(deidentify_output(b),fullfile(SD_path,'Sleep_diary_evening_modification_details.xlsx'),'WriteMode','replacefile');
writetable(deidentify_output(c),fullfile(SD_path,'Sleep_diary_evening_wide.xlsx'),'WriteMode','replacefile');
writetable(long_out,fullfile(file_path,'K08 master data.xlsx'),'Sheet','Sleep Diary Evening','WriteMode','overwritesheet');

old_csv = fullfile(SD_path,["Sleep_diary_evening_long.csv","Sleep_diary_evening_wide.csv","Sleep_diary_evening_modification_details.csv"]);
old_csv = old_csv(isfile(old_csv));
if ~isempty(old_csv)
    warning('EMA_to_sleep_diary_evening: old .csv outputs with full timestamps are still in %s - delete them: %s', ...
        SD_path,strjoin(string(old_csv),', '));
end
end

% -------------------------------------------------------------------------
function m = mod_rows(t,T_study,type,detail)
% modification log rows: study-sheet columns + what was changed
m = t(:,1:width(T_study));
m.modification_type   = repelem(string(type),height(m),1);
m.modification_detail = repelem(string(detail),height(m),1);
end
