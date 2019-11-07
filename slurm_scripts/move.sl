#!/bin/bash
#annoBCSQ.sl 
#SBATCH --job-name	Move
#SBATCH --time		4:00:00
#SBATCH --mem		24M
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/move/move-%j.out
#SBATCH --output	slurm/move/move-%j.out


RAMDISK=0

echo "Move on $(date) on $(hostname)"
echo "$0 $*"

set -euf -o pipefail
if [ -f ${parameterfile} ]
then
	source ${parameterfile}
else
	echo -e "Can't find the parameter file ${parameterfile}."
	exit 1
fi

REFA=${REF}.fasta
mkdir -p ${PROJECT_PATH}/move
# Generate a list of all the IDs in the output vcf.gz file

if [[ ${BCSQ} = "yes" ]]
then
	input=${PROJECT_PATH}/bcsq/${PROJECT}_ann.vcf.gz
else
	input=${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz
fi

if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_ID.list.done ]
then
	module purge
	module load ${bcftools}
	cmd="$(which bcftools) query -l ${input} > ${PROJECT_PATH}/move/${PROJECT}_ID.list"
	echo $cmd
	eval $cmd || exit 1$?
	mkdir -p ${PROJECT_PATH}/done/move
	touch ${PROJECT_PATH}/done/move/${PROJECT}_ID.list.done
else
	echo "INFO: Output for ${PROJECT_PATH}/move/${PROJECT}_ID.list already available"
fi

# Generate a file of all the annotations, number, types and descriptions in the vcf

if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_annotations.list.done ]
then
	#cmd="srun zcat ${input} | head -n 1000 | grep \"^##INFO=<ID=\" | sed 's/^##INFO=<\(.\+\)>$/\1/' > ${PROJECT_PATH}/move/${PROJECT}_annotations.list"
	module purge
	module load ${bcftools}
	cmd="srun \
$(which bcftools) view \
-h ${input} \
-Ov | \
grep \"^##INFO=<ID=\" | \
sed 's/^##INFO=<\(.\+\)>$/\1/' > \
${PROJECT_PATH}/move/${PROJECT}_annotations.list"
	echo $cmd
	eval "$cmd" || exit 1$?
	touch ${PROJECT_PATH}/done/move/${PROJECT}_annotations.list.done
else
	echo "INFO: Output for ${PROJECT_PATH}/move/${PROJECT}_annotations.list already available"
fi

set +u

if [ -z "${dest}" ]
then
	count=1
	
	while [ -d $(dirname ${unannotatedvcf})/${PROJECT}_Annotated_${count} ]
	do
		count=$(($count+1))
	done
	
	dest=$(dirname ${unannotatedvcf})/${PROJECT}_Annotated_${count}
	
	echo "dest=${dest}" >> ${parameterfile}
fi
if ! mkdir -p ${dest}
	then
	echo "Error creating destination folder!"
	exit 1
fi

echo -e "dest is ${dest}"

set -u


if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_ann.vcf.gz.move.done ]
then
	COUNT=0
	cmd="srun rsync -avP $(dirname ${input})/ ${dest}"
	echo ${cmd}
	until [ $COUNT -gt 10 ] || eval srun rsync -avP $(dirname ${input})/ ${dest}
	do
		((COUNT++))
		sleep 20s
		(echo "--FAILURE--      Syncing files from $(dirname ${input}) to ${dest} failed. Retrying..." 1>&2)
	done
	if [ $COUNT -le 10 ]
	then
		touch ${PROJECT_PATH}/done/move/${PROJECT}_ann.vcf.gz.move.done
	else
		(echo "--FAILURE--      Unable to move files from $(dirname ${input}) to ${dest}" 1>&2)
		exit 1
	fi
fi

if [ ! -f ${PROJECT_PATH}/done/move/move.done ]
then
	COUNT=0
	cmd="srun rsync -avP ${PROJECT_PATH}/move/ ${dest}"
	echo ${cmd}
	until [ $COUNT -gt 10 ] || eval ${cmd}
	do
		((COUNT++))
		sleep 20s
		(echo "--FAILURE--      Syncing files from ${PROJECT_PATH}/move/ to ${dest} failed. Retrying..." 1>&2)
	done
	if [ $COUNT -le 10 ]
	then
		touch ${PROJECT_PATH}/done/move/move.done
	else
		(echo "--FAILURE--      Unable to move files from ${PROJECT_PATH}/move/ to ${dest}" 1>&2)
		exit 1
	fi
fi

if [ ! -f ${PROJECT_PATH}/done/move/script_tar.done ]
then
	cmd="srun \
tar --exclude-vcs \
-cf ${PROJECT_PATH}/$(basename ${BASEDIR})_$(date +%F_%H-%M-%S_%Z).tar \
${BASEDIR}"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/script_tar.done
fi

touch ${PROJECT_PATH}/done/move/${PROJECT}.done

echo "Move completed"

exit 0
