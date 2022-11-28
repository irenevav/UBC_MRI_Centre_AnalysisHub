#!/bin/bash

echo '

# --------------------------------------------------------------------------------------------------------------------------------------------
# Script name:      vbrain_128dir_dti_processing.sh
#
# Description:      Script runs the following FSL tools to preprocess the diffusion data
#                   - topup
#                   - applytopup 
#                   - eddy 
#                   - dtifit 
#                   This script also is setup to run parallel processing up to the "MAX_POOL_SIZE" specified below. 
#
# Author:           Justin W. Andrushko PhD, CIHR & MSFHR Postdoctoral Fellow, Department of Physical Therapy, University of British Columbia
#
# Intended For:     V-Brain 128 direction 3 b-value DTI sequence
#
# User Guide:       Data should be converted to nifti from DICOMS using the latest version of dcm2niix (although PAR/REC should still work).
#                   Data must be in BIDS format with the following naming conventions:
#                   sub-#/dwi/sub-#_dir-AP_dwi.nii.gz ## AP specifies data were acquired in the Anterior >> Posterior direction
#                   sub-#/dwi/sub-#_dir-AP_dwi.json
#                   sub-#/dwi/sub-#_dir-AP_dwi.bvec
#                   sub-#/dwi/sub-#_dir-AP_dwi.bval
#                   sub-#/fmap/sub-#_dir-PA_dwi.nii.gz ## PA specifies data were acquired in the Posterior >> Anterior direction
#                   sub-#/fmap/sub-#_dir-PA_dwi.json
#                   ---OR---
#                   sub-#/ses-#/dwi/sub-#_dir-AP_dwi.nii.gz
#                   sub-#/ses-#/dwi/sub-#_dir-AP_dwi.json
#                   sub-#/ses-#/dwi/sub-#_dir-AP_dwi.bvec
#                   sub-#/ses-#/dwi/sub-#_dir-AP_dwi.bval
#                   sub-#/ses-#/fmap/sub-#_dir-PA_dwi.nii.gz
#                   sub-#/ses-#/fmap/sub-#_dir-PA_dwi.json
#
# Aknowledgements:  The author would like to acknowledge Alex Weber PhD, for contributing segments of code to this script
#
# Disclaimer:       Use scripts at own risk, the author does not take responsibility for any errors or typos 
#                   that may exist in the scripts original or edited form.
#
# --------------------------------------------------------------------------------------------------------------------------------------------'

#--------------------------------------#
#     Setup for Parallel Processing    #
#--------------------------------------#

# This is the concurrency limit. For parallel processing increase this value to your desired number of parallel processes.
# WARNING: increasing this value may cause script to fail if computer resources (RAM, CPU cores, swap memory) are insufficient.
MAX_POOL_SIZE=1

# This is used within the program. Do not change.
CURRENT_POOL_SIZE=0

# Print the output as a log with timestamp
_log() {
        echo " $(date +'[%F %T]') "
}

#--------------------------------------#
#          Define Directories          #
#--------------------------------------#

WDIR=/mnt/d/REST ## Set this to your data directory that is in BIDS format

# This is the custom function to process each job read from the file
process_job() {
# first argument to process_job is the subject ID from the subject list
subject=$1

if [ -d "$WDIR/$subject" ] ; then
    cd $WDIR/$subject
    if [ -d "$WDIR/$subject/ses-1" ] ; then
        for session in ses-* ; do
            cd $WDIR/$subject/$session/dwi
            for run in ${subject}_${session}_dir-AP_dwi.nii.gz ; do ## Can change the name to match your file names here
                run_noext="${run%%.*}"
                echo $run
                dim1=$(fslhd $run | grep -w dim1 | awk '{print $2}')
                dim2=$(fslhd $run | grep -w dim2 | awk '{print $2}')
                dim3=$(fslhd $run | grep -w dim3 | awk '{print $2}')
                numdirections=$(fslhd $run | grep -w dim4 | awk '{print $2}')
                PA_image=(${subject}_${session}_dir-PA_dwi.nii.gz) ## Can change the name to match your file names here
                PA_image_noext="${PA_image%%.*}"
                echo "#--------------------------------------------------------#"
                echo "Extracting EstimatedTotalReadoutTime from ${PA_image_noext}.json"
                PA_readout=$(grep 'EstimatedTotalReadoutTime' $WDIR/$subject/$session/fmap/${PA_image_noext}.json | awk '{ print $2 }')
                PA_readout=${PA_readout%??}
                if [ -z "$PA_readout" ] ; then
                    echo "For $PA_image EstimatedTotalReadoutTime was not found, will use a constant"
                    PA_readout=(1)
                    echo "Constant used in place of EstimatedTotalReadoutTime: $PA_readout"
                else
                    echo "For $PA_image EstimatedTotalReadoutTime was found"
                    echo "EstimatedTotalReadoutTime: $PA_readout"
                fi
                echo "Complete"
                echo "#--------------------------------------------------------#"
                fslroi $WDIR/$subject/${session}/fmap/$PA_image $WDIR/$subject/$session/fmap/${PA_image_noext}_nodif 0 1
                if [ $((dim3%2)) -eq 0 ]; then
                    echo "$run has an even number of slices";
                else
                    echo "$run has an odd number of slices cutting off bottom slice";
                    newdim=$(expr $dim3 - 1)
                    fslroi $run $run 0 $dim1 0 $dim2 1 $newdim
                    fslroi $WDIR/$subject/$session/fmap/${PA_image_noext}_nodif $WDIR/$subject/$session/fmap/${PA_image_noext}_nodif 0 $dim1 0 $dim2 1 $newdim
                fi   
                echo "#--------------------------------------------------------#"
                echo "The V-brain 128 direction 3 b-value sequence contains 12 b0 volumes"
                echo "Extracting b0 volumes from $run"
                fslroi ${run} ${run_noext}_nodif_vol-01 0 1
                fslroi ${run} ${run_noext}_nodif_vol-12 11 1
                fslroi ${run} ${run_noext}_nodif_vol-23 22 1
                fslroi ${run} ${run_noext}_nodif_vol-34 33 1
                fslroi ${run} ${run_noext}_nodif_vol-45 44 1
                fslroi ${run} ${run_noext}_nodif_vol-56 55 1
                fslroi ${run} ${run_noext}_nodif_vol-67 66 1
                fslroi ${run} ${run_noext}_nodif_vol-78 77 1
                fslroi ${run} ${run_noext}_nodif_vol-89 88 1
                fslroi ${run} ${run_noext}_nodif_vol-100 99 1
                fslroi ${run} ${run_noext}_nodif_vol-111 110 1
                fslroi ${run} ${run_noext}_nodif_vol-122 121 1
                echo "b0 volume extraction complete"
                echo "#--------------------------------------------------------#"
                echo "Moving b0 volumes to /fmap"
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-01.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-01.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-12.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-12.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-23.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-23.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-34.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-34.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-45.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-45.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-56.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-56.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-67.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-67.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-78.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-78.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-89.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-89.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-100.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-100.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-111.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-111.nii.gz
                mv $WDIR/$subject/$session/dwi/${run_noext}_nodif_vol-122.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-122.nii.gz
                echo "Moving b0 volumes to /fmap complete"
                echo "#--------------------------------------------------------#"
                echo "Extracting EstimatedTotalReadoutTime from ${run_noext}.json"
                AP_readout=$(grep 'EstimatedTotalReadoutTime' ${run_noext}.json | awk '{ print $2 }')
                AP_readout=${AP_readout%??}
                if [ -z "$AP_readout" ] ; then
                    echo "For $run EstimatedTotalReadoutTime was not found, will use a constant"
                    AP_readout=(1)
                    echo "Constant used in place of EstimatedTotalReadoutTime: $AP_readout"
                else
                    echo "For $run EstimatedTotalReadoutTime was found"
                    echo "EstimatedTotalReadoutTime: $AP_readout"
                fi
                echo "Complete"
                echo "#--------------------------------------------------------#"
                echo "Creating acqparams.txt" 
                printf "0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 1 0 $PA_readout" > $WDIR/$subject/fmap/acqparams.txt
                echo "#--------------------------------------------------------#"
                echo "Running fslmerge"
                fslmerge -t $WDIR/$subject/$session/fmap/b0_images_merged $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-01.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-12.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-23.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-34.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-45.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-56.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-67.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-78.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-89.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-100.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-111.nii.gz $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-122.nii.gz $WDIR/$subject/$session/fmap/${PA_image_noext}_nodif.nii.gz
                echo "Finished fslmerge"
                rm -r $WDIR/$subject/$session/fmap/${run_noext}_nodif_vol-*.nii.gz
                echo "#--------------------------------------------------------#"
                echo "Running topup"
                cd $WDIR/$subject/$session/fmap
                topup --verbose --imain=$WDIR/$subject/$session/fmap/b0_images_merged.nii.gz --datain=$WDIR/$subject/$session/fmap/acqparams.txt --config=$FSLDIR/src/topup/flirtsch/b02b0.cnf --fout=$WDIR/$subject/$session/fmap/${run_noext}_field_hz --iout=$WDIR/$subject/$session/fmap/${run_noext}_iout --out=$WDIR/$subject/$session/fmap/${run_noext}_topup
                echo "Finished topup"
                echo "#--------------------------------------------------------#"
                echo "Running applytopup"
                applytopup --imain=$WDIR/$subject/$session/dwi/$run --inindex=1 --method=lsr --datain=$WDIR/$subject/$session/fmap/acqparams.txt --topup=$WDIR/$subject/$session/fmap/${run_noext}_topup --out=$WDIR/$subject/$session/dwi/${run_noext}_corrected --verbose
                echo "Finished applytopup"
                echo "#--------------------------------------------------------#"
                echo " Running brain extraction on distortion corrected data"
                fslmaths $WDIR/$subject/$session/fmap/${run_noext}_iout -Tmean $WDIR/$subject/$session/fmap/${run_noext}_hifi_nodif
                bet $WDIR/$subject/$session/fmap/${run_noext}_hifi_nodif $WDIR/$subject/$session/dwi/${run_noext}_corrected_brain.nii.gz -R -m -f 0.2
                indx=""
                for ((i=1; i<=$numdirections; i+=1)); do indx="$indx 1"; done
                echo $indx > $WDIR/$subject/$session/dwi/index.txt
                echo "#--------------------------------------------------------#"
                echo "Running Eddy Correction"
                eddy --imain=$WDIR/$subject/$session/dwi/$run --mask=$WDIR/$subject/$session/dwi/${run_noext}_corrected_brain_mask.nii.gz --acqp=$WDIR/$subject/$session/fmap/acqparams.txt --index=$WDIR/$subject/$session/dwi/index.txt --bvecs=$WDIR/$subject/$session/dwi/${run_noext}.bvec --bvals=$WDIR/$subject/$session/dwi/${run_noext}.bval --topup=$WDIR/$subject/$session/fmap/${run_noext}_topup --niter=8 --fwhm=10,8,4,2,0,0,0,0 --repol --out=$WDIR/$subject/$session/dwi/${run_noext}_eddy_corrected_data --mporder=6 --s2v_niter=5 --s2v_lambda=1 --s2v_interp=trilinear
                echo "Running FSL's DTIFIT"
                dtifit --data=$WDIR/$subject/$session/dwi/${run_noext}_eddy_corrected_data --out=$WDIR/$subject/$session/dwi/${run_noext} --mask=$WDIR/$subject/$session/dwi/${run_noext}_corrected_brain_mask.nii.gz --bvecs=$WDIR/$subject/$session/dwi/${run_noext}.bvec --bvals=$WDIR/$subject/$session/dwi/${run_noext}.bval
                echo "#--------------------------------------------------------#"
                echo "$subject"
                echo "$session"
                echo "$run"
                echo "Complete"
                echo "#--------------------------------------------------------#"
                cd $WDIR/$subject/dwi
            done
        done
    else 
    cd $WDIR/$subject/dwi
        for run in ${subject}_dir-AP_dwi.nii.gz ; do ## Can change the name to match your file names here
            run_noext="${run%%.*}"
            echo $run
            dim1=$(fslhd $run | grep -w dim1 | awk '{print $2}')
            dim2=$(fslhd $run | grep -w dim2 | awk '{print $2}')
            dim3=$(fslhd $run | grep -w dim3 | awk '{print $2}')
            numdirections=$(fslhd $run | grep -w dim4 | awk '{print $2}')
            PA_image=(${subject}_dir-PA_dwi.nii.gz) ## Can change the name to match your file names here
            PA_image_noext="${PA_image%%.*}"
            echo "#--------------------------------------------------------#"
            echo "Extracting EstimatedTotalReadoutTime from ${PA_image_noext}.json"
            PA_readout=$(grep 'EstimatedTotalReadoutTime' $WDIR/$subject/fmap/${PA_image_noext}.json | awk '{ print $2 }')
            PA_readout=${PA_readout%??}
            if [ -z "$PA_readout" ] ; then
                echo "For $PA_image EstimatedTotalReadoutTime was not found, will use a constant"
                PA_readout=(1)
                echo "Constant used in place of EstimatedTotalReadoutTime: $PA_readout"
            else
                echo "For $PA_image EstimatedTotalReadoutTime was found"
                echo "EstimatedTotalReadoutTime: $PA_readout"
            fi
            echo "Complete"
            echo "#--------------------------------------------------------#"
            fslroi $WDIR/$subject/fmap/$PA_image $WDIR/$subject/fmap/${PA_image_noext}_nodif 0 1
            cd $WDIR/$subject/dwi
            if [ $((dim3%2)) -eq 0 ]; then
                echo "$run has an even number of slices";
            else
                echo "$run has an odd number of slices cutting off bottom slice";
                newdim=$(expr $dim3 - 1)
                fslroi $run $run 0 $dim1 0 $dim2 1 $newdim
                fslroi $WDIR/$subject/fmap/${PA_image_noext}_nodif $WDIR/$subject/fmap/${PA_image_noext}_nodif 0 $dim1 0 $dim2 1 $newdim
            fi   
            echo "#--------------------------------------------------------#"
            echo "The V-brain 128 direction 3 b-value sequence contains 12 b0 volumes"
            echo "Extracting b0 volumes from $run"
            fslroi ${run} ${run_noext}_nodif_vol-01 0 1
            fslroi ${run} ${run_noext}_nodif_vol-12 11 1
            fslroi ${run} ${run_noext}_nodif_vol-23 22 1
            fslroi ${run} ${run_noext}_nodif_vol-34 33 1
            fslroi ${run} ${run_noext}_nodif_vol-45 44 1
            fslroi ${run} ${run_noext}_nodif_vol-56 55 1
            fslroi ${run} ${run_noext}_nodif_vol-67 66 1
            fslroi ${run} ${run_noext}_nodif_vol-78 77 1
            fslroi ${run} ${run_noext}_nodif_vol-89 88 1
            fslroi ${run} ${run_noext}_nodif_vol-100 99 1
            fslroi ${run} ${run_noext}_nodif_vol-111 110 1
            fslroi ${run} ${run_noext}_nodif_vol-122 121 1
            echo "b0 volume extraction complete"
            echo "#--------------------------------------------------------#"
            echo "Moving b0 volumes to /fmap"
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-01.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-01.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-12.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-12.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-23.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-23.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-34.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-34.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-45.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-45.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-56.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-56.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-67.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-67.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-78.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-78.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-89.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-89.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-100.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-100.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-111.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-111.nii.gz
            mv $WDIR/$subject/dwi/${run_noext}_nodif_vol-122.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-122.nii.gz
            echo "Moving b0 volumes to /fmap complete"
            echo "#--------------------------------------------------------#"
            echo "Extracting EstimatedTotalReadoutTime from ${run_noext}.json"
            AP_readout=$(grep 'EstimatedTotalReadoutTime' ${run_noext}.json | awk '{ print $2 }')
            AP_readout=${AP_readout%??}
            if [ -z "$AP_readout" ] ; then
                echo "For $run_noext EstimatedTotalReadoutTime was not found, will use a constant"
                AP_readout=(1)
                echo "Constant used in place of EstimatedTotalReadoutTime: $AP_readout"
            else
                echo "For $run_noext EstimatedTotalReadoutTime was found"
                echo "EstimatedTotalReadoutTime: $AP_readout"
            fi
            echo "Complete"
            echo "#--------------------------------------------------------#"
            echo "Creating acqparams.txt" 
            printf "0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 1 0 $PA_readout" > $WDIR/$subject/fmap/acqparams.txt
            echo "#--------------------------------------------------------#"
            echo "Running fslmerge"
            fslmerge -t $WDIR/$subject/fmap/b0_images_merged $WDIR/$subject/fmap/${run_noext}_nodif_vol-01.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-12.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-23.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-34.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-45.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-56.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-67.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-78.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-89.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-100.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-111.nii.gz $WDIR/$subject/fmap/${run_noext}_nodif_vol-122.nii.gz $WDIR/$subject/fmap/${PA_image_noext}_nodif.nii.gz
            echo "Finished fslmerge"
            rm -r $WDIR/$subject/fmap/${run_noext}_nodif_vol-*.nii.gz
            echo "#--------------------------------------------------------#"
            echo "Running topup"
            cd $WDIR/$subject/fmap
            topup --verbose --imain=$WDIR/$subject/fmap/b0_images_merged.nii.gz --datain=$WDIR/$subject/fmap/acqparams.txt --config=$FSLDIR/src/topup/flirtsch/b02b0.cnf --iout=$WDIR/$subject/fmap/${run_noext}_iout --fout=$WDIR/$subject/fmap/${run_noext}_field_hz --out=$WDIR/$subject/fmap/${run_noext}_topup
            echo "Finished topup"
            echo "#--------------------------------------------------------#"
            echo "Running applytopup"
            applytopup --imain=$WDIR/$subject/dwi/$run --inindex=1 --method=lsr --datain=$WDIR/$subject/fmap/acqparams.txt --topup=$WDIR/$subject/fmap/${run_noext}_topup --out=$WDIR/$subject/dwi/${run_noext}_corrected --verbose
            echo "Finished applytopup"
            echo "#--------------------------------------------------------#"
            echo " Running brain extraction on distortion corrected data"
            fslmaths $WDIR/$subject/fmap/${run_noext}_iout -Tmean $WDIR/$subject/fmap/${run_noext}_hifi_nodif
            bet $WDIR/$subject/fmap/${run_noext}_hifi_nodif $WDIR/$subject/dwi/${run_noext}_corrected_brain.nii.gz -R -m -f 0.2
            indx=""
            for ((i=1; i<=$numdirections; i+=1)); do indx="$indx 1"; done
            echo $indx > $WDIR/$subject/dwi/index.txt
            echo "#--------------------------------------------------------#"
            echo "Running Eddy Correction"
            eddy --imain=$WDIR/$subject/dwi/$run --mask=$WDIR/$subject/dwi/${run_noext}_corrected_brain_mask.nii.gz --acqp=$WDIR/$subject/fmap/acqparams.txt --index=$WDIR/$subject/dwi/index.txt --bvecs=$WDIR/$subject/dwi/${run_noext}.bvec --bvals=$WDIR/$subject/dwi/${run_noext}.bval --topup=$WDIR/$subject/fmap/${run_noext}_topup --niter=8 --fwhm=10,8,4,2,0,0,0,0 --repol --out=$WDIR/$subject/dwi/${run_noext}_eddy_corrected_data --mporder=6 --s2v_niter=5 --s2v_lambda=1 --s2v_interp=trilinear
            echo "Running FSL's DTIFIT"
            dtifit --data=$WDIR/$subject/dwi/${run_noext}_eddy_corrected_data --out=$WDIR/$subject/dwi/${run_noext} --mask=$WDIR/$subject/dwi/${run_noext}_corrected_brain_mask.nii.gz --bvecs=$WDIR/$subject/dwi/${run_noext}.bvec --bvals=$WDIR/$subject/dwi/${run_noext}.bval
            echo "#--------------------------------------------------------#"
            echo "$subject"
            echo "$run"
            echo "Complete"
            echo "#--------------------------------------------------------#"
            cd $WDIR/$subject/dwi
        done
    fi
fi
}

#--------------------------------------#
#   Generate a list of all subjects    #
#--------------------------------------#
# Manually edit text file to select fewer or specific subjects

cd $WDIR
if [ -f "subj_list.txt" ]; then
    echo "subject list file already exists. Manually edit the file if you wish to make changes. Subject list: subj_list.txt can be found in $WDIR/subj_list.txt"
else
    for subject in sub-* ; do
        if [ -d "$subject" ]; then
            subject_name=$(basename -- "$subject")
            echo $subject_name >> $WDIR/subj_list.txt
        fi
    done
fi
JOB_LIST=subj_list.txt

# Read each line of the subject list
while IFS= read -r line; do
  echo $line
  # While the current number of processes >= the max number, don't start new parallel processes
  while [ $CURRENT_POOL_SIZE -ge $MAX_POOL_SIZE ]; do
    CURRENT_POOL_SIZE=$(jobs | wc -l)
  done

  # Process a participant and start next one in parallel unless process pool is full
  process_job $line &

  # When a new job is created, the program updates the $CURRENT_POOL_SIZE variable before next iteration
  CURRENT_POOL_SIZE=$(jobs | wc -l)
  _log "Current pool size = $CURRENT_POOL_SIZE"
done < $JOB_LIST

# wait for all background jobs (forks) to exit before exiting the parent process
wait

exit 0