#!/bin/bash

#printf %b '\e[44m' '\e[8]' '\e[H\e[J'

red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;34m'
mag=$'\e[1;35m'
cyn=$'\e[1;36m'
end=$'\e[1;39m'
declare -i selection
selection=0

#this variable is used to keep the entire page from being cleared
#when rendering the main menu
showMainMenuHeader=1

#if the runApp variable is one, the app will keep going
runApp=1

# Database version credential
qaHost=192.168.0.39
qaUserID=QAClient
qaUserPW=timeless
qaDB=versiondb

# disables the display of keyboard input
stty -echo

function create_client_branch {
    clear

    #Checkout Develop
    git checkout master

     #Get All clients
    /Applications/MAMP/Library/bin/mysql -h$qaHost -u$qaUserID -p$qaUserPW -D$qaDB  -BNr -e "SELECT clientBranchName,
                                                                                          clientOverrideFolder,
                                                                                          (SELECT vm.versionMG
                                                                                            FROM client_version cv, version_master vm
                                                                                            WHERE vm.versionID = cv.versionMasterID AND cv.clientID = cm.clientID
                                                                                            ORDER BY cv.lastUpdate DESC
                                                                                            LIMIT 1) as versionGit,

                                                                                            (SELECT vm.versionNumber
                                                                                            FROM client_version cv, version_master vm
                                                                                            WHERE vm.versionID = cv.versionMasterID AND cv.clientID = cm.clientID
                                                                                            ORDER BY cv.lastUpdate DESC
                                                                                            LIMIT 1) as versionNo

                                                                                    FROM client_master cm
                                                                                    WHERE isActive = 1 AND
                                                                                          clientVersioning = 1 AND
                                                                                          clientRepository = 'womenandinfants' AND
                                                                                          clientUploadFolder NOT LIKE 'DEMO%' AND
                                                                                          clientUploadFolder NOT LIKE 'PRE-RELEASE%' AND
                                                                                          clientUploadFolder NOT IN('ANNEARUNDEL','CINCINNATI','DANATALEMARAT','InnovaLoudoun','ROCKYMOUNTAINHOSPITALFORCHILDREN')
                                                                                    ORDER BY clientBranchName;" |
    while IFS=$'\t' read clientName clientOverrideFolder gitReference versionNo;
    do

      echo "Creating Branch For Client : $clientName";
      git branch "client/${clientName}"  $gitReference

      echo "Checkout Client : $clientName";
      git checkout "client/${clientName}"

      echo "Copy client override folder to the newly created client branch";
      cp -R ../womenandinfants/phpinc/overrides/Client\ Overrides/$clientOverrideFolder/ ./phpinc/overrides/

      echo $versionNo > ./phpinc/overrides/versionNo.txt

      #Append Dot Env
      gsed "36 i \$dotenv->load();" -i ./phpinc/includes.php;
      gsed "36 i \$dotenv = Dotenv\\\Dotenv::createMutable(__DIR__ . '/../');" -i ./phpinc/includes.php;
      gsed "36 i/* includes .env file variables */" -i ./phpinc/includes.php;
      #Append Appssettings
      gsed "23c\AppConfig::set(\'db_username\', getenv(\'DB_USERNAME\'));"  -i ./phpinc/app_settings.php;
      gsed "24c\AppConfig::set(\'db_password\', getenv(\'DB_PASSWORD\'));"  -i ./phpinc/app_settings.php;
      gsed "25c\AppConfig::set(\'db_host\', getenv(\'DB_HOST\'));"  -i ./phpinc/app_settings.php;
      gsed "26c\AppConfig::set(\'db_dbname\', getenv(\'DB_NAME\'));"  -i ./phpinc/app_settings.php;
      gsed "27 iAppConfig::set('db_dwarehouse', getenv('DB_DWAREHOUSE_NAME'));" -i ./phpinc/app_settings.php;
      #sample env variables
      echo '' > env_example;
      gsed "1 iDB_HOST=localhost" -i env_example;
      gsed "2 iDB_USERNAME=root" -i env_example;
      gsed "3 iDB_PASSWORD=password" -i env_example;
      gsed "4 iDB_NAME=client-db" -i env_example;
      gsed "5 iDB_DWAREHOUSE_NAME=dw-client-db" -i env_example;
      gsed "6 iSMS_CDYNE_KEY=6eff8e39-0fa4-4ba2-981a-918d8f6b239d" -i env_example;
      #composer json
      cp -R /Users/denocillas/dumps/composer.json ./;
      #git ignore
      gsed '$ a\.env' -i .gitignore;

      echo "Stage changes";
      git add -A

      echo "Unstage .idea changes";
      git reset .idea
      git clean -f

      echo "Unstage run_migration changes";
      git reset -- run_migration.sh
      git commit -am "$versionNo Client O v e r r i d e s"
      git push origin "client/${clientName}"
      git checkout master

      ########git branch -r | grep -Eo 'client/.*' | xargs -I {} git push origin :{}
      ########git branch -D $(git branch --list 'client/*')
    done

}

# Get the latest release from women and infants
function get_release {
    clear
    stty echo

    local versionName='v6.4.3.20'
    local branchName="${versionName}-For-Merging"

    echo '****** Get Release from womenandinfants repository *****'
    read -p "Enter release commit from womenandinfants repository: "  releaseCommitFromWomenAndInfants

    #Create branch from tag and checkout
    git checkout -b $branchName $versionName

    #Cherry pick release commit from womenandinfants repository, i assume that womenandinfants remote repository is already present
#    git cherry-pick -m 1 de9d6cc86618dfa1fa6210663ddbe29d6ff59163
    git cherry-pick -m 1 $releaseCommitFromWomenAndInfants

    #Remove Release folder if any
    git rm -r support/documents/releases

    #Change the comments
    git commit --amend -m $versionName

    # send your new tree (repo state) to github
    #git push origin $branchName

    #get current commit and Update version_master
#    git rev-parse --verify HEAD |
#    while IFS=$'\t' read commitNo;
#    do
#     echo "UPDATE version_master SET versionMG = '${commitNo}' WHERE versionNumber = '${versionName}'" | /Applications/MAMP/Library/bin/mysql -h$qaHost -u$qaUserID -p$qaUserPW -D$qaDB
#    done
}

# Upgrade Client
function upgrade_client {
    clear
    stty echo
    echo '****** Upgrade Client *****'
    read -p "Enter Client Branch eg. wandi_clientName or [cancel to Cancel this transaction]: "  clientBranch
    if [ $clientBranch == 'cancel' ]
    then
        echo 'Operation aborted..'
        return
    fi

    read -p "Enter Version Release TAG or [cancel to Cancel this transaction]: "  versionTagName
    if [ $versionTagName == 'cancel' ]
    then
        echo 'Operation aborted..'
        return
    fi

    # 'Checkout Client'
    git checkout $clientBranch

    echo $versionTagName > ./phpinc/overrides/Client\ Overrides/versionNo.txt

    # 'Merge Tag'
    git merge -m 'Merged '$versionTagName' into '$clientBranch $versionTagName

    # "Stage changes";
    git add -A

    # "Unstage .idea changes";
    git reset .idea
    git clean -f

    # "Unstage run_migration changes";
    git reset -- run_migration.sh

    #Change the comments
    git commit -am 'Upgraded to version '$versionTagName

#    # send your new tree (repo state) to github
#    git push origin $clientBranch

}

function remove_local_tags {
    clear
    git tag -d $(git tag -l)
}

menuOptions=(
"Create/Update Client Branch"
"Get Release from womenandinfants repository"
"Upgrade Client to Current Release"
"--------------------"
"Exit Menu"
)

function menu {
#        printf %b cyn '\e[8]' '\e[H\e[J'
        echo -e "${cyn}"
        echo -e "          Women and Infants Repository Migration"
        echo -e "${end}"
        echo -e "\t${yel}   Select a menu option and hit return:${end}\n"

}

# Renders a text based list of options that can be selected by the
# user using up, down and enter keys and returns the chosen option.
#
#   Arguments   : list of options, maximum of 256
#                 "opt1" "opt2" ...
#   Return value: selected index (0 for opt1, 1 for opt2 ...)
function select_option {

    # little helpers for terminal print control and key input
    ESC=$( printf "\033")
    cursor_blink_on()  { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
    print_option()     { printf "   $1 "; }
    print_selected()   { printf "  $ESC[7m $1 $ESC[27m"; }
    get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    key_input()        { read -s -n3 key 2>/dev/null >&2
                         if [[ $key = $ESC[A ]]; then echo up;    fi
                         if [[ $key = $ESC[B ]]; then echo down;  fi
                         if [[ $key = ""     ]]; then echo enter; fi; }

    # initially print empty new lines (scroll down if at bottom of screen)
    for opt; do printf "\n"; done

    # determine current screen position for overwriting the options
    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - $#))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local selected=0
    while true; do
        # print options by overwriting the last lines
        local idx=0
        for opt; do
            cursor_to $(($startrow + $idx))
            if [ $idx -eq $selected ]; then
                print_selected "$opt"
            else
                print_option "$opt"
            fi
            ((idx++))
        done

        # user key control
        case `key_input` in
            enter) break;;
            up)    ((selected--));
                   if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
            down)  ((selected++));
                   if [ $selected -ge $# ]; then selected=0; fi;;
        esac
    done

    # cursor position back to normal
    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    return $selected
}

# takes an array and loads the menu
function select_opt {
    select_option "$@" 1>&2
    local result=$?
    echo $result
    return $result
}

while [ "$runApp" = "1" ]
do
  clear
	menu
	echo -e "${cyn}"
	case `select_opt "${menuOptions[@]}"` in
	    0)
        create_client_branch;;
      1)
        get_release;;
      2)
        upgrade_client;;
      3)
        ;;
      4)
        break;;
	esac
    echo -e "\n\n"
    echo -e "${cyn}"
    read -r -s -p $'Press enter to continue...'
done
reset


# https://unix.stackexchange.com/questions/146570/arrow-key-enter-menu
# this is awesome

#DB_HOST=127.0.0.1
#DB_USERNAME=womenandinfants
#DB_PASSWORD=milk22
#DB_NAME=wandi_chkd-org
#DB_DWAREHOUSE_NAME=dw_chkd-org
#SMS_CDYNE_KEY=6eff8e39-0fa4-4ba2-981a-918d8f6b239d

