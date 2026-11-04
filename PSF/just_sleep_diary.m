%% Converted from just_sleep_diary.mlx (code cells only; outputs removed).
% Set the data folder paths below before running.

clear
warning('off','all')
file_path = 'C:\path\to\PSF DATA';      % <-- set to the PSF data folder
k08_path  = 'C:\path\to\K08\DATA';      % <-- K08 data folder (only used in the PSF + K08 evening merge cell)
cd(fullfile(file_path,'Sleep_diary','codes'))
raw_data = select_dataset(file_path);
T_study = select_studysheet(file_path);
raw_data(~contains(raw_data.user,digitsPattern),:) = [];
[EMA_morning, EMA_evening, forget_evening, forget_morning, EMA_on_mind] = sorting_SD(raw_data);
[sleep_diary_morning_long,sleep_diary_morning_mod] = EMA_to_sleep_diary_morning(EMA_morning,forget_morning,T_study,file_path);

%%
copy = sleep_diary_morning_long

%%
% DISABLED (Oct 2026): RA fixes are now applied inside EMA_to_sleep_diary_morning
% via apply_RA_fix.m (reads the newest file in PSF DATA\SleepDiaryDataCheck).
% Running this old block would re-apply RA times by row position from RA_fix\SW*.xlsx
% and overwrite Sleep_diary_morning_long.xlsx. Kept below for reference only.
%{
long = table;
for i = 1:3
    t = readtable([file_path '\Sleep_diary\RA_fix\SW' char(string(i)) '.xlsx']);
    %sub = readtable([file_path '\Sleep_diary\RA_fix\sub' char(string(i)) '.xlsx']);
    %sid = sub.SID_2;
    %t(ismember(t.SID_2,sid),sub.Properties.VariableNames) = sub;
    t(:,contains(t.Properties.VariableNames,["NOTE","Note","note","Sex_1"])) = [];
    long = [long;t];
end
clear t sub sid col_name new_col c num_pat tt 
long = sortrows(long,"SID","ascend");
long.get_out_of_bed_pst = datetime(string(long.Date)+ " " + extractAfter(string(long.get_out_of_bed_pst)," "));
long.first_sleep_pst = datetime(string(long.Date - day(1))+ " " + extractAfter(string(long.first_sleep_pst)," "));
long(long.Day == 1,:) = [];
SID = unique(long.SID);
copy(copy.Day == 1,:) = [];
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    tt = long(long.SID == SID(i),:);
    sw = unique(tt.StudyWeek);
    for j = 1:length(sw)
        t(t.StudyWeek == sw(j),["get_out_of_bed_pst","first_sleep_pst"]) = tt(tt.StudyWeek == sw(j),["get_out_of_bed_pst","first_sleep_pst"]);
        
    end
    copy(copy.SID == SID(i),:) = t;
end
copy.sleep_duration = copy.get_out_of_bed_pst - copy.first_sleep_pst - minutes(copy.fall_asleep_minutes) - minutes(copy.minutes_up_night);
copy.sleep_duration_in_mins = minutes(copy.sleep_duration);
fix = copy(copy.sleep_duration_in_mins >= 12*60,:);
fix{:,"first_sleep_pst"} = fix{:,"first_sleep_pst"} + day(1);
fix.sleep_duration = fix.get_out_of_bed_pst - fix.first_sleep_pst - minutes(fix.fall_asleep_minutes) - minutes(fix.minutes_up_night);
fix.sleep_duration_in_mins = minutes(fix.sleep_duration);
copy(copy.sleep_duration_in_mins >= 12*60,:) = fix;
copy.minutes_away_from_midnight_to_sleep_time = minutes(copy.first_sleep_pst - datetime(string(copy.Date)+ " " + string(timeofday(datetime("00:00:00","inputformat","HH:mm:ss")))));
new = table;
for j = 1:length(SID)
    t = copy(copy.SID == SID(j),:);
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
        new = [new;tt];
    end
end
new.residual_from_ave_sleep_duration = new.sleep_duration_in_mins - new.ave_sleep_duration_in_mins;
new{:,"bed_midpoint"} = mean(new{:,["get_out_of_bed_pst","first_sleep_pst"]},2);
new.minutes_away_from_midnight_to_mid_point = minutes(new.bed_midpoint - datetime(string(new.Date)+ " " + string(timeofday(datetime("00:00:00","inputformat","HH:mm:ss")))));
new
writetable(new,append(file_path,'\Sleep_diary\Sleep_diary_morning_long.xlsx'));
save(append(file_path,'\Sleep_diary\morning.mat'),'new')
%}

%%
psf = readtable([file_path '\Sleep_diary\sleep_diary_evening.xlsx']);
psf(~isnan(psf.nap_start),:)
psf.nap_duration = string(psf.nap_duration)
k08 = readtable([k08_path '\Sleep_diary\Sleep_diary_evening_long.csv']);
%k08.nap_start_time = datetime(k08{:,"nap_start"}/1000,'convertfrom','posixtime');
%k08.nap_start_time.TimeZone = 'local'
k08(~isnan(k08.nap_start),:)
%k08{:,"nap_start_time"} = datetime(k08{:,"nap_start"}/1000,'convertfrom','posixtime','timezone','local')
k08.Date = month(k08.Date,'long');
k08.nap_duration = string(k08.nap_duration);
T = [k08;psf(:,k08.Properties.VariableNames)]
study = readtable([file_path '\Studysheet\sex_age_match.xlsx'],'sheet','sheet1');
SID = [study.SID;study.SID_match];
t = T(ismember(string(T.SID),string(SID)),:)

%%
t{:,["nap_start_time","nap_end_time"]} = datetime(string(timeofday(t{:,["nap_start_time","nap_end_time"]})),'format','HH:mm:ss')
t{~isnan(t.nap_start),"nap_duration"} = string(t{~isnan(t.nap_start),"nap_end_time"} - t{~isnan(t.nap_start),"nap_start_time"})
t(~isnan(t.nap_start),:)

%%
writetable(deidentify_output(t),[file_path '\Cog_Tasks\postprocessed\OSPAN\new_data.xlsx'],'sheet','Sleep_diary_evening')

%%
writetable(deidentify_output(combined),[file_path '\Sleep_diary\sleep_diary_combined.xlsx'])

%%
x = load([file_path '\Sleep_diary\Sleep_diary_morning_long.mat']);
x = x.new;
d = x.Date;
x.Date = month(d);
x.Burst_Day_ = month(d,"shortname");
writetable(deidentify_output(x),[file_path '\Sleep_diary\Sleep_diary_morning_long.xlsx'])

%%
[sleep_diary_evening_long, sleep_diary_evening_mod,sleep_diary_evening_wide] = EMA_to_sleep_diary_evening(EMA_evening,forget_evening,T_study,file_path);
copy = sleep_diary_evening_long
copy.Date = month(copy.Date,'long');
writetable(deidentify_output(copy),[file_path '\Sleep_diary\codes\sleep_diary_evening.xlsx'],'WriteMode','replacefile')

%%
sleep_diary_evening_long = renamevars(sleep_diary_evening_long,"filling_out_diary","filling_out_diary_evening");
sleep_diary_evening_long(:,["started_at","finished_at"]) = [];
combined = [sleep_diary_morning_long sleep_diary_evening_long(:,width(T_study)+1:end)];
SID = unique(combined.SID);
Q = load([file_path '\Sleep_diary\CDI_CESD.mat'])
Q = Q.T
new = table;
for i = 1:length(SID)
    t = combined(combined.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        tw = t(t.StudyWeek == sw(j),:);
        tt = Q(and(Q.SID == SID(i),Q.study_week == sw(j)),2:end);
        if height(tt) == 0
            tt{end+1,:} = nan;
        end
        tw = [tw repelem(tt,height(tw),1)];
        new = [new;tw];
    end
    
end

%%
writetable(deidentify_output(new),[file_path '\Sleep_diary\all_combined.xlsx'])

%%
copy = CES_D_num;
copy.date = string(datetime(copy.started_at/1000,"convertfrom","posixtime","format","dd-MMM-yyyy","timezone","local"))
SID = string(unique(T_study.SID));
summary = table;
for i = 1:length(SID)
    t_study = T_study(T_study.SID == double(SID(i)),:);
    sw = unique(t_study.StudyWeek);
    t = copy(copy.SID == SID(i),:);
    ds = t.date;
    for j = 1:length(sw)
        tw = t_study(t_study.StudyWeek == sw(j),:);
        row = tw(1,["SID","StudyWeek"]);
        sd = unique(string([tw.Date; [max(tw.Date)+days(1):max(tw.Date)+days(32)].']));
        if sum(ismember(ds,sd)) == 1
            row = [row t(t.date == ds(ismember(ds,sd)),"total_score")];
            t(t.date == ds(ismember(ds,sd)),:) = [];
        elseif sum(ismember(ds,sd)) == 0
            row{1,"total_score"} = nan;
        else
            select = t(matches(t.date,ds(ismember(ds,sd))),:);
            try
                row = [row select(select.started_at == max(select.started_at),"total_score")];
                
            catch
                row = [row select(1,"total_score")];
            end
            t(matches(t.date,ds(ismember(ds,sd))),:) = [];
        end
        summary = [summary;row];

    end        
    if height(t)~= 0 
    end
end
summary

%%
child = readtable([file_path '\Questionnaires\App\CDI child.xlsx']);
parent = readtable([file_path '\Questionnaires\App\CDI parents.xlsx']);
parent(:,~contains(parent.Properties.VariableNames,["SID","study_week","Total"])) = []
child(:,~contains(child.Properties.VariableNames,["SID","study_week","Total"])) = []

%%
inds = find(contains(child.Properties.VariableNames,"study_week"));
long = table;
i = 1;
while i <= height(child)
    T = repelem(child(i,"SID"),3,1);
    col_names = child.Properties.VariableNames(inds(1):inds(2)-1);
    for j = 1:length(inds)
        try
            t = child(i,inds(j):inds(j+1)-1);
            t = renamevars(t,t.Properties.VariableNames,col_names);
        catch
            t = child(i,inds(j):end);
            t = renamevars(t,t.Properties.VariableNames,col_names);
        end
        T(j,col_names) = t;
    end
    long = [long;T];
    i = i+1;
end
long;
inds = find(contains(parent.Properties.VariableNames,"study_week"));
long_0 = table;
i = 1;
while i <= height(parent)
    T = repelem(parent(i,"SID"),3,1);
    col_names = parent.Properties.VariableNames(inds(1):inds(2)-1);
    for j = 1:length(inds)
        try
            t = parent(i,inds(j):inds(j+1)-1);
            t = renamevars(t,t.Properties.VariableNames,col_names);
        catch
            t = parent(i,inds(j):end);
            t = renamevars(t,t.Properties.VariableNames,col_names);
        end
        T(j,col_names) = t;
    end
    long_0 = [long_0;T];
    i = i+1;
end
long_0;
long_0 = renamevars(long_0,["Raw_Total","T_Total"],["Raw_total_parents","T_Total_parents"])
long.study_week__ = repmat([1:3].',height(long)/3,1);
long_0.study_week__ = repmat([1:3].',height(long_0)/3,1);
SID_0 = unique(long_0.SID);
SID = unique(long.SID);
non_exist = SID_0(~ismember(SID_0,SID))
long_0(ismember(long_0.SID, non_exist),:) = []
CDI = [long long_0(:,3:4)];
CESD = summary;
SID = unique(long_0.SID);
T = table;
col_names = string(long.Properties.VariableNames(3:end));
col_names_0 = string(long_0.Properties.VariableNames(3:end));
for i = 1:length(SID)
   cdi = CDI(CDI.SID == SID(i),:);
    cesd = CESD(CESD.SID == SID(i),:);
    try
        T = [T ; cdi cesd(:,"total_score")];
    catch
        if height(cesd) == 0
            cdi.total_score = nan(height(cdi),1);
        else
            cdi{ismember(cdi.study_week__,cesd.StudyWeek),"total_score"} = cesd{ismember(cesd.StudyWeek,cdi.study_week__),"total_score"};
        end
        T = [T ; cdi];
    end
end

%%
T = renamevars(T,["ABCD_Total","T_Total","Short_Total","total_score"],["ABCD_Total_child","T_Total_child","Short_Total_child","total_score_CESD"])
T.study_week = repmat([1:3].',height(T)/3,1)

%%
save([file_path '\Sleep_diary\CDI_CESD.mat'],"T")

%%
%for RA data checking
copy = new;
copy(copy.Day == 1,:) = [];
SID = unique(copy.SID);
wide = table;
for i = 1:length(SID)
    t = copy(copy.SID == SID(i),:);
    sw = unique(t.StudyWeek);
    for j = 1:length(sw)
        tw = t(t.StudyWeek == sw(j),:);
        sd = unique(tw.Day);
        week = table;
        for k = 1:length(sd)
            col_names = string(copy.Properties.VariableNames);
            td = tw(tw.Day == sd(k),:);
            for l = 1:length(col_names)
                col_names(l) = append(col_names(l),"_",string(sd(k)));
            end
            td = renamevars(td,td.Properties.VariableNames,col_names);
            week = [week,td];
        end
        wide = [wide;week];
    end
end
wide
select = wide(:,or(contains(wide.Properties.VariableNames,T_study.Properties.VariableNames),contains(wide.Properties.VariableNames,["fall_asleep","minutes_up_","pst","sleep_duration"])));
select(:,contains(select.Properties.VariableNames,"residual")) = [];
sw = [1:3]
for i = 1:length(sw)
    t = select(select.StudyWeek_2 == sw(i),:)
    writetable(t,[file_path '\Sleep_diary\sub' char(string(sw(i))) '.xlsx'])
end
