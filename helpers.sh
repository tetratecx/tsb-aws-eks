#!/usr/bin/env bash

# Colors
readonly END="\033[0m" ;
readonly BLACK="\033[0;30m" ;
readonly BLACKB="\033[1;30m" ;
readonly WHITE="\033[0;37m" ;
readonly WHITEB="\033[1;37m" ;
readonly RED="\033[0;31m" ;
readonly REDB="\033[1;31m" ;
readonly GREEN="\033[0;32m" ;
readonly GREENB="\033[1;32m" ;
readonly YELLOW="\033[0;33m" ;
readonly YELLOWB="\033[1;33m" ;
readonly BLUE="\033[0;34m" ;
readonly BLUEB="\033[1;34m" ;
readonly PURPLE="\033[0;35m" ;
readonly PURPLEB="\033[1;35m" ;
readonly LIGHTBLUE="\033[0;36m" ;
readonly LIGHTBLUEB="\033[1;36m" ;

# Print info messages
function print_info {
  echo -e "${GREENB}${1}${END}" ;
}

# Print warning messages
function print_warning {
  echo -e "${YELLOWB}${1}${END}" ;
}

# Print error messages
function print_error {
  echo -e "${REDB}${1}${END}" ;
}

# Print command messages
function print_command {
  echo -e "${LIGHTBLUEB}${1}${END}" ;
}