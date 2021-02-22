FROM ruby:2.7.4-slim
LABEL maintainer "Zweitag GmbH"
# Debian/Apt dependencies
RUN apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get -yq dist-upgrade \
  && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    dirmngr \
    ghostscript \
    git \
    gpg \
    less \
    libgs9-common \
    libicu-dev \
    libnss3 \
    libpq-dev \
    libtre-dev \
    postgresql-client \
    tar \
    xz-utils \
    zlib1g-dev \
    graphicsmagick \
  && apt-get clean \
  && rm -rf /var/cache/apt/archives/* \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && truncate -s 0 /var/log/*log
RUN curl -sSL -o- https://github.com/tmate-io/tmate/releases/download/2.4.0/tmate-2.4.0-static-linux-amd64.tar.xz | \
  tar -xJf- -C bin --strip-components=1 tmate-2.4.0-static-linux-amd64/tmate \
 && chmod +x /bin/tmate
# enable UTF-8 locale, fixes many Unicode issues
ENV LANG=C.UTF-8
# Set default / system time zone to Europe/Berlin
ENV TZ=Europe/Berlin
# Install current Bundler
RUN gem update --system && gem install bundler
# Application will run as 'nonroot' user without root privileges
RUN adduser --shell /bin/bash --home /app --disabled-password nonroot
USER nonroot
WORKDIR /app
# Install asdf version manager (can be used to install Node and other language dependencies)
RUN git clone --depth 1 https://github.com/asdf-vm/asdf.git $HOME/.asdf && \
    echo '. $HOME/.asdf/asdf.sh' >> $HOME/.bashrc && \
    echo '. $HOME/.asdf/asdf.sh' >> $HOME/.profile
ENV PATH="${PATH}:/app/.asdf/shims:/app/.asdf/bin"
COPY --chown=nonroot .tool-versions ./
# Install NodeJS through asdf (version comes from .tool-versions)
RUN asdf plugin add nodejs
RUN asdf install nodejs
# Install yarn packages (and throw an error if the lockfile would change)
RUN npm install -g yarn
COPY --chown=nonroot package.json yarn.lock ./
RUN yarn install --frozen-lockfile
# ARGs can be overridden at image build time through --build-arg
ARG RAILS_ENV
ENV RAILS_ENV=${RAILS_ENV:-production}
ARG GIT_REV
ENV GIT_REV=${GIT_REV:-unknown}
ARG BUNDLE_WITHOUT="development test"
ENV RAILS_SERVE_STATIC_FILES=true
ENV RAILS_LOG_TO_STDOUT=true
# bundle install ('deployment' here means bundling to vendor/bundle and erroring out when Gemfile.lock would change)
COPY --chown=nonroot .tool-versions Gemfile Gemfile.lock ./
RUN bundle config set deployment 'true' \
    && bundle install \
      --jobs 5 \
      --retry 3
# Copy all the rest of the application
COPY --chown=nonroot . ./
# Precompile assets with minimal env needed to run rake tasks:
RUN export $(cat .env.build | xargs) && bundle exec rake assets:precompile
# Run the web server by default and expose its port
EXPOSE 3000
CMD ["bundle", "exec", "puma"]
