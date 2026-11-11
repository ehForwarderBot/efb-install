# The legacy Telegram/WeChat plugins may not work on the newest Python.
# Python 3.12 retains imghdr (removed in Python 3.13).
ARG PYTHON_IMAGE=python:3.12-slim-bookworm
FROM ${PYTHON_IMAGE}

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/home/efb

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ffmpeg libmagic1 libcairo2 gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/efb-requirements.txt
RUN python -m pip install --no-cache-dir -r /tmp/efb-requirements.txt \
    && rm /tmp/efb-requirements.txt

RUN groupadd --gid 1000 efb \
    && useradd --uid 1000 --gid efb --create-home --home-dir /home/efb --shell /usr/sbin/nologin efb \
    && mkdir -p /home/efb/.ehforwarderbot \
    && chown -R efb:efb /home/efb

USER efb
WORKDIR /home/efb
CMD ["ehforwarderbot"]
