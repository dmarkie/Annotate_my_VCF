#!/bin/bash
#annoSnpEff.sl 
#SBATCH --job-name	AnnoSnpEff
#SBATCH --time		1-00:00:00
#SBATCH --mem		8G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	2
#SBATCH --error		slurm/annosnpeff-%A_%a-%j.out
#SBATCH --output	slurm/annosnpeff-%A_%a-%j.out

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
CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
CONTIG=${CONTIGARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}

if [[ ${vep} != yes ]] && [ ${#sourcetagarray[@]} -eq 0 ]; then
	output=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz
else
	output=${PROJECT_PATH}/${CONTIG}_SnpEff.vcf.gz
fi

if [ -f ${PROJECT_PATH}/${CONTIG}_snpeff.vcf.gz.done ] || [ -f ${PROJECT_PATH}/${CONTIG}_ann.vcf.gz.done ]; then
	echo -e "SnpEff annotation already complete."
	exit 0
fi

input=${unannotatedvcf}

##snpeff annotation
if [[ ${snpeff_format} = "EFF" ]]; then
	format="-formatEff"
else
	format=""
fi
module purge
module load BCFtools
module load snpEff
scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=SnpEff_${PROJECT}_${CONTIG}
STARTTIME=$(date +%s)
if [ ${CONTIG} == "whole" ];then
	tabregion=""
else
	tabregion="${CONTIG}"
fi
cmd="srun tabix -h ${input} ${tabregion} | $(which java) -Xmx${SLURM_MEM_PER_NODE}m \
	-jar $EBROOTSNPEFF/snpEff.jar \
	${format} \
	-c $EBROOTSNPEFF/snpEff.config \
	-s ${PROJECT_PATH}/${CONTIG}_snpEff_summary.html \
	-nodownload \
	-noStats \
	-t \
	${snpeffdataversion} \
	| bgzip > ${output}"
echo $cmd
eval $cmd || exit $?
module purge
module load BCFtools
cmd="srun $(which bcftools) index -t ${output}"
echo $cmd
eval $cmd || exit $?
ENDTIME=$(date +%s)
DURATION=$(($ENDTIME - $STARTTIME))
printf "SnpEff completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))
touch ${PROJECT_PATH}/${CONTIG}_snpeff.vcf.gz.done

exit 0
