function T = update_q_2(EMA_evening,row,col_names)
copy = EMA_evening;
try
    copy = [copy;row];
catch
    cols = copy.Properties.VariableNames;
    if sum(~ismember(col_names,cols))>0
        missing = col_names(~ismember(col_names,cols));
        for i = 1:length(missing)
            copy{end+1,missing(i)} = row{1,missing(i)};
        end
        copy(end,col_names) = row;
    else
        copy(end+1,col_names) = row;
    end
end
T = copy;
end

