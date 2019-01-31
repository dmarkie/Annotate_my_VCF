#!/bin/bash
# merge.sl 
# this script is intended to take a collection of non-overlapping contig vcf.gz files, all with the same individuals in them, and stitch them together into one vcf.gz
#SBATCH --job-name	MergeVCFs
#SBATCH --time		48:00:00
#SBATCH --mem		12G
#SBATCH --cpus-per-task	2
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --error		slurm/merge-%j.out
#SBATCH --output	slurm/merge-%j.out

if [ -f ${parameterfile} ];then
	source ${parameterfile}
else
	echo -e "Can't find the parameter file ${parameterfile}."
	exit 1
fi

# if the final output and done file already exists then exit with success
if [ -f ${PROJECT_PATH}/${PROJECT}.done ]; then
	echo "INFO: Output from Merge for ${PROJECT} already available"
 	exit 0
fi

REFA=${REF}.fasta
CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
CONTIG=${CONTIGARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}

if [ ${#CONTIGARRAY[@]} -gt 1 ]; then
	# generate the list of inputs 
	for CONTIG in ${CONTIGARRAY[@]}; do
		variant="${variant} I=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz"
	done

	scontrol update jobid=${SLURM_JOB_ID} jobname=Merge_${PROJECT}

	if [  ! -f ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.done ]; then
		module purge
		module load picard
		cmd="srun $(which java) -jar $EBROOTPICARD/picard.jar GatherVcfs \
			${variant} \
			O=${PROJECT_PATH}/${PROJECT}_ann.vcf.gz"

		echo $cmd
		eval $cmd || exit 1$?
		touch ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.done
	else
		echo "INFO: Output from Merge for ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz already available"		
	fi
	if [  ! -f ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi.done ]; then
		module purge
		module load BCFtools
		cmd="$(which bcftools) index -t ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz"
		echo $cmd
		eval $cmd || exit 1$?
		touch ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi.done
	else
		echo "INFO: Output from Merge for ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi already available"
	fi

elif [ ${#CONTIGARRAY[@]} -eq 1 ]; then
	mv ${PROJECT_PATH}/${CONTIGARRAY[0]}_ann.vcf.gz ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz
	mv ${PROJECT_PATH}/${CONTIGARRAY[0]}_ann.vcf.gz.tbi ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi
else
	echo "There are no appropriate \"contig\" files in ${PROJECT_PATH}."
	exit 1
fi


# Generate a list of all the IDs in the output vcf.gz file
if [ ! -f ${PROJECT_PATH}/${PROJECT}_ID.list.done ]; then
	module purge
	module load BCFtools
	cmd="$(which bcftools) query -l ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz > ${PROJECT_PATH}/${PROJECT}_ID.list"
	echo $cmd
	eval $cmd || exit 1$?
	touch ${PROJECT_PATH}/${PROJECT}_ID.list.done
else
	echo "INFO: Output from Merge for ${PROJECT_PATH}/${PROJECT}_ID.list already available"
fi
# Generate a file of all the annotations, number, types and descriptions in the vcf
if [ ! -f ${PROJECT_PATH}/${PROJECT}_annotations.list.done ]; then
	zcat ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz | head -n 1000 | grep "^##INFO=<ID=" | sed 's/^##INFO=<\(.\+\)>$/\1/' > ${PROJECT_PATH}/${PROJECT}_annotations.list || exit 4
	touch ${PROJECT_PATH}/${PROJECT}_annotations.list.done
else
	echo "INFO: Output from Merge for ${PROJECT_PATH}/${PROJECT}_annotations.list already available"
fi

count="1"
while [ -d $(dirname ${unannotatedvcf})/${PROJECT}_Annotated_${count} ]; do
	count=$(($count+1))
done
DEST=$(dirname ${unannotatedvcf})/${PROJECT}_Annotated_${count}

echo -e "DEST is ${DEST}"
srun mkdir -p ${DEST}/Logs
if [ ! -f ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.move.done ]; then
	mv ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz ${DEST} || exit 2
	touch ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.move.done
fi
if [ ! -f ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi.move.done ]; then
	mv ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi ${DEST} || exit 2
	touch ${PROJECT_PATH}/${PROJECT}_ann.vcf.gz.tbi.move.done
fi
if [ ! -f ${PROJECT_PATH}/${PROJECT}_ID.list.move.done ]; then
	mv ${PROJECT_PATH}/${PROJECT}_ID.list ${DEST} || exit 2
	touch ${PROJECT_PATH}/${PROJECT}_ID.list.move.done
fi
if [ ! -f ${PROJECT_PATH}/${PROJECT}_annotations.list.move.done ]; then
	mv ${PROJECT_PATH}/${PROJECT}_annotations.list ${DEST} || exit 2
	touch ${PROJECT_PATH}/${PROJECT}_annotations.list.move.done
fi
if [ ! -f touch ${PROJECT_PATH}/${PROJECT}slurm.move.done ]; then
	mv ${PROJECT_PATH}/slurm/* ${DEST}/Logs/ || exit 2
	touch ${PROJECT_PATH}/${PROJECT}slurm.move.done
fi
touch ${PROJECT_PATH}/${PROJECT}.done

cd ~

#rm -r ${PROJECT_PATH}

exit 0
