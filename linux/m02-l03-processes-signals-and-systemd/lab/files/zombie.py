import os, time
pid = os.fork()
if pid == 0:
    os._exit(0)      # the child exits at once
time.sleep(120)      # the parent never calls wait()
