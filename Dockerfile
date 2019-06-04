FROM base-7:latest

USER root
ADD pakket.json /etc/pakket.json

RUN sed -i "s/##aws_access_key_id##/$DQS_AWS_ACCESS_KEY_ID/g;s/##aws_secret_access_key##/$DQS_AWS_SECRET_ACCESS_KEY/g" /etc/pakket.json

WORKDIR /opt/pakket/app/pakket
