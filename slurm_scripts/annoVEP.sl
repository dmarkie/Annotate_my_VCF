#!/bin/bash
#annoVEP.sl 
#SBATCH --job-name	AnnoVEP
#SBATCH --time		1-00:00:00
#SBATCH --mem		3G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	2
#SBATCH --error		slurm/vep/vep-%A_%a-%j.out
#SBATCH --output	slurm/vep/vep-%A_%a-%j.out

RAMDISK=0

echo "AnnoVEP on $(date) on $(hostname)"
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
CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
CONTIG=${CONTIGARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}

# VEP annotation

if  [ -f ${PROJECT_PATH}/done/vep/${CONTIG}_VEP.vcf.gz.done ] || \
	[ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done ]
then
	echo -e "VEP annotation already complete."
else
	scontrol update \
		jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} \
		jobname=VEP_${PROJECT}_${CONTIG}
		
	STARTTIME=$(date +%s)
	
	if [[ ${snpeff} == "yes" ]]
	then
		input=${PROJECT_PATH}/snpeff/${CONTIG}_SnpEff.vcf.gz
	else
		input=${unannotatedvcf}
	fi
	
	if [ ${CONTIG} != "whole" ]
	then
		output=${SCRATCH_DIR}/${CONTIG}.vcf.gz
		module purge
		module load ${bcftools}
		cmd="srun $(which bcftools) view -r ${CONTIG} ${input} -Oz -o ${output}"
		echo $cmd
		eval $cmd || exit 1
		cmd="srun $(which bcftools) index ${output}"
		echo $cmd
		eval $cmd || exit 1
		input=${output}
	fi
	
	if [ ${#sourcetagarray[@]} -eq 0 ]
	then
		mkdir -p ${PROJECT_PATH}/ann
		output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
	else
		mkdir -p ${PROJECT_PATH}/vep
		output=${PROJECT_PATH}/vep/${CONTIG}_VEP.vcf.gz
	fi
	
	module purge
	module load VEP
	
	cmd="srun \
$(which vep) \
-i ${input} \
--format vcf \
--no_stats \
--offline \
--cache \
--merged \
--use_transcript_ref \
--vcf \
--species ${vepspecies} \
--assembly ${vepassembly} \
--compress_output bgzip \
--gene_phenotype --hgvs \
--fasta ${REFA} \
--hgvsg \
--regulatory \
--protein \
--symbol \
--ccds \
--check_existing \
--exclude_null_alleles \
--fork $SLURM_JOB_CPUS_PER_NODE \
--force_overwrite \
-o ${output}"

	echo $cmd
	eval $cmd || exit $?
	
	ENDTIME=$(date +%s)
	DURATION=$(($ENDTIME - $STARTTIME))
	
	printf "VEP annotation completed in %d:%02d:%02d\n" \
		$(($DURATION/3600)) \
		$(($DURATION%3600/60)) \
		$(($DURATION%60))
	
	mkdir -p ${PROJECT_PATH}/done/vep
	touch ${PROJECT_PATH}/done/vep/${CONTIG}_VEP.vcf.gz.done
fi

if  [ -f ${PROJECT_PATH}/done/vep/${CONTIG}_VEP.vcf.gz.tbi.done ] || \
	[ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]
then
	echo -e "VEP annotation index already complete."
else
	scontrol update \
		jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} \
		jobname=VEPindex_${PROJECT}_${CONTIG}
	
	STARTTIME=$(date +%s)
	
	if [ ${#sourcetagarray[@]} -eq 0 ]
	then
		output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
	else
		output=${PROJECT_PATH}/vep/${CONTIG}_VEP.vcf.gz
	fi
	
	module purge
	module load ${bcftools}
	
	cmd="srun $(which bcftools) index -t ${output}"
	echo $cmd
	eval $cmd || exit $?
	
	ENDTIME=$(date +%s)
	DURATION=$(($ENDTIME - $STARTTIME))
	
	printf "VEP index completed in %d:%02d:%02d\n" \
		$(($DURATION/3600)) \
		$(($DURATION%3600/60)) \
		$(($DURATION%60))
		
	touch ${PROJECT_PATH}/done/vep/${CONTIG}_VEP.vcf.gz.tbi.done
fi

echo "Annotate VEP complete"

exit 0
