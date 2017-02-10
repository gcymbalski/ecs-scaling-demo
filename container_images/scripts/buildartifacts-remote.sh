#!/bin/bash
. /etc/profile
cd /home/ubuntu/repo
$(cd /home/ubuntu/repo && bundle install --quiet)
RETURN=$?
if ! ( [ $RETURN == 0 ] || [ $RETURN == 1 ] ); then # XXX hack for a dumb gem bug
  echo "Had errors installing gems; research further"
  exit -1
fi
rm container_images/*.pem || true
bundle exec rake build:artifacts
touch /tmp/done
