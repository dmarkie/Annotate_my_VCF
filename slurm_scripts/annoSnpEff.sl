#!/bin/bash
#annoSnpEff.sl 
#SBATCH --job-name	AnnoSnpEff
#SBATCH --time		1-00:00:00
#SBATCH --mem		8G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	2
#SBATCH --error		slurm/snpeff/snpeff-%A_%a-%j.out
#SBATCH --output	slurm/snpeff/snpeff-%A_%a-%j.out

RAMDISK=0
STARTTIME=$(date +%s)

echo "$(date) on $(hostname)"
set -euf -o pipefail
if [ -f ${parameterfile} ];then
	source ${parameterfile}
else
	echo -e "Can't find the parameter file ${parameterfile}."
	exit 1
fi
REFA=${REF}.fasta
CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
CONTIG=${CONTIGARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}


input=${unannotatedvcf}
if [ -f "${PROJECT_PATH}/done/snpeff/${CONTIG}_SnpEff.vcf.gz.done" ] || [ -f "${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done" ]; then
	echo -e "SnpEff annotation already complete."
else
	if [ ${CONTIG} != "whole" ];then
		output=${SCRATCH_DIR}/${CONTIG}.vcf.gz
		module purge
		module load BCFtools
		cmd="srun $(which bcftools) view -r ${CONTIG} ${input} -Oz -o ${output}"
		echo $cmd
		eval $cmd || exit 1
		cmd="srun $(which bcftools) index ${output}"
		echo $cmd
		eval $cmd || exit 1
		input=${output}
	fi

##snpeff annotation
	if [[ ${vep} != yes ]] && [ ${#sourcetagarray[@]} -eq 0 ]; then
		mkdir -p ${PROJECT_PATH}/ann
		output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
	else
		mkdir -p ${PROJECT_PATH}/snpeff
		output=${PROJECT_PATH}/snpeff/${CONTIG}_SnpEff.vcf.gz
	fi
	if [[ ${snpeff_format} = "EFF" ]]; then
		format="-formatEff"
	else
		format=""
	fi
	module purge
	module load BCFtools
	module load snpEff
	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=SnpEff_${PROJECT}_${CONTIG}
	if [ ${CONTIG} == "whole" ];then
		region=""
	else
		region="-r ${CONTIG}"
	fi
	cmd="srun $(which java) -Xmx${SLURM_MEM_PER_NODE}m \
		-jar $EBROOTSNPEFF/snpEff.jar \
		${format} \
		-c $EBROOTSNPEFF/snpEff.config \
		-s ${PROJECT_PATH}/${CONTIG}_snpEff_summary.html \
		-nodownload \
		-noStats \
		-t \
		${snpeffdataversion} \
		${input} \
		| bgzip > ${output}"
	echo $cmd
	eval $cmd || exit $?
	mkdir -p ${PROJECT_PATH}/done/$(basename $(dirname ${output}))
	touch ${PROJECT_PATH}/done/$(basename $(dirname ${output}))/$(basename ${output}).done
fi
if [ -f ${PROJECT_PATH}/done/snpeff/${CONTIG}_Snpeff.vcf.gz.tbi.done ] || [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]; then
	echo -e "SnpEff annotation index already complete."
else	
	if [[ ${vep} != yes ]] && [ ${#sourcetagarray[@]} -eq 0 ]; then
		output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
	else
		output=${PROJECT_PATH}/snpeff/${CONTIG}_SnpEff.vcf.gz
	fi
	module purge
	module load BCFtools
	cmd="srun $(which bcftools) index -t -f ${output}"
	echo $cmd
	eval $cmd || exit $?
	touch ${PROJECT_PATH}/done/$(basename $(dirname ${output}))/$(basename ${output}).tbi.done
fi
ENDTIME=$(date +%s)
DURATION=$(($ENDTIME - $STARTTIME))
printf "SnpEff completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))

exit 0
