#!/bin/bash

if [ -z "$PLUGIN_HOSTS" ]; then
    echo "Specify at least one host!"
    exit 1
fi

if [ -z "$PLUGIN_TARGET" ]; then
  $PLUGIN_TARGET="tempdir"
fi

PORT=$PLUGIN_PORT
if [ -z "$PLUGIN_PORT" ]; then
    echo "Port not specified, using default port 22!"
    PORT=22
fi

SOURCE=$PLUGIN_SOURCE
if [ -z "$PLUGIN_SOURCE" ]; then
    echo "No source folder specified, using default './'"
    SOURCE="./"
fi

USER=$RSYNC_USER
if [ -z "$RSYNC_USER" ]; then
    if [ -z "$PLUGIN_USER" ]; then
        echo "No user specified, using root!"
        USER="root"
    else
        USER=$PLUGIN_USER
    fi
fi

## Hack for testing where the service on other end may not be started yet..
if [ -n "$PLUGIN_DO_SLEEP" ]; then
  sleep $PLUGIN_DO_SLEEP
fi

# SSH_KEY=$RSYNC_KEY
# if [ -z "$RSYNC_KEY" ]; then
#     if [ -z "$PLUGIN_KEY" ]; then
#         echo "No private key specified!"
#         exit 1
#     fi
#     SSH_KEY=$PLUGIN_KEY
# fi

SSH_PUBKEY=/root/keys/id_rsa.pub
if [ ! -f "$SSH_PUBKEY" ]; then
  echo "No SSH keys mounted at /root/keys"
  exit 1
fi

if [ -z "$PLUGIN_ARGS" ]; then
    ARGS=
else
    ARGS=$PLUGIN_ARGS
fi

# Building rsync command
expr="rsync -az $ARGS"

if [[ -n "$PLUGIN_RECURSIVE" && "$PLUGIN_RECURSIVE" == "true" ]]; then
    expr="$expr -r"
fi

if [[ -n "$PLUGIN_DELETE" && "$PLUGIN_DELETE" == "true" ]]; then
    expr="$expr --del"
fi

expr="$expr -e 'ssh -p $PORT -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -o StrictHostKeyChecking=no'"

# Include
IFS=','; read -ra INCLUDE <<< "$PLUGIN_INCLUDE"
for include in "${INCLUDE[@]}"; do
    expr="$expr --include=$include"
done

# Exclude
IFS=','; read -ra EXCLUDE <<< "$PLUGIN_EXCLUDE"
for exclude in "${EXCLUDE[@]}"; do
    expr="$expr --exclude=$exclude"
done

# Filter
IFS=','; read -ra FILTER <<< "$PLUGIN_FILTER"
for filter in "${FILTER[@]}"; do
    expr="$expr --filter=$filter"
done



# expr="$expr $SOURCE"

# Prepare temporary SSH files
home="/root"

mkdir -p "$home/.ssh"

printf "StrictHostKeyChecking no\n" > "$home/.ssh/config"
chmod 0700 "$home/.ssh/config"

cp /root/keys/id_rsa* /root/.ssh/

#keyfile="$home/.ssh/id_rsa.pub"
# echo "$SSH_KEY" | grep -q "ssh-ed25519"
# if [ $? -eq 0 ]; then
#     printf "Using ed25519 based key\n"
#     keyfile="$home/.ssh/id_ed25519"
# fi
# echo "$SSH_KEY" | grep -q "ecdsa-"
# if [ $? -eq 0 ]; then
#     printf "Using ecdsa based key\n"
#     keyfile="$home/.ssh/id_ecdsa"
# fi
# echo "$SSH_PUBKEY" > $keyfile
# chmod 0600 $keyfile

# Parse SSH commands.   Is this obtuse?
function join_with { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }
IFS=','; read -ra COMMANDS <<< "$PLUGIN_SCRIPT"
script=$(join_with ' && ' "${COMMANDS[@]}")

# Run rsync
IFS=','; read -ra HOSTS <<< "$PLUGIN_HOSTS"
result=0
for host in "${HOSTS[@]}"; do
    if [ $PLUGIN_TARGET == "tempdir" ]; then
      echo "Making tempdir on host"
      THIS_TARGET=$(ssh -p $PORT $USER@$host 'mktemp -d')
      result=$(($result+$?))

      if [ "$THIS_TARGET" == "" ]; then
        echo "Couldn't get temporary directory on remote host"
        exit -1
      fi

      ## Append a slash
      ##THIS_TARGET="$THIS_TARGET/"
      echo $(printf "Using tempdir %s" $THIS_TARGET)
      if [ "$result" -gt "0" ]; then exit $result; fi
    else
      $THIS_TARGET = $PLUGIN_TARGET
    fi

    echo "Sending code"
    echo $(printf "%s" "$ $expr $SOURCE $USER@$host:$THIS_TARGET ...")
    eval "$expr $SOURCE $USER@$host:$THIS_TARGET"
    result=$(($result+$?))
    if [ "$result" -gt "0" ]; then exit $result; fi

    if [ -n "$PLUGIN_SCRIPT" ]; then
        echo "Running script"

        this_script="cd $THIS_TARGET && $script"
        echo $(printf "%s" "$ ssh -p $PORT $USER@$host ...")
        echo $(printf "%s" " > $this_script ...")
        eval "ssh -p $PORT $USER@$host '$this_script'"
        result=$(($result+$?))
        echo $(printf "%s" "$ ssh -p $PORT $USER@$host result: $?")
        if [ "$result" -gt "0" ]; then exit $result; fi
    fi

    echo "Retrieving results"
    echo $(printf "%s" "$ $expr $USER@$host:$THIS_TARGET $SOURCE")
    eval "$expr $USER@$host:$THIS_TARGET $SOURCE;"
    result=$(($result+$?))
    if [ "$result" -gt "0" ]; then exit $result; fi

done

exit $result
