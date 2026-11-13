function copy = add_local_time_PSF(copy,file_path)
% ADD_LOCAL_TIME_PSF  Shift diary bed/wake from Pacific (PST) to the participant's LOCAL time.
%
%   copy = add_local_time_PSF(copy,file_path)
%
%   PSF version of add_local_time_T1D (Nov 2026 rule): phone_tz_check is NOT used.
%   The pipeline shows Pacific time for everyone, so  local = PST + offset_h.
%   Participants whose phone was actually on Pacific are caught later by the
%   device comparison (bed_time_comparison_PSF -> *_diary_closer / calc_clock).
%
%   In : first_sleep_pst / get_out_of_bed_pst = Pacific (as converted by the lab PC)
%   Out: first_sleep_pst / get_out_of_bed_pst = LOCAL (in place, so the clock-hour
%        rules in the mis-input fixes run on the participant's own clock)
%        + time_zone ("PST"/"MST"/"CST"/"EST"), offset_h (hours ahead of Pacific)
%   After the fixes: PST = local - offset_h  (offset_h NaN -> left as shown)
%
%   Zones: newest "PSF Timezone*.xlsx" in <file_path>\Studysheet (columns SID, Timezone)

n = height(copy);
copy.time_zone = strings(n,1);
copy.offset_h  = nan(n,1);

zdir = fullfile(file_path,'Studysheet');
zf = dir(fullfile(zdir,'PSF Timezone*.xlsx'));
zf = zf(~startsWith({zf.name},'~'));
if isempty(zf)
    warning('add_local_time_PSF: no "PSF Timezone*.xlsx" in %s - everyone treated as PST.',zdir);
    copy.time_zone(:) = "PST"; copy.offset_h(:) = 0;
    return
end
[~,newest] = max([zf.datenum]);
Z = readtable(fullfile(zdir,zf(newest).name));
Z.SID = double(string(Z.SID));
Z.Timezone = upper(strtrim(string(Z.Timezone)));

SIDs = unique(copy.SID(~isnan(copy.SID)));
missing = [];
for s = SIDs(:)'
    rows = copy.SID == s;
    z = Z.Timezone(Z.SID == s);
    if isempty(z) || strlength(z(1)) == 0, missing(end+1) = s; continue, end %#ok<AGROW>
    z = z(1);
    off = zone_offset(z);
    copy.time_zone(rows) = z;
    copy.offset_h(rows)  = off;
    if isnan(off) || off == 0, continue, end
    copy.first_sleep_pst(rows)    = copy.first_sleep_pst(rows)    + hours(off);
    copy.get_out_of_bed_pst(rows) = copy.get_out_of_bed_pst(rows) + hours(off);
end
if ~isempty(missing)
    warning('add_local_time_PSF: no time zone for SID(s) %s - local time not computed.',strjoin(string(missing),", "));
end
fprintf('add_local_time_PSF: %s used; %d non-Pacific participant(s) shifted to local\n', ...
    zf(newest).name, numel(unique(copy.SID(copy.offset_h > 0))));
end

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
