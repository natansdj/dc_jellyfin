#!/bin/bash

echo ""
echo "> docker exec -it jellyfin /usr/lib/jellyfin-ffmpeg/vainfo"
docker exec -it jellyfin /usr/lib/jellyfin-ffmpeg/vainfo

echo ""
echo "> docker exec -it jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -v verbose -init_hw_device vaapi=va -init_hw_device opencl@va"
docker exec -it jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -v verbose -init_hw_device vaapi=va -init_hw_device opencl@va

