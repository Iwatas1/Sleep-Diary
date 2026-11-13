function [copy,tz_check] = add_local_time_T1D(copy,file_path)
% ADD_LOCAL_TIME_T1D  Convert bed/wake time to the participant's LOCAL time.
%
%   [copy,tz_check] = add_local_time_T1D(copy,file_path)
%
%   Run this BEFORE the mis-input fixes (fix_sleep_inputs, bed/wake switch, >24 h),
%   so their clock-hour rules work on the participant's own clock.
%   COPY is the morning sleep diary table right after diaries are matched to study
%   days (bed_time / wake_time as converted with the lab computer's time zone,
%   started_at in ms). On return bed_time / wake_time are LOCAL time, and
%   copy.offset_h holds hours ahead of Pacific, so after the fixes:
%       PST = local - offset_h
%   (offset_h is NaN when the SID has no time zone; those rows are left as shown.)
%
%   How the app saves typed times: the PHONE reads a typed time ("9:00 AM") in the
%   phone's own time zone and saves the true moment. So:
%     * phone on the participant's own zone (normal):  the pipeline shows Pacific time
%           PST = shown,            local = shown + offset
%     * phone set to Pacific (e.g. set up in the lab): the pipeline shows the typed time
%           local = shown,          PST = shown - offset
%   (offset = hours ahead of Pacific: MST 1, CST 2, EST 3; PST 0)
%
%   NOTE (Nov 2026): conversion now ignores phone_tz_check. bed/wake shown by the
%   pipeline are always taken as PST and local = PST + offset for every participant.
%   The phone check below is still computed and written to the check file for reference only.
%
%   Which case applies is decided per participant from the data: people open the
%   morning diary shortly after the wake time they report. started_at is the true
%   moment the diary was opened, so
%     gap = diary opened - reported wake   (time of day, Pacific clock)
%   is near 0 on a phone on the own zone, and about -offset on a phone set to Pacific.
%   Participants whose days disagree are flagged "mixed - check by hand".
%   Manual overrides: PHONE_ON_PACIFIC / PHONE_ON_OWN_ZONE below.
%
%   Zones: <file_path>\demographics\T1D_timezones.xlsx (columns SID, TZ).
%
%   Adds columns:  time_zone, phone_tz_check, offset_h
%   TZ_CHECK (one row per SID) is also written, deidentified, to
%   <file_path>\Sleep_diary\Sleep_diary_morning_timezone_check.xlsx

PHONE_ON_PACIFIC  = [];     % SIDs to force into "phone set to Pacific", e.g. [SID]
PHONE_ON_OWN_ZONE = [];     % SIDs to force into "phone on own zone"
MIN_AGREE = 0.6;            % share of days that must agree, otherwise "mixed - check by hand"

n = height(copy);
copy.time_zone       = strings(n,1);
copy.phone_tz_check  = strings(n,1);
copy.offset_h        = nan(n,1);

% ---- zones per SID --------------------------------------------------------
zf = fullfile(file_path,'demographics','T1D_timezones.xlsx');
if isfile(zf)
    Z = readtable(zf);
    Z.SID = double(string(Z.SID));
    Z.TZ  = upper(strtrim(string(Z.TZ)));
else
    warning('add_local_time_T1D: %s not found - everyone treated as PST.',zf);
    Z = table(nan(0,1),strings(0,1),'VariableNames',["SID","TZ"]);
end

% ---- gap between opening the diary and reported wake (minutes) ------------
opened = datetime(copy.started_at/1000,'ConvertFrom','posixtime','TimeZone','America/Los_Angeles');
opened_min = hour(opened)*60 + minute(opened);
wake_min   = hour(copy.wake_time)*60 + minute(copy.wake_time);
gap = mod(opened_min - wake_min + 720,1440) - 720;

SIDs = unique(copy.SID(~isnan(copy.SID)));
tz_check = table('Size',[numel(SIDs) 7], ...
    'VariableTypes',["double","string","double","double","double","double","string"], ...
    'VariableNames',["SID","time_zone","offset_h","days","median_gap_min","pct_days_agree","phone_tz_check"]);
for s = 1:numel(SIDs)
    rows = copy.SID == SIDs(s);
    z = Z.TZ(Z.SID == SIDs(s));
    if isempty(z) || strlength(z(1)) == 0, z = ""; else, z = z(1); end
    off = zone_offset(z);                       % NaN if unknown
    g = gap(rows & ~isnan(gap));
    tz_check.SID(s) = SIDs(s);  tz_check.time_zone(s) = z;  tz_check.offset_h(s) = off;
    tz_check.days(s) = numel(g);
    tz_check.median_gap_min(s) = median(g);

    if isnan(off)
        group = "no time zone - local time not computed";
    elseif off == 0
        group = "PST";
    elseif ismember(SIDs(s),PHONE_ON_PACIFIC)
        group = "phone set to Pacific (manual)";
    elseif ismember(SIDs(s),PHONE_ON_OWN_ZONE)
        group = "phone on own zone (manual)";
    elseif isempty(g)
        group = "phone on own zone (assumed - no diary times)";
    else
        on_pacific = g < -off*60/2;             % closer to -offset than to 0
        pacific = median(g) < -off*60/2;
        agree = mean(on_pacific == pacific);
        tz_check.pct_days_agree(s) = round(100*agree);
        if pacific, group = "phone set to Pacific"; else, group = "phone on own zone"; end
        if agree < MIN_AGREE, group = group + " - mixed, check by hand"; end
    end
    tz_check.phone_tz_check(s) = group;

    % ---- convert to local time ----
    copy.time_zone(rows)      = z;
    copy.phone_tz_check(rows) = group;
    copy.offset_h(rows)       = off;
    if isnan(off), continue, end
    % shown = Pacific (PST) for everyone -> local = PST + offset.
    % phone_tz_check is informational only and NOT used for the conversion.
    copy.bed_time(rows)  = copy.bed_time(rows)  + hours(off);
    copy.wake_time(rows) = copy.wake_time(rows) + hours(off);
end

need_look = contains(tz_check.phone_tz_check,["mixed","no time zone"]);
if any(need_look)
    warning('add_local_time_T1D: check time zone by hand for SID(s): %s', ...
        strjoin(string(tz_check.SID(need_look)) + " (" + tz_check.phone_tz_check(need_look) + ")","; "));
end
fprintf('add_local_time_T1D: %d participant(s) with phone set to Pacific, %d on own non-Pacific zone, %d to check\n', ...
    sum(startsWith(tz_check.phone_tz_check,"phone set to Pacific")), ...
    sum(startsWith(tz_check.phone_tz_check,"phone on own zone")),sum(need_look));
writetable(deidentify_output(tz_check),fullfile(file_path,'Sleep_diary','Sleep_diary_morning_timezone_check.xlsx'),'WriteMode','replacefile');
end

% -------------------------------------------------------------------------
function h = zone_offset(z)
% hours ahead of Pacific; accepts "EST", "Eastern", "E", "America/New_York", ...
z = upper(strtrim(string(z)));
h = NaN;
if strlength(z) == 0, return, end
if startsWith(z,["P","AMERICA/LOS_ANGELES"]),                    h = 0;
elseif startsWith(z,["M","AMERICA/DENVER","AMERICA/PHOENIX"]),   h = 1;
elseif startsWith(z,["C","AMERICA/CHICAGO"]),                    h = 2;
elseif startsWith(z,["E","AMERICA/NEW_YORK"]),                   h = 3;
end
end