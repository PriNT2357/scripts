#!/bin/bash

echo "Renaming files for 4-Sided Dive"

while true; do
	read -p "Enter file filter: " filter
	
	printf "Files to be renamed: \n"
	printf "$(ls *$filter*)\n"

	read -p "Is this correct? [Y]es [N]o [E]xit " yesno
	case $yesno in
		[Yy]* )
			printf "Ok\n"
			break
		;;
		[Nn]* )
			printf "Retry\n"
			continue 
		;;
		[Ee]* )
			printf "Exiting\n"
			exit
		;;
		* ) printf "Answer either yes, no, or exit\n";;
	esac
done

season=0
while true; do
	read -p "Are these specials? [y/N] " specials
        case $specials in
                [Yy]* )
			printf "Renaming episodes as specials (S00)\n"
			season="00"
                        break
                ;;
                [Nn]* )
			read -p "What is the Season Number? (SXX) " season
			if [ "$season" -lt "10" ]
			then
				season="0$season"
			fi
			break
                ;;
                * ) printf "Answer either yes or no\n";;
        esac
done

while true; do
	# Different naming schema for specials as episode number not easily determined
	if [ "$season" = "00" ]
	then

		read -p "Episode Number for these files: " episode
        	if [ "$episode" -lt "10" ]
        	then
        	        episode="0$episode"
        	fi
	        if [ "$episode" -lt "100" ]
       		then
       	        	episode="0$episode"
       		fi
		printf "Episode is now $episode\n"

		printf "Files will be renamed as follows\n\n"
		rename -n 's/\d* - (.*)_More-Sided_Dive_4SDE(\d*) - (.*)/4-Sided Dive - S'"$season"'E'"$episode"' - $1 - 4SDE$2 - $3/' *$filter*
	else
		printf "Files will be renamed as follows\n\n"
		rename -n 's/\d* - (.*)_4-Sided_Dive_Episode_(\d*)_-_(.*) - (\(.*)/4-Sided Dive - S'"$season"'E$2 - $1 - $3 - $4/' *$filter*
	fi
	printf "\n"
	read -p "Is this correct? [Y]es [N]o " yesno
	case $yesno in
		[Yy]* )
			printf "Renaming...\n"
			
			if [ "$season" = "00" ]
        		then
				rename 's/\d* - (.*)_More-Sided_Dive_4SDE(\d*) - (.*)/4-Sided Dive - S'"$season"'E'"$episode"' - $1 - 4SDE$2 - $3/' *$filter*
			else
				rename 's/\d* - (.*)_4-Sided_Dive_Episode_(\d*)_-_(.*) - (\(.*)/4-Sided Dive - S'"$season"'E$2 - $1 - $3 - $4/' *$filter*
			fi
			break
		;;
		[Nn]* )
			printf "Exiting\n"
			exit
		;;
		* ) printf "Answer either yes or no\n";;
	esac
done

echo "Done"
