#!/bin/bash
# -*- mode:shell-script; coding:utf-8; -*-
#
# provisionQuotaAlert.sh
#
# A bash script for provisioning an API Product and a developer app on
# an organization in the Apigee Edge Gateway.
#
# Last saved: <2016-November-09 11:44:09>
#

verbosity=2
have_deployments=0
waittime=2
netrccreds=0
resetonly=0
wantdeploy=1
apiname=quota-alert
cacheName=cache1
quotalimit=80
invokePath=quota-alert/r1
checkPath=quota-alert/check
envname=test
thresholdFile="sample-config.json"
defaultmgmtserver="https://api.enterprise.apigee.com"
credentials=""
TAB=$'\t'

function usage() {
  local CMD=`basename $0`
  echo "$CMD: "
  echo "  Imports an API Proxy for the quota-alert sample. Creates an API Product for the proxy,"
  echo "  and creates a developer app that is enabled for that product. Emits the client id and secret."
  echo "  Also creates a named cache, or verifies that it exists.  And finally, invokes the quota-alert"
  echo "  proxy repeatedly to demonstrate the alert."
  echo "  Uses the following: curl, node."
  
  echo "usage: "
  echo "  $CMD [options] "
  echo "options: "
  echo "  -m url    the base url for the mgmt server."
  echo "  -o org    the org to use."
  echo "  -e env    the environment to deploy to."
  echo "  -u creds  http basic authn credentials for the API calls."
  echo "  -t file   quota alert configuration file with thresholds."
  echo "  -n        tells curl to use .netrc to retrieve credentials"
  echo "  -d        do not bother to deploy the bundle"
  echo "  -r        reset only; removes all ${apiname}-related configuration"
  echo "  -q        quiet; decrease verbosity by 1"
  echo "  -v        verbose; increase verbosity by 1"
  echo
  echo "Current parameter values:"
  echo "  mgmt api url: $defaultmgmtserver"
  echo "     verbosity: $verbosity"
  echo "   environment: $envname"
  echo
  exit 1
}

## function MYCURL
## Print the curl command, omitting sensitive parameters, then run it.
## There are side effects:
## 1. puts curl output into file named ${CURL_OUT}. If the CURL_OUT
##    env var is not set prior to calling this function, it is created
##    and the name of a tmp file in /tmp is placed there.
## 2. puts curl http_status into variable CURL_RC
function MYCURL() {
  [[ -z "${CURL_OUT}" ]] && CURL_OUT=`mktemp /tmp/apigee-edge-provision-${apiname}.curl.out.XXXXXX`
  [[ -f "${CURL_OUT}" ]] && rm ${CURL_OUT}
  [[ $verbosity -gt 0 ]] && echo "curl $@"

  # run the curl command
  CURL_RC=`curl $credentials -s -w "%{http_code}" -o "${CURL_OUT}" "$@"`
  [[ $verbosity -gt 0 ]] && echo "==> ${CURL_RC}"
}

function CleanUp() {
  [ -f ${CURL_OUT} ] && rm -rf ${CURL_OUT}
}

function echoerror() { echo "$@" 1>&2; }


# echo 1 if global command line program installed, else 0
#
# usage example: "$(program_is_installed node)"
function program_is_installed {
  # set to 1 initially
  local return_=1
  # set to 0 if not found
  type $1 >/dev/null 2>&1 || { local return_=0; }
  # return value
  echo "$return_"
}

function choose_mgmtserver() {
  local name
  echo
  read -p "  Which mgmt server (${defaultmgmtserver}) :: " name
  name="${name:-$defaultmgmtserver}"
  mgmtserver=$name
  echo "  mgmt server = ${mgmtserver}"
}

function choose_credentials() {
  local username password

  read -p "username for Edge org ${orgname} at ${mgmtserver} ? (blank to use .netrc): " username
  echo
  if [[ "$username" = "" ]] ; then  
    credentials="-n"
  else
    echo -n "Org Admin Password: "
    read -s password
    echo
    credentials="-u ${username}:${password}"
  fi
}

function maybe_ask_password() {
  local password
  if [[ ${credentials} =~ ":" ]]; then
    credentials="-u ${credentials}"
  else
    echo -n "password for ${credentials}?: "
    read -s password
    echo
    credentials="-u ${credentials}:${password}"
  fi
}

function check_org() {
  [[ $verbosity -gt 0 ]] && echo "checking org ${orgname}..."
  MYCURL -X GET  ${mgmtserver}/v1/o/${orgname}
  if [[ ${CURL_RC} -eq 200 ]]; then
    check_org=0
  else
    check_org=1
  fi
}

function check_env() {
  [[ $verbosity -gt 0 ]] && echo "checking environment ${envname}..."
  MYCURL -X GET  ${mgmtserver}/v1/o/${orgname}/e/${envname}
  if [[ ${CURL_RC} -eq 200 ]]; then
    check_env=0
  else
    check_env=1
  fi
}

function choose_org() {
  local all_done
  all_done=0
  while [[ $all_done -ne 1 ]]; do
      echo
      read -p "  Which org? " orgname
      check_org 
      if [[ ${check_org} -ne 0 ]]; then
        echo cannot read that org with the given creds.
        echo
        all_done=0
      else
        all_done=1
      fi
  done
  echo
  echo "  org = ${orgname}"
}


function choose_env() {
  local all_done
  all_done=0
  while [[ $all_done -ne 1 ]]; do
      echo
      read -p "  Which env? " envname
      check_env
      if [[ ${check_env} -ne 0 ]]; then
        echo cannot read that env with the given creds.
        echo
        all_done=0
      else
        all_done=1
      fi
  done
  echo
  echo "  env = ${envname}"
}


function random_string() {
  local rand_string
  rand_string=$(cat /dev/urandom |  LC_CTYPE=C  tr -cd '[:alnum:]' | head -c 10)
  echo ${rand_string}
}


function parse_deployments_output() {
  ## extract the environment names and revision numbers in the list of deployments.
  output_parsed=`cat ${CURL_OUT} | grep -A 6 -B 2 "revision"`

  if [ $? -eq 0 ]; then

    deployed_envs=`echo "${output_parsed}" | grep -B 2 revision | grep name | sed -E 's/[\",]//g'| sed -E 's/name ://g'`

    deployed_revs=`echo "${output_parsed}" | grep -A 5 revision | grep name | sed -E 's/[\",]//g'| sed -E 's/name ://g'`

    IFS=' '; declare -a rev_array=(${deployed_revs})
    IFS=' '; declare -a env_array=(${deployed_envs})

    m=${#rev_array[@]}
    if [ $verbosity -gt 1 ]; then
      echo "found ${m} deployed revisions"
    fi

    deployments=()
    let m-=1
    while [ $m -ge 0 ]; do
      rev=${rev_array[m]}
      env=${env_array[m]}
      # trim spaces
      rev="$(echo "${rev}" | tr -d '[[:space:]]')"
      env="$(echo "${env}" | tr -d '[[:space:]]')"
      echo "${env}=${rev}"
      deployments+=("${env}=${rev}")
      let m-=1
    done
    have_deployments=1
  fi
}


## function clear_env_state
## Removes any developer app with the prefix of ${apiname}, and any
## developer or api product with that prefix, and any API with that
## name.
function clear_env_state() {
  local prodarray devarray apparray revisionarray prod env rev deployment dev app i j

  [[ $verbosity -gt 0 ]] && echo "check for developers like ${apiname}..."
  MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/developers
  if [[ ${CURL_RC} -ne 200 ]]; then
    echo 
    echoerror "Cannot retrieve developers from that org..."
    CleanUp
    exit 1
  fi
  devarray=(`cat ${CURL_OUT} | grep "\[" | sed -E 's/[]",[]//g'`)
  for i in "${!devarray[@]}"; do
    dev=${devarray[i]}
    if [[ "$dev" =~ ^${apiname}.+$ ]] ; then
      [[ $verbosity -gt 0 ]] && echo "found a matching developer..."
      [[ $verbosity -gt 0 ]] && echo "list the apps for that developer..."
      MYCURL -X GET "${mgmtserver}/v1/o/${orgname}/developers/${dev}/apps"
      apparray=(`cat ${CURL_OUT} | grep "\[" | sed -E 's/[]",[]//g'`)
      for j in "${!apparray[@]}" ; do
        app=${apparray[j]}
        echo "delete the app ${app}..."
        MYCURL -X DELETE "${mgmtserver}/v1/o/${orgname}/developers/${dev}/apps/${app}"
        ## ignore errors
      done       

      echo "delete the developer $dev..."
      MYCURL -X DELETE "${mgmtserver}/v1/o/${orgname}/developers/${dev}"
      if [[ ${CURL_RC} -ne 200 ]]; then
        echo 
        echoerror "could not delete that developer (${dev})"
        echo
        CleanUp
        exit 1
      fi
    fi
  done

  [[ $verbosity -gt 0 ]] && echo "check for api products like ${apiname}..."
  MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/apiproducts
  if [[ ${CURL_RC} -ne 200 ]]; then
    echo 
    echoerror "Cannot retrieve apiproducts from that org..."
    CleanUp
    exit 1
  fi

  prodarray=(`cat ${CURL_OUT} | grep "\[" | sed -E 's/[]",[]//g'`)
  for i in "${!prodarray[@]}"; do
    prod=${prodarray[i]}

    if [[ "$prod" =~ ^${apiname}.+$ ]] ; then
       [[ $verbosity -gt 0 ]] && echo "found a matching product...deleting it."
       MYCURL -X DELETE ${mgmtserver}/v1/o/${orgname}/apiproducts/${prod}
       if [[ ${CURL_RC} -ne 200 ]]; then
         echo 
         echoerror "could not delete that product (${prod})"
         echo 
         CleanUp
         exit 1
       fi
    fi
  done

  [[ $verbosity -gt 0 ]] && echo "check for the ${apiname} apiproxy..."
  MYCURL -X GET "${mgmtserver}/v1/o/${orgname}/apis/${apiname}/deployments"
  if [[ ${CURL_RC} -eq 200 ]]; then
    [[ $verbosity -gt 0 ]] && echo "found, querying it..."
    parse_deployments_output

    # undeploy from any environments in which the proxy is deployed
    for deployment in ${deployments[@]}; do
      env=`expr "${deployment}" : '\([^=]*\)'`
      # trim spaces
      env="$(echo "${env}" | tr -d '[[:space:]]')"
      rev=`expr "$deployment" : '[^=]*=\([^=]*\)'`
      MYCURL -X POST "${mgmtserver}/v1/o/${orgname}/apis/${apiname}/revisions/${rev}/deployments?action=undeploy&env=${env}"
      ## ignore errors
    done

    # delete all revisions
    MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/apis/${apiname}/revisions
    revisionarray=(`cat ${CURL_OUT} | grep "\[" | sed -E 's/[]",[]//g'`)
    for i in "${!revisionarray[@]}"; do
      rev=${revisionarray[i]}
      [[ $verbosity -gt 0 ]] && echo "delete revision $rev"
      MYCURL -X DELETE "${mgmtserver}/v1/o/${orgname}/apis/${apiname}/revisions/${rev}"
    done

    if [ $resetonly -eq 1 ] ; then

        [[ $verbosity -gt 0 ]] && echo "delete the api"
        MYCURL -X DELETE ${mgmtserver}/v1/o/${orgname}/apis/${apiname}
        if [[ ${CURL_RC} -ne 200 ]]; then
          echo "failed to delete that API. This may or may not be a problem."
        fi
    fi 
  fi
}


function maybe_create_cache() {
  local wantedcache="$1"
  local existingcache c exists

  [[ $verbosity -gt 0 ]] && echo "check for existing caches..."
  MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/e/${envname}/caches
  if [[ ${CURL_RC} -ne 200 ]]; then
    echo 
    echoerror "Cannot retrieve caches for that environment..."
    echoerror
    CleanUp
    exit 1
  fi

  c=`cat ${CURL_OUT} | grep "\[" | sed -E 's/[]",[]//g'`
  IFS=' '; declare -a cachearray=($c)

  # trim spaces
  wantedcache="$(echo "${wantedcache}" | tr -d '[[:space:]]')"
  exists=0
  for i in "${!cachearray[@]}";  do
    existingcache="${cachearray[i]}"
    [[ $verbosity -gt 1 ]] && echo "found cache: ${existingcache}"
    if [[ "$wantedcache" = "$existingcache" ]] ; then
      exists=1
    fi
  done

  if [[ $exists -eq 0 ]]; then 
    echo "creating the cache \"$wantedcache\"..."
    MYCURL -X POST \
      -H "Content-type:application/json" \
      "${mgmtserver}/v1/o/${orgname}/e/${envname}/caches?name=$wantedcache" \
      -d '{
        "compression": {
          "minimumSizeInKB": 1024
        },
        "distributed" : true,
        "description": "cache supporting nonce mgmt in the HttpSig proxy",
        "diskSizeInMB": 0,
        "expirySettings": {
          "timeoutInSec" : {
            "value" : 86400
          },
          "valuesNull": false
        },
        "inMemorySizeInKB": 8000,
        "maxElementsInMemory": 3000000,
        "maxElementsOnDisk": 1000,
        "overflowToDisk": false,
        "persistent": false,
        "skipCacheIfElementSizeInKBExceeds": "12"
      }'
    if [[ ${CURL_RC} -eq 409 ]]; then
      ## should have caught this above, but just in case
      echo
      echo "That cache already exists."
    elif [[ ${CURL_RC} -ne 201 ]]; then
      echo
      echoerror "failed creating the cache."
      cat ${CURL_OUT}
      echo
      CleanUp
      echo
      exit 1
    fi
  else
    echo "A-OK: the needed cache, $wantedcache, exists..."
  fi
}


function deploy_new_bundle() {
    local SCRIPTPATH ZIPFILE TIMESTAMP origpwd
    pushd `dirname $0` > /dev/null
    SCRIPTPATH=`pwd`
    popd > /dev/null

  if [[ ! -d "${SCRIPTPATH}/../apiproxy" && ! -d "${SCRIPTPATH}/../apiproxy/proxies" ]] ; then 
     echo cannot find the apiproxy directory.
     echo this command needs expects to be run from a tools directory, sibling to apiproxy.
     echo
     exit 1
  fi
  
  TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
  ZIPFILE=/tmp/${apiname}-${TIMESTAMP}.zip
  if [[ -f "$ZIPFILE" ]]; then
    [[ $verbosity -gt 0 ]] && echo "removing the existing zip ${ZIPFILE}..."
    rm -f "$ZIPFILE"
  fi

  origpwd=`pwd`

  echo "  produce the bundle..."
  cd "$SCRIPTPATH"
  cd ..

  if [[ -f "apiproxy/resources/node/package.json" ]]; then
      [[ $verbosity -gt 0 ]] && echo "zipping node_modules..."
      cd "apiproxy/resources/node"
      if [[ -f package.json ]]; then
        [[ -f node_modules.zip ]] && rm -rf node_modules.zip
        npmout=`npm install 2>&1`
        [[ -f npm-debug.log ]] && rm npm-debug.log
        zipout=`zip node_modules.zip -r node_modules/  -x "*/Icon*" 2>&1`
      fi
      [[ -d node_modules ]] && rm -rf node_modules
      cd ../../../
  fi
  
  zip -r "$ZIPFILE" apiproxy  -x "*/*.*~" -x "*/Icon*" -x "*/#*.*#" -x "*/node_modules/*"
  echo

  cd "$origpwd"
  
  sleep 2
  [[ $verbosity -gt 0 ]] && echo "import the bundle..."
  sleep 2
  MYCURL -X POST -H "Content-Type:application/octet-stream" \
       "${mgmtserver}/v1/o/${orgname}/apis/?action=import&name=${apiname}" \
       -T ${ZIPFILE} 
  if [[ ${CURL_RC} -ne 201 ]]; then
    echo
    echoerror "  failed importing that bundle."
    cat ${CURL_OUT}
    echo
    echo
    exit 1
  fi

  [[ $verbosity -gt 0 ]] && echo "deploy the ${apiname} apiproxy..."
  sleep 2
  MYCURL -X POST \
  "${mgmtserver}/v1/o/${orgname}/apis/${apiname}/revisions/1/deployments?action=deploy&env=$envname"
  if [[ ${CURL_RC} -ne 200 ]]; then
    echo
    echoerror "  failed deploying that api."
    cat ${CURL_OUT}
    echo
    echo
    exit 1
  fi
}


function create_new_product() {
    local SCRIPTPATH quota_alerts_info payload
    pushd `dirname $0` > /dev/null
    SCRIPTPATH=`pwd`
    popd > /dev/null

  productname=${apiname}-`random_string`
  [[ $verbosity -gt 0 ]] && echo "create a new product (${productname}) which contains that API proxy"
  sleep 2

  # properly JSON-encode the thresholds
  quota_alerts_info=$(cat "${thresholdFile}" | node -e "fs=require('fs'); console.log(JSON.stringify(JSON.stringify(JSON.parse(fs.readFileSync('/dev/stdin').toString()))));")

  payload=$'{\n'
  payload+=$'  "approvalType" : "auto",\n'
  payload+=$'  "attributes" : [ { "name":"quota_alerts_info", "value" : '
  payload+="$quota_alerts_info"
  payload+=$'  } ],\n'
  payload+=$'  "displayName" : "'
  payload+="${apiname}"
  payload+=$' Test product '
  payload+="${productname}"
  payload+=$'",\n'
  payload+=$'  "name" : "'${productname}
  payload+=$'",\n'
  payload+=$'  "apiResources" : [ "/**" ],\n'
  payload+=$'  "description" : "Test for '
  payload+="${apiname}"
  payload+=$'",\n'
  payload+=$'  "environments": [ "'
  payload+="${envname}"
  payload+=$'" ],\n'
  payload+=$'  "proxies": [ "'
  payload+="${apiname}"
  payload+=$'" ],\n'
  payload+=$'  "quota": "'
  payload+="${quotalimit}"
  payload+=$'",\n'
  payload+=$'  "quotaInterval": "1",\n'
  payload+=$'  "quotaTimeUnit": "hour"\n'
  payload+=$'}\n'
  
  MYCURL \
    -H "Content-Type:application/json" \
    -X POST ${mgmtserver}/v1/o/${orgname}/apiproducts -d "$payload"
  
  if [[ ${CURL_RC} -ne 201 ]]; then
    echo
    echoerror "  failed creating that product."
    cat ${CURL_OUT}
    echo
    echo
    exit 1
  fi

  MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/apiproducts/${productname}

  if [[ ${CURL_RC} -ne 200 ]]; then
    echo
    echoerror "  failed querying that product."
    cat ${CURL_OUT}
    echo
    echo
    exit 1
  fi

  cat ${CURL_OUT}
  echo
  echo
}


function create_new_developer() {
  local shortdevname=${apiname}-`random_string`
  devname=${shortdevname}@apigee.com
  [[ $verbosity -gt 0 ]] && echo "create a new developer (${devname})..."
  sleep 2
  MYCURL -X POST \
    -H "Content-type:application/json" \
    ${mgmtserver}/v1/o/${orgname}/developers \
    -d '{
    "email" : "'${devname}'",
    "firstName" : "Dino",
    "lastName" : "Valentino",
    "userName" : "'${shortdevname}'",
    "organizationName" : "'${orgname}'",
    "status" : "active"
  }' 
  if [[ ${CURL_RC} -ne 201 ]]; then
    echo
    echoerror "  failed creating a new developer."
    cat ${CURL_OUT}
    echo
    echo
    exit 1
  fi
}


function create_new_app() {
  local payload
  appname=${apiname}-`random_string`
  [[ $verbosity -gt 0 ]] && echo "create a new app (${appname}) for that developer, with authorization for the product..."
  sleep 2

  payload=$'{\n'
  payload+=$'  "attributes" : [ {\n'
  payload+=$'     "name" : "creator",\n'
  payload+=$'     "value" : "provisioning script '
  payload+="$0"
  payload+=$'"\n'
  payload+=$'    } ],\n'
  payload+=$'  "apiProducts": [ "'
  payload+="${productname}"
  payload+=$'" ],\n'
  payload+=$'    "callbackUrl" : "thisisnotused://www.apigee.com",\n'
  payload+=$'    "name" : "'
  payload+="${appname}"
  payload+=$'",\n'
  payload+=$'    "keyExpiresIn" : "100000000"\n'
  payload+=$'}' 

  # MYCURL -X POST \
  #   -H "Content-type:application/json" \
  #   ${mgmtserver}/v1/o/${orgname}/developers/${devname}/apps \
  #   -d '{
  #   "attributes" : [ {
  #         "name" : "creator",
  #         "value" : "provisioning script '$0'"
  #   } ],
  #   "apiProducts": [ "'${productname}'" ],
  #   "callbackUrl" : "thisisnotused://www.apigee.com",
  #   "name" : "'${appname}'",
  #   "keyExpiresIn" : "100000000"
  # }' 

  MYCURL -X POST \
    -H "Content-type:application/json" \
    ${mgmtserver}/v1/o/${orgname}/developers/${devname}/apps \
    -d "${payload}"

  if [[ ${CURL_RC} -ne 201 ]]; then
    echo
    echoerror "  failed creating a new app."
    cat ${CURL_OUT}
    echo
    echo
    CleanUp
    exit 1
  fi
}


function retrieve_app_keys() {
  local array
  [[ $verbosity -gt 0 ]] && echo "get the keys for that app..."
  sleep 2
  MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/developers/${devname}/apps/${appname} 
  if [[ ${CURL_RC} -ne 200 ]]; then
    echo
    echoerror "  failed retrieving the app details."
    cat ${CURL_OUT}
    echo
    echo
    CleanUp
    exit 1
  fi  

  array=(`cat ${CURL_OUT} | grep "consumerKey" | sed -E 's/[",:]//g'`)
  consumerkey=${array[1]}
  array=(`cat ${CURL_OUT} | grep "consumerSecret" | sed -E 's/[",:]//g'`)
  consumersecret=${array[1]}

  echo "  consumer key: ${consumerkey}"
  echo "  consumer secret: ${consumersecret}"
  echo 
  sleep 2
}


function exercise_apiproxy() {
    local iterations=$1 apikey=$consumerkey
    local url=https://${orgname}-${envname}.apigee.net/${invokePath} 
    for((n=1; n<=$iterations; n++)) ; { curl -i -X GET -H apikey:${apikey} ${url} ; }
    [[ $verbosity -gt 0 ]] && echo "sleeping..."
    sleep 2
}

function invoke_check() {
    local apikey=$consumerkey 
    local url=https://${orgname}-${envname}.apigee.net/${checkPath} 
    
    curl -i -X POST -H apikey:${apikey} \
         -H content-type:application/json ${url} -d '{ "apikeys": ["'$apikey'"]}'
    
    [[ $verbosity -gt 0 ]] && echo "sleeping..."
    sleep 5
}


## =======================================================

echo
echo "This script optionally deploys the ${apiname}.zip bundle, creates an API"
echo "product, inserts the API proxy into the product, creates a developer and"
echo "a developer app, gets the keys for that app. It also creates a named cache, "
echo "or verifies that the required cache exists in Edge."

echo "=============================================================================="

while getopts "hm:o:e:u:ndrt:qv" opt; do
  case $opt in
    h) usage ;;
    m) mgmtserver=$OPTARG ;;
    o) orgname=$OPTARG ;;
    e) envname=$OPTARG ;;
    u) credentials=$OPTARG ;;
    n) netrccreds=1 ;;
    d) wantdeploy=0 ;;
    r) resetonly=1 ;;
    t) thresholdFile=$OPTARG ;;
    q) verbosity=$(($verbosity-1)) ;;
    v) verbosity=$(($verbosity+1)) ;;
    *) echo "unknown arg" && usage ;;
  esac
done


[[ $verbosity -gt 0 ]] && echo
if [[ $resetonly -eq 0 ]] ; then
    if [[ ! -f "$thresholdFile" ]] ; then 
        echoerror "You must specify a configuration file (JSON format) with threshold information."
        echo
        usage
        exit 1
    fi
    hasnode=$(program_is_installed node)
    if [[ $hasnode -ne 1 ]] ; then
        echoerror "This script depends on node. Please install node, and re-run."
        echo
        usage
        exit 1 
    fi 
    hascurl=$(program_is_installed curl)
    if [[ $hascurl -ne 1 ]] ; then
        echoerror "This script depends on curl. Please install curl, and re-run."
        echo
        usage
        exit 1 
    fi 
fi

[[ $verbosity -gt 0 ]] && echo
if [[ "X$mgmtserver" = "X" ]]; then
  mgmtserver="$defaultmgmtserver"
fi 

if [[ "X$orgname" = "X" ]]; then
    echo "You must specify an org name (-o)."
    echo
    usage
    exit 1
fi

if [[ "X$envname" = "X" ]]; then
    echo "You must specify an environment name (-e)."
    echo
    usage
    exit 1
fi

if [[ "X$credentials" = "X" ]]; then
  if [[ ${netrccreds} -eq 1 ]]; then
    credentials='-n'
  else
    choose_credentials
  fi 
else
  maybe_ask_password
fi 

check_org 
if [[ ${check_org} -ne 0 ]]; then
  echo "that org cannot be validated"
  CleanUp
  exit 1
fi

check_env
if [[ ${check_env} -ne 0 ]]; then
  echo "that environment cannot be validated"
  CleanUp
  exit 1
fi


## reset everything related to this api
clear_env_state

if [[ $resetonly -eq 0 ]] ; then

  maybe_create_cache "${cacheName}"
  if [[ $wantdeploy -eq 1 ]] ; then
    deploy_new_bundle
  fi
  
  create_new_product
  create_new_developer
  create_new_app
  retrieve_app_keys

  exercise_apiproxy 50
  invoke_check
  exercise_apiproxy 20
  invoke_check
  exercise_apiproxy 15
  invoke_check
  
fi

CleanUp
exit 0

