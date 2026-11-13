function T = update_q(EMA_evening,row,col_names)
if width(EMA_evening) == 0
    EMA_evening = row;
elseif sum(length(setdiff(col_names,EMA_evening.Properties.VariableNames))) > 0 || sum(length(setdiff(EMA_evening.Properties.VariableNames,col_names))) > 0
    if sum(length(setdiff(col_names,EMA_evening.Properties.VariableNames))) > 0
        miss_cols = setdiff(col_names,EMA_evening.Properties.VariableNames);
        match_cols = matches(col_names,EMA_evening.Properties.VariableNames);
        match_cols = EMA_evening(1,col_names(match_cols)).Properties.VariableNames;
        %EMA_morning = vertcat(EMA_morning,row(1,match_cols));
        EMA_evening(end+1,:)  = EMA_evening(end,:);
        EMA_evening(end,match_cols) = row(1,match_cols);
        for j = 1:length(miss_cols)
            EMA_evening{end,miss_cols{j}} = row{1,miss_cols{j}};
        end
    else
        miss_cols = setdiff(EMA_evening.Properties.VariableNames,col_names);
        match_cols = matches(col_names,EMA_evening.Properties.VariableNames);
        match_cols = EMA_evening(1,col_names(match_cols)).Properties.VariableNames;
        EMA_evening(end+1,:)  = EMA_evening(end,:);
        EMA_evening(end,match_cols) = row(1,match_cols);
        for j = 1:length(miss_cols)
            if class(EMA_evening{end,miss_cols{j}}) == "cell"
                EMA_evening{end,miss_cols{j}}{1} = {};
            elseif class(EMA_evening{end,miss_cols{j}}) == "string"
                EMA_evening{end,miss_cols{j}} = string(missing);
            elseif class(EMA_evening{end,miss_cols{j}}) == "double"
                EMA_evening{end,miss_cols{j}} = nan;
            end
        end
    end
else
    EMA_evening = vertcat(EMA_evening,row);
end
T = EMA_evening;
end