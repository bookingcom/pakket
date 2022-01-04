FROM perl

WORKDIR /srv/http/app
COPY    cpanfile /srv/http/app/cpanfile
RUN     cpanm -n --installdeps .

RUN     mkdir /srv/http/data
COPY    t/corpus/repos.v3 /srv/http/data

CMD     hypnotoad -f bin/pakket-web
