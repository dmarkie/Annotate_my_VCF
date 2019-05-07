#!/bin/bash
# merge.sl 
# this script is intended to take a collection of non-overlapping contig vcf.gz files, all with the same individuals in them, and stitch them together into one vcf.gz
#SBATCH --job-name	MergeVCFs
#SBATCH --time		1:00:00
#SBATCH --mem		4G
#SBATCH --cpus-per-task	2
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --error		slurm/merge/merge-%j.out
#SBATCH --output	slurm/merge/merge-%j.out

if [ -f ${parameterfile} ];then
	source ${parameterfile}
else
	echo -e "Can't find the parameter file ${parameterfile}."
	exit 1
fi

# if the final output and done file already exists then exit with success
if [ -f ${PROJECT_PATH}/done/merge/${PROJECT}.done ]; then
	echo "INFO: Output from Merge for ${PROJECT} already available"
 	exit 0
fi

REFA=${REF}.fasta
CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
CONTIG=${CONTIGARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}
mkdir -p ${PROJECT_PATH}/merge
if [ ${#CONTIGARRAY[@]} -gt 1 ]; then
	# generate the list of inputs 
	for CONTIG in ${CONTIGARRAY[@]}; do
		#variant="${variant} I=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz"
		variant="${variant} -I ${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz"
	done

	scontrol update jobid=${SLURM_JOB_ID} jobname=Merge_${PROJECT}

	if [  ! -f ${PROJECT_PATH}/done/merge/${PROJECT}_ann.vcf.gz.done ]; then
		module purge
#		module load picard
#		cmd="srun $(which java) -jar $EBROOTPICARD/picard.jar GatherVcfs \
#			${variant} \
#			O=${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz"

		module load GATK4
		cmd="srun gatk --java-options -Xmx2g GatherVcfs \
			${variant} \
			-O ${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz"
		echo $cmd
		eval $cmd || exit 1$?
		mkdir -p ${PROJECT_PATH}/done/merge
		touch ${PROJECT_PATH}/done/merge/${PROJECT}_ann.vcf.gz.done
	else
		echo "INFO: Output from Merge for ${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz already available"		
	fi
	if [  ! -f ${PROJECT_PATH}/done/merge/${PROJECT}_ann.vcf.gz.tbi.done ]; then
		module purge
		module load BCFtools
		cmd="$(which bcftools) index -t ${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz"
		echo $cmd
		eval $cmd || exit 1$?
		touch ${PROJECT_PATH}/done/merge/${PROJECT}_ann.vcf.gz.tbi.done
	else
		echo "INFO: Output from Merge for ${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz.tbi already available"
	fi

elif [ ${#CONTIGARRAY[@]} -eq 1 ]; then
	mv ${PROJECT_PATH}/ann/${CONTIGARRAY[0]}_ann.vcf.gz ${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz
	mkdir -p ${PROJECT_PATH}/done/merge
	touch ${PROJECT_PATH}/done/merge/${PROJECT}_ann.vcf.gz.done
	mv ${PROJECT_PATH}/ann/${CONTIGARRAY[0]}_ann.vcf.gz.tbi ${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz.tbi
	touch ${PROJECT_PATH}/done/merge/${PROJECT}_ann.vcf.gz.tbi.done
else
	echo "There are no appropriate \"contig\" files in ${PROJECT_PATH}/ann."
	exit 1
fi


touch ${PROJECT_PATH}/done/merge/${PROJECT}.done


exit 0
