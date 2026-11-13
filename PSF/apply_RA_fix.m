function [copy,ra_log] = apply_RA_fix(copy,file_path,update_workbook)
% APPLY_RA_FIX  Apply the RA (undergrad) checked bed/wake times, then refresh
%               the (deidentified) RA workbook so the next RA sees the latest data.
%
%   [copy,ra_log] = apply_RA_fix(copy,file_path)
%   [copy,ra_log] = apply_RA_fix(copy,file_path,false)   % apply only, don't touch the workbook
%
%   COPY is the morning sleep diary table AFTER the automatic fixes.
%
%   DEIDENTIFICATION of the RA workbook (every sheet):
%     * Date                                   -> "yyyy-MM-dd" in SW# RAW_<date> and SW# CLEANED_<date>
%                                                sheets (so RAs can check days); in existing CLEANED
%                                                sheets ONLY the Date cells are rewritten (RA edits kept)
%     * Burst_Day_ and any other date          -> year-month text "yyyy-MM"
%     * *_pst, bed_midpoint, durations          -> 24-hour time text "HH:mm"
%     * started_at, finished_at, first_sleep, get_out_of_bed (Unix timestamps) -> removed
%   Any sheet still holding full dates is converted automatically (an identified
%   copy is kept in <file_path>\Sleep_diary\RA_workbook_identified_backup, and
%   old *_backup_* files in SleepDiaryDataCheck\ARCHIVE are deleted).
%   RA notes are free text and are NOT edited; notes containing a date are warned about.
%
%   Because the sheets only hold HH:mm, the full datetime is rebuilt from the
%   pipeline's diary Date when an RA edit is applied:
%     wake = diary date + time
%     bed  = night before + time  if time >= 12:00, otherwise diary date + time
%   (checked against the first round of RA edits: every edited time is rebuilt exactly).
%
%   Step 1 - RA workbook: newest .xlsx in <file_path>\SleepDiaryDataCheck. Per study
%            week, the newest "SW# CLEANED_<MMddyyyy>" sheet is the RA-revised data.
%   Step 2 - snapshot of the times each RA was given:
%            <file_path>\Sleep_diary\RA_check_snapshot.mat (DO NOT DELETE).
%   Step 3 - a row is RA-revised only if CLEANED time ~= snapshot time (bed or wake,
%            HH:mm). Only the changed field is written into COPY (matched on SID,
%            StudyWeek, Day; year-month checked) and sleep duration is recalculated.
%   Step 4 - refresh the workbook (deidentified backup to SleepDiaryDataCheck\ARCHIVE
%            first; skipped with a warning if the file is open in Excel):
%            * SW# RAW sheet: overwritten with today's pipeline output (after
%              auto-fixes, before RA fixes), renamed "SW# RAW_<today>".
%            * SW# CLEANED sheet: existing rows are NEVER changed; rows not in it
%              yet are appended at the bottom for the RA to check.
%            * a study week with no sheets yet gets new RAW/CLEANED sheets.
%
%   RA_LOG (also <file_path>\Sleep_diary\Sleep_diary_morning_RA_fix_log.xlsx, analyst
%   only - it has full dates) lists every RA-revised row. Status:
%     "applied"            RA value written; pipeline still matches the snapshot
%     "applied - check"    RA value written, but today's pipeline time differs from
%                          what the RA was given (data/auto-fix changed) -> review
%     "not applied - ..."  row not found / year-month mismatch / duplicate

if nargin < 3, update_workbook = true; end
pre_RA = copy;                     % pipeline output before RA fixes (goes to RAW / new CLEANED rows)
ra_log = table;
key = ["SID","StudyWeek","Day"];
snap_file = fullfile(file_path,'Sleep_diary','RA_check_snapshot.mat');

% ---- Step 1: RA workbook and sheets ---------------------------------------
ra_dir = fullfile(file_path,'SleepDiaryDataCheck');
files = dir(fullfile(ra_dir,'*.xlsx'));
files(startsWith({files.name},'~$')) = [];          % Excel lock files
if isempty(files)
    warning('apply_RA_fix: no RA file found in %s. RA fix skipped.',ra_dir);
    return
end
[~,k] = max([files.datenum]);
ra_file = fullfile(ra_dir,files(k).name);
if numel(files) > 1
    warning('apply_RA_fix: %d .xlsx files in %s. Using newest: %s',numel(files),ra_dir,files(k).name);
end
fprintf('apply_RA_fix: using %s\n',files(k).name);
info = sheet_info(ra_file);
SW_clean = unique(info.SW(info.kind == "CLEANED")).';

% ---- Step 2: snapshot of what the RA was given (minutes after midnight) ---
if isfile(snap_file)
    S = load(snap_file,'snap');  snap = S.snap;
    if ismember("raw_bed",string(snap.Properties.VariableNames))     % older snapshot (full datetimes)
        snap.raw_bed_min  = dt_to_min(snap.raw_bed);
        snap.raw_wake_min = dt_to_min(snap.raw_wake);
        snap = snap(:,[key "raw_bed_min" "raw_wake_min"]);
    end
else
    fprintf('apply_RA_fix: no snapshot yet, building it from the SW# RAW_<date> sheets.\n');
    snap = table('Size',[0 5],'VariableTypes',repmat("double",1,5), ...
        'VariableNames',[key "raw_bed_min" "raw_wake_min"]);
    for w = SW_clean
        c = newest(info,w,"CLEANED");
        r = info(info.SW == w & info.kind == "RAW" & info.sheet_date == c.sheet_date,:);
        if isempty(r)
            warning('apply_RA_fix: no "SW%d RAW_%s" sheet to pair with "%s"; SW%d has no snapshot.', ...
                w,string(c.sheet_date,'MMddyyyy'),c.sheet,w);
            continue
        end
        R = read_ra_sheet(ra_file,r.name(1));
        R = renamevars(R(:,[key "bed_min" "wake_min"]),["bed_min","wake_min"],["raw_bed_min","raw_wake_min"]);
        snap = [snap ; R]; %#ok<AGROW>
    end
    snap = unique_keys(snap,key);
    save(snap_file,'snap');
end

% ---- Step 3: find RA edits and apply them ---------------------------------
rows = {};
for w = SW_clean
    c = newest(info,w,"CLEANED");
    C = read_ra_sheet(ra_file,c.name(1));
    C = renamevars(C,["bed_min","wake_min"],["ra_bed_min","ra_wake_min"]);
    J = innerjoin(snap(snap.StudyWeek == w,:),C,'Keys',key);
    n_missing = height(C) - height(J);
    if n_missing > 0
        warning('apply_RA_fix: %d row(s) in "%s" have no snapshot entry and are treated as unchecked.',n_missing,c.sheet);
    end
    bed_chg  = min_differs(J.raw_bed_min, J.ra_bed_min);
    wake_chg = min_differs(J.raw_wake_min,J.ra_wake_min);
    J = J(bed_chg | wake_chg,:);
    J.bed_chg  = bed_chg(bed_chg | wake_chg);
    J.wake_chg = wake_chg(bed_chg | wake_chg);
    J.RA_sheet = repelem(c.sheet,height(J),1);
    rows{end+1} = J; %#ok<AGROW>
    dated = C(contains(C.Notes,digitsPattern(1,2) + "/" + digitsPattern(1,2) + "/" + digitsPattern(2,4)) | ...
              contains(C.Notes,digitsPattern(4) + "-" + digitsPattern(2) + "-" + digitsPattern(2)),key);
    if height(dated) > 0
        warning('apply_RA_fix: %d RA note(s) in "%s" contain a full date - please edit them by hand: %s', ...
            height(dated),c.sheet,strjoin("SID " + dated.SID + " Day " + dated.Day,", "));
    end
end
if ~isempty(rows), J = vertcat(rows{:}); else, J = table; end

n = height(J);
status    = strings(n,1);  field     = strings(n,1);
pipe_bed  = NaT(n,1);      pipe_wake = NaT(n,1);
new_bed   = NaT(n,1);      new_wake  = NaT(n,1);
old_dur   = nan(n,1);      new_dur   = nan(n,1);
field_names = ["bed","wake"];
for i = 1:n
    idx = find(copy.SID == J.SID(i) & copy.StudyWeek == J.StudyWeek(i) & copy.Day == J.Day(i));
    field(i) = strjoin(field_names([J.bed_chg(i) J.wake_chg(i)])," + ");
    if isempty(idx)
        status(i) = "not applied - row not in pipeline output";  continue
    elseif numel(idx) > 1
        status(i) = "not applied - duplicate row in pipeline output";  continue
    elseif strlength(J.Date_ym(i)) > 0 && J.Date_ym(i) ~= string(copy.Date(idx),'yyyy-MM')
        status(i) = "not applied - year-month mismatch (pipeline " + string(copy.Date(idx),'yyyy-MM') + ")";  continue
    end
    D = dateshift(copy.Date(idx),'start','day');               % diary (morning) date
    pipe_bed(i)  = copy.first_sleep_pst(idx);
    pipe_wake(i) = copy.get_out_of_bed_pst(idx);
    old_dur(i)   = copy.sleep_duration_in_mins(idx);
    same_as_snapshot = true;
    if J.bed_chg(i)
        same_as_snapshot = same_as_snapshot && ~min_differs(dt_to_min(pipe_bed(i)),J.raw_bed_min(i));
        copy.first_sleep_pst(idx) = rebuild_bed(D,J.ra_bed_min(i));
    end
    if J.wake_chg(i)
        same_as_snapshot = same_as_snapshot && ~min_differs(dt_to_min(pipe_wake(i)),J.raw_wake_min(i));
        copy.get_out_of_bed_pst(idx) = D + minutes(J.ra_wake_min(i));   % NaN minutes -> NaT
    end
    copy.sleep_duration(idx) = copy.get_out_of_bed_pst(idx) - copy.first_sleep_pst(idx) ...
        - minutes(copy.fall_asleep_minutes(idx)) - minutes(copy.minutes_up_night(idx));
    copy.sleep_duration_in_mins(idx) = minutes(copy.sleep_duration(idx));
    new_bed(i)  = copy.first_sleep_pst(idx);
    new_wake(i) = copy.get_out_of_bed_pst(idx);
    new_dur(i)  = copy.sleep_duration_in_mins(idx);
    if same_as_snapshot, status(i) = "applied"; else, status(i) = "applied - check"; end
end
if n > 0
    ra_log = table(J.SID,J.StudyWeek,J.Day,field, ...
        pipe_bed,min_to_hhmm(J.raw_bed_min),min_to_hhmm(J.ra_bed_min),new_bed, ...
        pipe_wake,min_to_hhmm(J.raw_wake_min),min_to_hhmm(J.ra_wake_min),new_wake, ...
        old_dur,new_dur,status,J.FirstCheck,J.Notes, ...
        J.RA_sheet,repelem(string(files(k).name),n,1), ...
        'VariableNames',["SID","StudyWeek","Day","changed", ...
        "pipeline_bed","RA_given_bed","RA_bed","final_bed", ...
        "pipeline_wake","RA_given_wake","RA_wake","final_wake", ...
        "old_sleep_duration_in_mins","new_sleep_duration_in_mins","status", ...
        "RA_checker","RA_note","RA_sheet","RA_file"]);
    ra_log = sortrows(ra_log,key);
    writetable(deidentify_output(ra_log),fullfile(file_path,'Sleep_diary','Sleep_diary_morning_RA_fix_log.xlsx'),'WriteMode','replacefile');
end
fprintf('apply_RA_fix: %d RA-revised rows -> %d applied (%d need a look), %d not applied\n', ...
    n,sum(startsWith(status,"applied")),sum(status == "applied - check"),sum(startsWith(status,"not")));

% ---- Step 4: refresh the workbook for the next RA -------------------------
if ~update_workbook, return, end
fid = fopen(ra_file,'a');
if fid == -1
    warning('apply_RA_fix: "%s" is open/locked (close it in Excel). RA fixes were applied, but the workbook was NOT updated.',files(k).name);
    return
end
fclose(fid);
[~,nm,ext] = fileparts(ra_file);
stamp = string(datetime('now'),'yyyyMMdd_HHmmss');

% 4a. deidentify any sheet that still holds full dates / timestamps
deidentify_workbook(ra_file,ra_dir,file_path,nm,ext,stamp);

% 4b. deidentified backup of the current state
arch = fullfile(ra_dir,'ARCHIVE');
if ~isfolder(arch), mkdir(arch); end
copyfile(ra_file,fullfile(arch,nm + "_backup_" + stamp + ext));

raw_tmpl   = template_cols(ra_file,info,"RAW");
clean_tmpl = template_cols(ra_file,info,"CLEANED");
today_tag  = string(datetime('today'),'MMddyyyy');
SW_pipe = unique(pre_RA.StudyWeek(~isnan(pre_RA.StudyWeek))).';
% time zone shown to the RA (times stay PST; local = PST + offset_h)
has_tz = all(ismember(["time_zone","offset_h"],string(pre_RA.Properties.VariableNames)));
if has_tz
    tz_map = unique(pre_RA(~isnan(pre_RA.SID),["SID","time_zone","offset_h"]),'rows','stable');
else
    warning('apply_RA_fix: no time_zone/offset_h in the diary table - RA sheets get no time zone info.');
end
n_added = 0;
rename_from = strings(1,0);  rename_to = strings(1,0);
for w = SW_pipe
    P = sortrows(pre_RA(pre_RA.StudyWeek == w,:),["SID","Day"]);

    % RAW: overwrite with today's pipeline output (deidentified)
    r = info(info.SW == w & info.kind == "RAW",:);
    if isempty(r)
        raw_name = "SW" + w + " RAW_" + today_tag;  raw_cols = raw_tmpl;
    else
        r = r(r.sheet_date == max(r.sheet_date),:);
        raw_name = r.name(1);  raw_cols = sheet_cols(ra_file,raw_name);
    end
    if has_tz, raw_cols = add_tz_cols(raw_cols); end
    writecell(to_sheet_cells(P,raw_cols,true),ra_file,'Sheet',raw_name,'WriteMode','overwritesheet');
    if strtrim(raw_name) ~= "SW" + w + " RAW_" + today_tag      % rename to today's date after all writes
        rename_from(end+1) = raw_name;  rename_to(end+1) = "SW" + w + " RAW_" + today_tag; %#ok<AGROW>
    end

    % CLEANED: keep existing rows, append rows not in it yet (deidentified)
    c = info(info.SW == w & info.kind == "CLEANED",:);
    if isempty(c)
        new_rows = P;
        clean_cols = clean_tmpl;
        if has_tz, clean_cols = add_tz_cols(clean_cols); end
        writecell(to_sheet_cells(new_rows,clean_cols,true),ra_file,'Sheet',"SW" + w + " CLEANED_" + today_tag);
    else
        c = c(c.sheet_date == max(c.sheet_date),:);
        if has_tz, insert_tz_into_sheet(ra_file,c.name(1),tz_map); end   % existing RA rows unchanged, only columns added
        fill_full_dates(ra_file,c.name(1),P);       % Date column only -> yyyy-MM-dd
        C = read_ra_sheet(ra_file,c.name(1));
        new_rows = P(~ismember(P(:,key),C(:,key)),:);
        if height(new_rows) > 0
            last_row = size(readcell(ra_file,'Sheet',c.name(1)),1);
            cells = to_sheet_cells(new_rows,sheet_cols(ra_file,c.name(1)),true);
            writecell(cells(2:end,:),ra_file,'Sheet',c.name(1),'Range',char("A" + (last_row + 1)));
        end
    end
    if height(new_rows) > 0
        add = new_rows(:,key);
        add.raw_bed_min  = dt_to_min(new_rows.first_sleep_pst);
        add.raw_wake_min = dt_to_min(new_rows.get_out_of_bed_pst);
        snap = unique_keys([snap ; add],key);
        n_added = n_added + height(new_rows);
        fprintf('apply_RA_fix: SW%d -> appended %d new row(s) (%d SID(s)) for the RA to check\n', ...
            w,height(new_rows),numel(unique(new_rows.SID)));
    end
end
save(snap_file,'snap');
rename_sheets(ra_file,rename_from,rename_to);
fprintf('apply_RA_fix: workbook updated (RAW overwritten, %d new CLEANED row(s)); backup in ARCHIVE\n',n_added);
end

% =========================================================================
%  Deidentification
% =========================================================================
function deidentify_workbook(ra_file,ra_dir,file_path,nm,ext,stamp)
% Convert every sheet that still contains identifying dates/timestamps.
names = string(sheetnames(ra_file));
todo = false(size(names));
cells = cell(size(names));
is_raw = ~cellfun(@isempty,regexp(cellstr(strtrim(names)),'^SW\d+\s+(RAW|CLEANED)_\d{8}$','once','ignorecase'));   % these keep Date as yyyy-MM-dd
for i = 1:numel(names)
    cells{i} = readcell(ra_file,'Sheet',names(i));
    todo(i) = is_identified(cells{i},is_raw(i));
end
if ~any(todo), return, end

% identified copy goes OUTSIDE the RA folder, then old identified backups are removed
safe_dir = fullfile(file_path,'Sleep_diary','RA_workbook_identified_backup');
if ~isfolder(safe_dir), mkdir(safe_dir); end
copyfile(ra_file,fullfile(safe_dir,nm + "_identified_" + stamp + ext));
for i = find(todo(:)).'
    writecell(deid_cells(cells{i},is_raw(i)),ra_file,'Sheet',names(i),'WriteMode','overwritesheet');
    fprintf('apply_RA_fix: deidentified sheet "%s"\n',names(i));
end
old = dir(fullfile(ra_dir,'ARCHIVE','*_backup_*.xlsx'));
for i = 1:numel(old)
    delete(fullfile(old(i).folder,old(i).name));
end
if ~isempty(old)
    fprintf('apply_RA_fix: deleted %d old backup(s) with full dates from ARCHIVE\n',numel(old));
end
other = dir(fullfile(ra_dir,'ARCHIVE','*.xls*'));
if ~isempty(other)
    warning('apply_RA_fix: ARCHIVE still has %d older RA file(s) that may contain full dates (not touched): %s', ...
        numel(other),strjoin(string({other.name}),', '));
end
end

function tf = is_identified(C,full_date)
% true if the sheet has a removable timestamp column or a full date where it isn't allowed
% (FULL_DATE = true: the Date column may hold yyyy-MM-dd, as in SW# RAW / CLEANED sheets)
tf = false;
if isempty(C), return, end
[remove,~,is_date,is_day] = col_kinds(C(1,:));
if any(remove), tf = true; return, end
for j = 1:size(C,2)
    if full_date && is_day(j), continue, end
    for i = 2:size(C,1)
        x = C{i,j};
        if isdatetime(x) && ~isnat(x) && year(x) >= 1900, tf = true; return, end
        if is_date(j) && (ischar(x) || isstring(x)) && ...                 % full date typed/copied as text
                matches(strtrim(string(x)),digitsPattern(4) + "-" + digitsPattern(2) + "-" + digitsPattern(2))
            tf = true; return
        end
    end
end
end

function C = deid_cells(C,full_date)
% C: cell array, row 1 = header. Returns a deidentified copy.
% FULL_DATE = true -> the Date column is written as yyyy-MM-dd (SW# RAW / CLEANED sheets)
[remove,is_time,is_date,is_day] = col_kinds(C(1,:));
for j = 1:size(C,2)
    if remove(j), continue, end
    for i = 2:size(C,1)
        C{i,j} = deid_value(C{i,j},is_time(j),is_date(j),full_date && is_day(j));
    end
end
for j = 1:size(C,2)                                   % header: no missing values
    if ~(ischar(C{1,j}) || isstring(C{1,j})), C{1,j} = ''; end
end
C(:,remove) = [];
end

function [remove,is_time,is_date,is_day] = col_kinds(hdr)
h = strings(1,numel(hdr));
for j = 1:numel(hdr)
    if ischar(hdr{j}) || isstring(hdr{j}), h(j) = string(hdr{j}); end
end
base = lower(regexprep(strtrim(h),'_\d+$',''));         % wide sheets: first_sleep_pst_2 -> first_sleep_pst
remove  = ismember(base,["started_at","finished_at","first_sleep","get_out_of_bed"]);
is_time = endsWith(base,"_pst") | ismember(base,["bed_midpoint","sleep_duration", ...
          "ave_sleep_duration","ave_bedtime","ave_waketime"]);
is_date = ismember(base,["date","burst_day_"]);
is_day  = base == "date";                             % the only column allowed a full date
end

function y = deid_value(x,is_time,is_date,full_date)
if full_date && is_date, dfmt = 'yyyy-MM-dd'; else, dfmt = 'yyyy-MM'; end   % date columns
y = x;
if isa(x,'missing') || isempty(x) || iscell(x) || (isstring(x) && any(ismissing(x)))
    y = '';
elseif isdatetime(x)
    if isnat(x),                         y = '';
    elseif is_time || year(x) < 1900,    y = char(min_to_hhmm(dt_to_min(x)));   % time-only cell
    elseif is_date,                      y = char(string(x,dfmt));               % Date column
    else,                                y = char(string(x,'yyyy-MM'));          % any other date -> year-month
    end
elseif isduration(x)
    if isnan(x), y = ''; else, y = char(string(x,'hh:mm')); end
elseif isnumeric(x) || islogical(x)
    x = double(x);
    if isnan(x),                   y = '';
    elseif is_time && x >= 0,      y = char(min_to_hhmm(mod(round(mod(x,1)*1440),1440)));  % Excel time/serial
    elseif is_date && x > 20000,   y = char(string(datetime(x,'ConvertFrom','excel'),dfmt));
    else,                          y = x;
    end
elseif ischar(x) || isstring(x)
    s = strtrim(string(x));
    if is_time
        m = text_to_min(s);
        if ~isnan(m), y = char(min_to_hhmm(m)); else, y = char(s); end
    elseif is_date && strlength(s) > 0 && ~matches(s,digitsPattern(4) + "-" + digitsPattern(2))
        try,   y = char(string(datetime(s),dfmt));
        catch, y = char(s);
        end
    else
        y = char(s);
    end
end
end

function C = to_sheet_cells(src,cols,full_date)
% table -> deidentified cell array in the sheet's column layout (row 1 = header)
T = match_columns(src,cols);
C = [cellstr(cols) ; table2cell(T)];
C = deid_cells(C,full_date);
end

function fill_full_dates(f,s,P)
% Rewrite ONLY the Date column of an existing RA sheet as yyyy-MM-dd, using the
% pipeline's diary date for that SID / StudyWeek / Day. Every other cell (RA edits,
% notes, formatting) is left untouched. A cell is changed only if it is empty or its
% year-month agrees with the pipeline; disagreements are warned about and kept.
C = readcell(f,'Sheet',s);
if size(C,1) < 2, return, end
hdr = strings(1,size(C,2));
for j = 1:size(C,2)
    if ischar(C{1,j}) || isstring(C{1,j}), hdr(j) = string(C{1,j}); end
end
hdr = string(matlab.lang.makeValidName(strtrim(hdr)));
dc = find(hdr == "Date",1);  sc = find(hdr == "SID",1);  wc = find(hdr == "StudyWeek",1);  yc = find(hdr == "Day",1);
if isempty(dc) || isempty(sc) || isempty(wc) || isempty(yc), return, end
out = cell(size(C,1)-1,1);
changed = 0;  conflict = strings(0,1);
for r = 2:size(C,1)
    old = C{r,dc};
    if isa(old,'missing'), old = ''; end
    out{r-1} = old;
    sid = cell_num(C{r,sc});  sw = cell_num(C{r,wc});  d = cell_num(C{r,yc});
    idx = find(P.SID == sid & P.StudyWeek == sw & P.Day == d,1);
    if isnan(sid) || isempty(idx) || isnat(P.Date(idx)), continue, end
    full = char(string(P.Date(idx),'yyyy-MM-dd'));
    ym = cell_ym(old);
    if strlength(ym) > 0 && ym ~= string(P.Date(idx),'yyyy-MM')
        conflict(end+1) = "SID " + sid + " Day " + d; %#ok<AGROW>
        continue
    end
    if ~isequal(old,full), out{r-1} = full; changed = changed + 1; end
end
if changed > 0
    writecell(out,f,'Sheet',s,'Range',[col_letter(dc) '2']);     % only the Date column
    fprintf('apply_RA_fix: "%s" -> %d Date cell(s) set to yyyy-MM-dd\n',strtrim(s),changed);
end
if ~isempty(conflict)
    warning('apply_RA_fix: "%s": Date year-month differs from the pipeline, left as is: %s',strtrim(s),strjoin(conflict,", "));
end
end

function L = col_letter(n)
% Excel column letter(s) for column number n (1 -> A, 27 -> AA)
L = '';
while n > 0
    r = mod(n-1,26);
    L = [char(65 + r) L]; %#ok<AGROW>
    n = floor((n-1)/26);
end
end

% =========================================================================
%  Reading RA sheets
% =========================================================================
function T = read_ra_sheet(f,s)
% SID, StudyWeek, Day, Date_ym, bed_min, wake_min (minutes after midnight), FirstCheck, Notes
C = readcell(f,'Sheet',s);
hdr = strings(1,size(C,2));
for j = 1:size(C,2)
    if ischar(C{1,j}) || isstring(C{1,j}), hdr(j) = string(C{1,j}); end
end
hdr = string(matlab.lang.makeValidName(strtrim(hdr)));
need = ["SID","StudyWeek","Day","first_sleep_pst","get_out_of_bed_pst"];
if ~all(ismember(need,hdr))
    error('apply_RA_fix: sheet "%s" is missing column(s): %s',s,strjoin(setdiff(need,hdr),', '));
end
D = C(2:end,:);
col = @(name) find(hdr == name,1);
T = table;
T.SID       = cellfun(@cell_num,D(:,col("SID")));
T.StudyWeek = cellfun(@cell_num,D(:,col("StudyWeek")));
T.Day       = cellfun(@cell_num,D(:,col("Day")));
if ismember("Date",hdr), T.Date_ym = cell_strs(@cell_ym,D(:,col("Date"))); else, T.Date_ym = strings(height(T),1); end
T.bed_min   = cellfun(@cell_min,D(:,col("first_sleep_pst")));
T.wake_min  = cellfun(@cell_min,D(:,col("get_out_of_bed_pst")));
if ismember("FirstCheck",hdr), T.FirstCheck = cell_strs(@cell_txt,D(:,col("FirstCheck"))); else, T.FirstCheck = strings(height(T),1); end
if ismember("Notes",hdr),      T.Notes      = cell_strs(@cell_txt,D(:,col("Notes")));      else, T.Notes      = strings(height(T),1); end
T(isnan(T.SID),:) = [];
end

function s = cell_strs(fun,X)
% apply FUN (returns a string scalar) to each cell -> string column
s = strings(numel(X),1);
for i = 1:numel(X), s(i) = fun(X{i}); end
end

function v = cell_num(x)
v = NaN;
if isnumeric(x) && isscalar(x), v = double(x);
elseif ischar(x) || isstring(x), v = str2double(x);
end
end

function s = cell_txt(x)
s = "";
if (ischar(x) || isstring(x)) && ~any(ismissing(string(x))), s = string(x);
elseif isnumeric(x) && isscalar(x) && ~isnan(x), s = string(x);
end
end

function s = cell_ym(x)
s = "";
if isdatetime(x) && ~isnat(x), s = string(x,'yyyy-MM');
elseif isnumeric(x) && isscalar(x) && x > 20000, s = string(datetime(x,'ConvertFrom','excel'),'yyyy-MM');
elseif ischar(x) || isstring(x)
    t = strtrim(string(x));
    if matches(t,digitsPattern(4) + "-" + digitsPattern(2)), s = t;
    elseif strlength(t) > 0
        try, s = string(datetime(t),'yyyy-MM'); catch, end
    end
end
end

function m = cell_min(x)
% minutes after midnight from whatever is in the cell (HH:mm text, Excel time, legacy datetime)
m = NaN;
if isdatetime(x)
    m = dt_to_min(x);
elseif isduration(x)
    if ~isnan(x), m = mod(round(minutes(x)),1440); end
elseif isnumeric(x) && isscalar(x) && ~isnan(x) && x >= 0
    m = mod(round(mod(x,1)*1440),1440);
elseif ischar(x) || isstring(x)
    m = text_to_min(string(x));
end
end

function m = text_to_min(s)
% "21:44", "9:44", "21:44:00", "9:44 PM", "2024-08-21 21:44:00" -> minutes after midnight
m = NaN;
tk = regexp(s,'(\d{1,2}):(\d{2})','tokens','once');
if isempty(tk), return, end
h = str2double(tk(1));  mi = str2double(tk(2));
if contains(upper(s),"PM") && h < 12, h = h + 12; end
if contains(upper(s),"AM") && h == 12, h = 0; end
if h <= 23 && mi <= 59, m = h*60 + mi; end
end

% =========================================================================
%  Time helpers
% =========================================================================
function m = dt_to_min(t)
m = hour(t)*60 + minute(t);          % NaT -> NaN
end

function s = min_to_hhmm(m)
s = strings(size(m));
ok = ~isnan(m);
s(ok) = compose("%02d:%02d",floor(m(ok)/60),mod(m(ok),60));
end

function d = min_differs(a,b)
% true where two minute-of-day values differ (NaN == NaN counts as equal)
d = ~((a == b) | (isnan(a) & isnan(b)));
end

function t = rebuild_bed(D,m)
% bed time from HH:mm: 12:00-23:59 -> night before the diary date; 00:00-11:59 -> diary date
if isnan(m)
    t = NaT;
elseif m >= 12*60
    t = D - days(1) + minutes(m);
else
    t = D + minutes(m);
end
end

% =========================================================================
%  Sheet helpers
% =========================================================================
function info = sheet_info(f)
% sheet name, study week, RAW/CLEANED, date in the sheet name
names = string(sheetnames(f));
info = table('Size',[0 5],'VariableTypes',["string","string","double","string","datetime"], ...
    'VariableNames',["name","sheet","SW","kind","sheet_date"]);
for i = 1:numel(names)
    tk = regexp(strtrim(names(i)),'^SW(\d+)\s+(RAW|CLEANED)_(\d{8})$','tokens','once','ignorecase');
    if isempty(tk), continue, end
    info(end+1,:) = {names(i),strtrim(names(i)),str2double(tk(1)),upper(tk(2)), ...
        datetime(tk(3),'InputFormat','MMddyyyy')}; %#ok<AGROW>
end
end

function c = newest(info,w,kind)
c = info(info.SW == w & info.kind == kind,:);
c = c(find(c.sheet_date == max(c.sheet_date),1),:);
end

function cols = sheet_cols(f,s)
% header row of a sheet exactly as written in Excel (e.g. "First Check")
C = readcell(f,'Sheet',s);
cols = strings(1,size(C,2));
for j = 1:size(C,2)
    if ischar(C{1,j}) || isstring(C{1,j}), cols(j) = string(C{1,j}); end
end
end

function cols = template_cols(f,info,kind)
% column layout for a brand-new sheet: copied from an existing sheet of that kind
t = info(info.kind == kind,:);
if isempty(t)
    cols = strings(1,0);
else
    t = t(find(t.sheet_date == max(t.sheet_date),1),:);
    cols = sheet_cols(f,t.name(1));
end
end

function out = match_columns(src,cols)
% put SRC in the sheet's column order; columns the pipeline doesn't have
% (First Check, Notes, ...) are left blank; extra pipeline columns
% (e.g. birth date) are NOT written
if isempty(cols), error('apply_RA_fix: no template sheet to copy the column layout from.'); end
n = height(src);
src_names = string(src.Properties.VariableNames);
out = src(:,[]);                                  % n x 0 table
valid = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(cols));
for j = 1:numel(cols)
    v = char(valid(j));
    if ismember(v,src_names)
        out.(v) = src.(v);
    else
        out.(v) = strings(n,1);
    end
end
end

function cols = add_tz_cols(cols)
% put time_zone and offset_h right after SID if the layout doesn't have them yet
cols = cols(~ismember(cols,["time_zone","offset_h"]));
k = find(strtrim(cols) == "SID",1);
if isempty(k), k = 0; end
cols = [cols(1:k) "time_zone" "offset_h" cols(k+1:end)];
end

function insert_tz_into_sheet(f,s,tz_map)
% add time_zone / offset_h columns (after SID) to an existing CLEANED sheet.
% Uses Excel to INSERT the columns, so RA edits, notes and cell formatting/highlights
% stay as they are. Needs Windows + Excel; otherwise skipped with a warning.
C = readcell(f,'Sheet',s);
if isempty(C), return, end
hdr = strings(1,size(C,2));
for j = 1:size(C,2)
    if ischar(C{1,j}) || isstring(C{1,j}), hdr(j) = strtrim(string(C{1,j})); end
end
if any(hdr == "time_zone"), return, end
k = find(hdr == "SID",1);
if isempty(k), warning('apply_RA_fix: no SID column in "%s"; time zone not added.',s); return, end
n = size(C,1);
vals = cell(n,2);  vals(:) = {''};
vals(1,:) = {'time_zone','offset_h'};
for i = 2:n
    r = find(tz_map.SID == cell_num(C{i,k}),1);
    if ~isempty(r)
        vals{i,1} = char(tz_map.time_zone(r));
        if ~isnan(tz_map.offset_h(r)), vals{i,2} = tz_map.offset_h(r); end
    end
end
try
    excel = actxserver('Excel.Application');
catch
    warning('apply_RA_fix: Excel not available - time zone columns NOT added to "%s".',s);
    return
end
cleanup = onCleanup(@() quit_excel(excel)); %#ok<NASGU>
excel.DisplayAlerts = false;
try
    wb = excel.Workbooks.Open(char(f));
    ws = wb.Worksheets.Item(char(s));
    col = col_letter(k+1);
    ws.Range([col ':' col_letter(k+2)]).EntireColumn.Insert;          % shift columns right
    ws.Range(sprintf('%s1:%s%d',col,col_letter(k+2),n)).Value = vals;
    wb.Save;
    wb.Close(false);
    fprintf('apply_RA_fix: added time_zone/offset_h to "%s"\n',s);
catch ME
    warning('apply_RA_fix: adding time zone to "%s" failed (%s).',s,ME.message);
end
end

function T = unique_keys(T,key)
% keep the first entry per SID/StudyWeek/Day (what the RA was first given)
if isempty(T), return, end
[~,ia] = unique(T(:,key),'stable');
T = T(ia,:);
end

function rename_sheets(f,old_names,new_names)
% Rename sheets through Excel (writecell can't rename). Needs Windows + Excel;
% if Excel isn't available the data is still written, only the name stays old.
if isempty(old_names), return, end
try
    excel = actxserver('Excel.Application');
catch
    warning('apply_RA_fix: Excel not available, RAW sheets keep their old names (data is already updated).');
    return
end
cleanup = onCleanup(@() quit_excel(excel)); %#ok<NASGU>
excel.DisplayAlerts = false;
try
    wb = excel.Workbooks.Open(char(f));
    sheets_com = wb.Worksheets;
    existing = strings(1,sheets_com.Count);
    for i = 1:sheets_com.Count
        ws = sheets_com.Item(i);
        existing(i) = string(ws.Name);
    end
    for i = 1:numel(old_names)
        if ismember(new_names(i),strtrim(existing))
            warning('apply_RA_fix: a sheet named "%s" already exists; "%s" not renamed.',new_names(i),old_names(i));
            continue
        end
        ws = sheets_com.Item(char(old_names(i)));
        ws.Name = char(new_names(i));
        fprintf('apply_RA_fix: renamed "%s" -> "%s"\n',strtrim(old_names(i)),new_names(i));
    end
    wb.Save;
    wb.Close(false);
catch ME
    warning('apply_RA_fix: renaming RAW sheets failed (%s). Data is updated; names unchanged.',ME.message);
end
end

function quit_excel(excel)
try, excel.Quit; catch, end
try, delete(excel); catch, end
end
