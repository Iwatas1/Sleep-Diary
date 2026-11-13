# Sleep-Diary

MATLAB pipelines that turn HowRU app sleep diary submissions (morning and evening diaries) into
cleaned, analysis-ready tables. They include automatic fixes for mis-entered bed/wake times, the
merge of manual RA (research assistant) corrections, and deidentified Excel outputs.

No participant data is stored in this repository. Paths are placeholders, so set `file_path` to
your local data folder before running anything.

## Folders

| Folder | Study | Notes |
|---|---|---|
| `PSF/` | ongoing study | RA checking is still in progress; the code also refreshes the RA workbook each run |
| `K08/` | completed study | RA checks are final; the RA workbook is only read |
| `T1D/` | multi-time-zone study | morning diary pipeline with time zone handling and device comparison |
| `legacy/` | — | original single-script version, kept for reference |

Each study folder is self-contained (put the folder on the MATLAB path / in `Sleep_diary\codes`).

## Pipeline

```
select_dataset        newest Dataset_<MM.dd.yyyy> export in Raw_Data (K08 also merges a "missing" export)
select_studysheet     newest study sheet (SID, StudyWeek, Date, Day, ...)
sorting_SD / update_q decode the JSON submissions into morning / evening / "forgot" tables
EMA_to_sleep_diary_morning
   match diaries to study days (latest submission wins on duplicates)
   fix_sleep_inputs + switch rules    automatic AM/PM and bed/wake swap fixes
   apply_RA_fix (PSF) / apply_RA_fix_K08 (K08)   overwrite with RA-revised times
   12 h rule
   bed_time_comparison_<study>         Garmin / Muse vs sleep diary (see Time zones)
   weekly averages, std, z-score, residual, midpoint
EMA_to_sleep_diary_evening
   match diaries to study days, nap AM/PM fixes, long + wide tables
just_sleep_diary.m    driver script (converted from the live script; outputs removed)
```

### Automatic fixes
Bed and wake times are rebuilt on the diary date (bed on the night before). Impossible
durations are corrected with a few fixed rules: add 24 h to a bedtime after midnight, take 12 h
off a PM wake time, and swap bed and wake when they were entered in each other's fields. Every
change is logged in `Sleep_diary_morning_modification_details.xlsx`.

### RA corrections
RAs check the times by hand in a workbook in `SleepDiaryDataCheck` (newest `.xlsx` is used).

- A row counts as RA-revised only if the RA's CLEANED value differs from the RAW value they were
  given (HH:mm). Only the changed field (bed and/or wake) is replaced.
- The full datetime is rebuilt from the pipeline's diary date: wake = diary date + time;
  bed = night before + time if it's 12:00 or later, otherwise the diary date.
- Sleep duration and every variable derived from bed/wake time are recalculated afterwards.
- Every applied change is listed in `Sleep_diary_morning_RA_fix_log.xlsx`.

**PSF (ongoing).** `SW# RAW_<MMddyyyy>` / `SW# CLEANED_<MMddyyyy>` sheets. Each run:
1. Applies the RA edits, compared against `Sleep_diary\RA_check_snapshot.mat`. That file records
   what each RA was given, so keep it.
2. Overwrites the RAW sheets with the current pipeline output and renames them to today's date.
   Renaming uses Excel through `actxserver`, so it needs Windows with Excel installed.
3. Appends rows that aren't in CLEANED yet. Existing RA rows are never changed.
4. Makes a backup in `SleepDiaryDataCheck\ARCHIVE` first, and skips the update if the file is
   open in Excel.

**K08 (completed).** Wide sheets (`SW# RAW`/`SW# CLEANED` and a later batch `NEW SW#` /
`NEW SW# CLEANED`, columns suffixed `_2`–`_8`). For SID-weeks in both batches the `NEW` version
is used. The workbook is read only.

## Time zones and device check

The app saves the true moment of a typed time, and the pipeline shows it in Pacific time (PST).
For participants in another zone, local = PST + offset (MST 1, CST 2, EST 3).

- `add_local_time_<study>.m` reads the time zone sheet (`SID`, zone code) and shifts bed/wake to
  local time **before** the automatic fixes, so their clock-hour rules work on the participant's
  own clock. It adds `time_zone` and `offset_h`. Blank zones are treated as PST.
- PSF switches back to PST before the RA fix (the RA workbook is in PST), then adds
  `first_sleep_local` / `get_out_of_bed_local`.
- `bed_time_comparison_<study>.m` pulls Garmin sleep summary times and Muse `_ss` times, converts
  their unix timestamps to the participant's zone, and compares them with the device's own clock
  (`GARMIN_/MUSE_mismatch_30min/1hr`) and with diary local vs diary PST (`*_diary_closer`).
  - Garmin: sleep = `unixTimestampInMs`, wake = sleep + `durationInMs` + `awakeDurationInMs`,
    matched on `calendarDate` (the wake-up morning).
  - Muse: largest `_ss` file per night, W epochs removed; bed/wake = first/last sleep epoch.
    Nights are matched on the local wake-up date. Older files without a `timestamps` column are
    rebuilt from the file name + `times` and left out of the device clock check.
- `calc_clock` (per night) is `pst` only when every device with a 1-hr flag says diary PST is
  closer; otherwise `local`. Midpoint, `ave_bedtime_local` and `ave_waketime_local` use that clock.
- PSF also writes `RA_timezone_check`: RA-revised nights for non-PST participants, with
  `RA_entered_local = 1` when a device suggests the RA typed local time into the PST column.
- The PSF RA workbook gets `time_zone` and `offset_h` columns after `SID` (times stay PST).
  Existing CLEANED sheets get the columns inserted through Excel, so RA edits and formatting stay.
- K08 treats everyone as PST, so it runs the device comparison only.

Extra sheets in `Sleep_diary_morning_long.xlsx`: `sleep_comparison`, `MUSE_off`, `GARMIN_off`
(and `RA_timezone_check` for PSF). These keep full dates and unix timestamps.

## Deidentification

Files that stay on the lab server may keep full dates. In PSF, set `DEID = true` in
`EMA_to_sleep_diary_morning.m` (or run `deidentify_output.m` on a copy) before sharing anything
outside the lab. `deidentify_output.m` does:

| Column | Output |
|---|---|
| Unix timestamps (`started_at`, `finished_at`, `first_sleep`, `get_out_of_bed`, `nap_start`, `nap_end`, any ms-epoch column) | removed |
| birth date, burst day, age in days | removed |
| bed / wake / nap / midpoint times | `HH:mm` (00–23) |
| `Date` and other dates | `yyyy-MM` |

The PSF RA workbook follows the same rules. The one exception is the `Date` column of the
`SW# RAW_<date>` / `SW# CLEANED_<date>` sheets, which keeps `yyyy-MM-dd` so RAs can check days.
`.mat` files and in-memory tables keep full datetimes for the analyst steps; don't share them.

## Outputs (per study, in `Sleep_diary\`)

- `Sleep_diary_morning_long.xlsx`, `Sleep_diary_morning_wide.xlsx`
- `Sleep_diary_morning_modification_details.xlsx`, `Sleep_diary_morning_RA_fix_log.xlsx`
- `Sleep_diary_evening_long.xlsx`, `Sleep_diary_evening_wide.xlsx`,
  `Sleep_diary_evening_modification_details.xlsx`
- `<Study> master data.xlsx`, sheets `Sleep Diary Morning` and `Sleep Diary Evening`

Morning Day 1 (no night before it) is removed from the morning outputs. Evening Day 8 (K08) or
Day 5 (PSF long output) is removed from the evening outputs.

## Requirements

MATLAB R2020a or newer (`writetable` `WriteMode`, `readcell`, string functions). Renaming the
PSF RAW sheets needs Excel on Windows.
