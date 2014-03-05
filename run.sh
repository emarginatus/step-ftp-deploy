#!/bin/bash 

# confirm environment variables
if [ ! -n "$WERCKER_FTP_DEPLOY_DESTINATION" ]
then
    fail "missing option \"destination\", aborting"
fi
if [ ! -n "$WERCKER_FTP_DEPLOY_USERNAME" ]
then
    fail "missing option \"username\", aborting"
fi
if [ ! -n "$WERCKER_FTP_DEPLOY_PASSWORD" ]
then
    fail "missing option \"password\", aborting"
fi

DESTINATION=$WERCKER_FTP_DEPLOY_DESTINATION
USERNAME=$WERCKER_FTP_DEPLOY_USERNAME
PASSWORD=$WERCKER_FTP_DEPLOY_PASSWORD
REMOTE_FILE=$WERCKER_FTP_DEPLOY_REMOTE_FILE

if [ ! -n "$WERCKER_FTP_DEPLOY_REMOTE_FILE" ]
then
    echo "missing option \"remote-file\" so we will use all files"
    REMOTE_FILE=remote.txt
fi

# since wercker in beta allows max 25 minuter per build 
# upload of large files can be separated
TIMEOUT=20
date_start=$(date +"%s")
if [  -n "$WERCKER_FTP_DEPLOY_TIMEOUT" ]
then
    TIMEOUT=$WERCKER_FTP_DEPLOY_TIMEOUT
fi
echo "TIMEOUT is set to $TIMEOUT min. If wercker stops this script before TIMEOUT then $REMOTE_FILE lose synchronization. Clean FTP destination and start again."

echo "Test connection and list $DESTINATION files"
echo "curl -u $USERNAME:do_not_show_PASSWORD_in_log $DESTINATION/"
curl -u $USERNAME:$PASSWORD $DESTINATION/

echo "Calculating md5sum for local files" 
find . -type f -exec md5sum {} > $WERCKER_CACHE_DIR/local.txt \;
sort -k 2 -u $WERCKER_CACHE_DIR/local.txt -o $WERCKER_CACHE_DIR/local.txt > /dev/null

echo "Obtaining $REMOTE_FILE"
curl -u $USERNAME:$PASSWORD  $DESTINATION/$REMOTE_FILE -o $WERCKER_CACHE_DIR/remote.txt || (echo "No $REMOTE_FILE file" && echo "" > $WERCKER_CACHE_DIR/remote.txt )
echo "Sort unique"
sort -k 2 -u $WERCKER_CACHE_DIR/remote.txt -o $WERCKER_CACHE_DIR/remote.txt > /dev/null

echo "Sort all differences"
diff $WERCKER_CACHE_DIR/local.txt $WERCKER_CACHE_DIR/remote.txt | awk '{print $3}' | sort -u > $WERCKER_CACHE_DIR/diff.txt 
echo "total number of changed files "
cat $WERCKER_CACHE_DIR/diff.txt | wc -l

echo "Start removing and push new or changed files"
# if file is in diff.txt that means it is changed, removed of added
# in all cases it should be removed from server
# if it exists on local, then it should be pushed
while read file_name; do
  if [  -n "$file_name" ];
  then
    echo $file_name
    curl -u $USERNAME:$PASSWORD -X "DELE $file_name" $DESTINATION/ || echo "$file_name does not exists on server"
    # remove it from remote list also.
    # it does not change anything if file were not there
    sed -i "\|\b$file_name\b|d" $WERCKER_CACHE_DIR/remote.txt 
    if [ -f $file_name ];
    then
      # it is on local, so push it to server
      curl -u $USERNAME:$PASSWORD --ftp-create-dirs -T "$file_name" "$DESTINATION/$file_name" || echo "failed to push $file_name!!!!! do not know what to do. please remove all files from $DESTINATION and start again"
      md5sum $file_name >> $WERCKER_CACHE_DIR/remote.txt
    fi
    if [ "$TIMEOUT" -le $(( ($(date +"%s") - $date_start) / 60 )) ];
    then
      echo "TIMEOUT $TIMEOUT min has expired, pushing $REMOTE_FILE before wercker stop the script."
      curl -u $USERNAME:$PASSWORD -X "DELE $REMOTE_FILE" $DESTINATION/ || echo "$REMOTE_FILE has not been exist at the server"
      curl -u $USERNAME:$PASSWORD --ftp-create-dirs -T "$WERCKER_CACHE_DIR/remote.txt" "$DESTINATION/$REMOTE_FILE"

      fail "Please run again this script to finish all your files."
    fi
  fi
done < $WERCKER_CACHE_DIR/diff.txt

# local and remote should be equal
sort -k 2 -u $WERCKER_CACHE_DIR/remote.txt -o $WERCKER_CACHE_DIR/remote.txt > /dev/null
if diff $WERCKER_CACHE_DIR/remote.txt $WERCKER_CACHE_DIR/local.txt > /dev/null;then
  echo "ok"
else
  echo "They should not be different. Please remove all files from $DESTINATION and start Again"
fi

curl -u $USERNAME:$PASSWORD -X "DELE $REMOTE_FILE" $DESTINATION/ || echo "$REMOTE_FILE did not exists on server"
echo "Uploading $REMOTE_FILE"
curl -u $USERNAME:$PASSWORD --ftp-create-dirs -T "$WERCKER_CACHE_DIR/local.txt" "$DESTINATION/$REMOTE_FILE"

echo "Done uploading"

