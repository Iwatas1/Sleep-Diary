function [y,z] = expand_study(T_study)
copy = T_study;
copy(isnat(copy.Date),:) =[];
copy(isnan(copy.Sleep_Wake_condition),:) = [];
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

