FROM ruby:3.2-slim

RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/jekyll

EXPOSE 4000

CMD rm -f Gemfile.lock && bundle install && jekyll serve --watch --incremental --port 4000 --host 0.0.0.0
