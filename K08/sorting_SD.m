

function [T_6,T_7,T_9,T_10,T_30] = sorting_SD(current_T)
format long g
current_T.user = string(extract(current_T.user,digitsPattern));
EMA_morning = table;
EMA_evening = table;
EMA_on_mind = table;
forget_evening = table;
forget_morning = table;
EMA = table;

for i = 1:height(current_T)
    
    try
        json = current_T{i,'data'}{1};
        struct = jsondecode(json);
        struct_data = struct.data;
        struct_meta = struct.metadata;
        row_data = struct2table(struct_data,"AsArray", true);
        row_meta = struct2table(struct_meta,"AsArray",true);
        row_meta(:,'page_advances') = [];
        row = horzcat(current_T(i,"user"), row_data, row_meta);
        col_names = row.Properties.VariableNames;
       
        if sum(contains(col_names,"where_EMA_morning")) >= 1
            EMA_morning = update_q(EMA_morning,row,col_names);

        elseif sum(contains(col_names,"where_EMA_evening")) >= 1
            EMA_evening = update_q(EMA_evening,row,col_names);

        elseif sum(contains(col_names,"ema_on_mind")) >= 1
            EMA_on_mind = update_q(EMA_on_mind,row,col_names);
  
        elseif sum(contains(col_names,"caffeinated_beverages")) >= 1
            forget_evening = update_q(forget_evening,row,col_names);

        elseif sum(contains(col_names,"get_out_of_bed")) >= 1
            forget_morning = update_q(forget_morning,row,col_names);
 
        elseif sum(matches(col_names,"where_EMA"))>=1
            EMA = update_q(EMA,row,col_names);

        end
    catch
    end
        T_6 = EMA_morning;
        T_7 = EMA_evening;
        T_9 = forget_evening;
        T_10 = forget_morning;
        T_30 = EMA_on_mind;
    %{
    if assigned == false
        disp("unknown data")
        row
        break;
    end
    %}
end
end