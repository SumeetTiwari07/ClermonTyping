#!/usr/bin/env bash

#################################################
########## Clermont Typing pipeline #############
#################################################
# From a set a contigs in fasta format:
# 1] Launch mash for getting phylogroup
# 2] Make a blast db
# 3] Launch blast on a primers fasta file
# 4] Launch in silicco PCR for getting phylogroup
# 5] Reportings tools
#
# Current version : 1.4.1 (Jun. 2019)
version="Clermont Typing  Current version : 1.4.1 (Jun. 2019)"

# Contact: antoine.bridier-nahmias@inserm.fr

MY_PATH="`dirname \"$0\"`"
#Default threshold = 0 (disabled)
THRESHOLD=0
#Default name = date
DATE=$( date "+%F_%H%M%S")
NAME=analysis_$DATE
#Global variables
THREADS=4
#BLAST settings
PRIMERS="${MY_PATH}/data/primers.fasta"
PERC_IDENTITY=90
BLAST_TASK='blastn'
#MASH settings
DB_MASH="${MY_PATH}/data/mash/mash_reference.msh"

function usage(){
	printf "Script usage :\n"
	printf "\t-h					: print this message and exit\n"
	printf "\t-v					: print the version and exit\n"
	printf "\t--fasta					: fasta contigs file(s). If multiple files, they must be separated by an arobase (@) value\n"
	printf "\t--name					: name for this analysis (optional)\n"
	printf "\t--threshold				: Option for ClermontTyping, do not use contigs under this size (optional)\n"
}

function mash_analysis(){
	echo "============== Running mash ================"
	${MY_PATH}/bin/mash screen -w $DB_MASH $FASTA >$WORKING_DIR/${FASTA_NAME}_mash_screen.tab
}

function blast_analysis(){
	echo "============== Making blast db ================"
	echo "makeblastdb -in $FASTA -input_type fasta -out $WORKING_DIR/db/$NAME -dbtype nucl"
	makeblastdb -in $FASTA -input_type fasta -out $WORKING_DIR/db/$FASTA_NAME -dbtype nucl
	if [ $? -eq 0 ]
	then
        echo "============== Running blast =================="
        blastn -query $PRIMERS -perc_identity $PERC_IDENTITY -task $BLAST_TASK -word_size 6 -outfmt 5 -db $WORKING_DIR/db/$FASTA_NAME -out $WORKING_DIR/$FASTA_NAME.xml
        error=0
	else
        echo "Error detected! Stopping pipeline..."
        error=1
	fi

}

function report_calling(){
	# rscript = path to clermontReport.R
	# clermont_out = path to clermonTyping output 
	# namus = report name
	# out_dir = self explanatory!
	echo "============= Generating report ==============="
	rscript=$1
	shift
	clermont_out=$1
	shift
	namus=$1
	shift
	out_dir=$1

	modif_script=${out_dir}/${namus}.R
	cp ${rscript} ${modif_script}

	sed -i "s:TARTAMPION:$clermont_out:g" "${modif_script}"

	Rscript --slave -e "library(markdown); sink('/dev/null');rmarkdown::render('${modif_script}')"
}


if [ $# == 0 ]
then
	 usage
	 exit 1
fi

while [[ $# -gt 0 ]]
do
    case "$1" in
	-v)
	echo $version
	usage
	exit 0
	;;
        -h)
        usage
        exit 0
        ;;
        --fasta) 
		FASTAS="$2";
        shift
        ;;
        --name) 
		NAME="$2";
        shift
        ;;
        --threshold) 
		THRESHOLD="$2";
        shift
        ;;
        --) shift; break;;
    esac
    shift
done

if [ -z $FASTAS ]
then
	echo "Missing the contigs file. Option --fasta"
	usage
	exit 1
fi

echo "You asked for a Clermont typing analysis named $NAME of phylogroups on $FASTAS with a threshold under $THRESHOLD."

if [ ! -d $NAME ]
then
	mkdir $NAME
fi
CURRENT_DIR=`pwd`
WORKING_DIR=$CURRENT_DIR/$NAME
#Analysis of each fasta file
IFS='@' read -ra ARRAY_FASTA <<< "$FASTAS"
for FASTA in "${ARRAY_FASTA[@]}"; do
	if [ -f $FASTA ] && [ ! -z $FASTA ]
	then
		#Rename file
		BASE_NAME_FASTA=`basename $FASTA`
		FASTA_NAME=${BASE_NAME_FASTA%£*}
		echo "Analysis of ${FASTA_NAME}"
		cp $FASTA $WORKING_DIR/${FASTA_NAME}
		FASTA=$WORKING_DIR/$FASTA_NAME
		##### Step 1: MASH analysis #####
		# Generate ${FASTA_NAME}_mash_screen.tab
		mash_analysis
		##### Step 2: Blast #############
		# Generate ${FASTA_NAME}.xml
		blast_analysis
        if [ $error -gt 0 ]
        then
            echo "$FASTA_NAME				\"NA\"	${FASTA_NAME}_mash_screen.tab" >> $WORKING_DIR/${NAME}_phylogroups.txt
        else
            ##### Step 3: ClermonTyping #####
            echo "============== ClermonTyping =================="
            results=`${MY_PATH}/bin/clermont.py -x ${WORKING_DIR}/${FASTA_NAME}.xml -s $THRESHOLD`
            echo "$FASTA_NAME	$results	${FASTA_NAME}_mash_screen.tab" >> $WORKING_DIR/${NAME}_phylogroups.txt
        fi
	else
		echo "$FASTA doesn't exists"
	fi
done
##### Step 4: Reporting #########
report_calling "${MY_PATH}/bin/clermontReport.R" $WORKING_DIR/${NAME}_phylogroups.txt $NAME $WORKING_DIR


exit 0
