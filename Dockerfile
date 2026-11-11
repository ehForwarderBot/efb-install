# The legacy Telegram/WeChat plugins may not work on the newest Python.
# Python 3.12 retains imghdr (removed in Python 3.13).
ARG PYTHON_IMAGE=python:3.12-slim-bookworm
FROM ${PYTHON_IMAGE}

ARG EFB_UID=1000
ARG EFB_GID=1000

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/home/efb

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ffmpeg libmagic1 libcairo2 gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-extra.txt /tmp/
RUN python -m pip install --no-cache-dir -r /tmp/requirements.txt -r /tmp/requirements-extra.txt \
    && rm /tmp/requirements.txt /tmp/requirements-extra.txt
COPY tools/validate_profile.py /usr/local/lib/efb-install/validate_profile.py

RUN if ! getent group "${EFB_GID}" >/dev/null; then groupadd --gid "${EFB_GID}" efb; fi \
    && useradd --uid "${EFB_UID}" --gid "${EFB_GID}" --create-home --home-dir /home/efb --shell /usr/sbin/nologin efb \
    && mkdir -p /home/efb/.ehforwarderbot \
    && chown -R efb:"${EFB_GID}" /home/efb

USER efb
WORKDIR /home/efb
CMD ["ehforwarderbot"]
