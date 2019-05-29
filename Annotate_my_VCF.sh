#!/bin/bash

function mybanner {
cat << EOF

****************************************************************************************************
* Annotate_my_VCF                                                                                  *
*                                                                                                  *
*                                                                                                  *
*                                                                                                  *
*                                                                                                  *
*                                                                                                  *
* David Markie 2017                                                                                *
****************************************************************************************************
EOF
}
function restartbanner {
cat << EOF

****************************************************************************************************
* Annotate_my_VCF                                                                                  *
*                                                                                                  *
* This appears to be a re-started project based on the provided vcf filename. The same annotations *
* will be used as the previous attempt. If you wish to start afresh you should quit and:           *
* rm -r ${PROJECT_PATH} before starting again.                                                     *
*                                                                                                  *
* David Markie 2017                                                                                *
****************************************************************************************************
EOF
}

#$1 is the full path to the unannotated vcf to be annotated
#$2 is the full path to the defaults you would like to use

if [[ $email == "" ]]; then
	oldIFS=$IFS
	IFS=$'\n'
	userList=($(cat /etc/slurm/userlist.txt | grep $USER))
	for entry in ${userList[@]}; do
		testUser=$(echo $entry | awk -F':' '{print $1}')
		if [ "$testUser" == "$USER" ]; then
			export email=$(echo $entry | awk -F':' '{print $3}')
			break
		fi
	done
	IFS=$oldIFS
	if [ $email == "" ]; then
		(echo "FAIL: Unable to locate email address for $USER in /etc/slurm/userlist.txt!" 1>&2)
		exit 1
	else
		export MAIL_TYPE=REQUEUE,FAIL,END
		(printf "%-22s%s (%s)\n" "Email address" "${email}" "$MAIL_TYPE" 1>&2)
	fi
fi
if [[ ${email} != "none" ]]; then
	mailme="--mail-user ${email} --mail-type $MAIL_TYPE"
fi


mybanner
# assume if specifying at the command line, then you only wish to use the defaults
if [[ -z $1 ]]; then
	while [ -z ${unannotatedvcf} ] || [ ! -f "${unannotatedvcf}" ]; do
		echo -e "\n\nSpecify the vcf.gz file to which you would like to add annotations.\n"
		read -e -p "Provide the full path to the file, or q to quit, and press [RETURN]: " unannotatedvcf
		if [[ ${unannotatedvcf} == "q" ]]; then exit; fi;
	done
else
	if [ -f $1 ]; then
		unannotatedvcf=$1
		usedefaults="yes"
	else 
		echo -e "\nThe file ${unannotatedvcf} can not be found."
		exit 1
	fi
fi
export BASEDIR=$(dirname $0)
source ${BASEDIR}/basefunctions.sh
## if $2 is a file then source it for your specified default annotations, otherwise source a standard file 
## will need to write this to parameters so it can be picked up on restart
if [ -z $2 ]; then
	if [ -z ${default} ]; then
		default=${BASEDIR}/defaults.txt
	fi
else 
	default=$2
fi
if [ -f ${default} ]; then
	source ${default}
else
	echo -e "\nThe file ${default} specifying the default annotations can not be found."
	exit 1
fi 
export WORK_PATH="/scratch/$USER"
if [[ ${unannotatedvcf} =~ .*\.vcf\.gz ]]; then
	export PROJECT="$(basename ${unannotatedvcf} .vcf.gz)"
elif [[ ${unannotatedvcf} =~ .*\.vcf ]]; then
	export PROJECT="$(basename ${unannotatedvcf} .vcf)"
fi
export PROJECT_PATH=${WORK_PATH}/${PROJECT}_Annotating
export parameterfile="${PROJECT_PATH}/parameters.sh"


if [ -f ${parameterfile} ]; then
	source ${parameterfile}
	restartbanner
	CONTIGARRAY=($(echo ${CONTIGSTRING} | sed 's/,/ /g'))
else 
## may add to make it possible to choose alternative contigs - either none (whole genome) or non-gapped regions - currently can specify alternative contig definitions in the defaults file
	if [ -z $2 ]; then
		for i in ${!CONTIGARRAY[@]}; do
			echo ${CONTIGARRAY[${i}]}
		done
		echo -e "\n\nThe job will be broken up and processed in contigs. The default contigs are shown above.\n"
		echo -e "\nTo process without breaking up the file specify \"whole\".\n"
		echo -e "To use alternative contigs or a subset, enter them here separated by spaces,"
		read -e -p " or nothing for the default, or q to quit, and press [RETURN]: " mycontigs
		if [[ "${mycontigs}" == "q" ]]; then exit; fi;
		if [ ! -z "${mycontigs}" ]; then
			CONTIGARRAY=()
			for i in $(echo "${mycontigs}"); do
				if [[ " ${CONTIGARRAY[@]} " =~ " ${i} " ]]; then
					something=walrus
					while [[ ${something} == "walrus" ]]; do
						echo -e "The contig ${i} is repeated in your submitted contigs, but will be used only once."
						read -e -p " Enter nothing to continue, or q to quit, and press [RETURN]: " something
						if [[ "${something}" == "q" ]]; then exit; fi;
					done
				else
					CONTIGARRAY=(${CONTIGARRAY[@]} ${i})
				fi
			done
		fi
	fi
	# check each contig to see if there are any variants in the unannotated vcf, if not then don't put in the final contigstring
	for i in ${!CONTIGARRAY[@]}; do
		CONTIG=${CONTIGARRAY[$i]}
		module load BCFtools
		if [ $($(which bcftools) view -r ${CONTIG} -Ov ${unannotatedvcf} | grep -v "^#" | head -n 10 | wc -l) -gt 0 ]; then
			if [ -z ${CONTIGSTRING} ]; then
				CONTIGSTRING=${CONTIG}
			else
				CONTIGSTRING=${CONTIGSTRING},${CONTIG}
			fi
			echo -e "The region ${CONTIG} contains variants"
		else
			echo -e "The region ${CONTIG} contains no variants"
		fi
	done
	#turn the contigstring back into contigarray
	oldIFS=$IFS
	IFS=","
	CONTIGARRAY=(${CONTIGSTRING})
	IFS=$oldIFS
	echo -e "After excluding contigs without variants, the final contigs for processing are:"
	for i in ${!CONTIGARRAY[@]}; do
		echo ${CONTIGARRAY[${i}]}
	done
fi

if [ -z ${contigarraynumber} ]; then
	contigarraynumber=${#CONTIGARRAY[@]}
fi

#### run snpeff
if [[ ${snpeff} == "yes" ]] || [[ ${usedefaults} == "yes" ]]; then
	snpeff_format="${defaultsnpeff_format}"
	snpeffdataversion="${defaultsnpeffdataversion}"
elif [ -z ${snpeff} ]; then
	while [[ ${snpeff} != "yes" ]] && [[ ${snpeff} != "no" ]] ; do
		echo -e "\nWould you like to annotate with SnpEFF?"
		read -e -p "Type \"yes\" to annotate with SnpEff, \"no\" to skip, or q to quit, and press [RETURN]: " snpeff
		if [[ ${snpeff} == "q" ]]; then exit; fi;
	done
	if [[ ${snpeff} == "yes" ]]; then
		while [[ ${snpeff_format} != "ANN" ]] && [[ ${snpeff_format} != "EFF" ]] ; do
			echo -e "\nWould you like to use the current (ANN) format or the old (format) for SnpEff annotation?"
			read -e -p "Type \"ANN\" or \"EFF\", or q to quit, and press [RETURN]: " snpeff_format
			if [[ ${snpeff_format} == "q" ]]; then exit; fi;
		done
		snpeffdataversion="walrus"
		while [[ ${snpeffdataversion} == "walrus" ]] ; do
			echo -e "\nWould you like to use the default data version for snpEff annotation (${defaultsnpeffdataversion})?"
			read -e -p "Enter nothing to use the default, or enter the alternative version, or q to quit, and press [RETURN]: " snpeffdataversion
			if [[ ${snpeffdataversion} == "q" ]]; then exit; fi;
			if [ -z ${snpeffdataversion} ]; then
				snpeffdataversion=${defaultsnpeffdataversion}
			fi
		done
	fi
fi
## run bcftools csq
if [ -z ${BCSQ} ]; then
	while [[ ${BCSQ} != "yes" ]] && [[ ${BCSQ} != "no" ]] ; do
		echo -e "\nWould you like to annotate with bcftools CSQ (BCSQ annotation)?\nThis annotation requires the file to have the Ensembl Variant Effect Predictor's CSQ annotation.\nIf your input VCF is not already annotated using VEP then include it when asked.\n Note that this step will fail and should be avoided if any individuals have three or more alleles at any position eg XXX, XXY, XYY or trisomy 21."
		read -e -p "Type \"yes\" to annotate with BCSQ, \"no\" to skip, or q to quit, and press [RETURN]: " BCSQ
		if [[ ${BCSQ} == "q" ]]; then exit; fi;
	done
fi
if [ ${BCSQ} = yes ]; then
	while [ -z ${GFF3forBCSQ} ] || [ ! -f ${GFF3forBCSQ} ]; do
		echo -e "\nSelect a suitable Ensembl GFF3 file containing transcript information for use by the BCSQ annotation."
		read -e -p "Type the filename here, or q to quit, and press [RETURN]: " GFF3forBCSQ
		if [[ ${GFF3forBCSQ} == "q" ]]; then exit; fi;
	done
fi
#if [ ${BCSQ} = yes ]; then
#	while [[ ${Xcludedsamples} = "unknown" ]]; do
#		echo -e "\nBCSQ will not work on trisomic calls.\nTo exclude BCSQ annotation of the X chromosome for XXX females enter\na comma delimited list of XXX sample names in your cohort,"
#		read -e -p "or leave empty if none, or q to quit, and press [RETURN]: " Xcludedsamples
#		if [[ ${Xcludedsamples} == "q" ]]; then exit; fi;
#	done
#fi
## run VEP
if [[ ${vep} == "yes" ]] || [[ ${usedefaults} == "yes" ]]; then
	vepspecies="${defaultvepspecies}"
	vepassembly="${defaultvepassembly}"
elif [ -z ${vep} ]; then
	while [[ ${vep} != "yes" ]] && [[ ${vep} != "no" ]] ; do
		echo -e "\nWould you like to annotate with Ensembl Variant Effect Predictor?"
		read -e -p "Type \"yes\" to annotate with VEP, \"no\" to skip, or q to quit, and press [RETURN]: " vep
		if [[ ${vep} == "q" ]]; then exit; fi;
	done
	if [[ ${vep} == "yes" ]]; then
		echo -e "The species is currently ${defaultvepspecies}."
		read -e -p "Press [RETURN] to keep, or type an alternative species name, or q to quit, and press [RETURN]: " vepspecies
		if [[ ${vepspecies} == "q" ]]; then exit; fi;
		if [[ ${vepspecies} == "" ]]; then
			vepspecies="${defaultvepspecies}"
		fi
		echo -e "The assembly is currently ${defaultvepassembly}."
		read -e -p "Press [RETURN] to keep, or type an alternative assembly name, or q to quit, and press [RETURN]: " vepassembly
		if [[ ${vepassembly} == "q" ]]; then exit; fi;
		if [[ ${vepassembly} == "" ]]; then
			vepassembly="${defaultvepassembly}"
		fi
	fi
fi
# make an array for the default sourcetags
oldIFS=$IFS
IFS=","
defaultsourcetags=(${default_sourcetags})
IFS=$oldIFS

# Trying to design a generic set up to capture and prepare the information for annotating a file
#######################################
# declare associative arrays for a number of attributes for the source annotation files, that can be accessed by sourcecount
# store the full path to the filename
typeset -A sourcefile
# store the tag that will be used in the annotation to identify the source
typeset -A sourcetag
# store the format of the file - vcf, bed or tab
typeset -A filetype
# store the annotations to be used as a comma delimited string
typeset -A ann

typeset -A defaultannotations

typeset -A header

# each run though this while loop will set up the paramenters for annotation from a single source file.
# first it will run through the specified default sources, then will keep requesting further sources until it is declined
sourcecount=0
while [[ ${repeat} != "no" ]] && [ ! -f ${parameterfile} ]; do
	sourcecount=$(( ${sourcecount} + 1 ))
	#resets the repeat variable so that if a previous offer to run another annotation source was declined then this will be recognised, otherwise start fresh
	repeat=""
	if [ ! -z ${defaultsourcetags[$(( ${sourcecount} - 1 ))]} ]; then
		repeat="yes"
	elif [[ ${usedefaults} == "yes" ]] ; then
		repeat="no"
	fi
	while [ -z ${repeat} ] && [[ ${repeat} != "no" ]] && [[ ${repeat} != "yes" ]]; do
		echo -e "\nDo you want to annotate with fields from another source?\n"
		read -e -p "Enter \"yes\" or \"no\", or q to quit, and press [RETURN]: " repeat
		if [[ ${repeat} == "q" ]]; then exit; fi
	done
	
	if [[ ${repeat} != "no" ]]; then
	
	# grab the short tag for the source, and the associated information required
		if [ ! -z ${defaultsourcetags[$(( ${sourcecount} - 1 ))]} ]; then
			sourcetag[${sourcecount}]=${defaultsourcetags[$(( ${sourcecount} - 1 ))]}
		fi
		# once we have run out of the specified default tags, it will ask if you want to annotate with any other sources. If you specify a tag that is listed as a default, it will pick up the appropriate information
		while [ -z ${sourcetag[${sourcecount}]} ]; do
			echo -e "\n"
			read -e -p "Enter a short name that will become the source tag in your annotations, or q to quit, and press [RETURN]: " sourcetag[${sourcecount}]
			if [[ ${sourcetag[${sourcecount}]} == "q" ]]; then exit; fi
		done
		# get the source file if it has been previously specified (by a tag), and any default annotation string associated with that source tag
		source=${sourcetag[${sourcecount}]}
		if [[ ! -z ${!source} ]]; then
			sourcefile[${sourcecount}]=${!source}
			defannotations=defaultannotations_${sourcetag[${sourcecount}]}
			defaultannotations[${sourcecount}]=${!defannotations}
		fi
		
		# request the source file for annotation if it hasn't already been picked up
		while [[ ! -f ${sourcefile[${sourcecount}]} ]]; do
			echo -e "\n"
			read -e -p "Enter the full path to the compressed source file for ${sourcefile[${sourcecount}]}, or q to quit, and press [RETURN]: " sourcefile[${sourcecount}]
			if [[ ${sourcefile[${sourcecount}]} == "q" ]]; then exit; fi
		done
		echo -e "\n${sourcetag[${sourcecount}]} annotation\n"		
		# guess if the filename is consistent with a compressed vcf or bed file
		if [ ! -z ${sourcefile[${sourcecount}]} ]; then
			if $(echo ${sourcefile[${sourcecount}]} | grep -q ".vcf.gz$"); then
				filetype[${sourcecount}]=vcf
			elif $(echo ${sourcefile[${sourcecount}]} | grep -q ".vcf.bgz$"); then
				filetype[${sourcecount}]=vcf
			elif $(echo ${sourcefile[${sourcecount}]} | grep -q ".bed.gz$"); then
				filetype[${sourcecount}]=bed
			elif $(echo ${sourcefile[${sourcecount}]} | grep -q ".bed.bgz$"); then
				filetype[${sourcecount}]=bed
			else
				echo -e "\n"
				echo -e "${sourcefile[${sourcecount}]}"
				echo -e "\nThe filename is not consistent with a compressed vcf or bed file, assumed to be a tab delimited file with header line."
				filetype[${sourcecount}]=tab
			fi
		fi
		### depending on the type of source file - show the annotation options that may be used, and what the defaults are (if any)
		if [[ ${filetype[${sourcecount}]} == "vcf" ]]; then
			#This will produce a list of all the INFO annotations, with their descriptions
			echo -e "\n#################################################################################################"
			zcat ${sourcefile[${sourcecount}]} | head -n 500 | grep "^##INFO=<ID=" | sed 's/##INFO=<ID=\([^,]\+\),.\+,Description=\(.\+\)>$/\1 \2\n/'
			echo -e "#################################################################################################\n"
			echo -e "\nThe available fields in $(basename ${sourcefile[${sourcecount}]}) are shown above (one per line)\n"
			if [[ ! -z ${defaultannotations[${sourcecount}]} ]]; then
				echo -e "\n${sourcetag[${sourcecount}]} annotation\n"		
				echo -e "\nThe selected default fields (space separated) are:\n"
				echo ${defaultannotations[${sourcecount}]} | awk -F, '{ for (i=1; i<=NF; i++) print $i }' | tr '\n' ' ' 
				echo -e "\n"
			fi
		elif [[ ${filetype[${sourcecount}]} == "bed" ]]; then
			# this requires a descriptions file for that source to have been specified - it should have a line starting with ##columns which is tab delimited to specify the CHROM FROM TO REF and ALT column headers
			# and a tab delimited line for each possible annotation with four entries - ID Number Type and Description
			description="description_${sourcetag[${sourcecount}]}"
			if [ ! -z "${!description}" ] && [ -f "${!description}" ]; then
				echo -e "\n#################################################################################################"
				echo -e "Tag\tDescription"
				echo -e "#################################################################################################"
				awk -F"\t" '/^[^##]/ { print $2"\t\""$5"\"\n" }' ${!description} 
				echo -e "#################################################################################################\n"
			else
				echo -e "\n#################################################################################################"
				zcat ${sourcefile[${sourcecount}]} | head -n 5
				echo -e "#################################################################################################\n"
				echo -e "\n*************************************************************************************************"
				echo -e "\n${sourcetag[${sourcecount}]} annotation\n"		
				echo -e "\nThe first five lines of $(basename ${sourcefile[${sourcecount}]}) are shown above.\n"
				echo -e "*************************************************************************************************\n"
				echo -e "The first column is the chromosome, the second and third columns are the beginning and end co-ordinates for a feature, \nthe fourth column is the name for the feature described by each line, and the fifth column is a relevant score."
				echo -e "In standard bed files other columns are reserved for specific information, but sometimes that may be also contain useful annotations."
			fi
			if [[ ! -z ${defaultannotations[${sourcecount}]} ]]; then
				echo -e "\nThe selected default fields (space separated) are:\n"
				echo ${defaultannotations[${sourcecount}]} | awk -F, '{ for (i=1; i<=NF; i++) print $i }' | tr '\n' ' ' 
				echo -e "\n"
			fi
		elif [[ ${filetype[${sourcecount}]} == "tab" ]]; then
			# this requires a descriptions file for that source to have been specified - it should have a line starting with ##columns which is tab delimited to specify the CHROM FROM TO REF and ALT column headers
			# and a tab delimited line for each possible annotation with four entires - ID Number Type and Description
			description="description_${sourcetag[${sourcecount}]}"
			if [ ! -z "${!description}" ] && [ -f "${!description}" ]; then
				echo -e "\n#################################################################################################"
				echo -e "Tag\tDescription"
				echo -e "#################################################################################################"
				awk -F"\t" '/^[^##]/ { print $2"\t\""$5"\"\n" }' ${!description} 
				echo -e "#################################################################################################\n"
			# if there is no specified descriptions file for the source, it will grab the column headers from the original source file
			else
				echo -e "\n#################################################################################################"
	#  the "head -n 3 | grep -v "^##" | head -n 1"  is to ignore the first line or two if they begin with ##, ed the CADD file
				for i in $(zcat ${sourcefile[${sourcecount}]} | head -n 3 | grep -v "^##" | head -n 1 ); do
					echo ${i}
				done
				echo -e "#################################################################################################\n"
			fi
						
			echo -e "\n${sourcetag[${sourcecount}]} annotation\n"		
			echo -e "\nThe available fields in $(basename ${sourcefile[${sourcecount}]}) are shown above (one per line)\n"
			if [[ ! -z ${defaultannotations[${sourcecount}]} ]]; then
				echo -e "\nThe selected default fields (space separated) are:\n"
				echo ${defaultannotations[${sourcecount}]} | awk -F, '{ for (i=1; i<=NF; i++) print $i }' | tr '\n' ' ' 
				echo -e "\n"
			fi

			######## sort out the columns for specifying chromosome and position co-ordinates for a tab file (don't need to be specified for vcf and bed)
			chrom=""
			from=""
			to=""
			ref=""
			alt=""
			# if there is a description file for this source then get them out of that
			if [ -f "${!description}" ]; then
				defaultcolumnsarray=($(awk -F'\t' '/^##columns/ { print $2,$3,$4,$5,$6 }' ${!description}))
			fi
			# if the array has at least three things in it, use those to define positions
			# this provides the "name" for each value from the descriptions file - which should be a column headers from the source file
			if [[ "${#defaultcolumnsarray[@]}" -ge 3 ]]; then
				if [ ! -z ${defaultcolumnsarray[0]} ]; then
					chrom="${defaultcolumnsarray[0]}"
				fi
				if [ ! -z ${defaultcolumnsarray[1]} ]; then
					from="${defaultcolumnsarray[1]}"
				fi
				if [ ! -z ${defaultcolumnsarray[2]} ]; then
					to="${defaultcolumnsarray[2]}"
				fi
				if [ ! -z ${defaultcolumnsarray[3]} ]; then
					ref="${defaultcolumnsarray[3]}"
				fi
				if [ ! -z ${defaultcolumnsarray[4]} ]; then
					alt="${defaultcolumnsarray[4]}"
				fi
			else
				# if not previously defined, request the definitions - provides the name from the file column headers
				while [ -z ${chrom} ]; do
					echo -e "\n"
					read -e -p "Enter the column header that specifies the chromosome column, or q to quit, and press [RETURN]: " chrom
					if [[ ${chrom} == "q" ]]; then exit; fi
				done
				while [ -z ${from} ]; do
					echo -e "\n"
					read -e -p "Enter the column header that specifies the start co-ordinate column, or q to quit, and press [RETURN]: " from
					if [[ ${from} == "q" ]]; then exit; fi
				done
				while [ -z ${to} ]; do
					echo -e "\n If the start and end are specified by the same column \(ie a nucleotide position\), enter the same column header."
					read -e -p "Enter the column header that specifies the end co-ordinate column, or q to quit, and press [RETURN]: " to
					if [[ ${to} == "q" ]]; then exit; fi
				done
				ref="walrus"
				while [[ ${ref} == "walrus" ]]; do
					read -e -p "Enter the column header that specifies the reference co-ordinate column, if not present enter nothing, or q to quit, and press [RETURN]: " ref
					if [[ ${ref} == "q" ]]; then exit; fi
				done
				ref="walrus"
				while [[ ${alt} == "walrus" ]]; do
					read -e -p "Enter the column header that specifies the alternate co-ordinate column, if not present enter nothing, or q to quit, and press [RETURN]: " alt
					if [[ ${alt} == "q" ]]; then exit; fi
				done
			fi
		fi
		
## IF THERE ARE ALREADY DEFAULT ANNOTATIONS FOR THIS SOURCE DEFINED DECIDE WHETHER YOU WANT JUST THE DEFAULTS, OR TO ADD TO THEM OR TO REPLACE THEM, OR NOT USE THIS SOURCE AT ALL
		if [[ ! -z ${defaultannotations[${sourcecount}]} ]] && [[ ${usedefaults} != "yes" ]]; then
			echo -e "\nDo you want to annotate with just the default fields, add your own, replace with your own, or not use this source at all?"
			reply="walrus"
			while [ ! -z ${reply} ] && [[ ${reply} != "add" ]] && [[ ${reply} != "replace" ]]; do
				echo -e "Enter nothing to use just the defaults, \"add\" to include your selections with the default, \"replace\" to use only your own selections,"
				read -e -p "or \"no\" if you don't wish to use this source, or q to quit, and press [RETURN]: " reply
				if [[ ${reply} == "q" ]]; then exit; fi
				if [[ ${reply} == "no" ]]; then continue 2; fi
			done
		elif [[ ${usedefaults} != "yes" ]]; then
			reply="replace"
		fi
		
		# provides the option of writing out to a file for editing the available fields (if vcf or tab)
		if [[ ${filetype[${sourcecount}]} == "vcf" ]] || [[ ${filetype[${sourcecount}]} == "tab" ]] || [[ ${filetype[${sourcecount}]} == "bed" && -f "${!description}" ]]; then
			if [[ ${reply} == "add" ]] || [[ ${reply} == "replace" ]]; then
				filename="Annotations_${sourcetag[${sourcecount}]}.txt"
				file=""
				while [[ ${file} != "yes" ]] && [[ ${file} != "no" ]] && [[ ${usedefaults} != "yes" ]]; do
					echo -e "\nIf you would like to write the available fields to a file for editing"
					read -e -p "enter \"yes\" here, or \"no\" to continue without writing a file, or q to quit, and press [RETURN]: " file
					if [[ ${file} == "q" ]]; then exit; fi
				done
				if [[ ${file} == "yes" ]]; then
					if [[ ${filetype[${sourcecount}]} == "vcf" ]]; then
						zcat ${sourcefile[${sourcecount}]} | head -n 500 | grep "^##INFO=<ID=" | sed 's/##INFO=<ID=\([^,]\+\),.\+,Description=\(.\+\)>$/\1\t\2/' > ${filename}
					elif [[ ${filetype[${sourcecount}]} == "tab" ]]; then
						if [ -f ${filename} ]; then
							rm ${filename}
						fi
						if [ -f "${!description}" ]; then
							awk -F"\t" '/^[^##]/ {print $2"\t"$5}' ${!description} > ${filename}
						else
							for i in $(zcat ${sourcefile[${sourcecount}]} | head -n 1); do
								echo ${i} >> ${filename}
							done
						fi
					elif [[ ${filetype[${sourcecount}]} == "bed" ]]; then
						if [ -f ${filename} ]; then
							rm ${filename}
						fi
						if [ -f "${!description}" ]; then
							awk -F"\t" '/^[^##]/ {print $2"\t"$5}' ${!description} > ${filename}
						fi
					fi
					echo -e "\nThe available annotations from $(basename ${sourcefile[${sourcecount}]}) have been written to ${filename} for editing.\nThey will be deleted after the next step."
				fi
			fi
		fi
		
## GRAB THE NEWFIELDS TO INCLUDE ##		
		newfields=""
		if [[ ${filetype[${sourcecount}]} == "vcf" ]] || [[ ${filetype[${sourcecount}]} == "tab" ]] || [[ ${filetype[${sourcecount}]} == "bed" && -f "${!description}" ]]; then
			if [[ "${reply}" == "add" ]] || [[ "${reply}" == "replace" ]]; then
				echo -e "\nEnter your field selections, separated by spaces, or type \"file\" to pick these from "
				read -e -p "the edited file containing the field selections, or q to quit, and press [RETURN]: " newfields
				if [[ "${newfields}" == "q" ]]; then exit; fi
			fi
		elif [[ ${filetype[${sourcecount}]} == "bed" ]]; then
			if [[ "${reply}" == "add" ]] || [[ "${reply}" == "replace" ]]; then
				echo -e "\nEnter your column number selections, separated by spaces,"
				read -e -p "or q to quit, and press [RETURN]: " newfields
				if [[ "${newfields}" == "q" ]]; then exit; fi
			fi
		fi
		
		# need to clear the $annotations variable for the new round
		annotations=""
		#pick up the default annotations if appropriate
		if [[ "${reply}" == "add" ]] || [ -z "${reply}" ]; then
			annotations="${defaultannotations[${sourcecount}]}"
		fi
		
		#this makes a comma-delimited array of the annotation tags (vcf) or columns (bed) to include
		## IF NEWFIELDS ARE IN A FILE
		if [[ "${newfields}" == "file" ]] && [ -f "${filename}" ]; then
		# make an array of the new fields
			newfieldsarray=($(awk -F"\t" '{print $1}' ${filename} | tr '\n' ' '))
			for i in ${newfieldsarray[@]}; do	
				#check that the new annotations are not already in the file to be annotated - warn and don't use if already in there				
				for j in  $(zcat ${unannotatedvcf} | head -n 500 | grep "^##INFO=<ID=" | sed 's/##INFO=<ID=\([^,]\+\),.\+,Description=\(.\+\)>$/\1/'); do
					if [[ ${sourcetag[${sourcecount}]}_${i} == ${j} ]]; then
						echo -e "The ${i} tag specified in your selection already exists in the target vcf file. It will not be used.\n"
						continue 1
					fi
				done
				for j in $(echo "${annotations}" | sed 's/,/ /g'); do
				# check if you have specified an annotation from this source twice, or if it is already in the defaults
					if [[ "${j}" == "${i}" ]]; then
						echo -e "The ${i} tag specified in your selection already exists in the default fields or is repeated in your selection.\nIt will not be used twice.\n"
						continue 1
					fi
				done
				# check if the annotation is actually available from the source (can only be done for vcf and tab) - warn if unavailable, but continue
				if [[ ${filetype[${sourcecount}]} == "vcf" ]]; then
					for j in  $(zcat ${sourcefile[${sourcecount}]} | head -n 500 | grep "^##INFO=<ID=" | sed 's/##INFO=<ID=\([^,]\+\),.\+,Description=\(.\+\)>$/\1/'); do
						if [[ "${j}" == "${i}" ]]; then
							match="yes"
							if [[ -z "${annotations}" ]]; then
								annotations="${i}"
							else
								annotations="${annotations},${i}"
							fi
						fi
					done
				fi
				if [[ ${filetype[${sourcecount}]} == "tab" ]]; then
					if [ ! -z "${!description}" ] && [ -f "${!description}" ]; then
						for j in $(awk -F"\t" '/^[^##]/ {print $2}' ${!description} | tr '\n' ' '); do
							if [[ "${j}" == "${i}" ]]; then
								match="yes"
								if [[ -z "${annotations}" ]]; then
									annotations="${i}"
								else
									annotations="${annotations},${i}"
								fi
							fi
						done
					else
						for j in  $(zcat ${sourcefile[${sourcecount}]} | head -n 1); do
							if [[ "${j}" == "${i}" ]]; then
								match="yes"
								if [[ -z "${annotations}" ]]; then
									annotations="${i}"
								else
									annotations="${annotations},${i}"
								fi
							fi
						done
					fi
				fi
				if [[ ${filetype[${sourcecount}]} == "bed" ]]; then
					if [ ! -z "${!description}" ] && [ -f "${!description}" ]; then
						for j in $(awk -F"\t" '/^[^##]/ {print $2}' ${!description} | tr '\n' ' '); do
							if [[ "${j}" == "${i}" ]]; then
								match="yes"
								if [[ -z "${annotations}" ]]; then
									annotations="${i}"
								else
									annotations="${annotations},${i}"
								fi
							fi
						done
					fi
				fi
				if [[ ${match} != "yes" ]]; then 
					echo -e "\nYour selected field ${i} does not appear in $(basename ${sourcefile[${sourcecount}]}).\nIt will not be included."
				fi
				match=""
			done
			rm ${filename}
##OTHERWISE NOT IN A FILE 
		else
		# just making sure this array is empty for using columns from a bed file
			anncolsarray=()
			for i in $(echo "${newfields}" | sed 's/"[^"]\+"//g'); do
				if [[ ${filetype[${sourcecount}]} == "vcf" ]] || [[ ${filetype[${sourcecount}]} == "tab" ]] || [[ ${filetype[${sourcecount}]} == "bed" && -f "${!description}" ]]; then
					for j in  $(zcat ${unannotatedvcf} | head -n 500 | grep "^##INFO=<ID=" | sed 's/##INFO=<ID=\([^,]\+\),.\+,Description=\(.\+\)>$/\1/'); do
						if [[ ${sourcetag[${sourcecount}]}_${i} == ${j} ]]; then
							echo -e "The ${i} tag specified in your selection already exists in the target vcf file. It will not be used.\n"
							continue 1
						fi
					done
					for j in $(echo "${annotations}" | sed 's/,/ /g'); do
						if [[ "${j}" == "${i}" ]]; then
							echo -e "The ${i} tag specified in your selection already exists in the default fields or is repeated in your selection.\nIt will not be used twice.\n"
						continue 1
						fi
					done
					if [[ ${filetype[${sourcecount}]} == "vcf" ]]; then
						for j in  $(zcat ${sourcefile[${sourcecount}]} | head -n 500 | grep "^##INFO=<ID=" | sed 's/##INFO=<ID=\([^,]\+\),.\+,Description=\(.\+\)>$/\1/'); do
							if [[ "${j}" == "${i}" ]]; then
								match="yes"
								if [[ -z "${annotations}" ]]; then
									annotations="${i}"
								else
									annotations="${annotations},${i}"
								fi
							fi
						done
					fi
					if [[ ${filetype[${sourcecount}]} == "tab" ]] || [[ ${filetype[${sourcecount}]} == "bed" && -f "${!description}" ]]; then
						if [ ! -z "${!description}" ] && [ -f "${!description}" ]; then
							for j in $(awk -F"\t" '/^[^##]/ {print $2}' ${!description} | tr '\n' ' '); do
								if [[ "${j}" == "${i}" ]]; then
									match="yes"
									if [[ -z "${annotations}" ]]; then
										annotations="${i}"
									else
										annotations="${annotations},${i}"
									fi
								fi
							done
						else
							for j in  $(zcat ${sourcefile[${sourcecount}]} | head -n 1); do
								if [[ "${j}" == "${i}" ]]; then
									match="yes"
									if [[ -z "${annotations}" ]]; then
										annotations="${i}"
									else
										annotations="${annotations},${i}"
									fi
								fi
							done
						fi
					fi
					if [[ ${match} != "yes" ]]; then 
						echo -e "\nYour selected field \"${i}\" does not appear in $(basename ${sourcefile[${sourcecount}]}).\nIt will not be included."
					fi
					match=""
				elif [[ ${filetype[${sourcecount}]} == "bed" ]]; then
					for j in ${anncolsarray[@]}; do
						if [[ "${j}" == "${i}" ]]; then
							echo -e "\nThe \"${i}\" column specified is repeated in your selection.\nIt will not be used twice.\n"
							continue 1
						fi
					done
					if [ -z "${anncolsarray[@]}" ]; then
						anncolsarray=(${i})
					else
						anncolsarray=(${anncolsarray[@]} ${i})
					fi
				fi
			done
		fi
## CONVERT THE ANNOTATIONS INTO AN APPROPRIATE FORMAT DEPENDING ON SOURCE
	# for vcf
		if [[ ${filetype[${sourcecount}]} == "vcf" ]]; then
			#this converts a comma-delimited array of keys into the correct format for bcftools to use for vcf annotation
			for i in $(echo ${annotations} | awk -F, '{ for (i=1; i<=NF; i++) print $i }'); do
				if [ -z ${ann[${sourcecount}]} ]; then
					ann[${sourcecount}]="${sourcetag[${sourcecount}]}_${i}:=${i}"
					#ann[${sourcecount}]="${i}"
				else
					ann[${sourcecount}]="${ann[${sourcecount}]},${sourcetag[${sourcecount}]}_${i}:=${i}"
					#ann[${sourcecount}]="${ann[${sourcecount}]},${i}"
				fi
			done
	# for bed	
		elif [[ ${filetype[${sourcecount}]} == "bed" ]]; then
			# set up associative arrays for the individual entries, and the overall entry for each column
			unset ID
			unset Number
			unset Type
			unset Description
			unset Head
		# fix IDs for CHROM POS and TO -for a bed file these will always be the same - the index here is the column number
			ID[1]=CHROM
			ID[2]=FROM
			ID[3]=TO
			
			#oldIFS=$IFS
			IFS=","
			annotationsarray=(${annotations})
			IFS=$oldIFS
			# get the column numbers for annotations
			# if a descriptions file for the source has been specified and exists then just find the match in the second column and pull the column number out of the first
			if [ ! -z ${!description} ] && [ -f ${!description} ]; then
				# replace the unusable characters in column 2 with underscore
				newdescription=$(awk -F'\t' -v OFS='\t' 'NR>=3{gsub(/+|-|\(|\)/, "_", $2)} 1' ${!description})
				for i in $(echo ${annotations} | sed 's/,/ /g'); do
					# replace the unusable characters in the search term with underscores
					j=$(echo ${i} | sed 's/[-|+|(|)]/_/g')
					k=$(echo "${newdescription}" | awk -F"\t" "\$2 ~ /^${j}\$/ {print \$1}" -)
					if [ ! -z ${k} ]; then
						anncolsarray=(${anncolsarray[@]} ${k})
						ID[${k}]=${sourcetag[${sourcecount}]}_${i}
						Number[${k}]=$(echo "${newdescription}" | awk -F"\t" "\$2 ~ /^${j}\$/ {print \$3}" - )
						Type[${k}]=$(echo "${newdescription}" | awk -F"\t" "\$2 ~ /^${j}\$/ {print \$4}" - )
						Description[${k}]=$(echo "${newdescription}" |awk -F"\t" "\$2 ~ /^${j}\$/ {print \$5}" - )
					fi
				done
			fi
			# as you go through the for loop, for each annotation, pull out the appropriate comma delimited array, index it, then fix the variable for ID, Number, Type and Description using the array index (1 2 3 4 respectively).
			columncount=0
			#get the highest number in the annotation array
			lastcolumn=$(echo "${anncolsarray[@]}" | sed 's/ /\n/g' | sort -nr | head -n 1)
			while [[ ${columncount} -lt ${lastcolumn} ]]; do
				columncount=$(( ${columncount} + 1 ))
				for i in "${anncolsarray[@]}"; do
					if [ ${i} -eq ${columncount} ]; then
						while [ -z ${ID[${columncount}]} ] ; do
							echo -e "\n"
							read -p "Provide a brief ID (no spaces) for column ${columncount} that will be used as a tag, or q to quit, then press [RETURN]: " ID[${columncount}]
							if [[ ${ID[${columncount}]} == "q" ]]; then exit; fi
							ID[${columncount}]=${sourcetag[${sourcecount}]}_${ID[${columncount}]}
						done
						while [ -z "${Number[${columncount}]}" ] ; do
							echo -e "\nThe Number entry for an INFO field describes the number of values that can be in included."
							echo -e "Possible values are:"
							echo -e "An integer (eg \"1\" or \"2\" etc.)"
							echo -e "\"A\" if there is one value per alternate allele"
							echo -e "\"R\" if there is one value for each allele, including the reference"
							echo -e "\"G\" if there is one value for each possible genotype"
							echo -e "\".\" if the number of entries varies, is unbounded, or is unknown"
							read -p "Provide a number entry for column ${columncount}, or q to quit, then press [RETURN]: " Number[${columncount}]
							if [[ ${Number[${columncount}]} == "q" ]]; then exit; fi
						done
						while [ -z "${Type[${columncount}]}" ] ; do
							echo -e "\nThe Type entry for an INFO field describes the type of value included."
							echo -e "Possible values are:"
							echo -e "\"Integer\" where the number is an integer"
							echo -e "\"Float\" where the number is a floating point"
							echo -e "\"Flag\" where no value is entered, in this case the Number entry should be 0"
							echo -e "\"Character\""
							echo -e "\"String\""
							read -p "Provide a Type entry for column ${columncount}, or q to quit, then press [RETURN]: " Type[${columncount}]
							if [[ ${Type[${columncount}]} == "q" ]]; then exit; fi
						done
						while [ -z "${Description[${columncount}]}" ] ; do
							echo -e "\n"
							read -p "Provide a short description (one to two sentences) for this entry, or q to quit, then press [RETURN]: " Description[${columncount}]
							if [[ "${Description[${columncount}]}" == "q" ]]; then exit; fi
							Description[${columncount}]="${Description[${columncount}]}"
						done
						#make the header entry for this ID 
						Head[${columncount}]="##INFO=<ID=${ID[${columncount}]},Number=${Number[${columncount}]},Type=${Type[${columncount}]},Description=\"${Description[${columncount}]}\">"
						# ,Source=\"$(basename ${sourcefile[${sourcecount}]})\"
					fi
				done
				if [ -z ${ID[${columncount}]} ]; then
					ID[${columncount}]="-"
				fi
				#make the ann expression for a bed - this is a comma delimited list of column IDs up to the last one you wish to use - unused columns need - eg CHROM,FROM,TO,-,MYANNO 
				if [[ -z ${ann[${sourcecount}]} ]]; then
					ann[${sourcecount}]="${ID[${columncount}]}"
				else
					ann[${sourcecount}]="${ann[${sourcecount}]},${ID[${columncount}]}"
				fi
				# make the header entry - need to experiment with all the characters and the line break - some may need escaping - may need to put some other non-space delimiter in there (? |), and break up in the slurm script				 if [ ! -z ${Number[${i}]} ]; then 
				if [ -z "${header[${sourcecount}]}" ]; then
					header[${sourcecount}]="${Head[${columncount}]}"
				elif [ ! -z "${Head[${columncount}]}" ]; then
					header[${sourcecount}]="${header[${sourcecount}]}\n${Head[${columncount}]}"
				fi
			done
			
			
			
	#for tab 
		elif [[ ${filetype[${sourcecount}]} == "tab" ]]; then
			unset ID
			#typeset -A ID
	# sort out the column IDs for CHROM TO FROM	POS TO FROM	- uses column headers to identify column numbers - makes an array of CHROM POS etc indexed by column number the "head -n 3 | grep -v "^##" | head -n 1"  is to ignore the first line or two if they begin with ##, ed the CADD file
			tabheadarray=($(zcat ${sourcefile[${sourcecount}]} | head -n 3 | grep -v "^##" | head -n 1 ))
			columncount=0
			for i in "${tabheadarray[@]}"; do
				columncount=$(( ${columncount} + 1 ))
				if [ "${chrom}" == "${i}" ]; then
					ID[${columncount}]="CHROM"
				fi
				if [ "${from}" == "${i}" ] && [ "${to}" == "${i}" ]; then
					ID[${columncount}]="POS"
				elif [ "${from}" == "${i}" ]; then
					ID[${columncount}]="FROM"
				elif [ "${to}" == "${i}" ]; then
					ID[${columncount}]="TO"
				fi
				if [ "${ref}" == "${i}" ]; then
					ID[${columncount}]="REF"
				fi
				if [ "${alt}" == "${i}" ]; then
					ID[${columncount}]="ALT"
				fi
			done
			unset Number
			unset Type
			unset Description
			unset Head
			
			#oldIFS=$IFS
			IFS=","
			annotationsarray=(${annotations})
			IFS=$oldIFS
			anncolsarray=()
			# get the column numbers for annotations
			# if a descriptions file for the source has been specified and exists the just find the match in the second column and pull the column number out of the first
			if [ ! -z ${!description} ] && [ -f ${!description} ]; then
				# replace the unusable characters in column 2 with underscore
				newdescription=$(awk -F'\t' -v OFS='\t' 'NR>=3{gsub(/+|-|\(|\)/, "_", $2)} 1' ${!description})
				for i in $(echo ${annotations} | sed 's/,/ /g'); do
					# replace the unusable characters in the search term with underscores
					j=$(echo ${i} | sed 's/[-|+|(|)]/_/g')
					k=$(echo "${newdescription}" | awk -F"\t" "\$2 ~ /^${j}\$/ {print \$1}" -)
					if [ ! -z ${k} ]; then
						anncolsarray=(${anncolsarray[@]} ${k})
						ID[${k}]=${sourcetag[${sourcecount}]}_${i}
						Number[${k}]=$(echo "${newdescription}" | awk -F"\t" "\$2 ~ /^${j}\$/ {print \$3}" - )
						Type[${k}]=$(echo "${newdescription}" | awk -F"\t" "\$2 ~ /^${j}\$/ {print \$4}" - )
						Description[${k}]=$(echo "${newdescription}" |awk -F"\t" "\$2 ~ /^${j}\$/ {print \$5}" - )
					fi
				done
			fi
			
			#get the column numbers for any remaining annotations - ie if not in description file, or description file does not exist
			# there may be an issue here if there are any parentheses in the column headers - they ruin the arra - may beed to use comma delimited lists and expand with sed
			for i in "${!tabheadarray[@]}"; do
				for j in "${!annotationsarray[@]}"; do
					if [ "${tabheadarray[${i}]}" == "${annotationsarray[${j}]}" ]; then
						if [ -z ${ID[$(( ${i} + 1 ))]} ]; then
							anncolsarray=(${anncolsarray[@]} $(( ${i} + 1 )))
						fi
					fi
				done
			done
			# as you go through the for loop, for each annotation, pull out the appropriate comma delimited array, index it, then fix the variable for ID, Number, Type and Description using the array index (1 2 3 4 respectively).
			columncount=0
			#get the highest number in the annotation array
			lastcolumn=$(echo "${anncolsarray[@]}" | sed 's/ /\n/g' | sort -nr | head -n 1)
			while [[ ${columncount} -lt ${lastcolumn} ]]; do
				columncount=$(( ${columncount} + 1 ))
				for i in "${anncolsarray[@]}"; do
					if [ ${i} -eq ${columncount} ]; then
						if [ -z ${ID[${columncount}]} ]; then
							ID[${columncount}]=${sourcetag[${sourcecount}]}_${tabheadarray[$(( ${columncount} - 1 ))]}
						fi
						while [ -z "${Number[${columncount}]}" ] ; do
							echo -e "\nThe Number entry for an INFO field describes the number of values that can be in included."
							echo -e "Possible values are:"
							echo -e "An integer (eg \"1\" or \"2\" etc.)"
							echo -e "\"A\" if there is one value per alternate allele"
							echo -e "\"R\" if there is one value for each allele, including the reference"
							echo -e "\"G\" if there is one value for each possible genotype"
							echo -e "\".\" if the number of entries varies, is unbounded, or is unknown"
							read -p "Provide a number entry for ${ID[${columncount}]}, or q to quit, then press [RETURN]: " Number[${columncount}]
							if [[ ${Number[${columncount}]} == "q" ]]; then exit; fi
						done
						while [ -z "${Type[${columncount}]}" ] ; do
							echo -e "\nThe Type entry for an INFO field describes the type of value included."
							echo -e "Possible values are:"
							echo -e "\"Integer\" where the number is an integer"
							echo -e "\"Float\" where the number is a floating point"
							echo -e "\"Flag\" where no value is entered, in this case the Number entry should be 0"
							echo -e "\"Character\""
							echo -e "\"String\""
							read -p "Provide a Type entry for ${ID[${columncount}]}, or q to quit, then press [RETURN]: " Type[${columncount}]
							if [[ ${Type[${columncount}]} == "q" ]]; then exit; fi
						done
						while [ -z "${Description[${columncount}]}" ] ; do
							echo -e "\n"
							read -p "Provide a short description (one to two sentences) for ${ID[${columncount}]}, or q to quit, then press [RETURN]: " Description[${columncount}]
							if [[ "${Description[${columncount}]}" == "q" ]]; then exit; fi
							Description[${columncount}]="${Description[${columncount}]}"
						done
					#make the header entry for this ID 
						Head[${columncount}]="##INFO=<ID=${ID[${columncount}]},Number=${Number[${columncount}]},Type=${Type[${columncount}]},Description=\"${Description[${columncount}]}\">"
						# ,Source=\"$(basename ${sourcefile[${sourcecount}]})\"
					fi
				done
				if [ -z ${ID[${columncount}]} ]; then
					ID[${columncount}]="-"
				fi
				#make the ann expression for a tab - this is a comma delimited list of column IDs up to the last one you wish to use - unused columns need - eg CHROM,FROM,TO,-,MYANNO 
				if [[ -z ${ann[${sourcecount}]} ]]; then
					ann[${sourcecount}]="${ID[${columncount}]}"
				else
					ann[${sourcecount}]="${ann[${sourcecount}]},${ID[${columncount}]}"
				fi
				# make the header entry - 
				if [ -z "${header[${sourcecount}]}" ]; then
					header[${sourcecount}]="${Head[${columncount}]}"
				elif [ ! -z "${Head[${columncount}]}" ]; then
					header[${sourcecount}]="${header[${sourcecount}]}\n${Head[${columncount}]}"
				fi
			done
		fi
		# if there are no valid annotations remaining to add then make sure no entry is made for the sourcetag and other arrays
		if [[ -z ${ann[${sourcecount}]} ]]; then
			echo -e "\nThere are no annotations from $(basename ${sourcefile[${sourcecount}]}) to add"
			read -e -p "Type nothing to continue, or q to quit, and press [RETURN]: " proceed
			if [[ ${proceed} == "q" ]]; then exit; fi
		else
		# build a sourcetag array
			sourcetagarray=(${sourcetagarray[@]} ${sourcetag[${sourcecount}]})
		# build a sourcefile array
			sourcefilearray=(${sourcefilearray[@]} ${sourcefile[${sourcecount}]})
		# build a filetype array
			filetypearray=(${filetypearray[@]} ${filetype[${sourcecount}]})
		# build an annotation array
			annotatearray=(${annotatearray[@]} ${ann[${sourcecount}]})
		fi
	fi
done

if [ ! -f ${parameterfile} ]; then
	mkdir -p $(dirname ${parameterfile})
	echo "unannotatedvcf=${unannotatedvcf}" >> ${parameterfile}
	echo "default=${default}" >> ${parameterfile}
	echo "REF=${REF}" >> ${parameterfile}
	echo "CONTIGSTRING=${CONTIGSTRING}" >> ${parameterfile}
	echo "contigarraynumber=${contigarraynumber}" >> ${parameterfile}
	echo "snpeff=${snpeff}" >> ${parameterfile}
	echo "snpeff_format=${snpeff_format}" >> ${parameterfile}
	echo "snpeffdataversion=${snpeffdataversion}" >> ${parameterfile}
	echo "vep=${vep}" >> ${parameterfile}
	echo "vepassembly=${vepassembly}" >> ${parameterfile}
	echo "vepspecies=${vepspecies}" >> ${parameterfile}
	echo "BCSQ=${BCSQ}" >> ${parameterfile}
	echo "GFF3forBCSQ=${GFF3forBCSQ}" >> ${parameterfile}
	echo "Xcludedsamples=${Xcludedsamples}" >> ${parameterfile}
	echo "sourcetagarray=(${sourcetagarray[@]})" >> ${parameterfile}
	echo "sourcefilearray=(${sourcefilearray[@]})" >> ${parameterfile}
	echo "filetypearray=(${filetypearray[@]})" >> ${parameterfile}
	echo "annotatearray=(${annotatearray[@]})" >> ${parameterfile}
	for i in ${!header[@]}; do
		if [ ! -z "${header[${i}]}" ] && [[ "${header[${i}]}" != "null" ]]; then
			mkdir -p ${PROJECT_PATH}/headers
			echo -e "${header[${i}]}" > ${PROJECT_PATH}/headers/${sourcetag[${i}]}.hdr
		fi
	done
fi
if ! mkdir -p ${PROJECT_PATH}/slurm; then
	echo "Error creating output folder!"
	exit 1
fi
launch=$PWD
cd ${PROJECT_PATH}
if [[ ${snpeff} == "yes" ]]; then
	mkdir -p ${PROJECT_PATH}/slurm/snpeff
	snpeffArray=""
	for i in $(seq 1 ${#CONTIGARRAY[@]}); do
		CONTIG=${CONTIGARRAY[$(( ${i} - 1 ))]}
    	if [ ! -f ${PROJECT_PATH}/done/snpeff/${CONTIG}_SnpEff.vcf.gz.tbi.done ]; then
        	snpeffArray=$(appendList "${snpeffArray}"  $i ",")
    	fi
	done
	if [ "$snpeffArray" != "" ]; then
		snpeffjob=$(sbatch -J SnpEff_${PROJECT} ${mailme} --array ${snpeffArray}%12 ${BASEDIR}/slurm_scripts/annoSnpEff.sl | awk '{print $4}')
		if [ $? -ne 0 ] || [ "$snpeffjob" == "" ]; then
			(printf "FAILED!\n" 1>&2)
			exit 1
		else
			echo "SnpEff_${PROJECT} job is ${snpeffjob}"
			(printf "%sx%-4d [%s] Logs @ %s\n" "$snpeffjob" $(splitByChar "$snpeffArray" "," | wc -w) $(condenseList "$snpeffArray") "${PROJECT_PATH}/slurm/snpeff/snpeff-${snpeffjob}_*.out" 1>&2)
		fi
	fi
fi


if [[ ${vep} == "yes" ]]; then
	mkdir -p ${PROJECT_PATH}/slurm/vep
	vepArray=""
	for i in $(seq 1 ${#CONTIGARRAY[@]}); do
		CONTIG=${CONTIGARRAY[$(( ${i} - 1 ))]}
		if [ ! -f ${PROJECT_PATH}/done/vep/${CONTIG}_VEP.vcf.gz.tbi.done ]; then
        	vepArray=$(appendList "${vepArray}"  $i ",")
    	fi
	done
	if [ "$vepArray" != "" ]; then
		vepjob=$(sbatch -J VEP_${PROJECT} $(depCheck $snpeffjob) ${mailme} --array ${vepArray}%12 ${BASEDIR}/slurm_scripts/annoVEP.sl | awk '{print $4}')
		if [ $? -ne 0 ] || [ "$vepjob" == "" ]; then
			(printf "FAILED!\n" 1>&2)
			exit 1
		else
			echo "VEP_${PROJECT} job is ${vepjob}"
			# Tie each task to the matching task in the previous array.
			if [ ${snpeff} == "yes" ]; then
				tieTaskDeps "$vepArray" "$vepjob" "$snpeffArray" "$snpeffjob"
			fi
			(printf "%sx%-4d [%s] Logs @ %s\n" "$vepjob" $(splitByChar "$vepArray" "," | wc -w) $(condenseList "$vepArray") "${PROJECT_PATH}/slurm/vep/vep-${vepjob}_*.out" 1>&2)
		fi
	fi
fi

if [ "${#sourcetagarray[@]}" -ne 0 ]; then
	mkdir -p ${PROJECT_PATH}/slurm/ann
	annArray=""
	for i in $(seq 1 ${#CONTIGARRAY[@]}); do
		CONTIG=${CONTIGARRAY[$(( ${i} - 1 ))]}
		if [ ! -f ${PROJECT_PATH}/done/ann/${CONTIG}_ann.vcf.gz.tbi.done ]; then
  	      annArray=$(appendList "${annArray}"  $i ",")
  	  fi
	done
	if [ "$annArray" != "" ]; then
		annjob=$(sbatch -J AnnotateVCF_${PROJECT} $(depCheck $snpeffjob $vepjob) ${mailme} --array ${annArray}%12 ${BASEDIR}/slurm_scripts/annotateVCF.sl | awk '{print $4}')
		if [ $? -ne 0 ] || [ "$annjob" == "" ]; then
			(printf "FAILED!\n" 1>&2)
			exit 1
		else
			echo "Ann_${PROJECT} job is ${annjob}"
			if [ ${vep} == "yes" ]; then
				tieTaskDeps "$annArray" "$annjob" "$vepArray" "$vepjob"
			elif [ ${snpeff} == "yes" ]; then
				tieTaskDeps "$annArray" "$annjob" "$snpeffArray" "$snpeffjob"
			fi
			(printf "%sx%-4d [%s] Logs @ %s\n" "$annjob" $(splitByChar "$annArray" "," | wc -w) $(condenseList "$annArray") "${PROJECT_PATH}/slurm/ann/ann-${annjob}_*.out" 1>&2)
		fi
	fi
fi

#### Merge the annotated contig vcf.gz files together
mkdir -p ${PROJECT_PATH}/slurm/merge
# find the job that this stsge should check for dependencies
if [ "${#sourcetagarray[@]}" -ne 0 ]; then
	whatjob=$annjob
elif [[ ${vep} == "yes" ]]; then
	whatjob=$vepjob
elif [[ ${snpeff} == "yes" ]]; then
	whatjob=$snpeffjob
fi
if [ ! -f "${PROJECT_PATH}/done/merge/${PROJECT}.done" ]; then
	mergejob=$(sbatch $(depCheck $whatjob) -J Merge_${PROJECT} ${mailme} ${BASEDIR}/slurm_scripts/merge.sl | awk '{print $4}')
	if [ $? -ne 0 ] || [ "$mergejob" == "" ]; then
		(printf "FAILED!\n" 1>&2)
		exit 1
	else
		echo "Merge_${PROJECT} job is ${mergejob}"
		(printf "%s Log @ %s\n" "$mergejob" "${PROJECT_PATH}/slurm/merge/merge-${mergejob}.out" 1>&2)
	fi
fi


###### Do the BCSQ annotatiom
if [[ ${BCSQ} == "yes" ]]; then
	if [ ! -f "${PROJECT_PATH}/done/bcsq/${PROJECT}_ann.vcf.gz.tbi.done" ]; then
		bcsqjob=$(sbatch -J BCSQ_${PROJECT} $(depCheck $mergejob) ${mailme} ${BASEDIR}/slurm_scripts/annoBCSQ.sl | awk '{print $4}')
		if [ $? -ne 0 ] || [ "$bcsqjob" == "" ]; then
			(printf "FAILED!\n" 1>&2)
			exit 1
		else
			echo "BCSQ_${PROJECT} job is ${bcsqjob}"
			(printf "%s Log @ %s\n" "$bcsqjob" "${PROJECT_PATH}/slurm/bcsq/bcsq-${bcsqjob}.out" 1>&2)
		fi
	fi
fi

##### Move most files to destination directory
mkdir -p ${PROJECT_PATH}/slurm/move
if [[ ${BCSQ} == "yes" ]]; then
	whatjob=$bcsqjob
else
	whatjob=$mergejob
fi

if [ ! -f "${PROJECT_PATH}/done/move/${PROJECT}.done" ]; then
	movejob=$(sbatch -J Move_${PROJECT} $(depCheck $whatjob) ${mailme} ${BASEDIR}/slurm_scripts/move.sl | awk '{print $4}')
	if [ $? -ne 0 ] || [ "$movejob" == "" ]; then
		(printf "FAILED!\n" 1>&2)
		exit 1
	else
		echo "Move_${PROJECT} job is ${movejob}"
		(printf "%s Log @ %s\n" "$movejob" "${PROJECT_PATH}/slurm/move/move-${movejob}.out" 1>&2)
	fi
fi

#####clean up 
#this takes us back to the original launch directory so that the final slurm out file will be written there
cd ${launch}
cleanupjob=$(sbatch -J Cleanup_${PROJECT} $(depCheck $movejob) ${mailme} ${BASEDIR}/slurm_scripts/cleanup.sl | awk '{print $4}')
if [ $? -ne 0 ] || [ "$cleanupjob" == "" ]; then
	(printf "FAILED!\n" 1>&2)
	exit 1
else
	echo "Cleanup_${PROJECT} job is ${cleanupjob}"
	(printf "%s Log @ %s\n" "$cleanupjob" "${launch}/AnnotationCleanup-${cleanupjob}.out" 1>&2)
fi

