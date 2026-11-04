function [copy,modify_t] = fix_sleep_inputs(copy,modify_t,study_sd,additional_message)
E = copy(copy.sleep_duration_in_mins > 23*60,:);
bed = hour(E.first_sleep_pst);
E{bed<6,"first_sleep_pst"} = E{bed<6,"first_sleep_pst"} + hours(24);
E{bed<6,"sleep_duration"} = E{bed<6,"sleep_duration"} - hours(24);
E{bed<6,"sleep_duration_in_mins"} = E{bed<6,"sleep_duration_in_mins"} - 24*60;
B = E(bed<6,1:width(study_sd));
B.modification_details = repelem(append(additional_message,"added 24hrs on bed time and subtracted 24 hrs from sleep duration"),height(B),1);
modify_t = [modify_t ; B];
copy(copy.sleep_duration_in_mins > 23*60,:) = E;
E = copy(copy.sleep_duration_in_mins > 720,:);
wake = hour(E.get_out_of_bed_pst);
E{wake>15,"get_out_of_bed_pst"} = E{wake>15,"get_out_of_bed_pst"} - hours(12);
E{wake>15,"sleep_duration"} = E{wake>15,"sleep_duration"} - hours(12);
E{wake>15,"sleep_duration_in_mins"} = E{wake>15,"sleep_duration_in_mins"} - 12*60;
B = E(wake>15,1:width(study_sd));
B.modification_details = repelem(append(additional_message,"subtracted 12hrs from wake time and sleep duration"),height(B),1);
modify_t = [modify_t ; B];
copy(copy.sleep_duration_in_mins > 720,:) = E;

E = copy(copy.sleep_duration_in_mins > 720,:);
bed = hour(E.first_sleep_pst);
E{and(bed<17,bed>4),"first_sleep_pst"} = E{and(bed<17,bed>4),"first_sleep_pst"} + hours(12);
E{and(bed<17,bed>4),"sleep_duration"} = E{and(bed<17,bed>4),"sleep_duration"} - hours(12);
E{and(bed<17,bed>4),"sleep_duration_in_mins"} = E{and(bed<17,bed>4),"sleep_duration_in_mins"} - 12*60;
B = E(and(bed<17,bed>4),1:width(study_sd));
B.modification_details = repelem(append(additional_message,"added 12hrs on bed time and subtracted sleep duration"),height(B),1);
modify_t = [modify_t ; B];
copy(copy.sleep_duration_in_mins > 720,:) = E;
end

