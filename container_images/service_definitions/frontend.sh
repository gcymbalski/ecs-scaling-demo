#!/bin/sh
BACKEND=`cat /frontend/backend`
exec /frontend/frontend -backend $BACKEND >>/var/log/frontend.log 2>&1
