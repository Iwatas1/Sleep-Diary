function [T_6,T_7,T_9,T_10,T_22,T_30,TIME] = sorting_EMA(current_T)
format long g
current_T.user = string(extractAfter(current_T.user,"_"));
EMA_morning = table;
EMA_evening = table;
EMA_on_mind = table;
forget_evening = table;
forget_morning = table;
EMA = table;
TIME = table;
for i = 1:height(current_T)
    assigned = false;
    json = current_T{i,'data'}{1};
    struct = jsondecode(json);
    struct_data = struct.data;
    struct_meta = struct.metadata;
    row_data = struct2table(struct_data,"AsArray", true);
    row_meta = struct2table(struct_meta,"AsArray",true);
    row_meta(:,'page_advances') = [];
    row = horzcat(current_T(i,"user"), row_data, row_meta);
    t = row(:,["user","started_at","finished_at"]);
    col_names = row.Properties.VariableNames;
    
    if sum(contains(col_names,"where_EMA_morning")) >= 1
        EMA_morning = update_q(EMA_morning,row,col_names);
        t.task = "EMA_morning";
        assigned = true;
    elseif sum(contains(col_names,"where_EMA_evening")) >= 1
        EMA_evening = update_q_2(EMA_evening,row,col_names);
        t.task = "EMA_evening";
        assigned = true;
    elseif sum(contains(col_names,"where_EMA")) >= 1
        EMA= update_q(EMA,row,col_names);
        t.task = "EMA_midday";
        assigned = true;
    elseif sum(contains(col_names,"stable_mood")) >= 1
        forget_evening = update_q(forget_evening,row,col_names);
        t.task = "EMA_evening";
        assigned = true;
    elseif sum(contains(col_names,"get_out_of_bed")) >= 1
        forget_morning = update_q(forget_morning,row,col_names);
        t.task = "EMA_morning";
        assigned = true;
    end
    if assigned == true
        TIME = [TIME;t];
    end

    if i == height(current_T)
        disp("done sorting")
        %output
        T_6 = EMA_morning;
        T_7 = EMA_evening;
        T_9 = forget_evening;
        T_10 = forget_morning;
        T_22 = EMA_on_mind;
        T_30 = EMA;
    end
    %{
    if assigned == false
        disp("unknown data")
        row
        break;
    end
    %}
    
end
end