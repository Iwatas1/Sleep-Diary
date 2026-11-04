function [copy,ra_log] = apply_RA_fix_K08(copy,file_path)
% APPLY_RA_FIX_K08  Apply the FINAL RA-checked bed/wake times (K08, study completed).
%
%   [copy,ra_log] = apply_RA_fix_K08(copy,file_path)
%
%   COPY is the morning sleep diary table AFTER the automatic fixes.
%   The RA workbook is only READ (newest .xlsx in <file_path>\SleepDiaryDataCheck,
%   e.g. "NEW K08SleepDiaryCleaning_08112026.xlsx"); nothing is written to it.
%
%   Sheets (wide: one row per SID x StudyWeek, columns suffixed _2 ... _8 = Day):
%     "SW# RAW"  / "SW# CLEANED"          first batch the RAs checked
%     "NEW SW#"  / "NEW SW# CLEANED"      later batch; for any SID-week that is in
%                                         both, the NEW version wins
%
%   A row gets the RA value only if the RA changed it (CLEANED ~= RAW, compared
%   as HH:mm). Rows in CLEANED with no RAW row take the CLEANED value wherever it
%   differs from the pipeline. Only the changed field (bed and/or wake) is replaced.
%
%   The RAs often fixed the time but not the date, so the full datetime is rebuilt
%   from the pipeline's diary Date (the morning of the diary):
%     wake = diary date + time
%     bed  = night before + time  if time >= 12:00, otherwise diary date + time
%   sleep_duration / sleep_duration_in_mins are then recalculated.
%
%   RA_LOG (deidentified) -> <file_path>\Sleep_diary\Sleep_diary_morning_RA_fix_log.xlsx
%     "applied"                      RA edit applied; pipeline matched the RAW sheet
%     "applied - check"              RA edit applied; today's pipeline differs from RAW
%     "applied - no RAW row"         row only in CLEANED; CLEANED value used
%     "not applied - ..."            row not in pipeline / duplicate

ra_log = table;
key = ["SID","StudyWeek","Day"];

% ---- RA workbook ----------------------------------------------------------
ra_dir = fullfile(file_path,'SleepDiaryDataCheck');
files = dir(fullfile(ra_dir,'*.xlsx'));
files(startsWith({files.name},'~$')) = [];
if isempty(files)
    warning('apply_RA_fix_K08: no RA file found in %s. RA fix skipped.',ra_dir);
    return
end
[~,k] = max([files.datenum]);
ra_file = fullfile(ra_dir,files(k).name);
if numel(files) > 1
    warning('apply_RA_fix_K08: %d .xlsx files in %s. Using newest: %s',numel(files),ra_dir,files(k).name);
end
fprintf('apply_RA_fix_K08: using %s\n',files(k).name);

names = string(sheetnames(ra_file));
info = table('Size',[0 4],'VariableTypes',["string","string","double","string"], ...
    'VariableNames',["name","batch","SW","kind"]);
for i = 1:numel(names)
    tk = regexp(strtrim(names(i)),'^(NEW\s+)?SW(\d+)(\s+CLEANED)?$','tokens','once','ignorecase');
    if isempty(tk), continue, end
    batch = "orig";  if strlength(strtrim(tk(1))) > 0, batch = "NEW"; end
    kind  = "RAW";   if strlength(strtrim(tk(3))) > 0, kind  = "CLEANED"; end
    info(end+1,:) = {names(i),batch,str2double(tk(2)),kind}; %#ok<AGROW>
end

% ---- build the final CLEANED + matching RAW (NEW wins for its SID-weeks) ---
Cs = {};  Rs = {};
for w = unique(info.SW).'
    parts = struct();
    for b = ["orig","NEW"]
        for kd = ["RAW","CLEANED"]
            s = info.name(info.SW == w & info.batch == b & info.kind == kd);
            if isempty(s), parts.(b + "_" + kd) = table; else, parts.(b + "_" + kd) = read_wide(ra_file,s(1)); end
        end
    end
    oC = parts.orig_CLEANED;  oR = parts.orig_RAW;  nC = parts.NEW_CLEANED;  nR = parts.NEW_RAW;
    if ~isempty(nC)
        nk = unique(nC(:,["SID","StudyWeek"]));
        if ~isempty(oC), oC = oC(~ismember(oC(:,["SID","StudyWeek"]),nk),:); end
        if ~isempty(oR), oR = oR(~ismember(oR(:,["SID","StudyWeek"]),nk),:); end
        fprintf('apply_RA_fix_K08: SW%d -> %d SID-week(s) taken from NEW sheets\n',w,height(nk));
    end
    Cs = [Cs, {oC, nC}]; %#ok<AGROW>
    Rs = [Rs, {oR, nR}]; %#ok<AGROW>
end
C = vertcat(Cs{~cellfun(@isempty,Cs)});
R = vertcat(Rs{~cellfun(@isempty,Rs)});
[~,ia] = unique(C(:,key),'stable');
if numel(ia) < height(C)
    warning('apply_RA_fix_K08: %d duplicate SID/StudyWeek/Day row(s) in CLEANED sheets; first one kept.',height(C) - numel(ia));
end
C = C(ia,:);
[~,ia] = unique(R(:,key),'stable');  R = R(ia,:);

[has_raw,loc] = ismember(C(:,key),R(:,key));
C.raw_bed_min  = nan(height(C),1);  C.raw_wake_min = nan(height(C),1);
C.raw_bed_min(has_raw)  = R.bed_min(loc(has_raw));
C.raw_wake_min(has_raw) = R.wake_min(loc(has_raw));
C.bed_chg  = has_raw & min_differs(C.raw_bed_min, C.bed_min);
C.wake_chg = has_raw & min_differs(C.raw_wake_min,C.wake_min);
C.no_raw   = ~has_raw & (~isnan(C.bed_min) | ~isnan(C.wake_min));
J = C(C.bed_chg | C.wake_chg | C.no_raw,:);

% ---- apply ----------------------------------------------------------------
n = height(J);
status    = strings(n,1);  field     = strings(n,1);
pipe_bed  = NaT(n,1);      pipe_wake = NaT(n,1);
new_bed   = NaT(n,1);      new_wake  = NaT(n,1);
old_dur   = nan(n,1);      new_dur   = nan(n,1);
field_names = ["bed","wake"];
for i = 1:n
    idx = find(copy.SID == J.SID(i) & copy.StudyWeek == J.StudyWeek(i) & copy.Day == J.Day(i));
    if isempty(idx)
        status(i) = "not applied - row not in pipeline output";  continue
    elseif numel(idx) > 1
        status(i) = "not applied - duplicate row in pipeline output";  continue
    end
    D = dateshift(copy.Date(idx),'start','day');
    pipe_bed(i)  = copy.first_sleep_pst(idx);
    pipe_wake(i) = copy.get_out_of_bed_pst(idx);
    old_dur(i)   = copy.sleep_duration_in_mins(idx);
    if J.no_raw(i)          % no RAW row: use CLEANED wherever it differs from the pipeline
        do_bed  = min_differs(dt_to_min(pipe_bed(i)), J.bed_min(i));
        do_wake = min_differs(dt_to_min(pipe_wake(i)),J.wake_min(i));
        if ~(do_bed || do_wake), status(i) = "same as pipeline";  continue, end
        status(i) = "applied - no RAW row";
    else
        do_bed  = J.bed_chg(i);
        do_wake = J.wake_chg(i);
        same = (~do_bed  || ~min_differs(dt_to_min(pipe_bed(i)), J.raw_bed_min(i))) && ...
               (~do_wake || ~min_differs(dt_to_min(pipe_wake(i)),J.raw_wake_min(i)));
        if same, status(i) = "applied"; else, status(i) = "applied - check"; end
    end
    field(i) = strjoin(field_names([do_bed do_wake])," + ");
    if do_bed,  copy.first_sleep_pst(idx)    = rebuild_bed(D,J.bed_min(i));  end
    if do_wake, copy.get_out_of_bed_pst(idx) = D + minutes(J.wake_min(i));   end   % NaN -> NaT
    copy.sleep_duration(idx) = copy.get_out_of_bed_pst(idx) - copy.first_sleep_pst(idx) ...
        - minutes(copy.fall_asleep_minutes(idx)) - minutes(copy.minutes_up_night(idx));
    copy.sleep_duration_in_mins(idx) = minutes(copy.sleep_duration(idx));
    new_bed(i)  = copy.first_sleep_pst(idx);
    new_wake(i) = copy.get_out_of_bed_pst(idx);
    new_dur(i)  = copy.sleep_duration_in_mins(idx);
end
keep = status ~= "same as pipeline";
if n > 0
    ra_log = table(J.SID,J.StudyWeek,J.Day,field,J.batch, ...
        pipe_bed,min_to_hhmm(J.raw_bed_min),min_to_hhmm(J.bed_min),new_bed, ...
        pipe_wake,min_to_hhmm(J.raw_wake_min),min_to_hhmm(J.wake_min),new_wake, ...
        old_dur,new_dur,status,J.Checker,J.Note,J.sheet, ...
        'VariableNames',["SID","StudyWeek","Day","changed","RA_batch", ...
        "pipeline_bed","RA_raw_bed","RA_bed","final_bed", ...
        "pipeline_wake","RA_raw_wake","RA_wake","final_wake", ...
        "old_sleep_duration_in_mins","new_sleep_duration_in_mins","status", ...
        "RA_checker","RA_note","RA_sheet"]);
    ra_log = sortrows(ra_log(keep,:),key);
    writetable(deidentify_output(ra_log),fullfile(file_path,'Sleep_diary','Sleep_diary_morning_RA_fix_log.xlsx'),'WriteMode','replacefile');
end
fprintf('apply_RA_fix_K08: %d RA row(s) applied (%d need a look, %d from CLEANED without a RAW row), %d not applied\n', ...
    sum(startsWith(status,"applied")),sum(status == "applied - check"),sum(status == "applied - no RAW row"),sum(startsWith(status,"not")));
end

% =========================================================================
function L = read_wide(f,s)
% wide RA sheet -> long table: SID, StudyWeek, Day, bed_min, wake_min, Checker, Note, batch, sheet
C = readcell(f,'Sheet',s);
hdr = strings(1,size(C,2));
for j = 1:size(C,2)
    if ischar(C{1,j}) || isstring(C{1,j}), hdr(j) = strtrim(string(C{1,j})); end
end
lh = lower(hdr);
D = C(2:end,:);
nr = size(D,1);
chk = find(contains(lh,"check"));
checker = strings(nr,1);
for r = 1:nr
    v = strings(1,0);
    for j = chk, t = cell_txt(D{r,j}); if strlength(t) > 0, v(end+1) = t; end, end %#ok<AGROW>
    checker(r) = strjoin(v," | ");
end
pieces = cell(1,7);
for k = 2:8
    col = @(name) find(lh == lower(name),1);
    sidc = col("SID_" + k);  if isempty(sidc), sidc = col("SID"); end
    swc  = col("StudyWeek_" + k);
    dayc = col("Day_" + k);
    bedc = col("first_sleep_pst_" + k);
    wakc = col("get_out_of_bed_pst_" + k);
    notc = find(matches(lh,["notes_","note_","notes ","note ","notes"] + k),1);
    if isempty(sidc) || isempty(swc) || isempty(bedc) || isempty(wakc)
        error('apply_RA_fix_K08: sheet "%s" is missing SID/StudyWeek/first_sleep_pst/get_out_of_bed_pst for day %d',s,k);
    end
    T = table;
    T.SID       = num_col(D(:,sidc));
    T.StudyWeek = num_col(D(:,swc));
    if isempty(dayc), T.Day = repmat(k,nr,1); else, T.Day = num_col(D(:,dayc)); T.Day(isnan(T.Day)) = k; end
    T.bed_min   = min_col(D(:,bedc));
    T.wake_min  = min_col(D(:,wakc));
    T.Checker   = checker;
    if isempty(notc), T.Note = strings(nr,1); else, T.Note = txt_col(D(:,notc)); end
    pieces{k-1} = T;
end
L = vertcat(pieces{:});
L(isnan(L.SID) | isnan(L.StudyWeek),:) = [];
if startsWith(strtrim(s),"NEW",'IgnoreCase',true), b = "NEW"; else, b = "orig"; end
L.batch = repmat(b,height(L),1);
L.sheet = repmat(strtrim(s),height(L),1);
end

function v = num_col(X)
v = nan(numel(X),1);
for i = 1:numel(X)
    x = X{i};
    if isnumeric(x) && isscalar(x), v(i) = double(x);
    elseif ischar(x) || isstring(x), v(i) = str2double(x);
    end
end
end

function v = min_col(X)
v = nan(numel(X),1);
for i = 1:numel(X), v(i) = cell_min(X{i}); end
end

function v = txt_col(X)
v = strings(numel(X),1);
for i = 1:numel(X), v(i) = cell_txt(X{i}); end
end

function s = cell_txt(x)
s = "";
if (ischar(x) || isstring(x)) && ~any(ismissing(string(x))), s = strtrim(string(x));
elseif isnumeric(x) && isscalar(x) && ~isnan(x), s = string(x);
end
end

function m = cell_min(x)
% minutes after midnight from a cell (datetime, Excel time/serial, duration, or text)
m = NaN;
if isdatetime(x)
    m = dt_to_min(x);
elseif isduration(x)
    if ~isnan(x), m = mod(round(minutes(x)),1440); end
elseif isnumeric(x) && isscalar(x) && ~isnan(x) && x >= 0
    m = mod(round(mod(x,1)*1440),1440);
elseif ischar(x) || isstring(x)
    tk = regexp(string(x),'(\d{1,2}):(\d{2})','tokens','once');
    if ~isempty(tk)
        h = str2double(tk(1));  mi = str2double(tk(2));
        if contains(upper(string(x)),"PM") && h < 12, h = h + 12; end
        if contains(upper(string(x)),"AM") && h == 12, h = 0; end
        if h <= 23 && mi <= 59, m = h*60 + mi; end
    end
end
end

function m = dt_to_min(t)
m = hour(t)*60 + minute(t);          % NaT -> NaN
end

function s = min_to_hhmm(m)
s = strings(size(m));
ok = ~isnan(m);
s(ok) = compose("%02d:%02d",floor(m(ok)/60),mod(m(ok),60));
end

function d = min_differs(a,b)
d = ~((a == b) | (isnan(a) & isnan(b)));
end

function t = rebuild_bed(D,m)
% 12:00-23:59 -> night before the diary date; 00:00-11:59 -> diary date
if isnan(m)
    t = NaT;
elseif m >= 12*60
    t = D - days(1) + minutes(m);
else
    t = D + minutes(m);
end
end
