# Generates a Docker image that contains the Soccerverse Democrit
# poolbot Python script for running it in production.

FROM python:3-alpine
RUN apk add --no-cache build-base

COPY democrit/svpool/requirements.txt /root
RUN pip3 install -r /root/requirements.txt

COPY democrit/svpool/svpool.py /usr/local/bin/

RUN mkdir -p /usr/local/share/democrit-evm/poolbot \
      && mkdir -p /usr/local/share/democrit-evm/out
WORKDIR /usr/local/share/democrit-evm
COPY democrit/lib/democrit-evm/poolbot/ poolbot/
COPY democrit/out/ out/

ENV PYTHONPATH=/usr/local/share/democrit-evm/poolbot

LABEL description="Runs the Soccerverse Democrit poolbot"
EXPOSE 8000
ENTRYPOINT [ \
  "/usr/local/bin/svpool.py", \
  "--port=8000", \
  "--forgeout=/usr/local/share/democrit-evm/out" \
]
