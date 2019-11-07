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

echo "Cleanup on $(date) on $(hostname)"
echo "$0 $*"

if [ -f ${parameterfile} ]
then
	source ${parameterfile}
else
	exit 0
fi

if [ -d ${PROJECT_PATH}/snpeff ]
then
	cmd="srun rm -r ${PROJECT_PATH}/snpeff"
	echo $cmd
	eval $cmd || exit 1
fi

if [ -d ${PROJECT_PATH}/vep ]
then
	cmd="srun rm -r ${PROJECT_PATH}/vep"
	echo $cmd
	eval $cmd || exit 1
fi

if [ -d ${PROJECT_PATH}/ann ]
then
	cmd="srun rm -r ${PROJECT_PATH}/ann"
	echo $cmd
	eval $cmd || exit 1
fi

if [ -d ${PROJECT_PATH}/merge ]
then
	cmd="srun rm -r ${PROJECT_PATH}/merge"
	echo $cmd
	eval $cmd || exit 1
fi
if [ -d ${PROJECT_PATH}/bcsq ]
then
	cmd="srun rm -r ${PROJECT_PATH}/bcsq"
	echo $cmd
	eval $cmd || exit 1
fi

if [ -d ${PROJECT_PATH}/move ]
then
	cmd="srun rm -r ${PROJECT_PATH}/move"
	echo $cmd
	eval $cmd || exit 1
fi

if [ -d ${PROJECT_PATH}/done ]
then
	cmd="srun rm -r ${PROJECT_PATH}/done"
	echo $cmd
	eval $cmd || exit 1
fi

if [ -d ${PROJECT_PATH} ]; then
	COUNT=0
	cmd="srun tar --exclude-vcs -zcf ${dest}/${PROJECT}.tar.gz ${PROJECT_PATH}"
	echo ${cmd}
	until [ $COUNT -gt 10 ] || eval ${cmd}
	do
		((COUNT++))
		sleep 20s
		(echo "--FAILURE--      Sending compressed archive of ${PROJECT_PATH} to ${dest} failed. Retrying..." 1>&2)
	done
	if [ $COUNT -le 10 ]
	then
		cmd="srun rm -r ${PROJECT_PATH}"
		echo $cmd
		eval $cmd || exit 1
	else
		(echo "--FAILURE--      Unable to send compressed archive of ${PROJECT_PATH} to ${dest}" 1>&2)
		exit 1
	fi
fi

echo -e "It looks like you have successfully completed your annotation which should now be located in the directory ${dest}.\nYou can now delete this file."
	
exit 0
