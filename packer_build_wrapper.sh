#!/bin/bash

#This wrapper is necessary because packer is too 😎 to put things like logging in config files.
#Also, kickstart logs the boot command by default so we need to provide it a crypted root password.

#Packer has a name conflict on Red Hat family systems
if [[ -f /etc/redhat-release ]] ;
  then PACKER_BIN="packerio" ;
  else PACKER_BIN="packer" ;
fi

usage() {
printf "$0 [options] [config.json]\n\nDescription:\nThis script runs \"$PACKER_BIN build\" with some extra parameters.\nUser variables for packer are loaded from packer_vars.json.\n(This can be changed by editing PACKER_VAR_FILE in this wrapper script).\nIf no root password is specified in the vars file as key \"packer_rootpw\", the script will prompt for one.\nFor a list of packer build options, run \"$PACKER_BIN build --help\"\n"
exit 64
}

hregex='^-{1,2}h(elp)?$'
[[ "$#" -lt 1 || "$1" =~ $hregex ]] && usage

##### Configuration

## Setting key interval lower may result in lost keystrokes
#export PACKER_KEY_INTERVAL=100ms
export PACKER_LOG="1"
export PACKER_LOG_PATH="${PWD}/packer$(date --iso-8601).log"
export CHECKPOINT_DISABLE="1"

#Change this to the json format variables file you wish to use.
#P.S. Don't forget to add that to .gitignore
export PACKWRAP_VAR_FILE="packer_vars.json"

#Set this to anything besides 0 for DEBUG
PACKWRAP_DEBUG=0

#####

#Split python output on newline to make array
oldIFS=$IFS
IFS='
'
PYTHON_OUTPUT=($(python <(cat <<'EOF'
from __future__ import print_function
import os
import crypt
import random
import string
import json
import sys

was_prompted=False
packer_vars=os.getenv('PACKWRAP_VAR_FILE')
print("Packer vars file is: " + packer_vars, file=sys.stderr)
try:
  varfile=json.load(open(packer_vars))
  if 'packer_rootpw' in varfile and varfile["packer_rootpw"] is not None and varfile["packer_rootpw"].strip():
    password_text=varfile["packer_rootpw"]
    print("Using root password from: " + packer_vars, file=sys.stderr)
  else:
    print("No root password set in packer_vars.json or password is empty/null.", file=sys.stderr)
    sys.stderr.write("Please provide the root password for the Packer build.>")
    password_text=raw_input("")
    was_prompted=True

except IOError as e:
  print("Could not open " + packer_vars + "\n" + "I/O Error({0}): {1}".format(e.errno, e.strerror), file=sys.stderr)
  sys.exit(1)

except Exception as f:
  print("Unexpected error: " + f.message, file=sys.stderr)
  sys.exit(2)

if len(password_text.rstrip()) > 7:
  password_crypted=crypt.crypt(password_text, "$6$" + ''.join([random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(16)])) 
  print(password_crypted, file=sys.stdout)
else:
  print("Invalid password length. Please input at least an 8 digit password.", file=sys.stderr)
  sys.exit(3)

if was_prompted is True:
  print(password_text, file=sys.stdout)
else:
  print("False", file=sys.stdout)
EOF
)
)
)
IFS=$oldIFS

[[ $PACKWRAP_DEBUG -ne 0 ]] && printf "DEBUG: Python output is:\n '%s'\n" "${PYTHON_OUTPUT[@]}" 1>&2
[[ ! -z "${PYTHON_OUTPUT[0]}" && "${PYTHON_OUTPUT[0]}" =~ \$[6]\$[a-zA-Z0-9./]+ ]] || { echo "Error setting PACKWRAP_ROOTPW." ; exit 4 ; }

PACKWRAP_ROOTPW="${PYTHON_OUTPUT[0]}"
if [[ ${PYTHON_OUTPUT[1]} != "False" ]] ; then
  export PACKWRAP_ROOTPW_PLAIN="${PYTHON_OUTPUT[1]}"
  printf "Manual password input used. Add password to packer_rootpw key in ${PACKWRAP_VAR_FILE} for non-interactive use.\n" 1>&2
fi

for param in "$@" ; do
  case "$param" in
    RHEL*)
    read -r -s -p "Ansible Vault password required for RHEL registration:" PACKWRAP_VAULT_PASS
    ;;
    *)
    ;;
  esac
done

[[ -z $PACKWRAP_VAULT_PASS ]] && export PACKWRAP_VAULT_PASS

"$PACKER_BIN" build -var "crypted_rootpw=${PACKWRAP_ROOTPW}" -var-file="${PWD}/${PACKWRAP_VAR_FILE}" "$@"
