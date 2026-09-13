#!/bin/sh
rm -rf "$XDG_CACHE_HOME/art"
export ATL_UGLY_ENABLE_WEBVIEW=
export ATL_DISABLE_HW_DECODE=1
exec android-translation-layer --gapplication-app-id=net.newpipe.NewPipe /app/share/NewPipe.apk $@
