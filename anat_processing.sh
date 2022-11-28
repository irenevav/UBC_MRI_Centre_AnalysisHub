#!/bin/bash

echo '

# ----------------------------------------------------------------------------------------------------------------------------------------------
# Script name:      anat_preprocessing.sh
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
# Date Written:     October 3rd, 2022
#
# Version:          1.0
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
# Disclaimer:       Use scripts at own risk, the author does not take responsibility for any errors or typos 
#                   that may exist in the scripts original or edited form.
#
# ----------------------------------------------------------------------------------------------------------------------------------------------'

#--------------------------------------#
#          Define Directories          #
#--------------------------------------#

WDIR=/mnt/d/studies/REST # Set this to your BIDS formatted data directory

cd $WDIR
for subject in sub-* ; do
    if [ -d "$WDIR/$subject" ] ; then
        cd $WDIR/$subject
        if [ -d "$WDIR/$subject/ses-1" ] ; then
            for session in ses-* ; do
                cd $WDIR/$subject/$session/anat
                for struct in ${subject}_${session}_T1w.nii.gz ; do
                    struct_noext="${struct%%.*}"
                    echo $struct
                    echo "#-------------------------------------------------------------#"
                    echo "Step 1: Reorienting T1w image to standard orientation"
                    fslreorient2std $struct ${struct_noext}_reoriented
                    echo "Step 1: Complete"
                    echo "#-------------------------------------------------------------#"
                    echo "Step 2: Performing z-direction image cropping"
                    robustfov -i ${struct_noext}_reoriented -r ${struct_noext}_reoriented_cropped 
                    echo "Step 2: Complete"
                    echo "#-------------------------------------------------------------#"
                    echo "Step 3: Performing bias field correction and brain extraction"
                    bet ${struct_noext}_reoriented_cropped ${struct_noext}_brain -f 0.1 -R -B -m # https://pubmed.ncbi.nlm.nih.gov/22484407/
                    fsleyes ${struct_noext}_reoriented_cropped ${struct_noext}_brain -cm green -a 35
                    echo "Are you satisfied with the quality of the brain extraction? (Y/n)"
                    read varresponse
                    while [[ $varresponse == "N" ]] || [[ $varresponse == "n" ]] || [[ $varresponse == "No" ]] || [[ $varresponse == "no" ]] ; do
                        echo "You answered $varresponse. We will now rerun brain extraction with adjusted parameters"
                        echo "Please input your desired fractional intensity threshold (0->1); default=0.5; smaller values give larger brain outtline estimates"
                        read fractional_intensity_thresh
                        echo "Do you wish to run robust brain centre estimation (iterates BET several times)? (Y/n)"
                        read robust_brain_centre_est
                        if [[ $robust_brain_centre_est == "N" ]] || [[ $robust_brain_centre_est == "n" ]] || [[ $robust_brain_centre_est == "No" ]] || [[ $robust_brain_centre_est == "no" ]] ; then
                            bet ${struct_noext}_reoriented_cropped ${struct_noext}_brain -f $fractional_intensity_thresh -B -m 
                        elif [[ $robust_brain_centre_est == "Y" ]] || [[ $robust_brain_centre_est == "y" ]] || [[ $robust_brain_centre_est == "Yes" ]] || [[ $robust_brain_centre_est == "yes" ]] ; then
                            bet ${struct_noext}_reoriented_cropped ${struct_noext}_brain -f $fractional_intensity_thresh -R -B -m
                        fi
                        fsleyes ${struct_noext}_reoriented_cropped ${struct_noext}_brain -cm green -a 35
                        echo "Are you satisfied with the quality of the brain extraction? (Y/n)"
                        read varresponse
                    done
                    echo "Step 3: Complete"
                    echo "#-------------------------------------------------------------#"
                    echo "Step 4: Performing tissue type segmentation"
                    fast -t 1 -n 3 -g -o ${struct_noext}_brain ${struct_noext}_brain.nii.gz
                    echo "Step 4: Complete"
                    echo "#-------------------------------------------------------------#"
                    echo "Step 5: Performing subcortical segmentation"
                    mkdir $WDIR/$subject/$session/anat/first/
                    run_first_all -b -v -d -i ${struct_noext}_brain.nii.gz -o $WDIR/$subject/$session/anat/first/${struct_noext}_brain
                    echo "Step 5: Complete"
                    if [ -f "$WDIR/$subject/${session}/anat/${subject}_${session}_T1w_label-lesion_roi.nii.gz" ] ; then
                        lesion_mask="${subject}_${session}_T1w_label-lesion_roi.nii.gz"
                        lesion_mask_noext="${lesion_mask%%.*}"
                        echo "#-------------------------------------------------------------#"
                        echo "Lesion mask detected"
                        echo "Step 6: Performing lesion filling of T1w image"
                        fslreorient2std $lesion_mask $lesion_mask
                        robustfov -i $lesion_mask -r ${lesion_mask_noext}_cropped 
                        fslmaths ${struct_noext}_brain_pve_2.nii.gz -thr 0.99 -bin ${struct_noext}_mask-wm_thr_bin.nii.gz
                        lesion_filling -c -v -w ${struct_noext}_mask-wm_thr_bin.nii.gz -i ${struct_noext}_brain.nii.gz -l ${lesion_mask_noext}_cropped.nii.gz -o ${struct_noext}_lesion-filled_brain.nii.gz
                        echo "Step 6: Complete"
                    fi
                    echo "#-------------------------------------------------------------#"
                    echo "${struct_noext} T1w preprocessing complete"
                    echo "#-------------------------------------------------------------#"
                done
                cd $WDIR/$subject 
            done
        else 
            cd $WDIR/$subject/anat
            for struct in ${subject}_T1w.nii.gz ; do
                struct_noext="${struct%%.*}"
                echo $struct
                echo "#-------------------------------------------------------------#"
                echo "Step 1: Reorienting T1w image to standard orientation"
                fslreorient2std $struct ${struct_noext}_reoriented
                echo "Step 1: Complete"
                echo "#-------------------------------------------------------------#"
                echo "Step 2: Performing z-direction image cropping"
                robustfov -i ${struct_noext}_reoriented -r ${struct_noext}_reoriented_cropped 
                echo "Step 2: Complete"
                echo "#-------------------------------------------------------------#"
                echo "Step 3: Performing bias field correction and brain extraction"
                bet ${struct_noext}_reoriented_cropped ${struct_noext}_brain -f 0.1 -R -B -m # https://pubmed.ncbi.nlm.nih.gov/22484407/
                fsleyes ${struct_noext}_reoriented_cropped ${struct_noext}_brain -cm green -a 35
                echo "Are you satisfied with the quality of the brain extraction? (Y/n)"
                read varresponse
                while [[ $varresponse == "N" ]] || [[ $varresponse == "n" ]] || [[ $varresponse == "No" ]] || [[ $varresponse == "no" ]] ; do
                    echo "You answered $varresponse. We will now rerun brain extraction with adjusted parameters"
                    echo "Please input your desired fractional intensity threshold (0->1); default=0.5; smaller values give larger brain outtline estimates"
                    read fractional_intensity_thresh
                    echo "Do you wish to run robust brain centre estimation (iterates BET several times)? (Y/n)"
                    read robust_brain_centre_est
                    if [[ $robust_brain_centre_est == "N" ]] || [[ $robust_brain_centre_est == "n" ]] || [[ $robust_brain_centre_est == "No" ]] || [[ $robust_brain_centre_est == "no" ]] ; then
                        bet ${struct_noext}_reoriented_cropped ${struct_noext}_brain -f $fractional_intensity_thresh -B -m 
                    elif [[ $robust_brain_centre_est == "Y" ]] || [[ $robust_brain_centre_est == "y" ]] || [[ $robust_brain_centre_est == "Yes" ]] || [[ $robust_brain_centre_est == "yes" ]] ; then
                        bet ${struct_noext}_reoriented_cropped ${struct_noext}_brain -f $fractional_intensity_thresh -R -B -m
                    fi
                    fsleyes ${struct_noext}_reoriented_cropped ${struct_noext}_brain -cm green -a 35
                    echo "Are you satisfied with the quality of the brain extraction? (Y/n)"
                    read varresponse
                done
                echo "Step 3: Complete"
                echo "#-------------------------------------------------------------#"
                echo "Step 4: Performing tissue type segmentation"
                fast -t 1 -n 3 -g -o ${struct_noext}_brain ${struct_noext}_brain.nii.gz
                echo "Step 4: Complete"
                echo "#-------------------------------------------------------------#"
                echo "Step 5: Performing subcortical segmentation"
                mkdir $WDIR/$subject/anat/first/
                run_first_all -b -v -d -i ${struct_noext}_brain.nii.gz -o $WDIR/$subject/anat/first/${struct_noext}_brain
                echo "Step 5: Complete"
                if [ -f "$WDIR/$subject/anat/${subject}_T1w_label-lesion_roi.nii.gz" ] ; then
                    lesion_mask="${subject}_T1w_label-lesion_roi.nii.gz"
                    lesion_mask_noext="${lesion_mask%%.*}"
                    echo "#-------------------------------------------------------------#"
                    echo "Lesion mask detected"
                    echo "Step 6: Performing lesion filling of T1w image"
                    fslreorient2std $lesion_mask $lesion_mask
                    robustfov -i $lesion_mask -r ${lesion_mask_noext}_cropped 
                    fslmaths ${struct_noext}_brain_pve_2.nii.gz -thr 0.99 -bin ${struct_noext}_mask-wm_thr_bin.nii.gz
                    lesion_filling -c -v -w ${struct_noext}_mask-wm_thr_bin.nii.gz -i ${struct_noext}_brain.nii.gz -l ${lesion_mask_noext}_cropped.nii.gz -o ${struct_noext}_lesion-filled_brain.nii.gz
                    echo "Step 6: Complete"
                fi
                echo "#-------------------------------------------------------------#"
                echo "${struct_noext} T1w preprocessing complete"
                echo "#-------------------------------------------------------------#"
            done
            cd $WDIR
        fi
    fi
done

exit 0