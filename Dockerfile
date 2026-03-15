FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# Pre-install basics so the script's apt steps are faster
RUN apt-get update -qq && \
    apt-get install -y -qq dialog curl gnupg lsb-release software-properties-common sudo systemctl 2>/dev/null || \
    apt-get install -y -qq dialog curl gnupg lsb-release software-properties-common sudo

COPY setup-stack.sh /opt/setup-stack.sh
COPY lib/ /opt/lib/
COPY test-stack.sh /opt/test-stack.sh
RUN chmod +x /opt/setup-stack.sh /opt/test-stack.sh /opt/lib/*.sh

WORKDIR /opt
CMD ["/opt/test-stack.sh"]
