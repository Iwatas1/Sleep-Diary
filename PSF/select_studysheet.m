function y = select_studysheet(file_path)
ss_path = append(file_path,"\Studysheet");
file_names = string({dir(ss_path).name});
ss = file_names(contains(file_names,"StudySheet"));
ss(contains(ss,"~")) = [];
if isscalar(ss)
    ind = 1;
    y = readtable(append(ss_path,"\",ss(ind)));
else
    num_pat = extract(ss,digitsPattern);
    ds = datetime(append(num_pat(:,:,1),"-",num_pat(:,:,2),"-",num_pat(:,:,3)),"inputformat","MM-dd-uuuu");
    ind = find(ds == max(ds));
    y = readtable(append(ss_path,"\",ss(ind)));
    ss(ind) = [];
    for i = 1:length(ss)
        movefile(append(ss_path,"\",ss(i)),append(ss_path,"\","ARCHIVE"));
    end
end
y(isnat(y.Date),:) = [];
end