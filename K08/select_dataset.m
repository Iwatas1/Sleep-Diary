function y = select_dataset(file_path)
data_path = append(file_path,"\Raw_Data");
file_names = string({dir(data_path).name});
datasets = file_names(contains(file_names,"Dataset_"));
missing_data = datasets(contains(datasets,"missing"));
missing_data(~contains(missing_data,".mat")) = [];
miss_T = load(append(data_path,"\",missing_data));
miss_T = miss_T.y;
datasets(contains(datasets,"missing")) = [];
if isscalar(datasets)
    ind = 1;
else
    num_pat = extract(datasets,digitsPattern);
    ds = datetime(append(num_pat(:,:,1),"-",num_pat(:,:,2),"-",num_pat(:,:,3)),"InputFormat","MM-dd-uuuu");
    ind = find(ds == max(ds));
    if length(ind) > 1
        ind = max(ind);
    end
end
if contains(datasets(ind),".mat")
    m = load(append(data_path,"\",datasets(ind)));
    y = m.y;
    y = vertcat(y,miss_T);
else
    y = readtable(append(data_path,"\",datasets(ind)));
    y = vertcat(y,miss_T);
    datasets(ind) = [];
    for i = 1:length(datasets)
        if contains(datasets(i),".mat")
            delete(append(data_path,"\",datasets(i)));
        else
            movefile(append(data_path,"\",datasets(i)),append(data_path,"\archive"));
        end
    end
    save(append(data_path,"\Dataset_",string(datetime("today","format","MM.dd.yyyy")),".mat"),"y");
end
end