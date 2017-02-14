#!/bin/sh
exec /frontend/frontend -backend $BACKEND -backendPort $BACKENDPORT >>/var/log/frontend.log 2>&1
