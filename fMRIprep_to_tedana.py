# ---------------------------------------------------------------------------------------------------------------------
# Script name:      fMRIprep_to_tedana.py
#
# Description:      Script runs tedana (TE-dependent ICA for multi-echo data) from fMRIprep outputs.
#
# Author:           Brandon J. Forys, MA, PhD Student, Department of Psychology, University of British Columbia
# Maintained by:    brandon.forys@psych.ubc.ca
#
# Intended For:     BIDS_formatted mult-echo fMRI image data
#
# User Guide:       Data should be converted to nifti from DICOMS using the latest version of dcm2niix
#                   and run through fMRIprep with the argument --me-output-echoes (to ensure each echo is output
#                   directly).
#                   Data must be in BIDS format with the following naming convention:
#                   sub-#/anat/sub-#*echo-#_bold.nii.gz
#                   sub-#/anat/sub-#*echo-#_bold.json
#
#
# Disclaimer:       Use scripts at own risk, the author does not take responsibility for any errors or typos
#                   that may exist in the scripts original or edited form.
#
# Adapted from:     Julio Peraza, tedana
# ---------------------------------------------------------------------------------------------------------------------

import pandas as pd
from tedana import workflows
import argparse
import json
import os
import re
import time
from multiprocessing import Pool

# Parse arguments to script
parser = argparse.ArgumentParser(
    description='Give me a path to your fmriprep output and number of cores to run')
parser.add_argument('--fmriprepDir', default=None, type=str, help="This is the full path to your fmriprep dir")
parser.add_argument('--bidsDir', default=None, type=str, help="This is the full path to your BIDS directory")
parser.add_argument('--cores', default=None, type=int, help="This is the number of parallel jobs to run")

args = parser.parse_args()

# inputs
prep_data = args.fmriprepDir
bids_dir = os.path.join(args.bidsDir, 'rawdata')
cores = args.cores

# # Obtain Echo files
# find the prefix and suffix to that echo #
echo_images = [f for root, dirs, files in os.walk(prep_data)
               for f in files if ('_echo-' in f) & (f.endswith('_bold.nii.gz'))]

# Make a list of filenames that match the prefix
image_prefix_list = [re.search('(.*)_echo-', f).group(1) for f in echo_images]
image_prefix_list = set(image_prefix_list)

# Makes a dataframe where column 1 is Sub, column 2 is inputFiles and column 3 is echo_times
data = []
for acq in image_prefix_list:
    # Use RegEx to find Sub
    sub = "sub-" + re.search('sub-(.*)_task', acq).group(1)
    # Use RegEx to find Task
    task = "task-" + re.search('task-(.*)_run', acq).group(1)
    # Make a list of the json files w/ appropriate header info from BIDS
    ME_headerinfo = [os.path.join(root, f) for root, dirs, files in os.walk(bids_dir) for f in files
                     if (acq in f) & (sub in f) & (f.endswith('_bold.json'))]

    # Read Echo times out of header info and sort
    echo_times = [json.load(open(f))['EchoTime'] for f in ME_headerinfo]
    echo_times.sort()

    # Find images matching the appropriate acq prefix
    acq_image_files = [os.path.join(root, f) for root, dirs, files in os.walk(prep_data) for f in files
                       if (acq in f) & (sub in f) & ('echo' in f) & (f.endswith('_desc-preproc_bold.nii.gz'))]
    acq_image_files.sort()

    out_dir = os.path.join(
        os.path.abspath(
            os.path.dirname(prep_data)), "tedana/%s/%s" % (sub, task))

    # Create tedana directory
    tedana_path = os.path.join(
            os.path.abspath(
                os.path.dirname(prep_data)), "tedana/%s" % sub)
    if not os.path.exists(tedana_path):
        os.makedirs(tedana_path)

    data.append([sub, task, acq_image_files, echo_times, out_dir])

InData_df = pd.DataFrame(data=data, columns=['sub', 'task', 'echo_files', 'echo_times', 'out_dir'])
args = zip(InData_df['sub'].tolist(),
           InData_df['task'].tolist(),
           InData_df['echo_files'].tolist(),
           InData_df['echo_times'].tolist(),
           InData_df['out_dir'].tolist())

# Changes can be reasonably made to
# fittype: 'loglin' is faster but maybe less accurate than 'curvefit'
# tedpca:'mdl' Minimum Description Length returns the least number of components (default) and recommeded
# 'kic' Kullback-Leibler Information Criterion medium aggression
# 'aic' Akaike Information Criterion least aggressive; i.e., returns the most components.
# gscontrol: Post-processing to remove spatially diffuse noise.
# Global signal regression (GSR), minimum image regression (MIR),
# But anatomical CompCor, Go Decomposition (GODEC), and robust PCA can also be used


def run_tedana(sub_to_use, task_to_use, echo_files, echo_times_to_use, out_dir_to_use):
    time.sleep(2)

    workflows.tedana_workflow(
        echo_files,
        echo_times_to_use,
        out_dir=out_dir_to_use,
        prefix="%s_%s_space-Native" % (sub_to_use, task_to_use),
        fittype="curvefit",
        tedpca="kic",
        verbose=True,
        gscontrol=None)


if __name__ == '__main__':
    pool = Pool(cores)
    results = pool.starmap(run_tedana, args)
