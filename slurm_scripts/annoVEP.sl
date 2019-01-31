#!/bin/bash
#annoVEP.sl 
#SBATCH --job-name	AnnoVEP
#SBATCH --time		1-00:00:00
#SBATCH --mem		3G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	2
#SBATCH --error		slurm/annoVEP-%A_%a-%j.out
#SBATCH --output	slurm/annoVEP-%A_%a-%j.out

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


if [[ ${snpeff} == "yes" ]]; then
	input=${PROJECT_PATH}/${CONTIG}_SnpEff.vcf.gz
else
	input=${unannotatedvcf}
fi

# VEP annotation
if [[ ${vep} == "yes" ]]; then
	if [ -f ${PROJECT_PATH}/${CONTIG}_VEP.vcf.gz.done ] || [ -f ${PROJECT_PATH}/${CONTIG}_BCSQ.bcf.gz.done ] || [ -f ${PROJECT_PATH}/${CONTIG}_ann.vcf.gz.done ]; then
		echo -e "VEP annotation already complete."
	else
		scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=VEP_${PROJECT}_${CONTIG}
		if [[ ${BCSQ} != yes ]] && [ ${#sourcetagarray[@]} -eq 0 ]; then
			output=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz
		elif [[ ${BCSQ} != yes ]]; then
			output=${PROJECT_PATH}/${CONTIG}_VEP.vcf.gz
		else
			output=${SCRATCH_DIR}/${CONTIG}_VEP.vcf.gz
		fi
		STARTTIME=$(date +%s)
		module purge
		module load VEP
		if [ ${CONTIG} == "whole" ];then
			tabregion=""
		else
			tabregion="${CONTIG}"
		fi
		cmd="srun $(which tabix) -h ${input} ${tabregion} | \
			$(which vep) \
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
			-o ${output}"
		echo $cmd
		eval $cmd || exit $?
	
		module purge
		module load BCFtools
		cmd="srun $(which bcftools) index -t ${output}"
		echo $cmd
		eval $cmd || exit $?
	
		ENDTIME=$(date +%s)
		DURATION=$(($ENDTIME - $STARTTIME))
		input=${output}
		printf "VEP completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))
	fi
	if [[ ${BCSQ} == "yes" ]]; then
		if [ -f ${PROJECT_PATH}/${CONTIG}_BCSQ.bcf.gz.done ] || [ -f ${PROJECT_PATH}/${CONTIG}_ann.vcf.gz.done ]; then
			echo -e "BCSQ annotation already complete."
			exit 0
		else
			scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=BCSQ_${PROJECT}_${CONTIG}
			STARTTIME=$(date +%s)
			if [ ${#sourcetagarray[@]} -eq 0 ]; then
				output=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz
				foutput="-Oz"
				findex="-t"
			else
				output=${PROJECT_PATH}/${CONTIG}_BCSQ.bcf.gz
				foutput="-Ob"
				findex=""
			fi
			module purge
			module load BCFtools
			cmd="$(which bcftools) csq \
			--fasta-ref ${REFA} \
			--gff-annot ${GFF3forBCSQ} \
			-p s \
			${foutput} \
			-o ${output} \
			--phase a \
			${input}"
			echo $cmd
			eval $cmd || exit $?
	
			cmd="srun $(which bcftools) index ${findex} ${output}"
			echo $cmd
			eval $cmd || exit $?

			ENDTIME=$(date +%s)
			DURATION=$(($ENDTIME - $STARTTIME))
			printf "BCSQ completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))
		fi
	fi
	touch ${PROJECT_PATH}/$(basename ${output}).done

fi

exit 0
