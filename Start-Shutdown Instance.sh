#!/bin/bash

#########################################################
# Configuration
#########################################################

DOMAIN_HOME=""

HPROF_BACKUP="$DOMAIN_HOME/hprof_backup"

JAVA_HOME="../jdk1.8.0_391"
export JAVA_HOME

WLST="../bin/wlst.sh"

ADMIN_URL="t3://localhost:7001"

WLS_USER=""
WLS_PASS=""

LOGFILE="../logs/handle_hprof.log"

LOCKFILE="/tmp/handle_hprof.lock"

WLST_LOG="/tmp/wlst.log"

#########################################################

exec >> "$LOGFILE" 2>&1

echo "================================================"
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo "HPROF automation started"
echo "================================================"

#########################################################
# Prevent duplicate execution
#########################################################

if [ -f "$LOCKFILE" ]
then

    OLD_PID=$(cat "$LOCKFILE")

    if ps -p "$OLD_PID" >/dev/null 2>&1
    then
        echo "Another script still running PID=$OLD_PID"
        exit 1
    else
        echo "Removing stale lock file"
        rm -f "$LOCKFILE"
    fi

fi

echo $$ > "$LOCKFILE"

trap "rm -f $LOCKFILE $WLST_LOG" EXIT

mkdir -p "$HPROF_BACKUP"

#########################################################
# Process HPROF
#########################################################

for HPROF_FILE in "$DOMAIN_HOME"/java_pid*.hprof
do

    [ -f "$HPROF_FILE" ] || continue

    echo ""
    echo "Processing: $HPROF_FILE"

#########################################################
# Extract PID
#########################################################

    PID=$(basename "$HPROF_FILE" \
    | sed -E 's/java_pid([0-9]+)\.hprof/\1/')

    echo "PID=[$PID]"

#########################################################
# Find process
#########################################################

    PROCESS=$(ps -eo pid,args | grep "^ *$PID ")

    if [ -z "$PROCESS" ]
    then
        echo "Process not found"
        continue
    fi

    echo "PROCESS=$PROCESS"

#########################################################
# Get weblogic.Name
#########################################################

    PIDSAVED=$(echo "$PROCESS" \
    | grep -o '\-Dweblogic.Name=[^ ]*' \
    | head -1 \
    | cut -d= -f2 \
    | tr -d '\r\n' \
    | xargs)

    if [ -z "$PIDSAVED" ]
    then
        echo "Unable to determine weblogic.Name"
        continue
    fi

    echo "INSTANCE=[$PIDSAVED]"

#########################################################
# Process only AppReport*
#########################################################

    if [[ ! "$PIDSAVED" =~ ^Report ]]
    then
        echo "Skipping [$PIDSAVED]"
        continue
    fi

#########################################################
# Shutdown instance
#########################################################

echo "$(date '+%Y-%m-%d %H:%M:%S') Shutdown [$PIDSAVED]"
echo "Creating shutdown script..."

cat >/tmp/shutdown.py <<EOF
print('STEP1 connect')

connect('$WLS_USER','$WLS_PASS','$ADMIN_URL')

print('STEP2 connected')

shutdown('$PIDSAVED','Server',force='true')

print('STEP3 shutdown sent')

disconnect()

print('STEP4 disconnected')

exit()
EOF

echo "Running WLST..."

$WLST /tmp/shutdown.py > "$WLST_LOG" 2>&1

WLST_RC=$?

echo "WLST return code=$WLST_RC"

echo "WLST OUTPUT BEGIN"

cat "$WLST_LOG"

echo "WLST OUTPUT END"

#########################################################
# Cleanup
#########################################################

    SERVER_DIR="$DOMAIN_HOME/servers/$PIDSAVED"

    if [ -d "$SERVER_DIR" ]
    then

        echo "$(date '+%Y-%m-%d %H:%M:%S') Cleaning [$PIDSAVED]"

        cd "$SERVER_DIR"

        rm -rf cache
        rm -rf data/store
        rm -rf tmp

    else

        echo "Server directory not found"
    fi

#########################################################
# Start
#########################################################

    echo "$(date '+%Y-%m-%d %H:%M:%S') Start [$PIDSAVED]"

    cat >/tmp/start.py <<EOF
connect('$WLS_USER','$WLS_PASS','$ADMIN_URL')
start('$PIDSAVED')
disconnect()
exit()
EOF

    $WLST /tmp/start.py > "$WLST_LOG" 2>&1

    grep -v -E "Initializing|Welcome|Type help" \
    "$WLST_LOG"

    echo "$PIDSAVED completed"

done

#########################################################
# Archive
#########################################################

echo ""
echo "$(date '+%Y-%m-%d %H:%M:%S') Archive phase"

mv "$DOMAIN_HOME"/java_pid*.hprof \
"$HPROF_BACKUP"/ 2>/dev/null

cd "$HPROF_BACKUP"

gzip java_pid*.hprof 2>/dev/null

echo "Archive completed"

rm -f /tmp/start.py
rm -f /tmp/shutdown.py

echo ""
echo "Completed:"
date
echo ""