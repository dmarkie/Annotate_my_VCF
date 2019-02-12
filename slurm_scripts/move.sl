#!/bin/bash
#annoBCSQ.sl 
#SBATCH --job-name	Move
#SBATCH --time		1-00:00:00
#SBATCH --mem		1G
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/move/move-%j.out
#SBATCH --output	slurm/move/move-%j.out


RAMDISK=0

echo "$(date) on $(hostname)"
set -euf -o pipefail
if [ -f ${parameterfile} ];then
	source ${parameterfile}
else
	echo -e "Can't find the parameter file ${parameterfile}."
	exit 1
fi
REFA=${REF}.fasta
mkdir -p ${PROJECT_PATH}/move
# Generate a list of all the IDs in the output vcf.gz file
if [[ ${BCSQ} = "yes" ]]; then
	input=${PROJECT_PATH}/bcsq/${PROJECT}_ann.vcf.gz
else
	input=${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz
fi
if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_ID.list.done ]; then
	module purge
	module load BCFtools
	cmd="$(which bcftools) query -l ${input} > ${PROJECT_PATH}/move/${PROJECT}_ID.list"
	echo $cmd
	eval $cmd || exit 1$?
	mkdir -p ${PROJECT_PATH}/done/move
	touch ${PROJECT_PATH}/done/move/${PROJECT}_ID.list.done
else
	echo "INFO: Output for ${PROJECT_PATH}/move/${PROJECT}_ID.list already available"
fi
# Generate a file of all the annotations, number, types and descriptions in the vcf
if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_annotations.list.done ]; then
	cmd="srun zcat ${input} | head -n 1000 | grep \"^##INFO=<ID=\" | sed 's/^##INFO=<\(.\+\)>$/\1/' > ${PROJECT_PATH}/move/${PROJECT}_annotations.list"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/${PROJECT}_annotations.list.done
else
	echo "INFO: Output for ${PROJECT_PATH}/move/${PROJECT}_annotations.list already available"
fi
if [ -z ${DEST} ]; then
	count="1"
	while [ -d $(dirname ${unannotatedvcf})/${PROJECT}_Annotated_${count} ]; do
		count=$(($count+1))
	done
	DEST=$(dirname ${unannotatedvcf})/${PROJECT}_Annotated_${count}
	if ! mkdir -p ${DEST}; then
		echo "Error creating destination folder!"
		exit 1
	fi
	echo "DEST=${DEST}" >> ${parameterfile}
fi
echo -e "DEST is ${DEST}"

if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_ann.vcf.gz.move.done ]; then
	cmd="srun mv ${input} ${DEST}"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/${PROJECT}_ann.vcf.gz.move.done
fi
if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_ann.vcf.gz.tbi.move.done ]; then
	cmd="srun mv ${input}.tbi ${DEST}"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/${PROJECT}_ann.vcf.gz.tbi.move.done
fi
if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_ID.list.move.done ]; then
	cmd="srun mv ${PROJECT_PATH}/move/${PROJECT}_ID.list ${DEST}"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/${PROJECT}_ID.list.move.done
fi
if [ ! -f ${PROJECT_PATH}/done/move/${PROJECT}_annotations.list.move.done ]; then
	cmd="srun mv ${PROJECT_PATH}/move/${PROJECT}_annotations.list ${DEST}"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/${PROJECT}_annotations.list.move.done
fi
if [ ! -f ${PROJECT_PATH}/done/move/script_tar.done ]; then
	cmd="srun tar --exclude-vcs -cf ${PROJECT_PATH}/$(basename ${BASEDIR})_$(date +%F_%H-%M-%S_%Z).tar ${BASEDIR}"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/done/move/script_tar.done
fi

touch ${PROJECT_PATH}/done/move/${PROJECT}.done

exit 0