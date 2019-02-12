#!/bin/bash
#annotateVCF.sl 
#SBATCH --job-name	AnnoVCF
#SBATCH --time		1-00:00:00
#SBATCH --mem		1G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/ann/ann-%A_%a-%j.out
#SBATCH --output	slurm/ann/ann-%A_%a-%j.out

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

if [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]; then
	echo -e "Annotation already complete."
	exit 0
fi

if [[ ${vep} == "yes" ]]; then
	initinput=${PROJECT_PATH}/vep/${CONTIG}_VEP.vcf.gz
elif [[ ${snpeff} == "yes" ]]; then
	initinput=${PROJECT_PATH}/snpeff/${CONTIG}_SnpEff.vcf.gz
else
	initinput=${unannotatedvcf}
fi
input=${initinput}
if [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done ]; then
	echo -e "Annotation already complete."
else
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
		mkdir -p ${PROJECT_PATH}/ann
# if from a vcf
		if [[ ${filetypearray[${i}]} == "vcf" ]]; then
		#if this is the last element in the array then output to project path as a gz compressed vcf
			if [ ${i} -eq $((${#sourcetagarray[@]}-1)) ]; then
				output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
				cmd1="srun $(which bcftools) \
					annotate \
					-a ${sourcefilearray[${i}]} \
					-c ${annotatearray[${i}]} \
					${region} \
					--collapse all \
					${input} \
					--threads $SLURM_JOB_CPUS_PER_NODE \
					-Oz -o ${output} \
					&& mkdir -p ${PROJECT_PATH}/done/ann \
					&& touch ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done"
		
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
		
			fi
		elif [[ ${filetypearray[${i}]} == "bed" ]] || [[ ${filetypearray[${i}]} == "tab" ]]; then
	#if from a bed or tabbed file - this requires header information which should be in sperate files in the project directory
		#if this is the last element in the array then output to project path as a gz compressed vcf
			if [ ${i} -eq $((${#sourcetagarray[@]}-1)) ]; then
				output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
		
				cmd1="srun $(which bcftools) \
					annotate \
					-a ${sourcefilearray[${i}]} \
					-c ${annotatearray[${i}]} \
					${region} \
					-h ${PROJECT_PATH}/headers/${sourcetagarray[${i}]}.hdr \
					${input} \
					--threads $SLURM_JOB_CPUS_PER_NODE \
					-Oz -o ${output} \
					&& mkdir -p ${PROJECT_PATH}/done/ann \
					&& touch ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done"
			else
				output=${SCRATCH_DIR}/${CONTIG}_${sourcetagarray[${i}]}.bcf.gz
		
				cmd1="srun $(which bcftools) \
					annotate \
					-a ${sourcefilearray[${i}]} \
					-c ${annotatearray[${i}]} \
					${region} \
					-h ${PROJECT_PATH}/headers/${sourcetagarray[${i}]}.hdr \
					${input} \
					--threads $SLURM_JOB_CPUS_PER_NODE \
					-Ob -o ${output}"
			fi

		else
			echo -e "File type ${filetypearray[${i}]} is not recognised"
			exit 1
		fi
		echo ${cmd1}
		eval ${cmd1} || exit $?
	#only make a .csi index if not the last job in the array
		if [ ${i} -ne $((${#sourcetagarray[@]}-1)) ]; then
			scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=AnnIndex_${sourcetagarray[${i}]}_${PROJECT}_${CONTIG}
			cmd2="srun $(which bcftools) index ${output}"
			echo ${cmd2}
			eval ${cmd2} || exit $?
		fi
		ENDTIME=$(date +%s)
		DURATION=$(($ENDTIME - $STARTTIME))
		printf "Annotation with ${sourcetagarray[${i}]} completed in %d:%02d:%02d\n" $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60))

	# need to remove vcf files from previous annotation sources to reduce space taken in shared memory
		if [ -f ${input} ] && [[ "${input}" != "${initinput}" ]]; then
			rm ${input}
		fi
		input=${output}
	done
fi
if [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]; then
	echo -e "Annotation index already complete."
	exit 0
else
	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} jobname=AnnIndex_${sourcetagarray[${i}]}_${PROJECT}_${CONTIG}
	module purge
	module load BCFtools
	cmd2="srun $(which bcftools) index -t ${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz \
		&& touch ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done"
	echo ${cmd2}
	eval ${cmd2} || exit $?
fi


exit 0

