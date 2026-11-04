%% Converted from just_sleep_diary.mlx (code cells only; outputs removed).
% Set the data folder paths below before running.

clear
warning('off','all')
file_path = 'C:\path\to\K08\DATA';     % <-- set to the K08 data folder
cd(fullfile(file_path,'Sleep_diary','codes'))
raw_data = select_dataset(file_path);
T_study = select_studysheet(file_path);
[EMA_morning, EMA_evening, forget_evening, forget_morning, EMA_on_mind] = sorting_SD(raw_data);
clear raw_data

%%
[sleep_diary_morning_long,bad, modify_t,wide] = EMA_to_sleep_diary_morning(EMA_morning,forget_morning,T_study,file_path);

%%
[sleep_diary_evening_long, sleep_diary_evening_mod,sleep_diary_evening_wide] = EMA_to_sleep_diary_evening(EMA_evening,forget_evening,T_study,file_path);

%%
sleep_diary_evening_long(~isnan(sleep_diary_evening_long.nap_start),:)

%%
clear raw_data

%%
copy = sleep_diary_morning_long(:,contains(sleep_diary_morning_long.Properties.VariableNames,["SID","StudyWeek","Day","pst","ave_bedtime","sleep_duration"]));
copy(copy.Day == 1,:) = [];
wide = table;
SID = unique(copy.SID);
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        row = table;
        tw = t(t.StudyWeek == sw(j),:);
        for k = 2:8
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
wide
for i = 1:4
    writetable(deidentify_output(wide(wide.StudyWeek_2 == i,:)),append(file_path + "\Sleep_diary\",string(i),".xlsx"))
end

%%
copy = sleep_diary_morning_long(:,contains(sleep_diary_morning_long.Properties.VariableNames,["SID","StudyWeek","Day","pst","ave_bedtime","sleep_duration"]))
SID = unique(copy.SID);
summary = table;
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        tw = t(t.StudyWeek == sw(j),:);
        row = tw(1,["SID","StudyWeek"]);
        bed_time = unique(tw.ave_bedtime);
        bed_time(isnan(bed_time)) = [];
        sleep_duration = unique(tw.ave_sleep_duration);
        sleep_duration(isnan(sleep_duration)) = [];
        if isempty(bed_time)
            bed_time = nan;
        end
        if isempty(sleep_duration)
            sleep_duration = nan;
        end
        row{end,"ave_bedtime"} = bed_time;
        row{end,"ave_sleep_duration"} = sleep_duration;
        summary = [summary;row];
    end
end
% run the garmin code to get the steps
copy = combined;
copy = copy(:,["SID","StudyWeek","Day","steps"]);
copy(or(copy.Day == 1,copy.Day == 8),:) = [];
ave_steps = table;
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        tw = t(t.StudyWeek == sw(j),:);
        steps = tw.steps;
        steps(isnan(steps)) = [];
        ave_steps{end+1,"ave_steps"} = round(mean(steps),0);
    end
end
summary.ave_steps = ave_steps.ave_steps
writetable(deidentify_output(summary),[fileparts(file_path) '\certificate_summary.xlsx'])

%%
clear

%%
t = load([file_path '\Sleep_diary\morning.mat']);
am = t.new
pm = load([file_path '\Sleep_diary\Sleep_diary_evening_long.mat']);
pm = pm.a

%%
sleepdiary = outerjoin(pm,am,"Type","left","Keys",pm.Properties.VariableNames(1:15),"MergeKeys",true);
sleepdiary(:,["nap_end","nap_start","first_sleep","get_out_of_bed"]) = [];
sleepdiary.Date = string(month(sleepdiary.Date,'name'));
cols = ["nap_start_time","nap_end_time","get_out_of_bed_pst","first_sleep_pst","bed_midpoint"];
sleepdiary{:,["nap_start_time","nap_end_time"]} = datetime(string(timeofday(sleepdiary{:,["nap_start_time","nap_end_time"]})),'format','HH:mm:ss');
sleepdiary.nap_duration = string(sleepdiary.nap_duration);
sleepdiary{~isnat(sleepdiary.nap_start_time),"nap_duration"} = string(sleepdiary{~isnat(sleepdiary.nap_start_time),"nap_end_time"} - sleepdiary{~isnat(sleepdiary.nap_start_time),"nap_start_time"});
string(sleepdiary{~isnat(sleepdiary.nap_start_time),"nap_end_time"} - sleepdiary{~isnat(sleepdiary.nap_start_time),"nap_start_time"})
sleepdiary(~isnat(sleepdiary.nap_start_time),:)

for i = 1:numel(cols)
    %t_only = timeofday(final.(cols(i)));
    %final.(cols(i)) = datetime(2000, 1, 1) + t_only;
    sleepdiary.(cols(i)).Format = 'HH:mm:ss';
    sleepdiary.(cols(i)) = string(sleepdiary.(cols(i)));
end
sleepdiary{:,cols} = string(sleepdiary{:,cols})

%%
depression = readtable([file_path '\Questionnaires\depression_measure.xlsx']);
depression = renamevars(depression,"study_week","StudyWeek");
depression(:,["age","sex"]) = [];
T = outerjoin(sleepdiary,depression,"Type","left","Keys",["SID","StudyWeek"],"MergeKeys",true)

%%
questionnaire = load([file_path '\Questionnaires\App\questionnaire_summary_HowRU.mat']);
q = questionnaire.sample;
q(:,3:7) = [];
T = outerjoin(T,q,"Type","left","Keys",["SID","StudyWeek"],"MergeKeys",true)

%%
writetable(deidentify_output(T),[file_path '\K08_sleepdiary_questionnaires.xlsx'])
