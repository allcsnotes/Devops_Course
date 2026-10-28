#!/usr/bin/env python3
# backup.py: copy the latest upload to the backup folder
import subprocess

subprocess.run(["cp", "/data/uploads/lesson-05.mp4", "/backup/"], check=True)
print("backup done")
