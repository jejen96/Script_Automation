#!/bin/bash

###############################################################################
# HOUSEKEEPING SCRIPT
#
# FUNCTION:
# - Move files from backup/ based on month/year
# - Create folder backup_YYYYMM
# - SCP folder to remote NFS
#
# USAGE:
# ./housekeeping.sh 202605
#
###############################################################################

########################
# PARAMETER VALIDATION
########################

if [ $# -ne 1 ]; then
    echo "Usage: $0 YYYYMM"
    exit 1
fi

TARGET_YYYYMM="$1"

if ! [[ "$TARGET_YYYYMM" =~ ^[0-9]{6}$ ]]; then
    echo "[FAILED] Invalid format. Use YYYYMM"
    exit 1
fi

TARGET_YEAR=${TARGET_YYYYMM:0:4}
TARGET_MONTH=${TARGET_YYYYMM:4:2}

########################
# CONFIGURATION
########################

# BASE SOURCE
BASE_PATH=""

# INSTANCE LIST
INSTANCES=(
    "instance01"
    "instance02"
    "instance03"
    "instance04"
)

# REMOTE CONFIG
REMOTE_USER=""
REMOTE_HOST="remote-server.example.com"

# REMOTE BASE PATH
REMOTE_BASE=""

# LOG
LOG_DIR=""
LOG_FILE="${LOG_DIR}/housekeeping_${TARGET_YYYYMM}.log"

########################
# LOGGING SETUP
########################

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

########################
# START
########################

echo "=================================================="
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo "START HOUSEKEEPING : ${TARGET_YYYYMM}"
echo "LOG FILE : ${LOG_FILE}"
echo "=================================================="

########################
# LOOP INSTANCE
########################

for INSTANCE in "${INSTANCES[@]}"
do

    echo ""
    echo "=================================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') PROCESSING : ${INSTANCE}"
    echo "=================================================="

    BACKUP_PATH="${BASE_PATH}/${INSTANCE}/backup"

    ########################
    # VALIDATE BACKUP PATH
    ########################

    if [ ! -d "$BACKUP_PATH" ]; then
        echo "[FAILED] Backup path not found"
        echo "[FAILED] ${BACKUP_PATH}"
        continue
    fi

    TARGET_FOLDER="${BACKUP_PATH}/backup_${TARGET_YYYYMM}"

    ########################
    # CREATE TARGET FOLDER
    ########################

    echo "[INFO] Creating folder : ${TARGET_FOLDER}"

    mkdir -p "$TARGET_FOLDER"

    MKDIR_STATUS=$?

    if [ $MKDIR_STATUS -ne 0 ]; then
        echo "[FAILED] Cannot create folder"
        continue
    fi

    echo "[SUCCESS] Folder ready"

    ########################
    # MOVE FILES
    ########################

    echo "[INFO] Moving files based on modified date..."

    MOVE_FAILED=0
    MOVE_COUNT=0

    while IFS= read -r file; do
        mv "$file" "$TARGET_FOLDER"/
        if [ $? -ne 0 ]; then
            echo "[FAILED] Cannot move: $file"
            MOVE_FAILED=1
        else
            echo "[INFO] Moved: $(basename "$file")"
            MOVE_COUNT=$((MOVE_COUNT + 1))
        fi
    done < <(find "$BACKUP_PATH" \
        -maxdepth 1 \
        -type f \
        -newermt "${TARGET_YEAR}-${TARGET_MONTH}-01" \
        ! -newermt "$(date -d "${TARGET_YEAR}-${TARGET_MONTH}-01 +1 month" '+%Y-%m-%d')")

    if [ "$MOVE_FAILED" -eq 1 ]; then
        echo "[FAILED] One or more files failed to move"
        continue
    fi

    echo "[SUCCESS] File moving completed. Total moved: ${MOVE_COUNT}"

    ########################
    # CHECK FILE COUNT
    ########################

    FILE_COUNT=$(find "$TARGET_FOLDER" -type f | wc -l)

    if [ "$FILE_COUNT" -eq 0 ]; then
        echo "[INFO] No file found for ${TARGET_YYYYMM}"
        rmdir "$TARGET_FOLDER" 2>/dev/null
        continue
    fi

    echo "[INFO] Total files in target folder : ${FILE_COUNT}"

    ########################
    # REMOTE TARGET
    ########################

    REMOTE_TARGET="${REMOTE_BASE}/${INSTANCE}/"

    ########################
    # CREATE REMOTE FOLDER
    ########################

    echo "[INFO] Creating remote folder..."

    ssh ${REMOTE_USER}@${REMOTE_HOST} \
        "mkdir -p ${REMOTE_TARGET}"

    SSH_STATUS=$?

    if [ $SSH_STATUS -ne 0 ]; then
        echo "[FAILED] Cannot create remote folder"
        continue
    fi

    echo "[SUCCESS] Remote folder ready"

    ########################
    # SCP
    ########################

    echo "[INFO] Starting SCP..."
    echo "[INFO] Source : ${TARGET_FOLDER}"
    echo "[INFO] Target : ${REMOTE_HOST}:${REMOTE_TARGET}"

    scp -pr "$TARGET_FOLDER" \
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_TARGET}"

    SCP_STATUS=$?

    ########################
    # SCP RESULT
    ########################

    if [ $SCP_STATUS -eq 0 ]; then

        echo "[SUCCESS] SCP SUCCESS : ${INSTANCE}"

        #######################################################################
        # OPTIONAL DELETE AFTER SCP SUCCESS
        # CURRENTLY DISABLED
        #######################################################################

        echo "[INFO] Deleting local backup folder..."
        rm -rf "$TARGET_FOLDER"

    else

        echo "[FAILED] SCP FAILED : ${INSTANCE}"
        echo "[FAILED] SCP EXIT CODE : ${SCP_STATUS}"

    fi

done

########################
# FINISH
########################

echo ""
echo "=================================================="
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo "HOUSEKEEPING FINISHED"
echo "=================================================="
