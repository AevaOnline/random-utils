#!/usr/bin/env bash

MAX_SIZE=10000000    # 10GB

pushd /home/yunohost.backup/archives

echo
echo "### Starting Backup Wrapper ###"
echo "### Backup Size Limit is $MAX_SIZE ###"
echo "### Current local utilization is $(du -h | tail -1 | cut -f 1) ###"
echo

# clean up old backups down to max size
while [ $MAX_SIZE -lt $(du | tail -1 | cut -f 1 ) ]; do
  fd=$(ls -rt1 | head -1)
  echo "    Freeing space by deleting $fd"
  rm $fd
  echo "    Utilization now $(du -h | tail -1 | cut -f 1)"

done

echo
echo "### Taking Backup ###"
echo

yunohost backup create

echo
echo "### Done ###"
echo

popd
