# Annotate_my_VCF
- This is an annotation pipeline for use on a SLURM cluster, to add useful information from source files to a VCF file.
Requirements:
- It uses SnpEff, Ensembl VEP, and BCFtools for annotation. 
- It also requires GATK4 for merging contigs back together.
Annotation Source files:
- Requires access to snpeff database and VEP cache.
- In addition can use VCF, BED and tab-delimited text files to source annotation information.
- VCF and bed files should be standard format - bed files can have extra columns for further annotations.
- Tab-delimited text files should contain a first line (starting with a #) to provides headers to each column, and should contain a chromosome column and a position column (or to and from columns for intervals).
- BED and tab-delimited text files each require a "description" file that sets the individual annotation keys and interprets the type and number of each annotation, provides a description to be included in the VCF header, and provides the merge logic required when a file contains interval data (which can be overlapping). See examples in the SourceDescriptions folder.
- Annotation Source files often required a significant amount of manipulation before they are suitable to be used - eg adding chromosome and position columns (often based on gene names), removing problematic characters from column entries (eg white space, commas, +) etc etc
Other Required Files:
- the basefunctions.sh file provides a variety of useful functions required by the scripts
- the defaults.txt file contains information about the sources available and which ones to use. This file will need to be edited accordingly - the source files are often very large and none are available with this distribution.
- the defaults.txt file also specifies the reference sequence to use, and provides information about how the genome can be split up into contigs for parallel processing before remerging.
How to start:
Interactive mode: 
- run the master script (Annotate_my_VCF.sh) without any arguments
- script will source the defaults.txt file, and will ask for a vcf file to annotate, propose the contigs to parallelise with, and ask about what annotations you would like to use. It will go through all source files listed to use by default, but will still allow changes about which annotations to use from those sources. Finally it will allow you to specify any other (appropriately formatted) source file you may have access to, but will then request the information required for the header about each annotation.
Non-interactive mode:
- run the master script (Annotate_my_VCF.sh) with the full path to the VCF to annotate as the first argument, and a suitable defaults file to specify the annotation to use. This could be the standard defaults.txt file, or a copied and edited version specifying desired annotations, reference, contigs etc


