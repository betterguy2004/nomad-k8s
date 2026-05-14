FROM alpine:3.18

RUN apk add --no-cache curl bash jq

RUN curl -sL https://releases.hashicorp.com/nomad/1.7.0/nomad_1.7.0_linux_amd64.zip -o nomad.zip \
    && unzip nomad.zip \
    && mv nomad /usr/local/bin/ \
    && rm nomad.zip

ENTRYPOINT ["/bin/bash"]
