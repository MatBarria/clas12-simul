#!/bin/bash

#SBATCH --account=clas12
#SBATCH --partition=production
#SBATCH --job-name=lepto-gemc
#SBATCH --output=./out/%x.%j.array%a.out
#SBATCH --error=./err/%x.%j.array%a.err
#SBATCH --time=00:10:00
#SBATCH --mem=1G
#SBATCH --array=1-1000

echo "This is JOB ${SLURM_ARRAY_JOB_ID} task ${SLURM_ARRAY_TASK_ID}"
echo "Its name is ${SLURM_JOB_NAME} and its ID is ${SLURM_JOB_ID}"
### FUNCTIONS
AZ_assignation(){
    # Function to assignate A and Z according to the target specified
    if [[ "$1" == "D" || "$1" == "D2" ]]
    then
	echo "Using Deuterium"
	A=2
	Z=1
	echo "A=${A} and Z=${Z}"
    elif [[ "$1" == "C" ]]
    then
	echo "Using Carbon"
	A=12
	Z=6
	echo "A=${A} and Z=${Z}"
    elif [[ "$1" == "Fe" ]]
    then
	echo "Using Iron"
	A=56
	Z=26
	echo "A=${A} and Z=${Z}"
    elif [[ "$1" == "Pb" ]]
    then
	echo "Using Lead"
	A=207
	Z=82
	echo "A=${A} and Z=${Z}"
    else
	echo "No target input!"
	exit 1
    fi    
}

directory_files_check(){
    # checking execution directories
    if [[ ! -d ${LEPTO_dir} || ! -d ${execution_dir} || ! -d ${out_dir_lepto} || ! -d ${leptoLUND_dir} || ! -d ${out_dir_gemc} ]]
    then
	echo "One of the necessary directories does not exist."
	exit 1
    fi
    # checking lepto executable existence
    if [[ ! -f ${LEPTO_dir}/lepto.exe ]]
    then
	echo "The executable does not exist"
	exit 1
    fi
}

executable_file_check(){
    # checking dat2tuple executable existence
    if [[ ! -f ${dat2tuple_dir}/bin/dat2tuple ]]
    then
	echo "The dat2tuple executable does not exist"
	exit 1
    fi
}

## DIRECTORIES
main_dir=$(pwd)
LEPTO_dir=~/Lepto64Sim/bin ## CHECK THIS DIRECTORY!
execution_dir=/volatile/clas12/emolinac
lepto2dat_dir=${main_dir}/thrown/lepto2dat
dat2tuple_dir=${main_dir}/thrown/dat2tuple
leptoLUND_dir=${main_dir}/reconstructed
gcard_dir=${leptoLUND_dir}

out_dir_lepto=/work/clas12/rg-e/emolinac/lepto
out_dir_gemc=/work/clas12/rg-e/emolinac/evio

## VARIABLES
Nevents=100
target=D
id=${target}_${SLURM_ARRAY_JOB_ID}${SLURM_ARRAY_TASK_ID}
temp_dir=${execution_dir}/${id}


###########################################################################
###########################       PREAMBLE      ###########################
###########################################################################
# Directory and files check
directory_files_check

# Create folder in volatile to not interfere with other lepto executions
mkdir ${temp_dir}
cd ${temp_dir}

###########################################################################
###########################       LEPTO         ###########################
###########################################################################
# Prereqs setting
if [ -z "${CERN}" ]
then
    source ~/software/env_scripts/set_all.sh
fi

lepto_out=lepto_out_${id}
z_shift=0.

# Copy lepto executable to temp folder
cp ${LEPTO_dir}/lepto.exe ${temp_dir}/lepto_${id}.exe

# Assign the targets A and Z numbers
AZ_assignation ${target}
echo "${Nevents} ${A} ${Z}" > lepto_input.txt

# EXECUTE LEPTO
lepto_${id}.exe < lepto_input.txt > ${lepto_out}.txt

# Transform lepto's output to dat files
cp ${lepto2dat_dir}/lepto2dat.pl ${temp_dir}/
perl lepto2dat.pl ${z_shift} < ${lepto_out}.txt > ${lepto_out}.dat

# Transform's dat files into ROOT NTuples
executable_file_check
cp ${dat2tuple_dir}/bin/dat2tuple ${temp_dir}/
./dat2tuple ${lepto_out}.dat ${lepto_out}_ntuple.root

###########################################################################
###########################       GEMC          ###########################
###########################################################################
# Prereqs setting
if [ -z "${GEMC_DATA_DIR}" ]
then
    source /group/clas12/packages/setup.sh
    module load clas12
fi

gemc_out=gemc_out_${id}

# Transform lepto's output to LUND format
LUND_lepto_out=LUND${lepto_out}
cp ${leptoLUND_dir}/leptoLUND.pl ${temp_dir}/
perl leptoLUND.pl ${z_shift} < ${lepto_out}.txt > ${LUND_lepto_out}.dat

# Copy the gcard you'll use into the temp folder
cp ${gcard_dir}/clas12.gcard ${temp_dir}/

# EXECUTE GEMC
gemc clas12.gcard -INPUT_GEN_FILE="LUND, ${LUND_lepto_out}.dat" -OUTPUT="evio, ${gemc_out}.ev" -USE_GUI="0"

# Move output to its folder
#mv ${lepto_out}.txt ${lepto_out}.dat ${lepto_out}_ntuple.root ${LUND_lepto_out}.dat ${out_dir_lepto}/
mv ${lepto_out}_ntuple.root ${out_dir_lepto}/
mv ${gemc_out}.ev ${out_dir_gemc}/

# Remove folder
rm -rf ${temp_dir}
echo "Done!"