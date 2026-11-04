warning('off', 'all')
%import
%input path to each analyzed csv
T_study = readtable('C:\Users\230Student01\Desktop\ema\K08_StudySheet_032524.xlsx');
T_morning = readtable('C:\Users\230Student01\Desktop\ema\sleep_diary_morning_4.2.2024.csv');
T_midday = readtable('C:\Users\230Student01\Desktop\ema\Midday_mood_check_4.2.2024.csv');
T_evening = readtable('C:\Users\230Student01\Desktop\ema\sleep_diary_evening_4.2.2024.csv');
no_need = {'id', 'user_id','started_at_conv_gmt', 'finished_at_conv_gmt', 'waketime_conv_gmt', 'bedtime_conv_gmt'};
%setup for morning
T_morning(:,no_need) = [];
T_midday(:,{'id', 'user_id','started_at_conv_gmt', 'finished_at_conv_gmt'}) = [];
T_evening(:, {'id', 'user_id','started_at_conv_gmt', 'finished_at_conv_gmt'}) = [];
T_study.SID = string(T_study.SID);
T_morning.user = string(T_morning.user);
T_midday.user = string(T_midday.user);
T_evening.user = string(T_evening.user);
for i = 1:length(T_morning.user)
    c = char(T_morning.user(i));
    T_morning.user(i) = string(c(end-2:end));
end
for i = 1:length(T_midday.user)
    c = char(T_midday.user(i));
    T_midday.user(i) = string(c(end-2:end));
end
for i = 1:length(T_evening.user)
    c = char(T_evening.user(i));
    T_evening.user(i) = string(c(end-2:end));
end
user = unique(T_morning.user);
user = erase(user,["124", "125","126","127"]);
for i = 1:3
    user(17) = [];
end
T_morning.started_at_conv_pst = datetime(T_morning.started_at /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss');
T_morning.finished_at_conv_pst = datetime(T_morning.finished_at /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss');
T_midday.started_at_conv_pst = datetime(T_midday.started_at /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss');
T_midday.finished_at_conv_pst = datetime(T_midday.finished_at /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss');
T_evening.started_at_conv_pst = datetime(T_evening.started_at /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss');
T_evening.finished_at_conv_pst = datetime(T_evening.finished_at /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss');
T_morning.waketime_conv_pst = timeofday(datetime(T_morning.waketime /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss'));
T_morning.waketime_raw_pst = T_morning.waketime_conv_pst;
T_morning.bedtime_conv_pst = timeofday(datetime(T_morning.bedtime /1000, 'convertfrom','posixtime','TimeZone','America/Los_Angeles', 'Format','dd-MMM-yyyy HH:mm:ss'));
T_morning.bedtime_raw_pst = T_morning.bedtime_conv_pst;
T_morning.total_sleep_time = timeofday(datetime((T_morning.waketime - T_morning.bedtime)/1000,'convertfrom','posixtime', 'Format','dd-MMM-yyyy HH:mm:ss'));
T_morning.minutes_up_night(isnan(T_morning.minutes_up_night)) = 0;
columns_mor = T_morning.Properties.VariableNames;
columns_mid = T_midday.Properties.VariableNames;
columns_eve = T_evening.Properties.VariableNames;
columns_mor([22 23:end]) = columns_mor([end 22:end-1]);
columns_mor([21 22:end]) = columns_mor([end 21:end-1]);
columns_mor([19 20:end]) = columns_mor([end 19:end-1]);
T_morning = T_morning(:,columns_mor);
mod = table;
for i = 1:height(T_morning)
    sleep_time = T_morning{i,'total_sleep_time'};
    bed_time = T_morning{i,'bedtime_conv_pst'};
    wake_time = T_morning{i,'waketime_conv_pst'};
    if hours(sleep_time) > 14 && (hours(bed_time) < 18 & hours(bed_time) > 4)
        sleep_time = sleep_time - hours(12);
        bed_time = bed_time + hours(12);
        if hours(bed_time)> 24
            bed_time = bed_time - hours(24);
        end
        T_morning{i,'bedtime_conv_pst'} = bed_time;
        mod{end+1, 'user'} = T_morning{i,'user'};
        mod{height(mod), 'modified date'} = T_morning{i,'finished_at_conv_pst'};
        mod{height(mod), 'categories'} = "bed time";
        mod{height(mod),'detail'} = "+12 hours on bed time and -12hours on sleeping time";

    elseif hours(sleep_time) > 14 && hours(wake_time) > 15
        sleep_time = sleep_time - hours(12);
        T_morning{i, 'waketime_conv_pst'} = wake_time - hours(12);
        mod{height(mod) + 1, 'user'} = T_morning{i,'user'};
        mod{height(mod), 'modified date'} = T_morning{i,'finished_at_conv_pst'};
        mod{height(mod), 'categories'} = "wake up time";
        mod{height(mod),'detail'} = "-12 hours on sleeping time and wake up time";
    end
    T_morning{i,'total_sleep_time'} = sleep_time;
end
T_morning.total_sleep_time = T_morning.total_sleep_time - minutes(T_morning.fall_asleep_minutes) - minutes(T_morning.minutes_up_night);
%adjusting the SID to user on study sheet
T_study.Date = datetime(T_study.Date, "TimeZone","America/Los_Angeles");
final = table;
for i = 1:length(user)
    final_user = table;
    morning = adjust(user(i),T_morning,T_study,final);
    midday = adjust(user(i),T_midday, T_study,final);
    evening = adjust(user(i), T_evening, T_study,final);

    morning.user_midday = morning.user;
    morning.StudyWeek_midday = morning.StudyWeek;
    morning.Date_midday = morning.Date;
    morning.Day_midday = morning.Day;
    morning.started_at_midday = midday.started_at;
    morning.started_at_conv_pst_midday = midday.started_at_conv_pst;
    morning.finished_at_midday = midday.finished_at;
    morning.finished_at_conv_pst_midday = midday.finished_at_conv_pst;
    
    midday.user_evening = morning.user;
    midday.StudyWeek_evening = morning.StudyWeek;
    midday.Date_evening = morning.Date;
    midday.Day_evening = morning.Day;
    midday.started_at_evening = evening.started_at;
    midday.started_at_conv_pst_evening = evening.started_at_conv_pst;
    midday.finished_at_evening = evening.finished_at;
    midday.finished_at_conv_pst_evening = evening.finished_at_conv_pst;

    evening.filling_out_diary_evening = evening.filling_out_diary;

    overlap = {"user","StudyWeek","Date", "Day", "started_at", "started_at_conv_pst","finished_at", "finished_at_conv_pst", "filling_out_diary"};
    for j = 1:length(overlap)-1
        midday(:,overlap{j}) = [];
    end
    for j = 1:length(overlap) 
        evening(:, overlap{j}) = [];
    end
    final_user = horzcat(morning,midday,evening);
    final = vertcat(final, final_user);

end
final.wake_up_night(isnan(final.wake_up_night)) = 0;
final_update = table;
for i = 1:width(final)
    cols = final.Properties.VariableNames;
    if i < 41
        name = append(cols{i},"_1");
        final_update{:,name} = final{:,cols{i}};
    elseif i < 61
        name = append(cols{i},"_2");
        final_update{:,name} = final{:,cols{i}};
    else
        name = append(cols{i},"_3");
        final_update{:,name} = final{:,cols{i}};
    end
end
writetable(final_update, "C:\Users\230Student01\Desktop\ema\sleep_diary_ema_concatnated_xxx.csv")
%%
sleep_summary = table;
for i = 1:length(user)
    u = final(final.user == user(i), :);
    week = unique(u.StudyWeek);
    for j = 1:length(week)
        u_w = u(u.StudyWeek == week(j),:);
        a = 1;
        missing = [];
        for k = 1:height(u_w)
            if isnan(u_w{k,"total_sleep_time"})
                missing(a) = k;
                a = a + 1;
            end
        end
        u_w(missing,:) = [];
        sleep_summary{end+1, "user"} = user(i);
        sleep_summary{end,"study_week"} = week(j);
        sleep_summary{end, "bedtime_ave"} = mean(u_w.bedtime_conv_pst);
        sleep_summary{end, "bedtime_std"} = std(u_w.bedtime_conv_pst);
        sleep_summary{end, "waketime_ave"} = mean(u_w.waketime_conv_pst);
        sleep_summary{end, "waketime_std"} = std(u_w.waketime_conv_pst);
        sleep_summary{end,"total_sleep_time_ave"} = mean(u_w.total_sleep_time);
        sleep_summary{end, "total_sleep_time_std"} = std(u_w.total_sleep_time);
        sleep_summary{end, "fall_asleep_minutes_ave"} = mean(u_w.fall_asleep_minutes);
        sleep_summary{end, "fall_asleep_minutes_std"} = std(u_w.fall_asleep_minutes);
        sleep_summary{end, "wake_up_night_ave"} = mean(u_w.wake_up_night);
        sleep_summary{end, "wake_up_night_std"} = std(u_w.wake_up_night);
        sleep_summary{end, "minutes_up_night_ave"} = mean(u_w.minutes_up_night);
        sleep_summary{end, "minutes_up_night_std"} = std(u_w.minutes_up_night);
    end
end

%%
function y = adjust(user,T,T_study,final)
morning = T(T.user == user,:);
fix_morning = table;
study = T_study(T_study.SID == user,:);
fix_morning = study(:,2:4);
for i = 1:height(fix_morning)
    date = fix_morning{i,"Date"};
    for j = 1:height(morning)
        if month(date) == month(morning{j,"started_at_conv_pst"}) && day(date) == day(morning{j,"started_at_conv_pst"})
            fix_morning(i,4:3+width(morning)) = morning(j,:);
        end
    end
end
columns = fix_morning.Properties.VariableNames;
col_names = morning.Properties.VariableNames;
if length(columns) < length(col_names)
    cols = horzcat(columns,col_names);
    empty = table;
    for i = 1:length(cols)
        type = class(final{1,cols{i}});
        if type == "cell"
            empty{1:8,cols{i}} = cell(8,1);
        elseif type == "double"
            empty{1:8,cols{i}} = NaN(8,1);
        elseif type == "string"
            empty{1:8, cols{i}} = strings(8,1);
        elseif type == "datetime"
            empty{1:8, cols{i}} = NaT(8,1);
        else
            empty{1:8,cols{i}} = NaN(8,1);
        end
    end
    empty.StudyWeek = study.StudyWeek;
    empty.Date = study.Date;
    empty.Day = study.Day;
    empty.started_at_conv_pst = NaT(height(empty), 1);
    empty.started_at_conv_pst = datetime(empty.started_at_conv_pst, "TimeZone","America/Los_Angeles");
    empty.finished_at_conv_pst = NaT(height(empty), 1);
    empty.finished_at_conv_pst = datetime(empty.finished_at_conv_pst, "TimeZone","America/Los_Angeles");
    fix_morning = empty;

else
    fix_morning = renamevars(fix_morning, columns(4:end), col_names);
end

columns = fix_morning.Properties.VariableNames;
columns([1 2:4]) = columns([4 1:3]);
fix_morning = fix_morning(:,columns);
fix_morning.user = repelem(user, height(fix_morning),1);
for i = 1:height(fix_morning)
    for j = width(fix_morning):-1:1
        if fix_morning{i,"started_at"} == 0 && class(fix_morning{i,j}) == "double"
            if fix_morning{i,j} == 0
                fix_morning{i,j}= NaN;
            end
        elseif fix_morning{i,"started_at"} == 0 && class(fix_morning{i,j}) == "duration"
            if fix_morning{i,j} == 0
                fix_morning{i,j}= NaN;
            end
        end
    end
end
y = fix_morning;
end