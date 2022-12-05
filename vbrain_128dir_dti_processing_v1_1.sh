#!/bin/bash

echo '

# --------------------------------------------------------------------------------------------------------------------------------------------
# Script name:      vbrain_128dir_dti_processing_v1_1.sh
#
# Version:          1.1
#
# Version Date:     December 4, 2022 
#
# Version Notes:    Version 1.1 brings updated scripting to reduce redundancies and improve script flexibility, and saves all outputs to a 
#                   derivatives directory to better conform to the BIDS standard. This version also has commented out registration options
#                   for the dwi data to the T1w anatomical data but this is not functioning correctly. Future releases will aim to incorporate 
#                   working dwi to T1w registration.
#
# Description:      Script runs the following FSL tools to preprocess the diffusion data
#                   - topup
#                   - applytopup with jacobian modulation
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
# Aknowledgements:  The author would like to acknowledge Alex Weber PhD, and Brandon Forys, PhD student, for contributing segments of code to 
#                   this script.
#
# Disclaimer:       Use scripts at own risk, the author does not take responsibility for any errors or typos that may exist in the scripts
#                   original or edited form.
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

WDIR=/mnt/d/studies/REST ## Set this to your data directory that is in BIDS format
derivatives=$WDIR/derivatives
# This is the custom function to process each job read from the file
process_job() {
# first argument to process_job is the subject ID from the subject list
subject=$1

if [ -d "$WDIR/data/$subject" ] ; then
    cd $WDIR/data
    dir_list=$(dirname $(find . -name "fmap" -type d | sed 's/..//'))
    echo $dir_list
    for dir_path in $dir_list ; do
        dwi=$(basename $(find $WDIR/data/$dir_path/dwi -name "*dwi.ni*" -type f | sed 's/..//'))
        # anat=$(basename $(find $derivatives/$dir_path/anat -name "*T1w.ni*" -type f | sed 's/..//'))
        # anat_brain=$(basename $(find $derivatives/$dir_path/anat -name "*T1w_brain.ni*" -type f | sed 's/..//'))
        # anat_path=$(dirname $(find $derivatives/$dir_path -name "$anat" -type f))
        if [[ "$dwi" == *".nii.gz" ]] ; then # get dwi name without extension
            dwi_noext="${dwi%%.*}"
        else
            dwi_noext="${dwi%.*}"
        fi
        # if [[ "$anat" == *".nii.gz" ]] ; then # get T1w image without extension
        #     anat_noext="${anat%%.*}"
        # else
        #     anat_noext="${anat%.*}"
        # fi
        # if [[ "$anat_brain" == *".nii.gz" ]] ; then # get T1w_brain image without extension
        #     anat_brain_noext="${anat_brain%%.*}"
        # else
        #     anat_brain_noext="${anat_brain%.*}"
        # fi
        mkdir -p $derivatives/$dir_path/dwi
        mkdir -p $derivatives/$dir_path/fmap
        mkdir -p $derivatives/$dir_path/dwi/b0_images
        cp $WDIR/data/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/$dwi
        cp $WDIR/data/$dir_path/dwi/${dwi_noext}.json $derivatives/$dir_path/dwi/${dwi_noext}.json
        cp $WDIR/data/$dir_path/dwi/${dwi_noext}.bval $derivatives/$dir_path/dwi/${dwi_noext}.bval
        cp $WDIR/data/$dir_path/dwi/${dwi_noext}.bvec $derivatives/$dir_path/dwi/${dwi_noext}.bvec
        dim1=$(fslhd $derivatives/$dir_path/dwi/$dwi | grep -w dim1 | awk '{print $2}')
        dim2=$(fslhd $derivatives/$dir_path/dwi/$dwi | grep -w dim2 | awk '{print $2}')
        dim3=$(fslhd $derivatives/$dir_path/dwi/$dwi | grep -w dim3 | awk '{print $2}')
        numdirections=$(fslhd $derivatives/$dir_path/dwi/$dwi | grep -w dim4 | awk '{print $2}')
        PA_image=$(find $WDIR/data/$dir_path/fmap -name "*_dwi.nii.gz" -type f | sed 's/..//')
        PA_image=$(basename $PA_image)
        PA_image_noext="${PA_image%%.*}"
        echo "#--------------------------------------------------------#"
        echo "Extracting EstimatedTotalReadoutTime from ${PA_image_noext}.json"
        PA_readout=$(grep 'EstimatedTotalReadoutTime' $WDIR/data/$dir_path/fmap/${PA_image_noext}.json | awk '{ print $2 }')
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
        fslroi $WDIR/data/$dir_path/fmap/$PA_image $derivatives/$dir_path/dwi/b0_images/${PA_image_noext}_nodif 0 1
        if [ $((dim3%2)) -eq 0 ]; then
            echo "$dwi has an even number of slices";
        else
            echo "$dwi has an odd number of slices cutting off bottom slice";
            newdim=$(expr $dim3 - 1)
            fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/$dwi 0 $dim1 0 $dim2 1 $newdim
            fslroi $derivatives/$dir_path/dwi/b0_images/${PA_image_noext}_nodif $derivatives/$dir_path/dwi/b0_images/${PA_image_noext}_nodif 0 $dim1 0 $dim2 1 $newdim
        fi   
        echo "#--------------------------------------------------------#"
        echo "The V-brain 128 direction 3 b-value sequence contains 12 b0 volumes"
        echo "Extracting b0 volumes from $dwi"
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-01 0 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-12 11 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-23 22 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-34 33 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-45 44 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-56 55 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-67 66 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-78 77 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-89 88 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-100 99 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-111 110 1
        fslroi $derivatives/$dir_path/dwi/$dwi $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-122 121 1
        echo "b0 volume extraction complete"
        echo "#--------------------------------------------------------#"
        echo "Extracting EstimatedTotalReadoutTime from $dir_path/dwi/${dwi_noext}.json"
        AP_readout=$(grep 'EstimatedTotalReadoutTime' $dir_path/dwi/${dwi_noext}.json | awk '{ print $2 }')
        AP_readout=${AP_readout%??}
        if [ -z "$AP_readout" ] ; then
            echo "For $dwi EstimatedTotalReadoutTime was not found, will use a constant"
            AP_readout=(1)
            echo "Constant used in place of EstimatedTotalReadoutTime: $AP_readout"
        else
            echo "For $dwi EstimatedTotalReadoutTime was found"
            echo "EstimatedTotalReadoutTime: $AP_readout"
        fi
        echo "Complete"
        echo "#--------------------------------------------------------#"
        echo "Creating acqparams.txt" 
        printf "0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 -1 0 $AP_readout\n0 1 0 $PA_readout" > $derivatives/$dir_path/fmap/acqparams.txt
        echo "Finished creating acqparams.txt" 
        echo "#--------------------------------------------------------#"
        echo "Running fslmerge of b0 images"
        fslmerge -t $derivatives/$dir_path/fmap/b0_images_merged $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-01.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-12.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-23.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-34.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-45.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-56.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-67.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-78.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-89.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-100.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-111.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-122.nii.gz $derivatives/$dir_path/dwi/b0_images/${PA_image_noext}_nodif.nii.gz
        fslmerge -t $derivatives/$dir_path/fmap/AP_b0_images_merged $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-01.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-12.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-23.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-34.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-45.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-56.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-67.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-78.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-89.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-100.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-111.nii.gz $derivatives/$dir_path/dwi/b0_images/${dwi_noext}_nodif_vol-122.nii.gz
        echo "Finished fslmerge of b0 images"
        echo "#--------------------------------------------------------#"
        echo "Running topup"
        topup --verbose --imain=$derivatives/$dir_path/fmap/b0_images_merged.nii.gz --datain=$derivatives/$dir_path/fmap/acqparams.txt --config=$FSLDIR/src/topup/flirtsch/b02b0.cnf --fout=$derivatives/$dir_path/fmap/${dwi_noext}_field_hz --iout=$derivatives/$dir_path/fmap/${dwi_noext}_iout --out=$derivatives/$dir_path/fmap/${dwi_noext}_topup
        echo "Finished topup"
        echo "#--------------------------------------------------------#"
        echo "Running applytopup"
        applytopup --imain=$derivatives/$dir_path/dwi/$dwi --method=jac --inindex=1 --datain=$derivatives/$dir_path/fmap/acqparams.txt --topup=$derivatives/$dir_path/fmap/${dwi_noext}_topup --out=$derivatives/$dir_path/dwi/${dwi_noext}_corrected --verbose
        echo "Finished applytopup"
        echo "#--------------------------------------------------------#"
        echo "Running brain extraction on distortion corrected data"
        fslmaths $derivatives/$dir_path/fmap/${dwi_noext}_iout -Tmean $derivatives/$dir_path/fmap/${dwi_noext}_hifi_nodif
        bet $derivatives/$dir_path/fmap/${dwi_noext}_hifi_nodif $derivatives/$dir_path/dwi/${dwi_noext}_corrected_brain.nii.gz -m -f 0.2
        echo "Finished running brain extraction on distortion corrected data"
        indx=""
        for ((i=1; i<=$numdirections; i+=1)); do indx="$indx 1"; done
        echo $indx > $derivatives/$dir_path/dwi/index.txt
        echo "#--------------------------------------------------------#"
        echo "Running eddy correction"
        eddy --imain=$derivatives/$dir_path/dwi/$dwi --mask=$derivatives/$dir_path/dwi/${dwi_noext}_corrected_brain_mask.nii.gz --acqp=$derivatives/$dir_path/fmap/acqparams.txt --index=$derivatives/$dir_path/dwi/index.txt --bvecs=$derivatives/$dir_path/dwi/${dwi_noext}.bvec --bvals=$derivatives/$dir_path/dwi/${dwi_noext}.bval --topup=$derivatives/$dir_path/fmap/${dwi_noext}_topup --niter=8 --fwhm=10,8,4,2,0,0,0,0 --repol --out=$derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data --mporder=6 --s2v_niter=5 --s2v_lambda=1 --s2v_interp=trilinear
        echo "Finished running eddy correction"
        ######## OPTION TO ADD REGISTRATION AT A LATER RELEASE - CODE BELOW NOT CURRENTLY FUNCTIONING AS DESIRED ######## 
        # echo "#--------------------------------------------------------#"
        # echo " Running registration of corrected dwi data to T1w image"
        # fslroi $derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data.nii.gz $derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data_nodif_vol-01 0 1
        # epi_reg --epi=$derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data_nodif_vol-01 --t1=$anat_path/$anat --t1brain=$anat_path/$anat_brain --out=$derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data_space-T1w
        # flirt -in $derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data.nii.gz -ref $anat_path/$anat_brain -out ${dwi_noext}_eddy_corrected_data_space-T1w.nii.gz -init ${dwi_noext}_eddy_corrected_data_space-T1w.mat -applyxfm
        # rm $derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data_nodif_vol-01
        # echo " Registration complete"
        echo "#--------------------------------------------------------#"
        echo "Running FSL's DTIFIT"
        dtifit --data=$derivatives/$dir_path/dwi/${dwi_noext}_eddy_corrected_data --out=$derivatives/$dir_path/dwi/${dwi_noext} --mask=$derivatives/$dir_path/dwi/${dwi_noext}_corrected_brain_mask.nii.gz --bvecs=$derivatives/$dir_path/dwi/${dwi_noext}.bvec --bvals=$derivatives/$dir_path/dwi/${dwi_noext}.bval
        echo "Finished running FSL's DTIFIT"       
        echo "#--------------------------------------------------------#"
        echo "$dwi"
        echo "Complete"
        echo "#--------------------------------------------------------#"
        cd $WDIR/data
    done
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
    for subject in $WDIR/data/sub-* ; do
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
