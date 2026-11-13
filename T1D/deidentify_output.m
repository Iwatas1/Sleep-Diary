function T = deidentify_output(T)
% DEIDENTIFY_OUTPUT  Remove dates and timestamps from a table before writing it to .xlsx.
%
%   * Unix timestamps (started_at, finished_at, first_sleep, get_out_of_bed,
%     nap_start, nap_end, and ANY numeric column holding ms timestamps)   -> removed
%   * Birth date (Blurghbo / Blughbo), Burst_Day_, Agebydays...          -> removed
%   * bed / wake / sleep / nap / *_pst / midpoint datetimes              -> "HH:mm" (00-23)
%   * any other datetime (e.g. Date)                                     -> "yyyy-MM"
%   Durations and minute counts are kept (they are not dates).
%   Wide tables work too (first_sleep_pst_2, nap_start_time_PM_3, ...).

if isempty(T) || width(T) == 0, return, end
names = string(T.Properties.VariableNames);
base  = lower(regexprep(names,'_(PM_)?\d+$',''));      % strip wide suffixes _2, _PM_1
drop  = ismember(base,["started_at","finished_at","first_sleep","get_out_of_bed", ...
                       "nap_start","nap_end","blurghbo","blughbo","burst_day_"]) | ...
        startsWith(base,"agebydays");
for j = find(~drop)                                     % any other ms-epoch column (2001-2286)
    v = T.(char(names(j)));
    if isnumeric(v) && any(v(:) > 1e12 & v(:) < 1e13), drop(j) = true; end
end
T(:,drop) = [];

names = string(T.Properties.VariableNames);
base  = lower(regexprep(names,'_(PM_)?\d+$',''));
for j = 1:numel(names)
    v = T.(char(names(j)));
    if ~isdatetime(v), continue, end
    if endsWith(base(j),"_pst") || contains(base(j),["bed","wake","midpoint","sleep","nap"])
        s = string(v,'HH:mm');
    else
        s = string(v,'yyyy-MM');
    end
    s(ismissing(s)) = "";
    T.(char(names(j))) = s;
end
end
