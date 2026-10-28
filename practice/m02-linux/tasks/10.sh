uptime
nproc
top -bn1 | head -12
pgrep -a python3
ps -o pid,ppid,user,stat,%cpu,etime,cmd -p $(pgrep -u priya python3)
