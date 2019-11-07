#!/bin/bash
#annotateVCF.sl 
#SBATCH --job-name	AnnoVCF
#SBATCH --time		2-00:00:00
#SBATCH --mem		8G
#SBATCH --array		1-83
#SBATCH --mail-type	REQUEUE,FAIL,END
#SBATCH --cpus-per-task	2
#SBATCH --error		slurm/ann/ann-%A_%a-%j.out
#SBATCH --output	slurm/ann/ann-%A_%a-%j.out

RAMDISK=0

echo "AnnoVCF at $(date) on $(hostname)"
echo "$0 $*"

set -ef -o pipefail

if [ -f ${parameterfile} ]
then
	echo "Sourcing ${parameterfile}"
	source ${parameterfile}
else
	echo -e "Can't find the parameter file ${parameterfile}."
	exit 1
fi

REFA=${REF}.fasta
CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
CONTIG=${CONTIGARRAY[$(( $SLURM_ARRAY_TASK_ID - 1 ))]}

if [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]
then
	echo -e "Annotation already complete."
	exit 0
fi

if [[ ${vep} == "yes" ]]
then
	initinput=${PROJECT_PATH}/vep/${CONTIG}_VEP.vcf.gz
elif [[ ${snpeff} == "yes" ]]
then
	initinput=${PROJECT_PATH}/snpeff/${CONTIG}_SnpEff.vcf.gz
else
	initinput=${unannotatedvcf}
fi

input=${initinput}

if [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done ]
then
	echo -e "Annotation already complete."
else
	for i in ${!sourcetagarray[@]}
	do
	
		echo "Contig ${CONTIG}"
		echo "Source Tag ${sourcetagarray[${i}]}"
		echo "File type ${filetypearray[${i}]}"
		echo "Source file ${sourcefilearray[${i}]}"
		echo "Annotations ${annotatearray[${i}]}"
		echo "Merge options ${mergeearray[${i}]}"
# this limits the annotation to the contig - it may save time in accessing the source file (no guarantees).	

		if [ ${CONTIG} == "whole" ]
		then
			region=""
		else
			region="-r ${CONTIG}"
		fi

		scontrol update \
			jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} \
			jobname=Ann_${sourcetagarray[${i}]}_${PROJECT}_${CONTIG}
		
		module purge
		module load ${bcftools}
		
		STARTTIME=$(date +%s)
		mkdir -p ${PROJECT_PATH}/ann
# if from a vcf

		if [[ ${filetypearray[${i}]} == "vcf" ]]
		then
		#if this is the last element in the array then output to project path as a gz compressed vcf
			if [ ${i} -eq $((${#sourcetagarray[@]}-1)) ]
			then
				output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
				cmd1="srun \
$(which bcftools) \
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
				cmd1="srun \
$(which bcftools) \
annotate \
-a ${sourcefilearray[${i}]} \
-c ${annotatearray[${i}]} \
${region} \
--collapse all \
${input} \
--threads $SLURM_JOB_CPUS_PER_NODE \
-Ob -o ${output}"
			fi
		elif [[ ${filetypearray[${i}]} == "bed" ]] || \
			 [[ ${filetypearray[${i}]} == "tab" ]]
		then
	#if from a bed or tabbed file - this requires header information which should be in separate files in the project directory
	# This is an attempt to use the append option when merging annotations from overlapping regions
	# Needs to use the dev version of bcftools
	# need to make an array of all the tags, and then use this to make the merge locic append expression
	# currently set up such that if there is one tag specified as none in merge option column, then no merge logic option will be produced for any of the tags from that source
	# need to test to see of there is "none" specified (or perhaps if just no entry in the column) then just drop that tag from the merge logic array to see what happens
			mergelogic=""
			
			if	[[ "${annotatearray[${i}]}" =~ "FROM" ]] && \
				[[ "${annotatearray[${i}]}" =~ "TO" ]] \
				&& [[ ! "${mergearray[${i}]}" =~ "none" ]] \
				&& [[ ! "${mergearray[${i}]}" =~ "single-overlaps" ]]
			then
				tagarray=($(echo "${annotatearray[${i}]}" | tr ',' ' ' | sed 's/CHROM //g' | sed 's/FROM //g' | sed 's/TO //g' | sed 's/POS //g' | sed 's/REF //g' | sed 's/ALT //g' | sed 's/- //g' | sed 's/ $//g'))
				mergeoptionarray=($(echo "${mergearray[${i}]}" | tr ',' ' ' | sed 's/CHROM //g' | sed 's/FROM //g' | sed 's/TO //g' | sed 's/POS //g' | sed 's/REF //g' | sed 's/ALT //g' | sed 's/- //g' | sed 's/ $//g'))
				echo "Tagarray: \"$(echo ${tagarray[@]})\""
				echo "Merge option array: \"$(echo ${mergeoptionarray[@]})\""
				count=0
				
				for tag in $(echo "${tagarray[@]}")
				do
				#this if statement is intended to avoiding adding the tag to the mergelogic expression if no merging merging is required - it will use the default for this tag which is the first entry it comes across
					if [[ ${mergeoptionarray[${count}]} != +(first|none|"") ]]
					then
						if [ -z "${mergelogic}" ]
						then
							mergelogic="-l ${tag}:${mergeoptionarray[${count}]}"
						else 
							mergelogic="${mergelogic},${tag}:${mergeoptionarray[${count}]}"
						fi
					fi
					count=$((${count} + 1))
				done
			elif [[ "${annotatearray[${i}]}" =~ "FROM" ]] && [[ "${annotatearray[${i}]}" =~ "TO" ]]
			then
				mergelogic="--single-overlaps"
			fi
			
			echo "Merge logic: \"${mergelogic}\""
			module purge
			module load ${bcftools}
			
		#if this is the last element in the array then output to project path as a gz compressed vcf
			if [ ${i} -eq $((${#sourcetagarray[@]}-1)) ]
			then
				output=${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz
				cmd1="srun \
$(which bcftools) \
annotate \
-a ${sourcefilearray[${i}]} \
-c ${annotatearray[${i}]} \
${region} \
${mergelogic} \
-h ${PROJECT_PATH}/headers/${sourcetagarray[${i}]}.hdr \
${input} \
--threads $SLURM_JOB_CPUS_PER_NODE \
-Oz -o ${output} \
&& mkdir -p ${PROJECT_PATH}/done/ann \
&& touch ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.done"
# 				fi
			else
				output=${SCRATCH_DIR}/${CONTIG}_${sourcetagarray[${i}]}.bcf.gz
		
				cmd1="srun \
$(which bcftools) \
annotate \
-a ${sourcefilearray[${i}]} \
-c ${annotatearray[${i}]} \
${region} \
${mergelogic} \
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
	
		if [ ${i} -ne $((${#sourcetagarray[@]}-1)) ]
		then
			scontrol update \
				jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} \
				jobname=AnnIndex_${sourcetagarray[${i}]}_${PROJECT}_${CONTIG}
			
			cmd2="srun $(which bcftools) index ${output}"
			echo ${cmd2}
			eval ${cmd2} || exit $?
		fi
		
		ENDTIME=$(date +%s)
		DURATION=$(($ENDTIME - $STARTTIME))
		printf "Annotation with ${sourcetagarray[${i}]} completed in %d:%02d:%02d\n" \
			$(($DURATION/3600)) \
			$(($DURATION%3600/60)) \
			$(($DURATION%60))

	# need to remove vcf files from previous annotation sources to reduce space taken in shared memory
		if  [ -f ${input} ] && \
			[[ "${input}" != "${initinput}" ]]
		then
			rm ${input}
		fi
		
		input=${output}
	done
fi

if [ -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]
then
	echo -e "Annotation index already complete."
	exit 0
else
	scontrol update \
		jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} \
		jobname=AnnIndex_${PROJECT}_${CONTIG}
	
	module purge
	module load ${bcftools}
	
	cmd2="srun $(which bcftools) index -t ${PROJECT_PATH}/ann/${CONTIG}_ann.vcf.gz"
	echo ${cmd2}
	eval ${cmd2} && touch ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done || exit $?
fi

echo "Annotate VCF complete"

exit 0
