#!/bin/bash 
echo
echo
echo
#
#	Script for DKIM signing
#		Requires 10.8 (Lion) or higher
#
#	Written by Jeff Davis & Jeff Johnson
#		mactech -at- mac007.com
#
PATH=/Applications/Server.app/Contents/ServerRoot/usr/bin:$PATH
#
# Terminal Check
#
if [ "$TERM" != "dumb" ]; then
case $TERM in
	# for the most important terminal types we directly know the sequences
	xterm|xterm*|vt220|vt220*)
		 bold=`awk 'BEGIN { printf("%c%c%c%c", 27, 91, 49, 109); }' </dev/null 2>/dev/null`
		norm=`awk 'BEGIN { printf("%c%c%c", 27, 91, 109); }' </dev/null 2>/dev/null`
		;;
	vt100|vt100*|cygwin)
		bold=`awk 'BEGIN { printf("%c%c%c%c%c%c", 27, 91, 49, 109, 0, 0); }' </dev/null 2>/dev/null`
		norm=`awk 'BEGIN { printf("%c%c%c%c%c", 27, 91, 109, 0, 0); }' </dev/null 2>/dev/null`
		;;
esac
fi

#
# Show splash screen
#
color_1=`echo -en "\033[37;40m"` #Grey background
color_2=`echo -en "\033[30;46m"` #Cyan background
color_3=`echo -en "\033[0;34m"` #Blue text
color_4=`echo -en "\033[0;32m"` #Green text
color_5=`echo -en "\033[0;35m"` #Purple text
color_6=`echo -en "\033[0;31m"` #Red text
color_7=`echo -en "\033[0;36m"` #Cyan text
color_norm=`tput sgr0` # Reset to normal colors

PROJECT_NAME=$(basename "$0")
PROJECT_VERSION=1.0.0


if [ "$TERM" != "dumb" ]; then
clear
cat <<X
${color_1} +--------------------------------------------------------------------+ 
 |                                                                    | 
 |                             ${color_2} ${PROJECT_NAME} ${color_1}                             | 
 |                                                                    | 
 |                           Version ${PROJECT_VERSION}                            | 
 |                                                                    | 
 |                         Copyright (c) 2014                         | 
 |                   Mac007.com < mactech@mac007.com >                | 
 |                                                                    | 
 +--------------------------------------------------------------------+ 

X
tput sgr0
fi

#
# Check for root user
#
if [ `whoami` != "root" ]
then
  echo
  echo "$(basename "$0") must be run as ${bold}root${norm} user."
  echo
  exit 0;
fi


#
#	OS Version check
#
OSVersion=`sw_vers -productVersion | cut -d. -f1 -f2`

case $OSVersion in
    10.10)
        
        ;;
	10.9)
		
		server_root_path="/Applications/Server.app/Contents/ServerRoot"
		;;	
	10.8)
		
		server_root_path="/Applications/Server.app/Contents/ServerRoot"
		;;
	*)
		echo "This script requires 10.8 ( Mountain Lion) or higher"
		exit 1
		;;
esac

#
# Server Version Check
#
ServVersion=`/usr/sbin/serverinfo --shortversion | cut -d. -f1 -f2`

case $ServVersion in
    4)
      echo $ServVersion
      ;;  
  3.2)
      echo $ServVersion
      ;;
    *)
      echo "Does not meet requirements"
      exit
      ;;
esac

#####################################
#			Functions               #
#####################################
#
# Print usage
#

usage() {
		echo
        echo " ${color_2}DKIM Generator for OS X Server 10.8 and higher${color_norm}"
        echo ""
        echo " usage: ${color_7}$PROJECT_NAME${color_norm} [ ${color_4}-d ${color_1}days${color_norm} ] "
        echo
        echo " 	${color_4}-t${color_norm} to test previously generated keys"
        echo " 	${color_4}-a${color_norm} to do post testing config"
        echo " 	${color_4}-h${color_norm} to display this help message"
        echo ""
        exit 0
}

function empty
{
    local var="$1"

    # Return true if:
    # 1.    var is a null string ("" as empty string)
    # 2.    a non set variable is passed
    # 3.    a declared variable or array but without a value is passed
    # 4.    an empty array is passed
    if test -z "$var"
    then
        [[ $( echo "1" ) ]]
        return

    # Return true if var is zero (0 as an integer or "0" as a string)
    elif [ "$var" == 0 2> /dev/null ]
    then
        [[ $( echo "1" ) ]]
        return

    # Return true if var is 0.0 (0 as a float)
    elif [ "$var" == 0.0 2> /dev/null ]
    then
        [[ $( echo "1" ) ]]
        return
    fi

    [[ $( echo "" ) ]]
}

checkStatus() {

            status=`serveradmin status mail | cut -f2 -d'"'`
            if [ "$status" != "RUNNING" ]; then
                echo "Mail is not currently running. Please configure your mail service before running this tool."  
                exit
            fi          
}

reLoad() {
            postfix reload
            sudo -u _amavisd -H amavisd -c /Library/Server/Mail/Config/amavisd/amavisd.conf reload
}

bakupConfigs() {
            echo "Backing up current config files..."
            cp /Library/Server/Mail/Config/spamassassin/spamassassin/local.cf /Library/Server/Mail/Config/spamassassin/local.cf.bak
            cp /Library/Server/Mail/Config/amavisd/amavisd.conf /Library/Server/Mail/Config/amavisd/amavisd.conf.bak
            cp /Library/Server/Mail/Config/postfix/master.cf /Library/Server/Mail/Config/postfix/master.cf.bak
            cp /Library/Server/Mail/Config/postfix/main.cf /Library/Server/Mail/Config/postfix/main.cf.bak

}

tagLvl() {

            sed -i -e 's/$sa_tag_level_deflt  = 2.0;/$sa_tag_level_deflt  = -999.0;/g' /Library/Server/Mail/Config/amavisd/amavisd.conf

            ### checking if this has already been updated
            if grep -Fxq "#### Enable DKIM checking" /Library/Server/Mail/Config/spamassassin/local.cf
                then
                    echo "DKIM policy already set"
                else
                    echo "#### Enable DKIM checking" >> /Library/Server/Mail/Config/spamassassin/local.cf
                    echo "score DKIM_POLICY_SIGNALL 0.001" >> /Library/Server/Mail/Config/spamassassin/local.cf
                    echo "score DKIM_POLICY_SIGNSOME 0.001" >> /Library/Server/Mail/Config/spamassassin/local.cf
                    echo "score DKIM_POLICY_TESTING 0.001" >> /Library/Server/Mail/Config/spamassassin/local.cf
                    echo "score DKIM_SIGNED 0.001" >> /Library/Server/Mail/Config/spamassassin/local.cf
                    echo "score DKIM_VERIFIED -0.001" >> /Library/Server/Mail/Config/spamassassin/local.cf
            fi
            reLoad()
}

createKey() {

            echo "Enter your domain (i.e. example.com) : "; read domain;
            IFS=. read myDomain tLd <<< $domain;

            mkdir -p /var/db/dkim
            chown _amavisd /var/db/dkim
            sudo -u _amavisd -H amavisd genrsa /var/db/dkim/$myDomain.$tLd.default.pem
            sudo chown root:_amavisd /var/db/dkim/$myDomain.$tLd.default.pem
            sudo chmod 640 /var/db/dkim/$myDomain.$tLd.default.pem

}

updateAmavis() {

            sed -i -e 's/$enable_dkim_verification = 0;/$enable_dkim_verification = 1;/g' /Library/Server/Mail/Config/amavisd/amavisd.conf
            sed -i -e 's/$enable_dkim_signing = 0;/$enable_dkim_signing = 1;/g' /Library/Server/Mail/Config/amavisd/amavisd.conf

            #awk -v k=$amaKey '/enable_dkim_signing/ { print; print k; next }1' /Library/Server/Mail/Config/amavisd/amavisd.conf
            echo $amaKey >> /Library/Server/Mail/Config/amavisd/amavisd.conf
            reLoad()

}

showKeys() {
            ### We are going to display the default output then the actual DNS as it should be entered
            echo "Please make these text(TXT) entries into your DNS records:"
            echo;echo
            echo "_domain.$myDomain.$tld   TXT   \"o=~\" "
            echo
            echo `sudo -u _amavisd -H amavisd -c /Library/Server/Mail/Config/amavisd/amavisd.conf showkeys | awk '{if(NR>1)print}'`
            echo;echo
}

testKeys() {

            echo "Testing DNS records...";echo
            testKey=`sudo -u _amavisd -H amavisd -c /Library/Server/Mail/Config/amavisd/amavisd.conf testkeys | cut -f2 -d'=> '`
            if [ "$testKeys" != "pass" ]; then
                echo "The DNS entry does not match or has not updated yet."
            else
                echo "Success!! DNS is correct and keys match."
            fi
}

advConfig() {

            touch /Library/Server/Mail/Config/postfix/tag_for_signing
            echo "/^/  FILTER smtp-amavis:[127.0.0.1]:10026" > /Library/Server/Mail/Config/postfix/tag_for_signing
            touch /Library/Server/Mail/Config/postfix/tag_for_scanning
            echo "/^/  FILTER smtp-amavis:[127.0.0.1]:10024" > /Library/Server/Mail/Config/postfix/tag_for_scanning

          
            echo $block2 >> /Library/Server/Mail/Config/postfix/main.cf
            echo -e $block1 >> /Library/Server/Mail/Config/postfix/master.cf

            awk '/originating => 1/ {print; print "bypass_spam_checks_maps => [1],"; next }1' /Library/Server/Mail/Config/amavisd/amavisd.conf

            reLoad()
}



#####################################
#	Declarations & Default Values   #
#####################################

  block1="127.0.0.1:10027 inet n  -       y       -       -       smtpd\n
   -o content_filter=\n
   -o smtpd_tls_security_level=none\n
   -o smtpd_delay_reject=no\n
   -o smtpd_client_restrictions=permit_mynetworks,reject\n
   -o smtpd_helo_restrictions=\n
   -o smtpd_sender_restrictions=\n
   -o smtpd_recipient_restrictions=permit_mynetworks,reject\n
   -o smtpd_data_restrictions=reject_unauth_pipelining\n
   -o smtpd_end_of_data_restrictions=\n
   -o smtpd_restriction_classes=\n
   -o mynetworks=127.0.0.0/8\n
   -o smtpd_error_sleep_time=0\n
   -o smtpd_soft_error_limit=1001\n
   -o smtpd_hard_error_limit=1000\n
   -o smtpd_client_connection_count_limit=0\n
   -o smtpd_client_connection_rate_limit=0\n
   -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks,no_milters\n
   -o local_header_rewrite_clients=\n
   -o smtpd_milters=\n
   -o local_recipient_maps=\n
   -o relay_recipient_maps=\n"

   block2="smtpd_sender_restrictions = check_sender_access regexp:/Library/Server/Mail/Config/postfix/tag_for_signing permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_sender, check_sender_access regexp:/Library/Server/Mail/Config/postfix/tag_for_scanning permit"

    amaKey="dkim_key('$mydomain.$tld', 'default', '/var/db/dkim/$mydomain.$tld.default.pem'); @dkim_signature_options_bysender_maps = ({ '.' => { ttl => 21*24*3600, c => 'relaxed/simple' } } );"


#######################################
# Get Options and execute             #
#######################################

while getopts ta options
do
        case $options in

                t) testKeys()
                   ;;
                a) advConfig()
                   ;;
                h) usage;;
                *) checkStatus()
                   bakupConfigs()
                   tagLvl()
                   createKey()
                   updateAmavis()
                   showKeys()
                   echo;echo
                   echo "After DNS has propigated rerun run this tool using option -t and then option -a"
                   ;;


        esac
done

exit
