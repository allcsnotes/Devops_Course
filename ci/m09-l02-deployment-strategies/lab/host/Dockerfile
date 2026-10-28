# prod-01 host image: prod-01, the production server. Its own Docker engine (docker:29.5.3-dind, privileged as
# Docker-in-Docker needs) runs the load balancer and the app instances. asha logs in and runs the deploy scripts.
FROM docker:29.5.3-dind
RUN apk add --no-cache bash tmux curl jq coreutils ncurses tzdata \
 && adduser -D -s /bin/bash asha && addgroup asha docker \
 && install -d -o asha -g asha /srv/lb /srv/lb/conf.d /srv/lb/pools /srv/lb/log \
 && echo 'PS1="\u@\h:\w\$ "' > /home/asha/.bashrc && echo '. ~/.bashrc' > /home/asha/.bash_profile \
 && chown asha:asha /home/asha/.bashrc /home/asha/.bash_profile
