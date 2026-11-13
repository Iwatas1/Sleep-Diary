function z = select_dataset(file_path)
data_path = append(file_path,"\Raw_Data");
file_names = string({dir(data_path).name});
datasets = file_names(contains(file_names,"Dataset_adult"));
if isscalar(datasets)
    ind = 1;
else
    num_pat = extract(datasets,digitsPattern);
    ds = datetime(append(num_pat(:,:,1),"-",num_pat(:,:,2),"-",num_pat(:,:,3)),"InputFormat","MM-dd-uuuu");
    ind = find(ds == max(ds));
end
if sum(contains(datasets(ind),".mat"))>0
    if length(ind) ~= 1
        ind_0 = find(contains(datasets(ind),".mat"));
    else
        ind_0 = 1;
    end
    m = load(append(data_path,"\",datasets(ind(ind_0))));
    y = m.y;
else
    y = readtable(append(data_path,"\",datasets(ind)));
    datasets(ind) = [];
    for i = 1:length(datasets)
        if contains(datasets(i),".mat")
            delete(append(data_path,"\",datasets(i)));
        else
            movefile(append(data_path,"\",datasets(i)),append(data_path,"\archive"));
        end
    end
    save(append(data_path,"\Dataset_adult_",string(datetime("today","format","MM.dd.yyyy")),".mat"),"y");
end
datasets = file_names(contains(file_names,"Dataset_peds"));
if isscalar(datasets)
    ind = 1;
else
    num_pat = extract(datasets,digitsPattern);
    ds = datetime(append(num_pat(:,:,1),"-",num_pat(:,:,2),"-",num_pat(:,:,3)),"InputFormat","MM-dd-uuuu");
    ind = find(ds == max(ds));
end
if sum(contains(datasets(ind),".mat"))>0
    if length(ind) ~= 1
        ind_0 = find(contains(datasets(ind),".mat"));
    else
        ind_0 = 1;
    end
    m = load(append(data_path,"\",datasets(ind(ind_0))));
    x = m.x;
else
    x = readtable(append(data_path,"\",datasets(ind)));
    datasets(ind) = [];
    for i = 1:length(datasets)
        if contains(datasets(i),".mat")
            delete(append(data_path,"\",datasets(i)));
        else
            movefile(append(data_path,"\",datasets(i)),append(data_path,"\archive"));
        end
    end
    save(append(data_path,"\Dataset_peds_",string(datetime("today","format","MM.dd.yyyy")),".mat"),"x");
end
z = [x;y];
end