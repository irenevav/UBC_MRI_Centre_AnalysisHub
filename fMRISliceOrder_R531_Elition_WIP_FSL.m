%% ************************************************************************
%%
%% Provides the acquisition slice order for an FFE-EPI fMRI sequence
%%
%% Validated for R5.3.1, assumes 1 package
%%
%% Guillaume Gilbert
%% Philips Healthcare Canada
%% 2017,2018
%%
%%
%% Bug fix 2018-12-05: MB-SENSE with default ordering
%% Bug fix 2019-05-21: MB-SENSE with default ordering and odd number of slices per package
%% Bug fix 2020-10-13: MB-SENSE=1 special case handling
%% ELM Added details 2022-04-20: UBC Specific Details Added & Now Saves Slice Timing Text File
%% Justin W. Andrushko 2023-04-02: Added relative slice timing information specific for FSL slicetimer
%% Justin W. Andrushko 2023-04-03: Added automation to getting sequence information
%% ************************************************************************
clear all;


%% ************************************************************************
%% INPUT YOUR SEQUENCE PARAMETERS HERE
% Slices=51; % UBC Details: VBRAIN single echo has 62 slices. VBRAIN ME has 51 slices.
% MB_SENSE='yes';
% MB_SENSE_factor=3;
% Actual_TR = 2000; % TR in ms; VBRAIN TR = 2000 ms
Slice_scan_order='default';  %Options: default, FH, HF, rev. central, interleaved
Enhanced_dyn_stab = 'yes'; % When dynamic stabilization is set to enhanced, an 
        % EPI phase navigator is acquired prior to the first slice in each dynamic (or frame)
        % so the first readout is not a slice of fMRI data
%% ************************************************************************
%% Automation of extracting sequence information
% If you do not have the json files and named the same as the nifi, please
% comment this section out and revert to manual inputs above.

[file,path] = uigetfile({'*.nii.gz';'*.nii'},'Select the file you wish to extract slice timing information from');
fullFileNameNifti = fullfile(path, file);

% Determine if nifti is zipped or not and remove file extension accordingly
if contains(file,'.nii.gz')
    [filepath,name,ext] = fileparts(fullFileNameNifti);
    [filepath2,name,ext2] = fileparts(name);
else
    [filepath,name,ext] = fileparts(fullFileNameNifti); 
end

% generate path and filename for json file
jsonname = append(name,'.json');
fullFileNameJson = fullfile(path, jsonname);

% Get nifti metadata / header information
info = niftiinfo(fullfile(path, file));

% Get slice number from nifi header
Slices = info.ImageSize(3);

% Get TR from nifti header
Actual_TR = info.PixelDimensions(4);

% setup and read json file
fid = fopen(fullFileNameJson); 
raw = fread(fid,inf); 
str = char(raw'); 
fclose(fid); 
jsonfile = jsondecode(str);

% Determine if data are acquired with multiband
if jsonfile.ParallelAcquisitionTechnique == 'MBSENSE'
    MB_SENSE='yes';
else
    MB_SENSE='no';
end

% get multiband factor from json
MB_SENSE_factor = jsonfile.ParallelReductionOutOfPlane;

%% ************************************************************************
%We first perform a sanity check
if (mod(Slices,MB_SENSE_factor)~=0 && strcmp(MB_SENSE,'yes'))
    error('These parameters are impossible')
end

Slice_order=[];
%FH
if (strcmp(Slice_scan_order,'FH'))
    
    if ((strcmp(MB_SENSE,'yes')) && (MB_SENSE_factor >1))
        
        Slices_per_band=Slices/MB_SENSE_factor;
        for k=1:MB_SENSE_factor
            Slice_order(k,:)=[Slices_per_band*(k-1):1:Slices_per_band*(k-1)+(Slices_per_band)-1];
        end
    else
        
        Slice_order=[0:1:Slices-1];
        
    end
    
    
    %HF
elseif (strcmp(Slice_scan_order,'HF'))
    if ((strcmp(MB_SENSE,'yes')) && (MB_SENSE_factor >1))
        
        Slices_per_band=Slices/MB_SENSE_factor;
        for k=1:MB_SENSE_factor
            Slice_order(k,:)=[Slices_per_band*(k-1)+(Slices_per_band)-1:-1:Slices_per_band*(k-1)];
        end
    else
        
        Slice_order=[Slices-1:-1:0];
        
    end
    
    %rev. central
elseif (strcmp(Slice_scan_order,'rev. central'))
    if ((strcmp(MB_SENSE,'yes')) && (MB_SENSE_factor >1))
        
        Slices_per_band=Slices/MB_SENSE_factor;
        for k=1:MB_SENSE_factor
            up=[Slices_per_band*(k-1):1:Slices_per_band*(k-1)+floor((Slices_per_band-1)/2)];
            down=[Slices_per_band*(k-1)+Slices_per_band-1:-1:Slices_per_band*(k-1)+ceil((Slices_per_band)/2)];
            Slice_order(k,1:2:Slices_per_band)=up;
            Slice_order(k,2:2:Slices_per_band)=down;
        end
    else
        up=[0:1:floor((Slices-1)/2)];
        down=[Slices-1:-1:ceil((Slices)/2)];
        Slice_order(1:2:Slices)=up;
        Slice_order(2:2:Slices)=down;
        
    end
    
    %interleaved
elseif (strcmp(Slice_scan_order,'interleaved'))
    if ((strcmp(MB_SENSE,'yes')) && (MB_SENSE_factor >1))
        
        Slices_per_band=Slices/MB_SENSE_factor;
        SliceGroup=1;
        temp_order=1;
        step=round(sqrt(double(Slices_per_band)));
        for k=2:Slices_per_band
            
            current=temp_order(k-1)+step;
            if (current>Slices_per_band)
                SliceGroup=SliceGroup+1;
                current=SliceGroup;
            end
            temp_order=[temp_order current];
        end
        for k=1:MB_SENSE_factor
            Slice_order(k,:)=(temp_order-1)+(k-1)*Slices_per_band;
        end
    else
        SliceGroup=1;
        Slice_order=1;
        step=round(sqrt(double(Slices)));
        for k=2:Slices
            
            current=Slice_order(k-1)+step;
            if (current>Slices)
                SliceGroup=SliceGroup+1;
                current=SliceGroup;
            end
            Slice_order=[Slice_order current];
        end
        Slice_order=Slice_order-1;
    end
    
    %default
elseif (strcmp(Slice_scan_order,'default'))
    if ((strcmp(MB_SENSE,'yes')) && (MB_SENSE_factor >1))
        
        Slices_per_band=Slices/MB_SENSE_factor;
        % The are a few special cases to consider here
        if (Slices_per_band<=6)
             step=2;
                temp_order=zeros(1,Slices_per_band);
                half_locs_per_package=(Slices_per_band+1)/step;
                low_part_start_loc=0;
                low_part_act_loc=low_part_start_loc;
                high_part_start_loc=Slices_per_band-1;
                high_part_act_loc=high_part_start_loc;
                order=1;
                
                for(ii=0:Slices_per_band)
                    
                    if (low_part_act_loc<half_locs_per_package-1)
                        temp_order(order)=low_part_act_loc;
                        low_part_act_loc=low_part_act_loc+step;
                        order=order+1;
                    elseif (high_part_act_loc>=half_locs_per_package-1)
                        temp_order(order)=high_part_act_loc;
                        high_part_act_loc=high_part_act_loc-step;
                        order=order+1;
                    else
                        low_part_act_loc=low_part_start_loc+1;
                        high_part_act_loc=high_part_start_loc-1;
                    end
                    
                end
                temp_order=temp_order+1;
        elseif (Slices_per_band==8)
            factor=1;
            SliceGroup=1;
            temp_order=1;
            step=round(sqrt(double(Slices_per_band)));
            for k=2:Slices_per_band
                
                current=temp_order(k-1)+step;
                if (current>Slices_per_band)
                    SliceGroup=SliceGroup+1;
                    current=SliceGroup;
                end
                temp_order=[temp_order current];
            end
        else
            if (mod(Slices_per_band,2)==0)
                step=2;
                temp_order=zeros(1,Slices_per_band);
                half_locs_per_package=(Slices_per_band+1)/step;
                low_part_start_loc=0;
                low_part_act_loc=low_part_start_loc;
                high_part_start_loc=Slices_per_band-1;
                high_part_act_loc=high_part_start_loc;
                order=1; 
                
                
                for(ii=0:Slices_per_band)
                    
                    if (low_part_act_loc<half_locs_per_package-1) 
                        temp_order(order)=low_part_act_loc;
                        low_part_act_loc=low_part_act_loc+step;
                        order=order+1;
                    elseif (high_part_act_loc>=half_locs_per_package-1) 
                        temp_order(order)=high_part_act_loc;
                        high_part_act_loc=high_part_act_loc-step;
                        order=order+1;
                    else
                        low_part_act_loc=low_part_start_loc+1;
                        high_part_act_loc=high_part_start_loc-1;
                    end
                    
                end
                temp_order=temp_order+1;
            else
                part1=[0:2:(Slices_per_band-1)];
                part2=[1:2:(Slices_per_band-1)];
                temp_order=cat(2,part1,part2);
                temp_order=temp_order+1; % Bug fix 2019-05-31
            end
        end
        
        for k=1:MB_SENSE_factor
            Slice_order(k,:)=(temp_order-1)+(k-1)*Slices_per_band;
        end
    else
        part1=[0:2:(Slices-1)];
        part2=[1:2:(Slices-1)];
        Slice_order=cat(2,part1,part2);
    end
    
end
display(Slice_order)

%% ************************************************************************
% Convert the slice order file into relative timings for FSL with 
%      no shift slice == 0 within a range of -0.5 - + 0.5
%**************************************************************************

% Make first index 1 not 0
slice_order_index_at_1 = Slice_order+1;
band1 = slice_order_index_at_1(1,:);

% Find the middle index
middleIndex = max(slice_order_index_at_1(1,:))/2;
middleIndex = round(middleIndex);

% Set the middle number to 0
no_shift = 0;

% Convert slice order values to distance from middleIndex
diffs = abs(band1 - middleIndex);

% Set slice spacing relative to 1 TR
slice_spacing = 1/length(band1);

% For loop to convert values to relative TR shifts
for i = 1:length(diffs)
    if band1(i) <  middleIndex
        fsl_slice_timing_file_single_band(i) = no_shift + (diffs(i) * slice_spacing);
    elseif band1(i) == middleIndex
        fsl_slice_timing_file_single_band(i) = 0;
    elseif band1(i) >  middleIndex
        fsl_slice_timing_file_single_band(i) = no_shift - (diffs(i) * slice_spacing);
    end  
end

% Takes the timing information for the first band and replicates it for
% each MB factor and combines it into 1 long column.
fsl_slice_timing_file = repmat(fsl_slice_timing_file_single_band, 1, MB_SENSE_factor)';

fileID = fopen(['fMRISliceTimes_R531_Elition_for_FSL_' num2str(Slices, '%d') 'Sl_MB' num2str(MB_SENSE_factor, '%d') '.txt'],'w');
fprintf(fileID, '%0.4f\n', fsl_slice_timing_file);
fclose(fileID)
%%

% fileID = fopen(['fMRISliceTimes_R531_Elition_' num2str(Slices, '%d') 'Sl_MB' num2str(MB_SENSE_factor, '%d') '.txt'],'w');
% fprintf(fileID, '%0.4f\n', fsl_slice_timing_file);
% fclose(fileID)