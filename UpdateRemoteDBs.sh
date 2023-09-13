#!/bin/bash

# Program name: UpdateRemoteDBs.sh
# Author name: Ye Li
# Date created: 5th April, 2023
# Date updated: 14th April, 2023
# Description:
#   This program will extract five tables from the database
#   and scp the extracted table files into all 6 remote servers.
#   After files are copied to the remote server, it will run the
#   import script to import tables in the remote servers.

# Function: send email
# $1: email
# $2: subject
# $3: summary
function send_email () {
  echo -e "$3" | mail -s "$2" -b "li130@sheridancollege.ca" "$1"
}

# Function: read list of remote servers from file RemoteSystemsList
function read_remote_servers () {
  while read -r line; do
    remote_servers+=("$line")
  done < $HOME/bin/RemoteSystemsList
}

# Function: output string to log file
# $1: content
function write_log () {
  echo $1 >> $extract_log_file
}

# create directories
mkdir -p ~/bin ~/tables ~/log

# create empty log file first
extract_log_file="$HOME/log/extract-$(date +%Y-%m-%d_%H-%M-%S).log"
touch $extract_log_file

# summary holder
summary="----- Summary for today at $(date +%Y-%m-%d_%H-%M-%S) -----\n"

# extract all tables
rm -f ~/tables/*
for file in $HOME/bin/ExtractTable*;
do
  write_log "Executing file $file"
  $file >> $extract_log_file
  write_log "Successfully extracted table with $file"
done

# count how many were extracted successfully
extracted_success=$(ls ~/tables | wc -l)
summary="$summary\nThere were $extracted_success tables extracted successfully as shown below"

# check if extracted files exist by counting how many files got created
for i in {1..5}; do
  if [[ -f "$HOME/tables/Table$i.Extract" ]]; then
    summary="$summary\nTable$i.Extract: SUCCESS"
  else
    summary="$summary\nTable$i.Extract: FAILED"
  fi
done

# list of remote servers -- read from RemoteSystemsList file
remote_servers=()
read_remote_servers

# copy all extracted table files to all remote servers
summary="$summary\n\nImported table in server status shown below:"
for server in "${remote_servers[@]}"
do
  write_log ""
  write_log "Copying table files to remote server $server"

  # setup directory structure in remote server
  ssh a02_18090@$server "mkdir -p ~/bin ~/log ~/tables"

  # copy all files to remote server
  scp ~/tables/Table*.Extract a02_18090@$server:/home/a02_18090/tables/
  scp $HOME/bin/ImportTable* a02_18090@$server:/home/a02_18090/bin/
  write_log "Finished copying all table files to remote server $server"

  # import files in remote
  import_log_file="import-$server-$(date +%Y-%m-%d_%H-%M-%S).log"
  ssh a02_18090@$server "bash -lc 'cd ~/bin; for i in {1..5}; do ImportTable\$i ; done'" >> $HOME/log/$import_log_file

  summary="$summary\n$server:"
  # check if import is successful for each table 'Importing Table ?' keyword showed up in the log file
  for i in {1..5}; do
    cnt=$(grep -c "Importing Table $i" $HOME/log/$import_log_file)

    if [[ $cnt -eq 1 ]]; then
      summary="$summary\n  - Table$i: SUCCESS"
      write_log "Finished importing Table$i in remote server $server"
    else
      summary="$summary\n  - Table$i: FAILED"
      write_log "Failed to import Table$i in remote server $server"
    fi
  done

  write_log "See log file for details: $import_log_file"
done

# send summary to email
send_email "syst13416-1231@dmginc.com" "1231_18090 - Summary for today at $(date +%Y-%m-%d_%H-%M-%S)" "$summary"
