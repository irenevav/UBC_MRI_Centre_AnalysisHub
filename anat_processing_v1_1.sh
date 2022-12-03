#!/bin/bash

echo '

# ----------------------------------------------------------------------------------------------------------------------------------------------
# Script name:      anat_preprocessing_v1_1.sh
#
# Version:          1.1
#
# Version Date:     November 21, 2022 
#
# Version Notes:    Version 1.1 brings updated scripting to reduce redundancies and improve script flexibility. This version now also saves
#                   outputs to a derivatives directory to better conform to the BIDS standard.
#
# Description:      Script runs the following FSL tools to preprocess the T1w data
#                   - fslreorient2std
#                   - robustfov 
#                   - bet 
#                   - fast
#                   - first 
#                   - lesion_filling if a lesion mask exists
#
# Authors:          Justin W. Andrushko, PhD, CIHR & MSFHR Postdoctoral Fellow, Department of Physical Therapy, University of British Columbia
#                   Brandon J. Forys, MA, PhD Student, Department of Psychology, University of British Columbia
#
# Intended For:     T1w brain imaging data
#
# User Guide:       Data should be converted to nifti from DICOMS using the latest version of dcm2niix (although PAR/REC should still work).
#                   Data must be in BIDS format with the following naming convention:
#                   sub-#/anat/sub-#_T1w.nii.gz
#                   sub-#/anat/sub-#_T1w.json
#                   sub-#/anat/sub-#_T1w_label-lesion_roi.nii.gz <-- lesion mask if data contains lesions
#                   ---OR---
#                   sub-#/ses-#/anat/sub-#_ses-#_T1w.nii.gz
#                   sub-#/ses-#/anat/sub-#_ses-#_T1w.json
#                   sub-#/ses-#/anat/sub-#_ses-#_T1w_label-lesion_roi.nii.gz <-- lesion mask if data contains lesions
#
# Disclaimer:       Use scripts at own risk, the authors do not take responsibility for any errors or typos 
#                   that may exist in the scripts original or edited form.
#
# ----------------------------------------------------------------------------------------------------------------------------------------------'

#--------------------------------------#
#          Define Directories          #
#--------------------------------------#

WDIR=/mnt/d/test # Set this to your top level BIDS formatted directory
data=$WDIR/data # BIDS formatted data directory

if [ -d "$WDIR/derivatives" ] ; then
    derivatives=$WDIR/derivatives # All outputs will be placed in the derivatives directory
else
    mkdir $WDIR/derivatives
    derivatives=$WDIR/derivatives
fi 

cd $data
for subject in sub-* ; do
    echo $subject
    if [ -d "$data/$subject" ] ; then
        cd $data/$subject
        dir_list=$(dirname $(find . -name "*T1w.nii.gz" -type f | sed 's/..//'))
        for dir_path in $dir_list ; do
            filename=$(basename $dir_path/*T1w.nii.gz)
            echo $filename
            filename_noext="${filename%%.*}"
            mkdir -p $derivatives/$subject/$dir_path/
            echo "#-------------------------------------------------------------#"
            echo "Step 1: Reorienting T1w image to standard orientation"
            fslreorient2std $data/$subject/$dir_path/$filename $derivatives/$subject/$dir_path/${filename_noext}_reoriented
            echo "Step 1: Complete"
            echo "#-------------------------------------------------------------#"
            echo "Step 2: Performing z-direction image cropping"
            robustfov -i $derivatives/$subject/$dir_path/${filename_noext}_reoriented -r $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped 
            echo "Step 2: Complete"
            echo "#-------------------------------------------------------------#"
            echo "Step 3: Performing bias field correction and brain extraction"
            bet $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped $derivatives/$subject/$dir_path/${filename_noext}_brain -f 0.1 -R -B -m # https://pubmed.ncbi.nlm.nih.gov/22484407/
            fsleyes $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped $derivatives/$subject/$dir_path/${filename_noext}_brain -cm green -a 35
            echo "Are you satisfied with the quality of the brain extraction? (Y/n)"
            read varresponse
            while [[ $varresponse == "N" ]] || [[ $varresponse == "n" ]] || [[ $varresponse == "No" ]] || [[ $varresponse == "no" ]] ; do
                echo "You answered $varresponse. We will now rerun brain extraction with adjusted parameters"
                echo "Please input your desired fractional intensity threshold (0->1); default=0.5; smaller values give larger brain outtline estimates"
                read fractional_intensity_thresh
                echo "Do you wish to run robust brain centre estimation (iterates BET several times)? (Y/n)"
                read robust_brain_centre_est
                if [[ $robust_brain_centre_est == "N" ]] || [[ $robust_brain_centre_est == "n" ]] || [[ $robust_brain_centre_est == "No" ]] || [[ $robust_brain_centre_est == "no" ]] ; then
                    bet $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped $derivatives/$subject/$dir_path/${filename_noext}_brain -f $fractional_intensity_thresh -B -m 
                elif [[ $robust_brain_centre_est == "Y" ]] || [[ $robust_brain_centre_est == "y" ]] || [[ $robust_brain_centre_est == "Yes" ]] || [[ $robust_brain_centre_est == "yes" ]] ; then
                    bet $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped $derivatives/$subject/$dir_path/${filename_noext}_brain -f $fractional_intensity_thresh -R -B -m
                fi
                fsleyes $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped $derivatives/$subject/$dir_path/${filename_noext}_brain -cm green -a 35
                echo "Are you satisfied with the quality of the brain extraction? (Y/n)"
                read varresponse
            done
            echo "Step 3: Complete"
            echo "#-------------------------------------------------------------#"
            echo "Step 4: Performing tissue type segmentation"
            fast -t 1 -n 3 -g -o $derivatives/$subject/$dir_path/${filename_noext}_brain $derivatives/$subject/$dir_path/${filename_noext}_brain.nii.gz
            echo "Step 4: Complete"
            echo "#-------------------------------------------------------------#"
            echo "Step 5: Performing subcortical segmentation"
            mkdir $derivatives/$subject/$dir_path/first/
            run_first_all -b -d -i $derivatives/$subject/$dir_path/${filename_noext}_brain.nii.gz -o $derivatives/$subject/$dir_path/first/${filename_noext}_brain
            echo "Step 5: Complete"
            if [ -f "$data/$subject/$dir_path/*T1w_label-lesion_roi.nii.gz" ] ; then
                lesion_mask=$(basename $data/$subject/$dir_path/*T1w_label-lesion_roi.nii.gz)
                lesion_mask_noext="${lesion_mask%%.*}"
                echo "#-------------------------------------------------------------#"
                echo "Lesion mask detected"
                echo "Step 6: Performing lesion filling of T1w image"
                fslreorient2std $data/$subject/$dir_path/$lesion_mask $derivatives/$subject/$dir_path/$lesion_mask
                robustfov -i $derivatives/$subject/$dir_path/$lesion_mask -r $derivatives/$subject/$dir_path/${lesion_mask_noext}_cropped
                rm $derivatives/$subject/$dir_path/$lesion_mask
                mv $derivatives/$subject/$dir_path/${lesion_mask_noext}_cropped.nii.gz $derivatives/$subject/$dir_path/$lesion_mask
                fslmaths $derivatives/$subject/$dir_path/${filename_noext}_brain_pve_2.nii.gz -thr 0.99 -bin $derivatives/$subject/$dir_path/${filename_noext}_mask-wm_thr_bin.nii.gz
                lesion_filling -c -v -w $derivatives/$subject/$dir_path/${filename_noext}_mask-wm_thr_bin.nii.gz -i $derivatives/$subject/$dir_path/${filename_noext}_brain.nii.gz -l $derivatives/$subject/$dir_path/$lesion_mask -o $derivatives/$subject/$dir_path/${filename_noext}_lesion-filled_brain.nii.gz
                echo "Step 6: Complete"
            fi
            echo "#-------------------------------------------------------------#"
            echo "Final Step: Renaming ${filename_noext}_reoriented_cropped to $filename and removing unneeded files in derivatives directory"
            cp $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped.nii.gz $derivatives/$subject/$dir_path/$filename       
            rm $derivatives/$subject/$dir_path/${filename_noext}_reoriented_cropped.nii.gz 
            rm $derivatives/$subject/$dir_path/${filename_noext}_reoriented.nii.gz
            echo "Final Step: Complete"          
            echo "#-------------------------------------------------------------#"
            echo "$filename preprocessing complete"
            echo "#-------------------------------------------------------------#"
        done
        cd $data
    fi
done

exit 0
