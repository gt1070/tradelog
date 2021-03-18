#!/bin/sh
POSIXLY_CORRECT=yes
#OPTS
while getopts "ha: b: t: w:-" OPTION; do		## nacte dostupne options
	case $OPTION in
		h | -) ## dovoluje sice misto --help napsat i --* ale nastesti neni potreba zadavat vice long options takze to neni na skodu
printf "Analize stock exchange logs.
Usage: tradelog [-h|--help] [OPTION]... [COMMAND] [LOG]...
Default behaviour is to print content of logs one after another. If no logs provided, expecting input from stdin.
OPTIONS:
-a DATETIME	After date pass. DATETIME format: \"YYYY-MM-DD HH:MM:SS\". Note that \"\" are essential. 
-b DATETIME	Before date pass.
-t TICKER	Ticker pass. TICKER must be uppercase.
-w WIDTH	Width number of maximum displayed characters for graph-pos and hist-ord.
		WIDTH must be integer greater than 1. Without parameter default behaviour is:
		one char per 1000,- for graph-pos, and one char per one transaction for hist-ord.
		If WIDTH is specified, all values are relative to maximum value.
COMMANDS:
list-tick	List mentioned tickers.
profit		Print profit from all transactions.
pos 		Position. Value of actualy holded shares. Note that price of one share 
		is last known price of specific ticker from analized log.
last-price	Print last mentioned price of avalible tickers.
hist-ord	Print number of transactions in histogram. More in -w description.
graph-pos 	Print position in graph. \"#\" is for positive numbers \"!\" for negative numbers. More in -w description.

EXITCODES:
0 = good
1 = log file not found or not readable
2 = no argument for filter
3 = wrong filter format
4 = previous use of unique filter
5 = illegal option
\n"
			exit 0;;
		a) 	
			if [ "$TIME_AFTER" ]; then echo ERROR: previous use of -a ; exit 4 ; fi
			if [ ! "$OPTARG" ]; then echo ERROR: no argument for -a ; exit 2 ; fi
			if ! echo "$OPTARG" | grep -wq "[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]" ; then 
				echo ERROR: time format for option -a is wrong. Do you use \"\"? ; exit 3
			fi
			TIME_AFTER=$(echo $OPTARG | sed -e "s/://g" -e "s/ //g" -e "s/-//g") ;;  ## rovnou prevest na porovnavatelny format 
		b) 	
			if [ "$TIME_BEFORE" ]; then echo ERROR: previous use of -b ; exit 4 ; fi
			if [ ! "$OPTARG" ]; then echo ERROR: no argument for -b ; exit 2 ; fi
			if ! echo "$OPTARG" | grep -wq "[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]" ; then
				echo ERROR: time format for option -b is wrong. Do you use \"\"? ; exit 3
			fi
			TIME_BEFORE=$(echo $OPTARG | sed -e "s/://g" -e "s/ //g" -e "s/-//g") ;;			
		w) 	
			if [ "$WIDTH" ]; then echo ERROR: previous use of -w ; exit 4 ; fi
			if [ ! "$OPTARG" ]; then echo ERROR: no argument for -w ; exit 2 ; fi
			if ! echo "$OPTARG" | grep -wq "[0-9]*[0-9]" || [ $OPTARG -le 1 ]; then 	#wq quiet and take only perfect matching line
				echo ERROR: width format for option -w is wrong. ; exit 3
			fi
			WIDTH=$OPTARG ;;

		t)
			if [ ! "$OPTARG" ]; then echo ERROR: no argument for -t ; exit 2 ; fi
			if ! echo "$OPTARG" | grep -wq "[A-Z]*[A-Z]" ; then echo ERROR: ticker format for option -t is wrong. Do you use UPPERCASE ?; exit 3 ; fi
			if [ ! $TICKER ] ; then TICKER=$OPTARG 
			else TICKER="$TICKER\|$OPTARG" ; fi
			;;
		\?)
			echo ERROR: illegal option. Type \"tradelog -h\" for help. ; exit 5;
	esac
done
shift $(expr $OPTIND - 1)			

#CMDS CHECK
for cmd in list-tick profit pos last-price hist-ord graph-pos	## zkontroluje jestli je zadan jeden z prikazu
do
	if [ "$1" = "$cmd" ]; then
		CMD=$cmd
		shift 1
		break 	# zajisti aby se po prvnim nalezu vyskocilo z for cyklu hledani prikazu
	fi
done

#STDIN CHECK
if [ ! $1 ]; then				## zkontroluje jestli je vubec zadan aspon log jestli ne tak bere ze stdin
	#echo TRADELOG FROM STDIN: 
	input='cat - '
	STDIN=1
fi

# MAIN LOOP
while [ true ]; do		
	unset IFS
# kontrola inputu
	if [ ! $STDIN ]; then	
		if [ ! -r $1 ]; then echo ERROR: cant read file $1 ; exit 1 ; fi
		if echo $1 | grep -q ".gz" ; then	## potichu otestuj jestli je input file kompresovany
			input="gzip -cd $1 "
		else
			input="cat $1 "
		fi
		#echo TRADELOG FROM FILE: $1
		shift 1		
	fi			

# ulozeni vstupu do vicekrat pouzitelne formy ( presmerovany stdin mi sel puzit jen jednou )
	file=""		
	IFS="" 	## je silene jak dlouho mi trvalo nez jsem prisel na tento jednoduchy zpusob jak ulozit obsah souboru do promenne shellu
	file=$(eval $input)
	input="echo '$file'"
	unset IFS
##################### filtry
	filters=""
# b
	if [ "$TIME_BEFORE" ]; then
		listofdates=$(printf "$file\n" | awk 'BEGIN { FS=";" } ; { print $1 }' | sed -e "s/://g" -e "s/ //g" -e "s/-//g") #convert date for compare
		headnum=0
		for cmp in $listofdates ; do
			if [ $cmp -ge $TIME_BEFORE ] ; then break ; fi
			headnum=$((headnum + 1))
		done
		filters="$filters | head -n $headnum"
	fi
# a
	if [ "$TIME_AFTER" ]; then
		listofdates=$(printf "$file\n" | awk 'BEGIN { FS=";" } ; { print $1 }' | sed -e "s/://g" -e "s/ //g" -e "s/-//g") #convert date for compare
		tailnum=0
		for cmp in $listofdates ; do
			if [ $cmp -eq $TIME_AFTER ]; then timematch=1 ;fi
			if [ $cmp -ge $TIME_AFTER ] ; then break ; fi
			tailnum=$((tailnum + 1))
		done
		if [ $timematch ] ; then tailnum=$((tailnum + 1)); fi 		## osetreni kolize v pripade shody datumu
		tailnum=$(( tailnum + 1 ))
		filters="$filters | tail -n +$tailnum"
	fi
# t
	if [ "$TICKER" ]; then
		filters="$filters | grep ';$TICKER;'"
	fi

# ulozeni vystupu filtru ( filtry by sli predat prikazum i pomoci eval ale to je mnohem vice vypocetne narocne )
	filtered=""
	IFS=""
	filtered=$(eval $input $filters)
	unset IFS
## konec filtru

###################### prikazy
	if [ ! $CMD ] ; then 
		printf "$filtered\n"
       	else
		case $CMD in
			list-tick)
				printf "$filtered\n" | awk 'BEGIN { FS=";" } ; { print $2 }' | sort | uniq
				;;
			profit)
				sell=0
				buy=0
				if printf "$filtered\n" | grep -q sell ; then
					sell=$(printf "$filtered\n" | grep sell | awk 'BEGIN { FS=";" } ; { sum += $4 * $6; n++ } END { if (NR > 0) printf "%.2f\n", sum }')
				fi
				if printf "$filtered\n" | grep -q buy ; then
					buy=$(printf "$filtered\n" | grep buy | awk 'BEGIN { FS=";" } ; { sum += $4 * $6; n++ } END { if (NR > 0) printf "%.2f\n", sum }')
				fi
				echo "$sell-$buy" | bc
				;;
			pos) 	
				listoftck=$(printf "$filtered\n" | awk 'BEGIN { FS=";" } ; { print $2 }' | sort | uniq)
				listofpos=""
				for tck in $listoftck ; do
					sell=0
					buy=0
					if printf "$filtered\n" | grep ";$tck;" | grep -q sell ; then
						sell=$(printf "$filtered\n" | grep ";$tck;" | grep sell | awk 'BEGIN { FS=";" } ; { sum += $6; n++ } END { if (NR > 0) printf "%.2f\n", sum }')
					fi
					if printf "$filtered\n" | grep ";$tck;" | grep -q buy ; then
						buy=$(printf "$filtered\n" | grep ";$tck;" | grep buy | awk 'BEGIN { FS=";" } ; { sum += $6; n++ } END { if (NR > 0) printf "%.2f\n", sum }')
					fi
					price=$(printf "$filtered\n" | tac | grep -m 1 ";$tck;" | awk 'BEGIN { FS=";" } ; { print $4 }')
					hold=$( echo "$buy - $sell" | bc)
					prof=$(echo "$hold * $price" | bc)
					listofpos="$listofpos $prof $tck \n"
				done
				echo $listofpos | sort -gr | awk 'BEGIN { FS=" " } ; { printf "%s\t:\t%20.2f\n", $2, $1 }' | tac | tail -n +2 | tac
				;;
			last-price)
				listoftck=$(printf "$filtered\n" | awk 'BEGIN { FS=";" } ; { print $2 }' | sort | uniq)
				for tck in $listoftck ; do
					printf "$filtered\n" | tac | grep -m 1 ";$tck;" | awk 'BEGIN { FS=";" } ; { printf "%s\t:\t%20.2f\n", $2, $4 }'
				done
				;;
			hist-ord)
				listoftck=$(printf "$filtered\n" | awk 'BEGIN { FS=";" } ; { print $2 }' | sort | uniq)
				if [ $WIDTH ] ; then
					count=0
					max=0
					for tck in $listoftck ; do
						count=$(printf "$filtered\n" | grep -c ";$tck;")
						if [ $count -gt $max ] ; then max=$count ; fi
					done
					frac=$( echo "scale=20; $WIDTH / $max" | bc )
				fi
				for tck in $listoftck ; do
					printf "$tck \t : "
					count=$(printf "$filtered\n" | grep -c ";$tck;")
					if [ $WIDTH ] ; then 
						raw=0
						raw=$( echo "$frac * $count - 0.5" | bc )
						count=$(printf "%.0f\n" $raw)
						## zde jeste osetrit max value
				       	fi	
					i=0
					while [ $i -lt $count ] ; do
						printf "#"
						i=$((i+1))
					done
					printf "\n"
				done
				;;
			graph-pos)
				max=0
				listoftck=$(printf "$filtered\n" | awk 'BEGIN { FS=";" } ; { print $2 }' | sort | uniq)
				listofpos=""
				for tck in $listoftck ; do
					sell=0
					buy=0
					if printf "$filtered\n" | grep ";$tck;" | grep -q sell ; then
						sell=$(printf "$filtered\n" | grep ";$tck;" | grep sell | awk 'BEGIN { FS=";" } ; { sum += $6; n++ } END { if (NR > 0) printf "%.2f\n", sum }')
					fi
					if printf "$filtered\n" | grep ";$tck;" | grep -q buy ; then
						buy=$(printf "$filtered\n" | grep ";$tck;" | grep buy | awk 'BEGIN { FS=";" } ; { sum += $6; n++ } END { if (NR > 0) printf "%.2f\n", sum }')
					fi
					price=$(printf "$filtered\n" | tac | grep -m 1 ";$tck;" | awk 'BEGIN { FS=";" } ; { print $4 }')
					hold=$( echo "$buy - $sell" | bc)
					prof=$(echo "$hold * $price" | bc)
					listofpos="$listofpos $prof $tck \n"
					if [ $WIDTH ] ; then
						check=$( echo "x=$prof; if(x<0) x=$prof * -1; x" | bc )
						if [ $(echo "$check > $max" | bc ) -eq 1 ] ;then max=$check ; fi
					fi
				done
				IFS=""
				pos=$(echo $listofpos | sort -gr | awk 'BEGIN { FS=" " } ; { printf ";%s;%.2f\n", $2, $1 }' | tac | tail -n +2 | tac)
				unset IFS
				if [ $WIDTH ] ;then frac=$( echo "scale=20; $WIDTH / $max" | bc ) ; fi
				for tck in $listoftck ; do
					printf "$tck \t : "
					actual=$(printf "$pos\n" | grep ";$tck;" | awk 'BEGIN { FS=";" } ; { printf "%.2f", $3}' ) 
					if [ ! $WIDTH ] ;then
						count=$(echo "$actual / 1000" | bc)
					else
						if [ $( echo "$actual > 0" | bc ) -eq 1 ] ; then 	# prepare round to zero
							raw=$(echo "$actual * $frac - 0.5" | bc)
						else
							raw=$(echo "$actual * $frac + 0.5" | bc)
						fi
						count=$(printf "%.0f" $raw) 				# round to zero
						if [ "$actual" = "$max" ] ; then count=$WIDTH ; fi	# cure bc procesing .99999
						if [ "$actual" = "-$max" ] ; then count="-$WIDTH" ; fi	# cure max value
						#raw2=$(echo "$actual * $frac" | bc)
						#echo raw $raw raw2 $raw2 count $count max $max act $actual
					fi
					i=0
					while [ $i -lt $count ] ; do
						printf "#"
						i=$((i+1))
					done
					while [ $i -gt $count ] ; do
						printf "!"
						i=$((i-1))
					done
					printf "\n"
				done
				;;
		esac

	fi

	#### konec prikazu


##end main funkce
	if [ ! $1 ]; then exit 0 ; fi		#nahrada do while
done
