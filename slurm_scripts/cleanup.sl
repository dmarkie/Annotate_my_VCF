#!/bin/bash
#annoBCSQ.sl 
#SBATCH --job-name	Cleanup
#SBATCH --time		1:00:00
#SBATCH --mem		24M
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	1
#SBATCH --error		AnnotationCleanup-%j.out
#SBATCH --output	AnnotationCleanup-%j.out

# this will write a slurm out file into the 

echo "$(date) on $(hostname)"
if [ -f ${parameterfile} ];then
	source ${parameterfile}
else
	exit 0
fi

if [ -d ${PROJECT_PATH}/snpeff ]; then
	cmd="srun rm -r ${PROJECT_PATH}/snpeff"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH}/vep ]; then
	cmd="srun rm -r ${PROJECT_PATH}/vep"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH}/ann ]; then
	cmd="srun rm -r ${PROJECT_PATH}/ann"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH}/merge ]; then
	cmd="srun rm -r ${PROJECT_PATH}/merge"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH}/move ]; then
	cmd="srun rm -r ${PROJECT_PATH}/move"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH}/done ]; then
	cmd="srun rm -r ${PROJECT_PATH}/done"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH} ]; then
	cmd="srun tar --exclude-vcs -zcf ${dest}/${PROJECT}.tar.gz ${PROJECT_PATH}"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH} ]; then
	cmd="srun rm -r ${PROJECT_PATH}"
	echo $cmd
	eval $cmd || exit 1
fi
	
exit 0