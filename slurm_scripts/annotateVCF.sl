#!/bin/bash
#annotateVCF.sl 
#SBATCH --job-name	AnnoVCF
#SBATCH --time		1-00:00:00
#SBATCH --mem		1G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/annovcf-%A_%a-%j.out
#SBATCH --output	slurm/annovcf-%A_%a-%j.out

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

if [ -f ${PROJECT_PATH}/${CONTIG}_ann.vcf.gz.done ]; then
	echo -e "Annotation already complete."
	exit 0
fi

if [[ ${BCSQ} == "yes" ]]; then
	input=${PROJECT_PATH}/${CONTIG}_BCSQ.bcf.gz
elif [[ ${vep} == "yes" ]]; then
	input=${PROJECT_PATH}/${CONTIG}_VEP.vcf.gz
elif [[ ${snpeff} == "yes" ]]; then
	input=${PROJECT_PATH}/${CONTIG}_SnpEff.vcf.gz
else
	input=${unannotatedvcf}
fi

for i in ${!sourcetagarray[@]}; do
	
	echo "Contig ${CONTIG}"
	echo "Source Tag ${sourcetagarray[${i}]}"
	echo "File type ${filetypearray[${i}]}"
	echo "Source file ${sourcefilearray[${i}]}"
	echo "Annotations ${annotatearray[${i}]}"
# this limits the annotation to the contig - it may save time in accessing the source file (no guarantees).	
	if [ ${CONTIG} == "whole" ];then
		region=""
	else
		region="-r ${CONTIG}"
	fi

	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=Ann_${sourcetagarray[${i}]}_${PROJECT}_${CONTIG}
	module purge
	module load BCFtools
	STARTTIME=$(date +%s)
# if from a vcf
	if [[ ${filetypearray[${i}]} == "vcf" ]]; then
		#if this is the last element in the array then output to project path as a gz compressed vcf
		if [ ${i} -eq $((${#sourcetagarray[@]}-1)) ]; then
			output=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz
			cmd1="srun $(which bcftools) \
				annotate \
				-a ${sourcefilearray[${i}]} \
				-c ${annotatearray[${i}]} \
				${region} \
				--collapse all \
				${input} \
				--threads $SLURM_JOB_CPUS_PER_NODE \
				-Oz -o ${output}"
		
			cmd2="srun $(which bcftools) index -t ${output}"

		else		
			output=${SCRATCH_DIR}/${CONTIG}_${sourcetagarray[${i}]}.bcf.gz
			cmd1="srun $(which bcftools) \
				annotate \
				-a ${sourcefilearray[${i}]} \
				-c ${annotatearray[${i}]} \
				${region} \
				--collapse all \
				${input} \
				--threads $SLURM_JOB_CPUS_PER_NODE \
				-Ob -o ${output}"
		
			cmd2="srun $(which bcftools) index ${output}"

		fi
	elif [[ ${filetypearray[${i}]} == "bed" ]] || [[ ${filetypearray[${i}]} == "tab" ]]; then
	#if from a bed or tabbed file - this requires header information which should be in sperate files in the project directory
		STARTTIME=$(date +%s)
		#if this is the last element in the array then output to project path as a gz compressed vcf
		if [ ${i} -eq $((${#sourcetagarray[@]}-1)) ]; then
			output=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz
		
			cmd1="srun $(which bcftools) \
				annotate \
				-a ${sourcefilearray[${i}]} \
				-c ${annotatearray[${i}]} \
				${region} \
				-h ${PROJECT_PATH}/${sourcetagarray[${i}]}.hdr \
				${input} \
				--threads $SLURM_JOB_CPUS_PER_NODE \
				-Oz -o ${output}"
		
			cmd2="srun $(which bcftools) index -t ${output}"

		else
			output=${SCRATCH_DIR}/${CONTIG}_${sourcetagarray[${i}]}.bcf.gz
		
			cmd1="srun $(which bcftools) \
				annotate \
				-a ${sourcefilearray[${i}]} \
				-c ${annotatearray[${i}]} \
				${region} \
				-h ${PROJECT_PATH}/${sourcetagarray[${i}]}.hdr \
				${input} \
				--threads $SLURM_JOB_CPUS_PER_NODE \
				-Ob -o ${output}"
		
			cmd2="srun $(which bcftools) index ${output}"
		
		fi

	else
		echo -e "File type ${filetypearray[${i}]} is not recognised"
		exit 1
	fi
	echo ${cmd1}
	eval ${cmd1} || exit $?
	echo ${cmd2}
	eval ${cmd2} || exit $?
	ENDTIME=$(date +%s)
	DURATION=$(($ENDTIME - $STARTTIME))
	printf "Annotation with ${sourcetagarray[${i}]} completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))

	# need to remove vcf files from previous annotation sources to reduce space taken in shared memory
	if [ -f ${input} ]; then
		rm ${input}
	fi
	input=${output}
done
# if above done as bcf then need to convert compressed bcf to compressed vcf 
#output=${PROJECT_PATH}/${CONTIG}_ann.vcf.gz

#cmd="srun $(which bcftools) view -Oz -o ${output} ${input}"
#echo $cmd
#eval $cmd || exit $?

# make the index in .tbi format so it can be used by GATK, RTG
#cmd="srun $(which bcftools) index -t ${output}"
#echo $cmd
#eval $cmd || exit $?

touch ${PROJECT_PATH}/${CONTIG}_ann.vcf.gz.done

exit 0

