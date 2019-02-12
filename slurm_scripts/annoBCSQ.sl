#!/bin/bash
#annoBCSQ.sl 
#SBATCH --job-name	AnnoBCSQ
#SBATCH --time		1-00:00:00
#SBATCH --mem		1G
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/bcsq/bcsq-%j.out
#SBATCH --output	slurm/bcsq/bcsq-%j.out


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

if [ ${#sourcetagarray[@]} -gt 0 ] || [ ${snpeff} = yes ] || [ ${vep} = yes ]; then
	input=${PROJECT_PATH}/merge/${PROJECT}_ann.vcf.gz
else
	input=${unannotatedvcf}
fi
mkdir -p ${PROJECT_PATH}/bcsq
output=${PROJECT_PATH}/bcsq/${PROJECT}_ann.vcf.gz
module purge
module load BCFtools

if [ -f ${output}.done ]; then
	echo -e "${output} already complete."
else
	STARTTIME=$(date +%s)
	scontrol update jobid=${SLURM_JOB_ID} jobname=BCSQ_${PROJECT}
	cmd="$(which bcftools) csq \
		--fasta-ref ${REFA} \
		--gff-annot ${GFF3forBCSQ} \
		-p s \
		-Oz \
		-o ${output} \
		--phase a \
		${input}"
	echo $cmd
	eval $cmd || exit $?
	mkdir -p ${PROJECT_PATH}/done/bcsq
	touch ${PROJECT_PATH}/done/bcsq/$(basename ${output}).done
	ENDTIME=$(date +%s)
	DURATION=$(($ENDTIME - $STARTTIME))
	printf "bcftools CSQ completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))
fi
if [ -f ${output}.tbi.done ]; then
	echo -e "${output}.tbi already complete."
else
	STARTTIME=$(date +%s)
	scontrol update jobid=${SLURM_JOB_ID} jobname=BCSQindex_${PROJECT}
	cmd="srun $(which bcftools) index -t ${output}"
	echo $cmd
	eval $cmd || exit $?
	touch ${PROJECT_PATH}/done/bcsq/$(basename ${output}).tbi.done
	ENDTIME=$(date +%s)
	DURATION=$(($ENDTIME - $STARTTIME))
	printf "bcftools CSQ index completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))
fi

exit 0